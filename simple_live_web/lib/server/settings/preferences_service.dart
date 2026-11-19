import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../storage/data_directory.dart';

class PreferencesService {
  final directory = localDataDirectory();
  Future<void> _queue = Future.value();

  File get _file => File('${directory.path}/preferences.json');

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) async {
      await directory.create(recursive: true);
      final lock = await File(
        '${directory.path}/preferences.lock',
      ).open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.blockingExclusive);
        return await action();
      } finally {
        await lock.close();
      }
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Map<String, dynamic>> _read() async {
    if (!await _file.exists()) return {};
    if ((await _file.stat()).size > 64 * 1024) {
      throw const FormatException('本地设置文件过大，已停止写入，请先手动备份');
    }
    try {
      return _validate(jsonDecode(await _file.readAsString()));
    } on FormatException {
      throw const FormatException('本地设置文件损坏，已停止写入，请先手动备份');
    }
  }

  Future<Map<String, dynamic>> read() =>
      _locked(() async => {'data': await _read()});

  Future<Map<String, dynamic>> write(Map<String, dynamic> body) =>
      _locked(() async {
        final patch = _validate(body['patch']);
        final current = await _read();
        final onlyMissing = body['onlyMissing'] == true;
        // Merge individual nested fields so other pages' edits are preserved.
        for (final entry in patch.entries) {
          if (entry.key == 'player' || entry.key == 'webdav') {
            final nested = Map<String, dynamic>.from(
              current[entry.key] as Map<String, dynamic>? ?? {},
            );
            for (final field in (entry.value as Map<String, dynamic>).entries) {
              if (!onlyMissing || !nested.containsKey(field.key)) {
                nested[field.key] = field.value;
              }
            }
            current[entry.key] = nested;
          } else if (!onlyMissing || !current.containsKey(entry.key)) {
            current[entry.key] = entry.value;
          }
        }
        final temporary = File('${_file.path}.tmp');
        try {
          await temporary.writeAsString(jsonEncode(current), flush: true);
          await temporary.rename(_file.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
        return {'data': current};
      });
}

Map<String, dynamic> _validate(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('设置格式无效');
  }
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final valid = switch (entry.key) {
      'mode' => ['system', 'light', 'dark'].contains(entry.value),
      'primaryColor' =>
        entry.value is String &&
            RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(entry.value as String),
      'sidebarCollapsed' => entry.value is bool,
      'playbackSidebarCollapsed' => entry.value is bool,
      'player' => entry.value is Map<String, dynamic>,
      'webdav' => entry.value is Map<String, dynamic>,
      _ => false,
    };
    if (!valid) throw const FormatException('设置字段无效');
    result[entry.key] = switch (entry.key) {
      'player' => _validatePlayer(entry.value as Map<String, dynamic>),
      'webdav' => _validateWebdav(entry.value as Map<String, dynamic>),
      _ => entry.value,
    };
  }
  return result;
}

Map<String, dynamic> _validateWebdav(Map<String, dynamic> value) {
  const limits = {'url': 4096, 'username': 2048, 'password': 8192};
  for (final entry in value.entries) {
    final limit = limits[entry.key];
    if (limit == null ||
        entry.value is! String ||
        (entry.value as String).length > limit) {
      throw const FormatException('WebDAV 配置字段无效或过长');
    }
  }
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> _validatePlayer(Map<String, dynamic> value) {
  const limits = {
    'opacity': (0.1, 1.0),
    'size': (8.0, 48.0),
    'weight': (1.0, 9.0),
    'duration': (1.0, 10.0),
    'area': (0.1, 1.0),
    'topMargin': (0.0, 48.0),
    'verticalGap': (0.0, 40.0),
    'horizontalGap': (0.0, 100.0),
  };
  for (final entry in value.entries) {
    if (['enabled', 'fortune', 'antiOverlap'].contains(entry.key)) {
      if (entry.value is bool) continue;
    } else {
      final limit = limits[entry.key];
      final number = entry.value;
      if (limit != null &&
          number is num &&
          number.isFinite &&
          number >= limit.$1 &&
          number <= limit.$2) {
        continue;
      }
    }
    throw const FormatException('弹幕设置字段无效');
  }
  return Map<String, dynamic>.from(value);
}

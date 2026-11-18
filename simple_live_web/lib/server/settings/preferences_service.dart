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

  Future<Map<String, dynamic>> write(Map<String, dynamic> body) => _locked(
    () async {
      final patch = _validate(body['patch']);
      final current = await _read();
      final onlyMissing = body['onlyMissing'] == true;
      // Merge only changed fields under the lock, including individual sliders.
      for (final entry in patch.entries) {
        if (entry.key == 'player') {
          final player = Map<String, dynamic>.from(
            current['player'] as Map<String, dynamic>? ?? {},
          );
          for (final field in (entry.value as Map<String, dynamic>).entries) {
            if (!onlyMissing || !player.containsKey(field.key)) {
              player[field.key] = field.value;
            }
          }
          current['player'] = player;
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
    },
  );
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
      'player' => entry.value is Map<String, dynamic>,
      _ => false,
    };
    if (!valid) throw const FormatException('设置字段无效');
    result[entry.key] = entry.key == 'player'
        ? _validatePlayer(entry.value as Map<String, dynamic>)
        : entry.value;
  }
  return result;
}

Map<String, dynamic> _validatePlayer(Map<String, dynamic> value) {
  const limits = {
    'opacity': (0.1, 1.0),
    'size': (8.0, 48.0),
    'weight': (1.0, 9.0),
    'duration': (1.0, 10.0),
    'area': (0.1, 1.0),
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

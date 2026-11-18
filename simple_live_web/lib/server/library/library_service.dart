import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class LibraryConflict implements Exception {}

class LibraryService {
  final Directory directory = Directory(_dataPath());
  Future<void> _queue = Future.value();
  final _random = Random.secure();

  static String _dataPath() {
    final env = Platform.environment;
    final override = env['SIMPLE_LIVE_DATA_DIR'];
    if (override != null && override.isNotEmpty) return override;
    final base = Platform.isWindows
        ? env['APPDATA']
        : env['XDG_DATA_HOME'] ??
              (env['HOME'] == null ? null : '${env['HOME']}/.local/share');
    if (base == null || base.isEmpty) {
      throw const FileSystemException('无法定位本地数据目录');
    }
    return '$base${Platform.pathSeparator}simple-live-web';
  }

  File get _file => File('${directory.path}/library.json');

  // Serialize within this process and lock across servers on different ports.
  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) async {
      await directory.create(recursive: true);
      final lock = await File(
        '${directory.path}/library.lock',
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

  Future<Map<String, dynamic>> read() => _locked(_read);

  Future<Map<String, dynamic>> _read() async {
    if (!await _file.exists()) return {'revision': '', 'data': null};
    final stat = await _file.stat();
    final corruptRevision =
        'invalid:${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    if (stat.size > 20 * 1024 * 1024) {
      throw const FileSystemException('本地数据文件过大，请手动备份后处理');
    }
    final raw = await _file.readAsString();
    try {
      final envelope = _map(jsonDecode(raw));
      final revision = _text(envelope['revision']);
      return {'revision': revision, 'data': validateLibrary(envelope['data'])};
    } on FormatException {
      return {
        'revision': corruptRevision,
        'data': null,
        'raw': raw,
        'error': '本地数据文件损坏，已停止写入。请先备份原始数据，再清除损坏数据。',
      };
    }
  }

  Future<Map<String, dynamic>> write(Map<String, dynamic> body) =>
      _locked(() async {
        final current = await _read();
        if (body['revision'] != current['revision']) throw LibraryConflict();
        if (current['error'] != null && body['reset'] != true) {
          throw const FormatException('请先备份原始数据，再清除损坏数据');
        }
        final data = body['reset'] == true
            ? <String, dynamic>{
                'follows': [],
                'histories': [],
                'tags': [],
                'blocked': [],
              }
            : validateLibrary(body['data']);
        final result = <String, dynamic>{
          'revision': base64UrlEncode(
            List.generate(24, (_) => _random.nextInt(256)),
          ),
          'data': data,
        };
        final encoded = jsonEncode(result);
        if (utf8.encode(encoded).length > 20 * 1024 * 1024) {
          throw const FormatException('本地数据不能超过 20 MB');
        }
        final temporary = File('${_file.path}.tmp');
        try {
          await temporary.writeAsString(encoded, flush: true);
          await temporary.rename(_file.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
        return result;
      });
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('本地数据格式无效');
  }
  return value;
}

String _text(Object? value, {bool allowEmpty = false}) {
  if (value is! String ||
      value.length > 10000 ||
      (!allowEmpty && value.trim().isEmpty)) {
    throw const FormatException('本地数据字段无效');
  }
  return value;
}

List<dynamic> _list(Object? value) {
  if (value is! List || value.length > 50000) {
    throw const FormatException('本地数据列表无效或过大');
  }
  return value;
}

String _date(Object? value) {
  final text = _text(value);
  if (DateTime.tryParse(text) == null) {
    throw const FormatException('本地数据日期无效');
  }
  return text;
}

Map<String, dynamic> _user(Object? value) {
  final item = _map(value);
  final id = _text(item['id']);
  final siteId = _text(item['siteId']);
  final roomId = _text(item['roomId']);
  if (id != '${siteId}_$roomId') {
    throw const FormatException('本地数据房间标识不一致');
  }
  return {
    'id': id,
    'siteId': siteId,
    'roomId': roomId,
    'userName': _text(item['userName'], allowEmpty: true),
    'face': _text(item['face'], allowEmpty: true),
  };
}

List<Map<String, dynamic>> _unique(Iterable<Map<String, dynamic>> items) =>
    {for (final item in items) item['id'] as String: item}.values.toList();

Map<String, dynamic> validateLibrary(Object? value) {
  final data = _map(value);
  return {
    'follows': _unique(
      _list(data['follows']).map((value) {
        final item = _map(value);
        return {
          ..._user(item),
          'addTime': _date(item['addTime']),
          'tag': item['tag'] == null
              ? '全部'
              : _text(item['tag'], allowEmpty: true),
        };
      }),
    ),
    'histories': _unique(
      _list(data['histories']).map(
        (value) => {
          ..._user(value),
          'updateTime': _date(_map(value)['updateTime']),
        },
      ),
    ),
    'tags': _unique(
      _list(data['tags']).map((value) {
        final item = _map(value);
        return {
          'id': _text(item['id']),
          'tag': _text(item['tag']),
          'userId': _list(item['userId']).map((id) => _text(id)).toList(),
        };
      }),
    ),
    'blocked': _list(data['blocked'])
        .map((word) => _text(word).trim())
        .where((word) => word.isNotEmpty)
        .toSet()
        .toList(),
  };
}

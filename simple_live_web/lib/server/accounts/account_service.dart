import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';

import '../library/library_service.dart';
import '../storage/data_directory.dart';

const accountSites = ['bilibili', 'douyu', 'douyin'];

Map<String, String> normalizeAccounts(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('账号数据格式无效');
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    if (!accountSites.contains(entry.key) ||
        entry.value is! String ||
        (entry.value as String).length > 50000) {
      throw const FormatException('账号字段无效或过长');
    }
    var text = (entry.value as String).trim();
    if (text.isNotEmpty && entry.key == 'bilibili') {
      text = normalizeCookie(text);
      if (text.isEmpty) throw const FormatException('Cookie 格式无效');
    } else if (text.isNotEmpty) {
      final key = entry.key == 'douyu' ? 'dy_auth' : 'ttwid';
      final match = RegExp('(?:^|[;\\s])$key=([^;\\s]+)').firstMatch(text);
      if (match != null) {
        text = match[1]!;
      } else if (text.contains(';') || text.contains('$key=')) {
        throw FormatException('未识别到 $key');
      }
      text = text.replaceAll(RegExp(r'''^["']|["';]+$'''), '').trim();
      if (text.isEmpty || RegExp(r'[\x00-\x20\x7f;,]').hasMatch(text)) {
        throw FormatException('$key 格式无效');
      }
      if (entry.key == 'douyin') text = 'ttwid=$text';
    }
    if (RegExp(r'[\r\n\x00]').hasMatch(text)) {
      throw const FormatException('账号数据含有无效字符');
    }
    result[entry.key] = text;
  }
  return result;
}

class AccountService {
  AccountService(this.sites, this.onChanged);
  final Map<String, LiveSite> sites;
  final void Function() onChanged;
  final _directory = localDataDirectory();
  final _random = Random.secure();
  final _network = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      followRedirects: false,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    ),
  );
  Future<void> _queue = Future.value();
  String? _revision;
  Map<String, String> _data = {for (final site in accountSites) site: ''};
  final _states = <String, Map<String, dynamic>>{};
  final _qr = <String, ({String key, String revision, DateTime expires})>{};
  final _polling = <String>{};

  File get _file => File('${_directory.path}/accounts.json');
  String _token() => base64UrlEncode(
    List.generate(24, (_) => _random.nextInt(256)),
  ).replaceAll('=', '');

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _queue.then((_) async {
      await _directory.create(recursive: true);
      final lock = await File(
        '${_directory.path}/accounts.lock',
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
    if (!await _file.exists()) {
      return {'revision': '', 'data': <String, String>{}};
    }
    if ((await _file.stat()).size > 256 * 1024) {
      throw const FormatException('账号文件过大，已停止写入，请先手动备份');
    }
    try {
      final value = jsonDecode(await _file.readAsString());
      if (value is! Map<String, dynamic> || value['revision'] is! String) {
        throw const FormatException();
      }
      return {
        'revision': value['revision'],
        'data': normalizeAccounts(value['data']),
      };
    } on FormatException {
      throw const FormatException('账号文件损坏，已停止写入，请先手动备份');
    }
  }

  Future<void> refresh() => _locked(() async {
    final value = await _read();
    if (_revision == value['revision']) return;
    _revision = value['revision'] as String;
    _data = {
      for (final site in accountSites) site: '',
      ...value['data'] as Map<String, String>,
    };
    _states.clear();
    final bili = BiliBiliSite()
      ..cookie = _data['bilibili']!
      ..userId =
          int.tryParse(cookieValue(_data['bilibili'], 'DedeUserID')) ?? 0;
    BiliBiliSite.clearWbiCache();
    sites['bilibili'] = bili;
    sites['douyu'] = DouyuSite()..dyAuth = _data['douyu']!;
    sites['douyin'] = DouyinSite()..cookie = _data['douyin']!;
    onChanged();
  });

  Map<String, dynamic> _summary() => {
    'revision': _revision ?? '',
    'items': [
      for (final site in [...accountSites, 'huya'])
        {
          'site': site,
          'configured': _data[site]?.isNotEmpty ?? false,
          'state': site == 'huya'
              ? 'default'
              : _data[site]!.isEmpty
              ? (site == 'douyin' ? 'default' : 'empty')
              : 'saved',
          ...?_states[site],
        },
    ],
  };

  Future<Map<String, dynamic>> summary() async {
    await refresh();
    return _summary();
  }

  Future<bool> markDouyuInvalid(String credential) async {
    await refresh();
    // 旧取流结果不能覆盖用户刚替换的授权；未登录时保留账号页的未登录状态。
    if (_data['douyu'] != credential) return false;
    if (credential.isNotEmpty) {
      _states['douyu'] = {'state': 'invalid', 'message': '授权已失效，请重新登录'};
    }
    return true;
  }

  void _expect(Object? revision) {
    if (revision != _revision) throw LibraryConflict();
  }

  Future<void> _save(
    Object? revision,
    Map<String, String> patch, {
    bool Function()? allowed,
  }) async {
    await _locked(() async {
      if (allowed != null && !allowed()) {
        throw const HttpException('二维码已取消或过期，请重新扫码');
      }
      final current = await _read();
      if (revision != current['revision']) throw LibraryConflict();
      final next = {
        'revision': _token(),
        'data': {...current['data'] as Map<String, String>, ...patch},
      };
      final temporary = File('${_file.path}.tmp');
      try {
        await temporary.writeAsString(jsonEncode(next), flush: true);
        await temporary.rename(_file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    await refresh();
  }

  Future<Map<String, String>> export(Object? revision, Object? selected) async {
    await refresh();
    _expect(revision);
    if (selected is! List ||
        selected.any((site) => !accountSites.contains(site))) {
      throw const FormatException('请选择有效的账号类型');
    }
    return {for (final site in selected) site as String: _data[site]!};
  }

  Future<void> _verify(String site) async {
    final revision = _revision;
    final credential = _data[site]!;
    if (credential.isEmpty || site == 'douyin') return;
    var state = <String, dynamic>{
      'state': 'unknown',
      'message': '已保存，暂时无法校验，请稍后重试',
    };
    try {
      if (site == 'bilibili') {
        final response = await _network.get<dynamic>(
          'https://api.bilibili.com/x/member/web/account',
          options: Options(headers: {'Cookie': credential}),
        );
        final value = response.data;
        if (value is Map && value['code'] == 0 && value['data'] is Map) {
          state = {
            'state': 'valid',
            'name': value['data']['uname']?.toString() ?? '已登录',
          };
        } else if (value is Map && value['code'] == -101) {
          state = {'state': 'invalid', 'message': '登录已失效，请重新登录'};
        }
      } else if (!const bool.fromEnvironment('SIMPLE_LIVE_NO_NATIVE')) {
        final douyu = DouyuSite()..dyAuth = credential;
        final rooms = await douyu.getRecommendRooms(page: 1);
        if (rooms.items.isNotEmpty) {
          final detail = await douyu.getRoomDetail(
            roomId: rooms.items.first.roomId,
          );
          if (detail.status) {
            final valid = await douyu.verifyAuth(
              detail.roomId,
              args: detail.data.toString(),
            );
            if (valid != null) {
              state = {
                'state': valid ? 'valid' : 'invalid',
                'message': valid ? '已授权' : '授权已失效，请重新登录',
              };
            }
          }
        }
      }
    } catch (_) {
      // Network errors do not prove that saved authorization has expired.
    }
    await refresh();
    if (_revision == revision) _states[site] = state;
  }

  Future<Object> handle(Map<String, dynamic> body) async {
    await refresh();
    final action = body['action'];
    if (action == 'export') {
      return {'data': await export(body['revision'], body['sites'])};
    }
    if (action == 'validate') {
      normalizeAccounts(body['data']);
      return {'status': true};
    }
    if (action == 'restore') {
      await _save(body['revision'], normalizeAccounts(body['data']));
      return _summary();
    }
    if (['save', 'clear', 'check'].contains(action)) {
      final site = body['site'];
      if (!accountSites.contains(site)) {
        throw const FormatException('该平台无需管理账号');
      }
      if (action == 'check') {
        _expect(body['revision']);
      } else {
        final patch = normalizeAccounts({
          site as String: action == 'clear' ? '' : body['credential'],
        });
        await _save(body['revision'], patch);
      }
      if (action != 'clear') await _verify(site as String);
      return _summary();
    }
    if (action == 'qr-cancel') {
      _qr.remove(body['sessionId']);
      return {'status': true};
    }
    if (action == 'qr-generate') {
      _expect(body['revision']);
      final revision = _revision!;
      _qr.removeWhere((_, value) => value.expires.isBefore(DateTime.now()));
      if (_qr.length >= 32) throw const HttpException('登录请求过多，请稍后重试');
      final response = await _network.get<dynamic>(
        'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
      );
      final value = response.data;
      final data = value is Map ? value['data'] : null;
      final uri = Uri.tryParse(data is Map ? '${data['url']}' : '');
      if (value is! Map ||
          value['code'] != 0 ||
          data is! Map ||
          data['qrcode_key'] is! String ||
          uri?.scheme != 'https' ||
          uri?.host != 'passport.bilibili.com') {
        throw const HttpException('二维码获取失败，请稍后重试');
      }
      final id = _token();
      final expires = DateTime.now().add(const Duration(minutes: 3));
      _qr[id] = (
        key: data['qrcode_key'] as String,
        revision: revision,
        expires: expires,
      );
      return {
        'sessionId': id,
        'url': uri.toString(),
        'expiresAt': expires.millisecondsSinceEpoch,
      };
    }
    if (action == 'qr-poll') {
      final id = body['sessionId'];
      final session = _qr[id];
      if (session == null || session.expires.isBefore(DateTime.now())) {
        _qr.remove(id);
        return {'state': 'expired'};
      }
      if (!_polling.add(id as String)) return {'state': 'waiting'};
      try {
        final response = await _network.get<dynamic>(
          'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
          queryParameters: {'qrcode_key': session.key},
        );
        final value = response.data;
        if (value is! Map || value['code'] != 0 || value['data'] is! Map) {
          throw const HttpException('二维码登录状态获取失败，请重试');
        }
        final code = value['data']['code'];
        if (code == 0) {
          final cookie = normalizeCookie(
            (response.headers['set-cookie'] ?? [])
                .map((value) => value.split(';').first)
                .join(';'),
          );
          if (!hasCookieValue(cookie, 'SESSDATA')) {
            throw const HttpException('登录未返回有效凭据，请重新扫码');
          }
          if (!_qr.containsKey(id)) return {'state': 'expired'};
          await _save(
            session.revision,
            {'bilibili': cookie},
            allowed: () =>
                _qr.containsKey(id) && session.expires.isAfter(DateTime.now()),
          );
          _qr.remove(id);
          return {'state': 'success', 'accounts': _summary()};
        }
        if (code == 86038) {
          _qr.remove(id);
          return {'state': 'expired'};
        }
        return {'state': code == 86090 ? 'scanned' : 'waiting'};
      } finally {
        _polling.remove(id);
      }
    }
    throw const FormatException('未知账号操作');
  }
}

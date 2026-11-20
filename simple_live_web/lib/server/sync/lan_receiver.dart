import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../accounts/account_service.dart';
import '../library/library_service.dart';

class LanSyncReceiver {
  LanSyncReceiver(this._library, this._accounts);

  final LibraryService _library;
  final AccountService _accounts;
  final Random _random = Random.secure();
  HttpServer? _server;
  Timer? _expiry;
  String? _token;
  DateTime? _expiresAt;

  Future<Map<String, dynamic>> control(Map<String, dynamic> body) async {
    switch (body['action']) {
      case 'status':
        return _status();
      case 'start':
        return _start();
      case 'stop':
        await _stop();
        return {'status': true};
      default:
        throw const FormatException('未知局域网接收操作');
    }
  }

  Future<Map<String, dynamic>> _status() async {
    final server = _server;
    final token = _token;
    final expiresAt = _expiresAt;
    if (server == null || token == null || expiresAt == null) {
      return {'status': false};
    }
    if (!expiresAt.isAfter(DateTime.now())) {
      await _stop();
      return {'status': false};
    }
    return {
      'status': true,
      'port': server.port,
      'token': token,
      'addresses': await _localAddresses(),
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    };
  }

  Future<Map<String, dynamic>> _start() async {
    await _stop();
    HttpServer? server;
    for (var port = 23239; port <= 23248; port++) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        break;
      } on SocketException {
        // Another Web session may already own this port.
      }
    }
    server ??= await HttpServer.bind(InternetAddress.anyIPv4, 0);

    final token = base64UrlEncode(
      List<int>.generate(24, (_) => _random.nextInt(256)),
    ).replaceAll('=', '');
    _server = server;
    _token = token;
    final expiresAt = DateTime.now().add(const Duration(minutes: 10));
    _expiresAt = expiresAt;
    _expiry = Timer(const Duration(minutes: 10), () {
      if (identical(_server, server)) unawaited(_stop());
    });
    unawaited(_serve(server));
    final addresses = await _localAddresses();
    if (addresses.isEmpty) {
      await _stop();
      throw const FormatException('未检测到局域网 IPv4 地址，请连接网络后重试');
    }

    return {
      'status': true,
      'port': server.port,
      'token': token,
      'addresses': addresses,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
    };
  }

  Future<void> _stop() async {
    _expiry?.cancel();
    _expiry = null;
    _token = null;
    _expiresAt = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<List<String>> _localAddresses() async {
    final result = <String>{};
    for (final interface in await NetworkInterface.list()) {
      for (final address in interface.addresses) {
        if (_isPrivateV4(address) && !address.isLoopback) {
          result.add(address.address);
        }
      }
    }
    return result.toList()..sort();
  }

  bool _isPrivateV4(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    if (address.isLoopback) return true;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request, server));
    }
  }

  Future<void> _handle(HttpRequest request, HttpServer server) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.headers.set('Cache-Control', 'no-store');
    var status = HttpStatus.ok;
    Object result = {'status': true};
    try {
      if (!identical(_server, server)) {
        throw const _ReceiverError(HttpStatus.gone, '接收服务已关闭');
      }
      final remote = request.connectionInfo?.remoteAddress;
      if (remote == null || !_isPrivateV4(remote)) {
        throw const _ReceiverError(HttpStatus.forbidden, '仅允许局域网连接');
      }
      if (request.method == 'GET' && request.uri.path == '/info') {
        result = {
          'id': 'simple-live-web',
          'type': 'web',
          'name': 'Simple Live Web',
          'version': '1',
          'address': (await _localAddresses()).join(';'),
          'port': server.port,
        };
      } else {
        if (request.method != 'POST') {
          throw const _ReceiverError(HttpStatus.methodNotAllowed, '不支持的请求方法');
        }
        final supplied = request.headers.value('x-simple-live-token') ?? '';
        if (supplied.isEmpty || supplied != _token) {
          throw const _ReceiverError(HttpStatus.unauthorized, '配对码无效或已过期');
        }
        final payload = await _readJson(request);
        final overlay = request.uri.queryParameters['overlay'] == '1';
        await _receive(request.uri.path, payload, overlay);
      }
    } on _ReceiverError catch (error) {
      status = error.status;
      result = {'status': false, 'message': error.message};
    } on LibraryConflict {
      status = HttpStatus.conflict;
      result = {'status': false, 'message': '数据已变化，请重新同步'};
    } on FormatException catch (error) {
      status = HttpStatus.badRequest;
      result = {'status': false, 'message': error.message};
    } on HttpException catch (error) {
      status = HttpStatus.badRequest;
      result = {'status': false, 'message': error.message};
    } on FileSystemException {
      status = HttpStatus.internalServerError;
      result = {'status': false, 'message': '本地数据写入失败'};
    } catch (_) {
      status = HttpStatus.internalServerError;
      result = {'status': false, 'message': '同步失败，请检查本地数据和网络'};
    }
    response.statusCode = status;
    response.write(jsonEncode(result));
    await response.close();
  }

  Future<Object?> _readJson(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > 20 * 1024 * 1024) {
        throw const FormatException('同步数据不能超过 20 MB');
      }
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes));
  }

  Future<void> _receive(String path, Object? payload, bool overlay) async {
    switch (path) {
      case '/sync/follow':
        return _receiveLibrary('follows', payload, overlay);
      case '/sync/tag':
        return _receiveLibrary('tags', payload, overlay);
      case '/sync/history':
        return _receiveLibrary('histories', payload, overlay);
      case '/sync/blocked_word':
        return _receiveLibrary('blocked', payload, overlay);
      case '/sync/account/bilibili':
        return _receiveAccount('bilibili', 'cookie', payload);
      case '/sync/account/douyu':
        return _receiveAccount('douyu', 'auth', payload);
      default:
        throw const _ReceiverError(HttpStatus.notFound, '不支持的数据类型');
    }
  }

  Future<void> _receiveLibrary(
    String field,
    Object? payload,
    bool overlay,
  ) async {
    final normalized = validateLibrary({
      'follows': field == 'follows' ? payload : <Object?>[],
      'tags': field == 'tags' ? payload : <Object?>[],
      'histories': field == 'histories' ? payload : <Object?>[],
      'blocked': field == 'blocked' ? payload : <Object?>[],
    });
    final current = await _library.read();
    if (current['error'] != null || current['data'] is! Map<String, dynamic>) {
      throw const FormatException('本地数据不可用，请先检查数据文件');
    }
    final oldData = Map<String, dynamic>.from(current['data'] as Map);
    final next = Map<String, dynamic>.from(oldData);
    final incoming = normalized[field] as List<dynamic>;

    if (field == 'follows') {
      next[field] = overlay ? incoming : _mergeById(oldData[field], incoming);
    } else if (field == 'tags') {
      next[field] = overlay ? incoming : _mergeTags(oldData[field], incoming);
    } else if (field == 'histories') {
      next[field] = overlay
          ? incoming
          : _mergeHistories(oldData[field], incoming);
    } else {
      next[field] = overlay
          ? incoming
          : {
              ...(oldData[field] as List).cast<String>(),
              ...incoming.cast<String>(),
            }.toList();
    }

    await _library.write({'revision': current['revision'], 'data': next});
  }

  List<Map<String, dynamic>> _mergeById(
    Object? current,
    List<dynamic> incoming,
  ) {
    final merged = <String, Map<String, dynamic>>{
      for (final item in (current as List).cast<Map<String, dynamic>>())
        item['id'] as String: item,
    };
    for (final item in incoming.cast<Map<String, dynamic>>()) {
      merged[item['id'] as String] = item;
    }
    return merged.values.toList();
  }

  List<Map<String, dynamic>> _mergeTags(
    Object? current,
    List<dynamic> incoming,
  ) {
    final merged = <String, Map<String, dynamic>>{
      for (final item in (current as List).cast<Map<String, dynamic>>())
        item['id'] as String: item,
    };
    for (final item in incoming.cast<Map<String, dynamic>>()) {
      final id = item['id'] as String;
      final old = merged[id];
      merged[id] = old == null
          ? item
          : {
              ...item,
              'userId': {
                ...(old['userId'] as List).cast<String>(),
                ...(item['userId'] as List).cast<String>(),
              }.toSet().toList(),
            };
    }
    return merged.values.toList();
  }

  List<Map<String, dynamic>> _mergeHistories(
    Object? current,
    List<dynamic> incoming,
  ) {
    final merged = <String, Map<String, dynamic>>{
      for (final item in (current as List).cast<Map<String, dynamic>>())
        item['id'] as String: item,
    };
    for (final item in incoming.cast<Map<String, dynamic>>()) {
      final id = item['id'] as String;
      final old = merged[id];
      if (old == null ||
          DateTime.parse(
            item['updateTime'] as String,
          ).isAfter(DateTime.parse(old['updateTime'] as String))) {
        merged[id] = item;
      }
    }
    return merged.values.toList();
  }

  Future<void> _receiveAccount(
    String site,
    String field,
    Object? payload,
  ) async {
    if (payload is! Map<String, dynamic> ||
        payload[field] is! String ||
        (payload[field] as String).length > 50000) {
      throw const FormatException('账号数据格式无效');
    }
    final snapshot = await _accounts.summary();
    await _accounts.handle({
      'action': 'save',
      'revision': snapshot['revision'],
      'site': site,
      'credential': payload[field],
    });
  }
}

class _ReceiverError implements Exception {
  const _ReceiverError(this.status, this.message);

  final int status;
  final String message;
}

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../network.dart';
import '../accounts/account_service.dart';

Future<Map<String, dynamic>> webdav(Map<String, dynamic> body) async {
  final base = Uri.tryParse(body['url'] as String? ?? '');
  if (base == null ||
      !['http', 'https'].contains(base.scheme) ||
      base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment) {
    throw const FormatException('请输入有效的 WebDAV 根地址');
  }
  final authorization =
      'Basic ${base64Encode(utf8.encode('${body['username'] ?? ''}:${body['password'] ?? ''}'))}';
  final root = base.replace(
    path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/simple_live_app',
  );
  final backup = root.replace(path: '${root.path}/backup.zip');
  Future<Response<dynamic>> send(
    String method,
    Uri url, {
    Object? data,
    Map<String, String>? extra,
  }) => network.request<dynamic>(
    url.toString(),
    data: data,
    options: Options(
      method: method,
      responseType: ResponseType.stream,
      headers: {'Authorization': authorization, ...?extra},
    ),
  );

  final action = body['action'];
  if (action == 'check') {
    final response = await send('PROPFIND', base, extra: {'Depth': '0'});
    await discard(response);
    requireSuccess(response);
    return {'status': true};
  }
  if (action == 'download') {
    final response = await send('GET', backup);
    if (response.statusCode == 404) {
      await discard(response);
      return {'missing': true};
    }
    if ((response.statusCode ?? 0) >= 300) {
      await discard(response);
      requireSuccess(response);
    }
    final bytes = await limitedBytes(response);
    return {
      'data': base64Encode(bytes),
      'etag': response.headers.value('etag'),
    };
  }
  if (action == 'upload') {
    final bytes = base64Decode(body['data'] as String);
    if (bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('备份不能超过 20 MB');
    }
    final mkdir = await send('MKCOL', root);
    await discard(mkdir);
    if (mkdir.statusCode != 405) requireSuccess(mkdir);
    final etag = body['etag'] as String?;
    final response = await send(
      'PUT',
      backup,
      data: Stream.value(bytes),
      extra: {
        'Content-Type': 'application/zip',
        'Content-Length': '${bytes.length}',
        if (body['missing'] == true) 'If-None-Match': '*',
        if (etag != null && etag.isNotEmpty && !etag.startsWith('W/'))
          'If-Match': etag,
      },
    );
    await discard(response);
    requireSuccess(response);
    return {'status': true};
  }
  throw const FormatException('未知同步操作');
}

Future<void> discard(Response<dynamic> response) async {
  await (response.data as ResponseBody).stream.listen(null).cancel();
}

Future<List<int>> limitedBytes(Response<dynamic> response) async {
  final bytes = <int>[];
  await for (final chunk in (response.data as ResponseBody).stream.timeout(
    const Duration(seconds: 30),
  )) {
    if (bytes.length + chunk.length > 20 * 1024 * 1024) {
      throw const FormatException('备份不能超过 20 MB');
    }
    bytes.addAll(chunk);
  }
  return bytes;
}

void requireSuccess(Response<dynamic> response) {
  final code = response.statusCode ?? 0;
  if (code < 200 || code >= 300) {
    throw HttpException(switch (code) {
      401 || 403 => '认证失败或没有访问权限',
      404 => '远端文件或目录不存在',
      412 => '远端备份已变化，请重新同步',
      >= 300 && < 400 => '服务返回重定向，请使用最终的 WebDAV 地址',
      _ => '远端请求失败（HTTP $code）',
    });
  }
}

Future<Object> device(
  Map<String, dynamic> body,
  AccountService accounts,
) async {
  final address = InternetAddress.tryParse(body['address'] as String? ?? '');
  if (address == null || address.type != InternetAddressType.IPv4) {
    throw const FormatException('请输入设备的 IPv4 地址');
  }
  final octets = address.rawAddress;
  if (!(octets[0] == 10 ||
      octets[0] == 127 ||
      (octets[0] == 192 && octets[1] == 168) ||
      (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31))) {
    throw const FormatException('仅支持本机或局域网设备');
  }
  final kind = body['kind'];
  if (![
    'info',
    'follow',
    'tag',
    'history',
    'blocked_word',
    'account/bilibili',
    'account/douyu',
  ].contains(kind)) {
    throw const FormatException('不支持的数据类型');
  }
  final uri = Uri(
    scheme: 'http',
    host: address.address,
    port: 23234,
    path: kind == 'info' ? '/info' : '/sync/$kind',
    queryParameters: kind == 'info'
        ? null
        : {'overlay': body['overlay'] == true ? '1' : '0'},
  );
  Object? payload = body['data'];
  if (kind == 'account/bilibili' || kind == 'account/douyu') {
    final site = (kind as String).split('/').last;
    final saved = await accounts.export(body['revision'], [site]);
    payload = {site == 'bilibili' ? 'cookie' : 'auth': saved[site]};
  }
  final response = await network.request<dynamic>(
    uri.toString(),
    data: kind == 'info' ? null : jsonEncode(payload),
    options: Options(
      method: kind == 'info' ? 'GET' : 'POST',
      responseType: ResponseType.stream,
      headers: {'Content-Type': 'application/json'},
    ),
  );
  if ((response.statusCode ?? 0) >= 300) {
    await discard(response);
    requireSuccess(response);
  }
  final result = jsonDecode(utf8.decode(await limitedBytes(response)));
  if (result is! Map || (kind != 'info' && result['status'] != true)) {
    throw const HttpException('设备拒绝同步，部分数据可能已传输');
  }
  return kind == 'info'
      ? {
          'name': result['name'],
          'type': result['type'],
          'version': result['version'],
        }
      : {'status': true};
}

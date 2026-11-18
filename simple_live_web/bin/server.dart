import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';

const maxBody = 28 * 1024 * 1024;
final sites = <String, LiveSite>{
  'bilibili': BiliBiliSite(),
  'douyu': DouyuSite(),
  'huya': HuyaSite(),
  'douyin': DouyinSite(),
};
final network = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
    followRedirects: false,
    validateStatus: (_) => true,
  ),
);

Future<void> main() async {
  CoreLog.enableLog = false;
  CoreLog.requestLogType = RequestLogType.none;
  final port = int.parse(Platform.environment['PORT'] ?? '23236');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Simple Live Web: http://127.0.0.1:$port');
  await for (final request in server) {
    unawaited(handle(request));
  }
}

Future<void> handle(HttpRequest request) async {
  final response = request.response;
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('Referrer-Policy', 'no-referrer');
  response.headers.set('Cache-Control', 'no-store');
  try {
    // Loopback binding alone does not prevent DNS rebinding or cross-site writes.
    final host = request.headers.value('host')?.split(':').first;
    if (host != '127.0.0.1' && host != 'localhost') {
      throw const HttpException('不允许的访问来源');
    }
    final origin = request.headers.value('origin');
    if (origin != null) {
      final uri = Uri.tryParse(origin);
      if (uri == null ||
          !['127.0.0.1', 'localhost'].contains(uri.host) ||
          uri.scheme != 'http') {
        throw const HttpException('不允许跨站访问本地服务');
      }
    }
    if (!request.uri.path.startsWith('/api/')) {
      await serveStatic(request);
      return;
    }
    if (request.headers.value('x-simple-live') != 'web') {
      throw const HttpException('缺少请求标识');
    }
    Object result;
    if (request.method == 'GET') {
      result = await readApi(request.uri).timeout(const Duration(seconds: 90));
    } else if (request.method == 'POST') {
      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 30))) {
        if (bytes.length + chunk.length > maxBody) {
          throw const FormatException('请求数据过大');
        }
        bytes.addAll(chunk);
      }
      final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      result = switch (request.uri.path) {
        '/api/webdav' => await webdav(body),
        '/api/device' => await device(body),
        _ => throw const FormatException('接口不存在'),
      };
    } else {
      throw const FormatException('不支持的请求方法');
    }
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(result));
  } catch (error) {
    response.statusCode = error is FormatException ? 400 : 502;
    response.headers.contentType = ContentType.json;
    // Never echo upstream URLs, credentials, or private response bodies.
    final message = switch (error) {
      FormatException e => e.message,
      HttpException e => e.message,
      TimeoutException _ => '请求超时，请重试',
      _ => '请求失败，请检查网络、连接配置或平台访问限制',
    };
    response.write(jsonEncode({'error': message}));
  } finally {
    await response.close();
  }
}

Future<Object> readApi(Uri uri) async {
  if (uri.path == '/api/health') return {'status': true, 'version': '0.1.0'};
  final q = uri.queryParameters;
  final site = sites[q['site']];
  if (site == null) throw const FormatException('未知直播平台');
  if (const bool.fromEnvironment('SIMPLE_LIVE_NO_NATIVE') &&
      q['site'] == 'douyin' &&
      uri.path == '/api/rooms') {
    throw const HttpException('抖音推荐及分类直播需要 QuickJS 原生运行库，请使用完整模式启动服务');
  }
  final page = int.tryParse(q['page'] ?? '1') ?? 1;
  if (page < 1 || page > 1000) throw const FormatException('页码超出范围');
  if (uri.path == '/api/categories') {
    return (await site.getCategores())
        .map(
          (group) => {
            'id': group.id,
            'name': group.name,
            'children': group.children
                .map(
                  (sub) => {
                    'id': sub.id,
                    'name': sub.name,
                    'parentId': sub.parentId,
                    'pic': sub.pic,
                  },
                )
                .toList(),
          },
        )
        .toList();
  }
  List<LiveRoomItem> rooms;
  bool hasMore;
  if (uri.path == '/api/search') {
    final keyword = (q['q'] ?? '').trim();
    if (keyword.isEmpty || keyword.length > 100) {
      throw const FormatException('搜索内容长度须为 1 至 100 字');
    }
    final result = await site.searchRooms(keyword, page: page);
    rooms = result.items;
    hasMore = result.hasMore;
  } else if (uri.path == '/api/rooms') {
    final category = q['category'];
    final result = category == null
        ? await site.getRecommendRooms(page: page)
        : await site.getCategoryRooms(
            LiveSubCategory(
              id: category,
              parentId: q['parent'] ?? '',
              name: '',
            ),
            page: page,
          );
    rooms = result.items;
    hasMore = result.hasMore;
  } else {
    throw const FormatException('接口不存在');
  }
  return {
    'hasMore': hasMore,
    'items': rooms
        .map(
          (room) => {
            'roomId': room.roomId,
            'siteId': site.id,
            'title': room.title,
            'cover': room.cover,
            'userName': room.userName,
            'online': room.online,
          },
        )
        .toList(),
  };
}

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

Future<Object> device(Map<String, dynamic> body) async {
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
  if (!['info', 'follow', 'tag', 'history', 'blocked_word'].contains(kind)) {
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
  final response = await network.request<dynamic>(
    uri.toString(),
    data: kind == 'info' ? null : jsonEncode(body['data']),
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

Future<void> serveStatic(HttpRequest request) async {
  if (request.method != 'GET') throw const FormatException('不支持的请求方法');
  final segments = request.uri.pathSegments;
  if (segments.any(
    (s) => s == '..' || s.contains('/') || s.contains('\\') || s.contains(':'),
  )) {
    throw const FormatException('无效文件路径');
  }
  final path = segments.where((s) => s.isNotEmpty).join('/');
  final file = File('dist/${path.isEmpty ? 'index.html' : path}');
  if (!await file.exists()) {
    request.response.statusCode = 404;
    request.response.write('Not found. Run npm run build first.');
    return;
  }
  final extension = file.path.split('.').last;
  request.response.headers.contentType = ContentType.parse(switch (extension) {
    'html' => 'text/html; charset=utf-8',
    'js' => 'application/javascript; charset=utf-8',
    'css' => 'text/css; charset=utf-8',
    'png' => 'image/png',
    'svg' => 'image/svg+xml',
    _ => 'application/octet-stream',
  });
  await request.response.addStream(file.openRead());
}

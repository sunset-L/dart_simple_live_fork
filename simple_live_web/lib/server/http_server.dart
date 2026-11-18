import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_quickjs/dart_quickjs.dart';
import 'package:simple_live_core/simple_live_core.dart';

import 'accounts/account_service.dart';
import 'danmaku/danmaku_service.dart';
import 'library/library_service.dart';
import 'playback/playback_service.dart';
import 'routes/catalog_routes.dart';
import 'routes/live_status_routes.dart';
import 'routes/playback_routes.dart';
import 'routes/static_routes.dart';
import 'settings/preferences_service.dart';
import 'sync/sync_service.dart';

const maxBody = 28 * 1024 * 1024;
final sites = <String, LiveSite>{
  'bilibili': BiliBiliSite(),
  'douyu': DouyuSite(),
  'huya': HuyaSite(),
  'douyin': DouyinSite(),
};
final playback = PlaybackService(sites);
final accounts = AccountService(sites, playback.invalidate);
final playbackRoutes = PlaybackRoutes(playback);
final danmaku = DanmakuService(playback);
final library = LibraryService();
final preferences = PreferencesService();
final liveStatuses = LiveStatusRoutes(sites);

Future<void> main() async {
  CoreLog.enableLog = false;
  CoreLog.requestLogType = RequestLogType.none;
  if (!const bool.fromEnvironment('SIMPLE_LIVE_NO_NATIVE')) {
    try {
      final runtime = JsRuntime();
      runtime.dispose();
    } catch (error) {
      stderr.writeln('QuickJS 运行库初始化失败，服务未启动：$error');
      exitCode = 1;
      return;
    }
  }
  final port = int.parse(Platform.environment['PORT'] ?? '23236');
  try {
    await accounts.refresh();
  } catch (_) {
    stderr.writeln('账号数据读取失败，请在账号管理中检查本地数据文件');
  }
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Simple Live Web: http://127.0.0.1:$port');
  await for (final request in server) {
    unawaited(handle(request));
  }
}

Future<void> handle(HttpRequest request) async {
  final response = request.response;
  var upgraded = false;
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
      if (request.uri.path == '/ws/danmaku') {
        await accounts.refresh();
        final socket = await WebSocketTransformer.upgrade(request);
        upgraded = true;
        await danmaku.serve(socket, request.uri);
        return;
      }
      await serveStatic(request);
      return;
    }
    final proxyMatch = RegExp(
      r'^/api/playback/proxy/([A-Za-z0-9_-]{20,64})$',
    ).firstMatch(request.uri.path);
    if (proxyMatch != null && request.method == 'GET') {
      await playbackRoutes.proxy(request, proxyMatch.group(1)!);
      return;
    }
    if (request.headers.value('x-simple-live') != 'web') {
      throw const HttpException('缺少请求标识');
    }
    Object result;
    if (request.method == 'GET') {
      if (request.uri.path == '/api/health') {
        result = {
          'status': true,
          'native': !const bool.fromEnvironment('SIMPLE_LIVE_NO_NATIVE'),
        };
      } else if (request.uri.path == '/api/library') {
        result = await library.read();
      } else if (request.uri.path == '/api/preferences') {
        result = await preferences.read();
      } else if (request.uri.path == '/api/accounts') {
        result = await accounts.summary();
      } else if (request.uri.path == '/api/live-status') {
        await accounts.refresh();
        result = await liveStatuses.read(request.uri);
      } else if (request.uri.path.startsWith('/api/playback/')) {
        await accounts.refresh();
        result = await playbackRoutes
            .read(request.uri)
            .timeout(const Duration(seconds: 90));
      } else {
        await accounts.refresh();
        result = await readCatalogApi(
          request.uri,
          sites,
        ).timeout(const Duration(seconds: 90));
      }
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
        '/api/library' => await library.write(body),
        '/api/preferences' => await preferences.write(body),
        '/api/accounts' => await accounts.handle(body),
        '/api/webdav' => await webdav(body),
        '/api/device' => await device(body, accounts),
        _ => throw const FormatException('接口不存在'),
      };
    } else {
      throw const FormatException('不支持的请求方法');
    }
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(result));
  } catch (error) {
    if (upgraded) return;
    response.statusCode = error is LibraryConflict
        ? 409
        : error is FormatException
        ? 400
        : 502;
    response.headers.contentType = ContentType.json;
    // Never echo upstream URLs, credentials, or private response bodies.
    final message = switch (error) {
      LibraryConflict _ => '数据已在其他页面更新，请重新执行操作',
      FileSystemException _ => '本地数据文件读写失败，请检查数据目录权限和磁盘空间',
      FormatException e => e.message,
      HttpException e => e.message,
      TimeoutException _ => '请求超时，请重试',
      _ => '请求失败，请检查网络、连接配置或平台访问限制',
    };
    response.write(jsonEncode({'error': message}));
  } finally {
    if (!upgraded) await response.close();
  }
}

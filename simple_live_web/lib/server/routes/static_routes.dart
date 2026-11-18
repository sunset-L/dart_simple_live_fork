import 'dart:io';

Future<void> serveStatic(HttpRequest request) async {
  if (Platform.environment['SIMPLE_LIVE_SERVE_STATIC'] != '1') {
    request.response.statusCode = 404;
    request.response.headers.contentType = ContentType.text;
    request.response.write('这是 API 服务，请使用前端开发地址。');
    return;
  }
  if (request.method != 'GET') throw const FormatException('不支持的请求方法');
  final segments = request.uri.pathSegments;
  if (segments.any(
    (s) => s == '..' || s.contains('/') || s.contains('\\') || s.contains(':'),
  )) {
    throw const FormatException('无效文件路径');
  }
  final path = segments.where((s) => s.isNotEmpty).join('/');
  final isPlayback = RegExp(
    r'^(live|playback)/(bilibili|douyu|huya|douyin)/[A-Za-z0-9_-]{1,100}$',
  ).hasMatch(path);
  final file = File('dist/${path.isEmpty || isPlayback ? 'index.html' : path}');
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

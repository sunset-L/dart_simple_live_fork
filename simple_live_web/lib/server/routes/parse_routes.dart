import 'dart:async';
import 'dart:io';

const _roomIdPattern = r'^[A-Za-z0-9_-]{1,100}$';

Future<Map<String, String>> parseLiveLink(Uri requestUri) async {
  final value = requestUri.queryParameters['url']?.trim() ?? '';
  if (value.isEmpty || value.length > 2000) {
    throw const FormatException('直播链接不能为空且长度不能超过 2000 个字符');
  }
  final direct = _parseDirect(Uri.tryParse(value));
  if (direct != null) return direct;
  final input = Uri.tryParse(value);
  if (input == null || !_isShortHost(input)) {
    throw const FormatException('无法解析直播链接');
  }
  final resolved = await _resolveRedirect(input);
  final result = _parseDirect(resolved);
  if (result == null) throw const FormatException('无法解析直播链接');
  return result;
}

Map<String, String>? _parseDirect(Uri? uri) {
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
  final first = segments.isEmpty ? '' : segments.first;
  if (_isHost(host, 'bilibili.com') && _validRoomId(first)) {
    return {'site': 'bilibili', 'roomId': first};
  }
  if (_isHost(host, 'douyu.com')) {
    final roomId = segments.isNotEmpty && segments.first == 'topic'
        ? uri.queryParameters['rid'] ?? ''
        : first;
    if (_validRoomId(roomId)) return {'site': 'douyu', 'roomId': roomId};
  }
  if (_isHost(host, 'huya.com') && _validRoomId(first)) {
    return {'site': 'huya', 'roomId': first};
  }
  if (host == 'live.douyin.com' && _validRoomId(first)) {
    return {'site': 'douyin', 'roomId': first};
  }
  if (host == 'webcast.amemv.com') {
    final match = RegExp(r'/reflow/([0-9]+)').firstMatch(uri.path);
    if (match != null) return {'site': 'douyin', 'roomId': match.group(1)!};
  }
  return null;
}

bool _isHost(String host, String domain) =>
    host == domain || host.endsWith('.$domain');

bool _validRoomId(String value) => RegExp(_roomIdPattern).hasMatch(value);

bool _isShortHost(Uri uri) =>
    (uri.host == 'b23.tv' || uri.host == 'v.douyin.com') &&
    (uri.scheme == 'http' || uri.scheme == 'https');

Future<Uri> _resolveRedirect(Uri start) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  var current = start;
  try {
    for (var index = 0; index < 5; index++) {
      final request = await client
          .getUrl(current)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'Simple-Live-Web');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null ||
          response.statusCode < 300 ||
          response.statusCode >= 400) {
        return current;
      }
      final next = current.resolve(location);
      if (next.scheme != 'http' && next.scheme != 'https') {
        throw const FormatException('直播链接重定向地址无效');
      }
      current = next;
    }
  } finally {
    client.close(force: true);
  }
  throw const FormatException('直播链接重定向次数过多');
}

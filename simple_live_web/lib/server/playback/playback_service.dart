import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:simple_live_core/simple_live_core.dart';

class PlaybackService {
  PlaybackService(this.sites);
  final Map<String, LiveSite> sites;
  final _rooms = <String, ({LiveRoomDetail detail, DateTime time})>{};
  final _pending = <String, Future<LiveRoomDetail>>{};
  final _targets =
      <String, ({String url, Map<String, String> headers, DateTime expires})>{};
  final _random = Random.secure();

  LiveSite site(String id) {
    if (!{'bilibili', 'douyu', 'huya', 'douyin'}.contains(id)) {
      throw const FormatException('本版暂不支持该平台播放');
    }
    if ({'douyu', 'douyin'}.contains(id) &&
        const bool.fromEnvironment('SIMPLE_LIVE_NO_NATIVE')) {
      throw const HttpException('斗鱼和抖音播放需要 QuickJS，请使用 npm run server 启动完整模式');
    }
    return sites[id]!;
  }

  Future<LiveRoomDetail> detail(
    String id,
    String roomId, {
    bool fresh = false,
  }) async {
    final platform = site(id);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(roomId)) {
      throw const FormatException('房间号格式无效');
    }
    final key = '$id:$roomId';
    final pending = _pending[key];
    if (pending != null) return pending;
    final cached = _rooms[key];
    if (!fresh &&
        cached != null &&
        DateTime.now().difference(cached.time).inSeconds < 30) {
      return cached.detail;
    }
    if (_pending.length >= 20) throw const HttpException('正在处理过多请求，请稍后重试');
    final future = platform
        .getRoomDetail(roomId: roomId)
        .timeout(const Duration(seconds: 60));
    _pending[key] = future;
    try {
      final value = await future;
      if (_rooms.length >= 100) _rooms.remove(_rooms.keys.first);
      _rooms[key] = (detail: value, time: DateTime.now());
      return value;
    } finally {
      _pending.remove(key);
    }
  }

  Future<Map<String, dynamic>> room(String siteId, String roomId) async {
    final value = await detail(siteId, roomId, fresh: true);
    return {
      'roomId': roomId,
      'canonicalRoomId': value.roomId,
      'siteId': siteId,
      'title': value.title,
      'cover': value.cover,
      'userName': value.userName,
      'userAvatar': value.userAvatar,
      'online': value.online,
      'status': value.status,
      'url': value.url,
      'notice': value.notice,
    };
  }

  Future<List<LivePlayQuality>> qualities(String id, String room) async {
    final value = await detail(id, room);
    if (!value.status) return [];
    return site(id).getPlayQualites(detail: value);
  }

  // Only upstream-derived URLs enter this bounded registry, never client URLs.
  String registerProxy(String url, Map<String, String>? headers) {
    final uri = Uri.parse(url);
    if (!{'https', 'http'}.contains(uri.scheme) || uri.userInfo.isNotEmpty) {
      throw const FormatException('不支持的播放协议');
    }
    final now = DateTime.now();
    _targets.removeWhere((_, value) => value.expires.isBefore(now));
    for (final entry in _targets.entries) {
      final existing = entry.value;
      if (existing.url == url &&
          existing.headers.length == (headers?.length ?? 0) &&
          existing.headers.entries.every(
            (header) => headers?[header.key] == header.value,
          )) {
        proxyTarget(entry.key);
        return entry.key;
      }
    }
    if (_targets.length >= 10000) _targets.remove(_targets.keys.first);
    final token = base64UrlEncode(
      List.generate(24, (_) => _random.nextInt(256)),
    ).replaceAll('=', '');
    _targets[token] = (
      url: url,
      headers: Map<String, String>.of(headers ?? {}),
      expires: now.add(const Duration(minutes: 30)),
    );
    return token;
  }

  ({String url, Map<String, String> headers})? proxyTarget(String token) {
    final value = _targets[token];
    if (value == null || value.expires.isBefore(DateTime.now())) return null;
    _targets[token] = (
      url: value.url,
      headers: value.headers,
      expires: DateTime.now().add(const Duration(minutes: 30)),
    );
    return (url: value.url, headers: value.headers);
  }
}

Map<String, dynamic> qualityJson(int index, LivePlayQuality quality) => {
  'index': index,
  'quality': quality.quality,
  'sort': quality.sort,
};
String formatOf(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  if (path.contains('.m3u8')) return 'hls';
  if (path.contains('.flv')) return 'flv';
  return 'native';
}

Map<String, dynamic> liveMessageJson(LiveMessage value) {
  final sc = value.data is LiveSuperChatMessage
      ? value.data as LiveSuperChatMessage
      : null;
  return {
    'type': value.type.name,
    'userName': sc?.userName ?? value.userName,
    'message': sc?.message ?? value.message,
    'color': value.color.toString(),
    if (sc != null) 'price': sc.price,
    if (sc != null) 'endTime': sc.endTime.millisecondsSinceEpoch,
    if (value.type == LiveMessageType.online)
      'online': int.tryParse(value.data.toString()) ?? 0,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
}

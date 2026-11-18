import 'dart:io';

import 'package:simple_live_core/simple_live_core.dart';

class LiveStatusRoutes {
  LiveStatusRoutes(this.sites);
  final Map<String, LiveSite> sites;
  final _cache = <String, ({bool status, DateTime time})>{};
  final _pending = <String, Future<bool>>{};

  Future<Object> read(Uri uri) async {
    final siteId = uri.queryParameters['site'] ?? '';
    final roomId = uri.queryParameters['roomId'] ?? '';
    final site = sites[siteId];
    if (site == null) throw const FormatException('未知直播平台');
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(roomId)) {
      throw const FormatException('房间号格式无效');
    }
    final key = '$siteId:$roomId';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.time).inSeconds < 30) {
      return {'status': cached.status};
    }
    var future = _pending[key];
    if (future == null) {
      if (_pending.length >= 20) {
        throw const HttpException('状态查询过多，请稍后刷新');
      }
      future = _fetch(key, site, roomId);
      _pending[key] = future;
    }
    return {'status': await future};
  }

  Future<bool> _fetch(String key, LiveSite site, String roomId) async {
    try {
      final status = await site
          .getLiveStatus(roomId: roomId)
          .timeout(const Duration(seconds: 25));
      if (_cache.length >= 1000) _cache.remove(_cache.keys.first);
      _cache[key] = (status: status, time: DateTime.now());
      return status;
    } finally {
      _pending.remove(key);
    }
  }
}

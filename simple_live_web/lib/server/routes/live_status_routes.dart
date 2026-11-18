import 'dart:io';

import 'package:simple_live_core/simple_live_core.dart';

class LiveStatusRoutes {
  LiveStatusRoutes(this.sites);
  final Map<String, LiveSite> sites;
  final _cache = <String, ({bool status, DateTime time})>{};
  final _profiles = <String, ({Map<String, dynamic> data, DateTime time})>{};
  final _pending = <String, Future<Map<String, dynamic>>>{};

  Future<Object> read(Uri uri) async {
    final siteId = uri.queryParameters['site'] ?? '';
    final roomId = uri.queryParameters['roomId'] ?? '';
    final site = sites[siteId];
    if (site == null) throw const FormatException('未知直播平台');
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(roomId)) {
      throw const FormatException('房间号格式无效');
    }
    final key = '$siteId:$roomId';
    final withProfile = uri.queryParameters['profile'] == '1';
    final profile = _profiles[key];
    final metadata =
        profile != null &&
            DateTime.now().difference(profile.time).inMinutes < 10
        ? profile.data
        : null;
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.time).inSeconds < 30 &&
        (!withProfile || metadata != null)) {
      return {
        if (withProfile && metadata != null) ...metadata,
        'status': cached.status,
      };
    }
    final pendingKey = '$key:${withProfile && metadata == null}';
    var future = _pending[pendingKey];
    if (future == null) {
      if (_pending.length >= 20) {
        throw const HttpException('状态查询过多，请稍后刷新');
      }
      future = _fetch(
        key,
        pendingKey,
        site,
        roomId,
        withProfile: withProfile && metadata == null,
      );
      _pending[pendingKey] = future;
    }
    final result = await future;
    return {if (withProfile && metadata != null) ...metadata, ...result};
  }

  Future<Map<String, dynamic>> _fetch(
    String key,
    String pendingKey,
    LiveSite site,
    String roomId, {
    required bool withProfile,
  }) async {
    try {
      bool status;
      Map<String, dynamic>? metadata;
      if (withProfile) {
        try {
          metadata = await _profile(
            site,
            roomId,
          ).timeout(const Duration(seconds: 20));
          status = metadata['status'] as bool;
          final avatar = (metadata['face'] as String).trim();
          final uri = Uri.tryParse(
            avatar.startsWith('//') ? 'https:$avatar' : avatar,
          );
          if (uri != null &&
              {'http', 'https'}.contains(uri.scheme) &&
              uri.host.isNotEmpty) {
            metadata['face'] = uri.toString();
          } else {
            metadata.remove('face');
          }
          if (metadata.containsKey('face')) {
            if (_profiles.length >= 1000) {
              _profiles.remove(_profiles.keys.first);
            }
            _profiles[key] = (data: metadata, time: DateTime.now());
          }
        } catch (_) {
          // Missing profile data must not turn a known live state into a failure.
          status = await site
              .getLiveStatus(roomId: roomId)
              .timeout(const Duration(seconds: 25));
        }
      } else {
        status = await site
            .getLiveStatus(roomId: roomId)
            .timeout(const Duration(seconds: 25));
      }
      if (_cache.length >= 1000) _cache.remove(_cache.keys.first);
      _cache[key] = (status: status, time: DateTime.now());
      return {if (metadata != null) ...metadata, 'status': status};
    } finally {
      _pending.remove(pendingKey);
    }
  }

  Future<Map<String, dynamic>> _profile(LiveSite site, String roomId) async {
    if (site is BiliBiliSite) {
      // Public room metadata avoids requesting danmaku credentials for cards.
      final info = await site.getRoomInfo(roomId: roomId);
      final room = info['room_info'];
      final anchor = info['anchor_info']['base_info'];
      return {
        'status': int.tryParse(room['live_status'].toString()) == 1,
        'face': anchor['face']?.toString() ?? '',
        'title': room['title']?.toString() ?? '',
        'cover': room['cover']?.toString() ?? '',
        'online': int.tryParse(room['online'].toString()) ?? 0,
      };
    }
    final detail = await site.getRoomDetail(roomId: roomId);
    return {
      'status': detail.status,
      'face': detail.userAvatar,
      'title': detail.title,
      'cover': detail.cover,
      'online': detail.online,
    };
  }
}

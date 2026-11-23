import 'dart:io';
import 'package:simple_live_core/simple_live_core.dart';
import '../accounts/account_service.dart';
import '../playback/playback_service.dart';
import '../playback/media_proxy.dart';

class PlaybackRoutes {
  PlaybackRoutes(this.playback, this.accounts);
  final PlaybackService playback;
  final AccountService accounts;
  Future<Object> read(Uri uri) async {
    final query = uri.queryParameters;
    final site = query['site'] ?? '';
    final roomId = query['roomId'] ?? '';
    if (uri.path == '/api/playback/room') return playback.room(site, roomId);
    if (uri.path == '/api/playback/session') {
      final detail = await playback.detail(site, roomId, fresh: true);
      final siteApi = _playbackSite(site);
      final qualities = detail.status
          ? await siteApi.getPlayQualites(detail: detail)
          : <LivePlayQuality>[];
      final requestedName = query['qualityName'];
      final requestedSort = int.tryParse(query['sort'] ?? '0');
      final index = requestedName == null
          ? (qualities.isEmpty ? -1 : 0)
          : qualities.indexWhere(
              (item) =>
                  item.quality == requestedName && item.sort == requestedSort,
            );
      List<Map<String, dynamic>> sources = [];
      Map<String, dynamic>? authWarning;
      if (index >= 0) {
        final result = await siteApi.getPlayUrls(
          detail: detail,
          quality: qualities[index],
        );
        if (result.urls.isEmpty) {
          throw const HttpException('当前清晰度没有可用线路');
        }
        sources = _sourceJson(site, result);
        authWarning = await _authWarning(siteApi);
      }
      return {
        'detail': roomJson(site, roomId, detail),
        'qualities': qualities
            .asMap()
            .entries
            .map((entry) => qualityJson(entry.key, entry.value))
            .toList(),
        'quality': index < 0 ? null : qualityJson(index, qualities[index]),
        'sources': sources,
        if (authWarning != null) 'authWarning': authWarning,
      };
    }
    if (uri.path == '/api/playback/qualities') {
      final qualities = await playback.qualities(site, roomId);
      return {
        'items': qualities
            .asMap()
            .entries
            .map((e) => qualityJson(e.key, e.value))
            .toList(),
      };
    }
    if (uri.path != '/api/playback/source') {
      throw const FormatException('接口不存在');
    }
    final detail = await playback.detail(site, roomId, fresh: true);
    if (!detail.status) throw const HttpException('主播暂未开播');
    final siteApi = _playbackSite(site);
    final qualities = await siteApi.getPlayQualites(detail: detail);
    final qualityName = query['qualityName'];
    final sort = int.tryParse(query['sort'] ?? '0');
    final index = qualities.indexWhere(
      (item) => item.quality == qualityName && item.sort == sort,
    );
    if (index < 0) throw const HttpException('所选清晰度已不可用，请刷新后重新选择');
    final result = await siteApi.getPlayUrls(
      detail: detail,
      quality: qualities[index],
    );
    if (result.urls.isEmpty) throw const HttpException('当前清晰度没有可用线路');
    final authWarning = await _authWarning(siteApi);
    return {
      'quality': qualities[index].quality,
      'items': _sourceJson(site, result),
      if (authWarning != null) 'authWarning': authWarning,
    };
  }

  LiveSite _playbackSite(String id) {
    final platform = playback.site(id);
    // 每次取流使用独立实例，避免多直播页串用授权标记或临时匿名回退。
    return platform is DouyuSite
        ? (DouyuSite()..dyAuth = platform.dyAuth)
        : platform;
  }

  Future<Map<String, dynamic>?> _authWarning(LiveSite platform) async {
    if (platform is! DouyuSite || !platform.authNotEffective) return null;
    try {
      if (!await accounts.markDouyuInvalid(platform.dyAuth)) return null;
    } catch (_) {
      // 账号状态更新失败不能打断已经成功的取流，也不清除保存的票据。
    }
    final label = platform.lastQualityDowngraded
        ? platform.lastDowngradeLabel
        : '';
    final message = label.isNotEmpty
        ? '斗鱼未登录或票据已失效，当前为$label（登录后可看原画）'
        : platform.lastQualityDowngraded
        ? '斗鱼未登录或票据已失效，画质被降档且地址会定期失效（登录后可看原画）'
        : '斗鱼授权已失效，已用普通方式取流（画质与地址有效期会受限）';
    return {'code': 'douyu_auth_not_effective', 'message': message};
  }

  List<Map<String, dynamic>> _sourceJson(String site, LivePlayUrl result) {
    final now = DateTime.now();
    final headers = result.headers ?? {};
    return result.urls.toSet().toList().asMap().entries.map((entry) {
      final token = playback.registerProxy(entry.value, headers);
      return {
        'index': entry.key,
        'url': entry.value,
        'format': formatOf(entry.value),
        'direct': headers.isEmpty,
        'proxyUrl': '/api/playback/proxy/$token',
        'expiresAt': LiveStreamExpiry.expiresAt(
          entry.value,
          siteId: site,
          fetchedAt: now,
        )?.millisecondsSinceEpoch,
      };
    }).toList();
  }

  Future<void> proxy(HttpRequest request, String token) =>
      MediaProxy(playback).serve(request, token);
}

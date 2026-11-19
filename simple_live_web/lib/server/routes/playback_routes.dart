import 'dart:io';
import 'package:simple_live_core/simple_live_core.dart';
import '../playback/playback_service.dart';
import '../playback/media_proxy.dart';

class PlaybackRoutes {
  PlaybackRoutes(this.playback);
  final PlaybackService playback;
  Future<Object> read(Uri uri) async {
    final query = uri.queryParameters;
    final site = query['site'] ?? '';
    final roomId = query['roomId'] ?? '';
    if (uri.path == '/api/playback/room') return playback.room(site, roomId);
    if (uri.path == '/api/playback/session') {
      final detail = await playback.detail(site, roomId, fresh: true);
      final siteApi = playback.site(site);
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
      if (index >= 0) {
        final result = await siteApi.getPlayUrls(
          detail: detail,
          quality: qualities[index],
        );
        if (result.urls.isEmpty) {
          throw const HttpException('当前清晰度没有可用线路');
        }
        sources = _sourceJson(site, result);
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
    final qualities = await playback.site(site).getPlayQualites(detail: detail);
    final qualityName = query['qualityName'];
    final sort = int.tryParse(query['sort'] ?? '0');
    final index = qualities.indexWhere(
      (item) => item.quality == qualityName && item.sort == sort,
    );
    if (index < 0) throw const HttpException('所选清晰度已不可用，请刷新后重新选择');
    final result = await playback
        .site(site)
        .getPlayUrls(detail: detail, quality: qualities[index]);
    if (result.urls.isEmpty) throw const HttpException('当前清晰度没有可用线路');
    return {
      'quality': qualities[index].quality,
      'items': _sourceJson(site, result),
    };
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

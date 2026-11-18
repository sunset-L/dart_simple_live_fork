import 'dart:convert';
import 'dart:io';

import 'package:simple_live_core/simple_live_core.dart';

Future<Object> readCatalogApi(Uri uri, Map<String, LiveSite> sites) async {
  final q = uri.queryParameters;
  final site = sites[q['site']];
  if (site == null) throw const FormatException('未知直播平台');
  if (const bool.fromEnvironment('SIMPLE_LIVE_NO_NATIVE') &&
      q['site'] == 'douyin' &&
      uri.path == '/api/rooms') {
    throw const HttpException('抖音直播列表需要 QuickJS 原生运行库');
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
  final List<LiveRoomItem> rooms;
  final bool hasMore;
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

Map<String, dynamic> decodeJsonMap(String body) {
  final result = jsonDecode(body);
  if (result is! Map<String, dynamic>) throw const FormatException('请求数据格式无效');
  return result;
}

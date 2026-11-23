import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';

import '../network.dart';

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
    final result = site.id == 'douyu'
        ? await _readDouyuRooms(category, page)
        : category == null
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

Future<LiveCategoryResult> _readDouyuRooms(String? category, int page) async {
  final url = category == null
      ? 'https://www.douyu.com/japi/weblist/apinc/allpage/6/$page'
      : 'https://www.douyu.com/gapi/rkc/directory/mixList/2_${Uri.encodeComponent(category)}/$page';
  final response = await network.get<dynamic>(
    url,
    options: Options(
      responseType: ResponseType.json,
      followRedirects: true,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
      headers: {
        'referer': 'https://www.douyu.com/',
        'user-agent': DouyuSite.kUserAgent,
      },
    ),
  );
  final result = response.data;
  final data = result is Map ? result['data'] : null;
  if (data is! Map || data['rl'] is! List) {
    throw const HttpException('斗鱼直播列表返回了无效数据，请重试');
  }
  final rawItems = data['rl'] as List;
  final items = <LiveRoomItem>[];
  for (final item in rawItems) {
    if (item is! Map) {
      throw const HttpException('斗鱼直播列表返回了无效数据，请重试');
    }
    if (item['type'] != 1) continue;
    items.add(
      LiveRoomItem(
        cover: item['rs16'].toString(),
        online: int.tryParse('${item['ol']}') ?? 0,
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      ),
    );
  }
  final pageCount = int.tryParse('${data['pgcnt']}');
  // 斗鱼热门列表会在仍有下一页时返回 pgcnt=0，不能将它视为结束。
  // 使用过滤前的列表判断，避免只有非直播条目的页面提前终止分页。
  final hasMore =
      rawItems.isNotEmpty &&
      (pageCount == null || pageCount <= 0 || page < pageCount);
  return LiveCategoryResult(hasMore: hasMore, items: items);
}

Map<String, dynamic> decodeJsonMap(String body) {
  final result = jsonDecode(body);
  if (result is! Map<String, dynamic>) throw const FormatException('请求数据格式无效');
  return result;
}

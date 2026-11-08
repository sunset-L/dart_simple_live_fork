import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:simple_live_core/src/common/convert_helper.dart';
import 'package:simple_live_core/src/common/cookie_util.dart';
import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/bilibili_danmaku.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_message.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';

class BiliBiliSite implements LiveSite {
  @override
  String id = "bilibili";

  @override
  String name = "哔哩哔哩直播";

  String cookie = "";
  int userId = 0;

  @override
  LiveDanmaku getDanmaku() => BiliBiliDanmaku();

  static const String kDefaultUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0";
  static const String kDefaultReferer = "https://live.bilibili.com/";

  String buvid3 = "";
  String buvid4 = "";
  String accessId = "";
  Future<Map<String, String>> getHeader() async {
    // 统一做一次规范化：把换行/制表符清掉、每个值两侧 trim、丢掉空项。
    //
    // 这一步不是「锦上添花」，而是防 412 的硬要求：
    // 用户从浏览器复制出来的 cookie 常见形态是 `buvid3=xxx ; buvid4=yyy ;`，
    // 值尾部的空格会让 api.bilibili.com/x/web-interface/nav 直接返回
    // HTTP 412（风控拦截）。而 WBI 签名必须先请求 nav 拿 img_key/sub_key，
    // 于是整个取流链在 getRoomDetail 就断了，页面上表现为
    // 「直播间加载失败，错误码 412」，看起来像「登录了反而播不了」。
    final normalized = normalizeCookie(cookie);
    if (buvid3.isEmpty) {
      // 先尝试从 cookie 串里就地取值，避免多打一次接口
      buvid3 = cookieValue(normalized, "buvid3");
      buvid4 = cookieValue(normalized, "buvid4");
    }
    if (buvid3.isEmpty) {
      var buvidInfo = await getBuvid();
      buvid3 = buvidInfo["b_3"] ?? "";
      buvid4 = buvidInfo["b_4"] ?? "";
    }
    // buvid3/buvid4 本身也可能带脏空白（来自接口或用户输入）
    buvid3 = buvid3.trim();
    buvid4 = buvid4.trim();

    final fingerprint = <String>[
      if (buvid3.isNotEmpty) "buvid3=$buvid3",
      if (buvid4.isNotEmpty) "buvid4=$buvid4",
    ].join(';');

    // 已经带了有效 buvid3 就不要重复拼，重复的同名键会让服务端取第一个，
    // 而第一个有可能正是用户填的空值 `buvid3=`。
    final needAppend = buvid3.isNotEmpty && !hasCookieValue(normalized, "buvid3");

    String finalCookie;
    if (normalized.isEmpty) {
      finalCookie = fingerprint.isEmpty ? "" : "$fingerprint;";
    } else if (needAppend) {
      finalCookie = fingerprint.isEmpty
          ? normalized
          : "${normalized.endsWith(';') ? normalized : "$normalized;"}$fingerprint;";
    } else {
      finalCookie = normalized;
    }

    return {
      "user-agent": kDefaultUserAgent,
      "referer": kDefaultReferer,
      if (finalCookie.isNotEmpty) "cookie": finalCookie,
    };
  }

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getJson(
      "https://api.live.bilibili.com/room/v1/Area/getList",
      queryParameters: {
        "need_entrance": 1,
        "parent_id": 0,
      },
      header: await getHeader(),
    );
    for (var item in result["data"]) {
      List<LiveSubCategory> subs = [];
      for (var subItem in item["list"]) {
        var subCategory = LiveSubCategory(
          id: subItem["id"].toString(),
          name: asT<String?>(subItem["name"]) ?? "",
          parentId: asT<String?>(subItem["parent_id"]) ?? "",
          pic: "${asT<String?>(subItem["pic"]) ?? ""}@100w.png",
        );
        subs.add(subCategory);
      }
      var category = LiveCategory(
        children: subs,
        id: item["id"].toString(),
        name: asT<String?>(item["name"]) ?? "",
      );
      categories.add(category);
    }
    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category,
      {int page = 1}) async {
    const baseUrl =
        "https://api.live.bilibili.com/xlive/web-interface/v1/second/getList";

    var url =
        "$baseUrl?platform=web&parent_area_id=${category.parentId}&area_id=${category.id}&sort_type=&page=$page&w_webid=${await getAccessId()}";

    var result = await getJsonWithWbiSign(baseUrl, url);

    var hasMore = result["data"]["has_more"] == 1;
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["list"]) {
      var roomItem = LiveRoomItem(
        roomId: item["roomid"].toString(),
        title: item["title"].toString(),
        cover: "${item["cover"]}@400w.jpg",
        userName: item["uname"].toString(),
        online: int.tryParse(item["online"].toString()) ?? 0,
      );
      items.add(roomItem);
    }
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    List<LivePlayQuality> qualities = [];
    var result = await HttpClient.instance.getJson(
      "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
      queryParameters: {
        "room_id": detail.roomId,
        "protocol": "0,1",
        "format": "0,1,2",
        "codec": "0,1",
        "platform": "web",
      },
      header: await getHeader(),
    );
    final playUrlInfo = result["data"]?["playurl_info"];
    if (playUrlInfo is! Map) {
      // 房间未开播或不在播时没有 playurl_info，返回空列表让上层提示「无法读取清晰度」，
      // 不要在这里抛异常导致整个页面变成加载失败。
      return qualities;
    }
    var qualitiesMap = <int, String>{};
    final gQnDesc = playUrlInfo["playurl"]?["g_qn_desc"];
    if (gQnDesc is List) {
      for (var item in gQnDesc) {
        qualitiesMap[int.tryParse(item["qn"].toString()) ?? 0] =
            item["desc"].toString();
      }
    }

    // accept_qn 位于 stream[0].format[0].codec[0]，但不同房间的
    // 流结构不一定完全一致（例如只有 HLS 没有 FLV），逐层判空更稳。
    final acceptQn = _firstAcceptQn(playUrlInfo["playurl"]?["stream"]);
    for (var item in acceptQn) {
      var qualityItem = LivePlayQuality(
        quality: qualitiesMap[item] ?? "未知清晰度",
        data: item,
      );
      qualities.add(qualityItem);
    }
    return qualities;
  }

  /// 从 stream 结构里找出第一组 accept_qn
  List _firstAcceptQn(dynamic stream) {
    if (stream is! List) {
      return const [];
    }
    for (var streamItem in stream) {
      final formatList = streamItem["format"];
      if (formatList is! List) {
        continue;
      }
      for (var formatItem in formatList) {
        final codecList = formatItem["codec"];
        if (codecList is! List) {
          continue;
        }
        for (var codecItem in codecList) {
          final accept = codecItem["accept_qn"];
          if (accept is List && accept.isNotEmpty) {
            return accept;
          }
        }
      }
    }
    return const [];
  }

  /// 从接口返回里拼一句更具体的错误提示
  String _biliErrHint(Map result) {
    final code = result["code"];
    final msg = result["message"] ?? result["msg"] ?? "";
    if (code == null || code == 0) {
      return "";
    }
    return "（code=$code${msg.toString().isEmpty ? "" : "，$msg"}）";
  }

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    List<String> urls = [];
    var result = await HttpClient.instance.getJson(
      "https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo",
      queryParameters: {
        "room_id": detail.roomId,
        "protocol": "0,1",
        "format": "0,2",
        "codec": "0",
        "platform": "web",
        "qn": quality.data,
      },
      header: await getHeader(),
    );

    // 接口在某些情况下不返回 playurl_info（房间未开播、或该清晰度无权播放），
    // 原来这里直接下标取值，会抛「type 'Null' is not a subtype of type 'Map'」，
    // 用户看到的就是一个莫名的报错弹窗。这里给出可读的错误。
    final playUrlInfo = result["data"]?["playurl_info"];
    if (playUrlInfo is! Map) {
      throw CoreError("哔哩哔哩取流失败：该清晰度无法播放${_biliErrHint(result)}");
    }
    final streamList = playUrlInfo["playurl"]?["stream"];
    if (streamList is! List) {
      throw CoreError("哔哩哔哩取流失败：返回数据缺少 stream${_biliErrHint(result)}");
    }

    for (var streamItem in streamList) {
      var formatList = streamItem["format"];
      if (formatList is! List) {
        continue;
      }
      for (var formatItem in formatList) {
        var codecList = formatItem["codec"];
        if (codecList is! List) {
          continue;
        }
        for (var codecItem in codecList) {
          var urlList = codecItem["url_info"];
          if (urlList is! List) {
            continue;
          }
          var baseUrl = codecItem["base_url"]?.toString() ?? "";
          for (var urlItem in urlList) {
            urls.add(
              "${urlItem["host"]}$baseUrl${urlItem["extra"]}",
            );
          }
        }
      }
    }

    // 授权不足时接口会正常返回，但 url_info 是空的。
    // 这种情况必须报错，否则上层会拿到空列表并当成「无地址」处理，
    // 表现同样是「登录后反而播不了」。
    if (urls.isEmpty) {
      throw CoreError("哔哩哔哩取流失败：无可用地址（清晰度：${quality.quality}）");
    }
    // 对链接进行排序，包含mcdn的在后
    urls.sort((a, b) {
      if (a.contains("mcdn")) {
        return 1;
      } else {
        return -1;
      }
    });
    // 播放请求头必须带上登录 Cookie（以及设备指纹 buvid3/buvid4）。
    //
    // 这里原来只给了 referer 和 user-agent，没带 cookie，导致：
    // - 未登录时取到的都是 qn<=250 的公开流，不带 cookie 也能拉；
    // - 登录后选择原画/蓝光（qn=400/10000）时，播放地址带的是
    //   **与当前账号绑定**的鉴权参数，拉流时缺少 cookie 会被服务端拒绝，
    //   表现为「配置登录后进直播间就报错、不能播放」，
    //   而「不配置登录、播低清晰度反而正常」。
    //
    // 直接复用 [getHeader]：它已经处理好了两种登录态
    // （未登录带 buvid3/buvid4，登录额外带 SESSDATA），
    // 避免这里再维护一套同样的拼装逻辑而产生漂移。
    return LivePlayUrl(
      urls: urls,
      headers: await getHeader(),
    );
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    const baseUrl =
        "https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea";
    var url = "$baseUrl?platform=web&sort=online&page_size=30&page=$page";

    var result = await getJsonWithWbiSign(baseUrl, url);

    var hasMore = (result["data"]["list"] as List).isNotEmpty;
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["list"]) {
      var roomItem = LiveRoomItem(
        roomId: item["roomid"].toString(),
        title: item["title"].toString(),
        cover: "${item["cover"]}@400w.jpg",
        userName: item["uname"].toString(),
        online: int.tryParse(item["online"].toString()) ?? 0,
      );
      items.add(roomItem);
    }
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    var roomInfo = await getRoomInfo(roomId: roomId);
    var realRoomId = roomInfo["room_info"]["room_id"].toString();

    const danmuInfoBaseUrl =
        "https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo";
    var danmuInfoUrl = "$danmuInfoBaseUrl?id=$realRoomId";
    var roomDanmakuResult = await getJsonWithWbiSign(danmuInfoBaseUrl, danmuInfoUrl);
    List<String> serverHosts =
        (roomDanmakuResult["data"]?["host_list"] as List? ?? [])
            .map<String>((e) => e["host"].toString())
            .toList();

    //var buvid = await getBuvid();
    // 从 roomInfo 中提取 live_start_time
    String? liveStartTime =
        roomInfo["room_info"]?["live_start_time"]?.toString();

    // 计算开播时长并打印到控制台 (参考斗鱼的实现)
    if (liveStartTime != null &&
        liveStartTime.isNotEmpty &&
        liveStartTime != "0") {
      // 检查是否为0，0可能表示未开播或无此信息
      try {
        int startTimeStamp = int.parse(liveStartTime);
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        print('Bilibili直播间 $roomId 开播时长: $formattedDuration');
      } catch (e) {
        print('计算 Bilibili 开播时长出错: $e');
      }
    }

    return LiveRoomDetail(
      roomId: realRoomId,
      title: roomInfo["room_info"]["title"].toString(),
      cover: roomInfo["room_info"]["cover"].toString(),
      userName: roomInfo["anchor_info"]["base_info"]["uname"].toString(),
      userAvatar: "${roomInfo["anchor_info"]["base_info"]["face"]}@100w.jpg",
      online: asT<int?>(roomInfo["room_info"]["online"]) ?? 0,
      status: (asT<int?>(roomInfo["room_info"]["live_status"]) ?? 0) == 1,
      url: "https://live.bilibili.com/$roomId",
      introduction: roomInfo["room_info"]["description"].toString(),
      notice: "",
      danmakuData: BiliBiliDanmakuArgs(
        roomId: int.tryParse(realRoomId) ?? 0,
        uid: userId,
        token: roomDanmakuResult["data"]["token"].toString(),
        serverHost: serverHosts.isNotEmpty
            ? serverHosts.first
            : "broadcastlv.chat.bilibili.com",
        buvid: buvid3,
        cookie: cookie,
      ),
      showTime: liveStartTime, // 将 liveStartTime 赋值给 showTime 字段
    );
  }

  Future<Map<String, dynamic>> getRoomInfo({required String roomId}) async {
    const baseUrl =
        "https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom";
    var url = "$baseUrl?room_id=$roomId";
    var result = await getJsonWithWbiSign(baseUrl, url);
    // 原来直接 return result["data"]，接口报错时返回 null，
    // 上一层 `roomInfo["room_info"]` 就抛 Null 不是 Map 的 TypeError，
    // 真正的失败原因（code / message）被完全掩盖。这里显式报错。
    final data = result is Map ? result["data"] : null;
    if (data is! Map) {
      throw CoreError(
        "哔哩哔哩直播间信息获取失败${_biliErrHint(result is Map ? result : {})}",
      );
    }
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://api.bilibili.com/x/web-interface/search/type?context=&search_type=live&cover_type=user_cover",
      queryParameters: {
        "order": "",
        "keyword": keyword,
        "category_id": "",
        "__refresh__": "",
        "_extra": "",
        "highlight": 0,
        "single_column": 0,
        "page": page
      },
      header: await getHeader(),
    );

    var items = <LiveRoomItem>[];
    for (var item in result["data"]["result"]["live_room"] ?? []) {
      var title = item["title"].toString();
      //移除title中的<em></em>标签
      title = title.replaceAll(RegExp(r"<.*?em.*?>"), "");
      var roomItem = LiveRoomItem(
        roomId: item["roomid"].toString(),
        title: title,
        cover: "https:${item["cover"]}@400w.jpg",
        userName: item["uname"].toString(),
        online: int.tryParse(item["online"].toString()) ?? 0,
      );
      items.add(roomItem);
    }
    return LiveSearchRoomResult(hasMore: items.length >= 40, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://api.bilibili.com/x/web-interface/search/type?context=&search_type=live_user&cover_type=user_cover",
      queryParameters: {
        "order": "",
        "keyword": keyword,
        "category_id": "",
        "__refresh__": "",
        "_extra": "",
        "highlight": 0,
        "single_column": 0,
        "page": page
      },
      header: await getHeader(),
    );

    var items = <LiveAnchorItem>[];
    for (var item in result["data"]["result"] ?? []) {
      var uname = item["uname"].toString();
      //移除title中的<em></em>标签
      uname = uname.replaceAll(RegExp(r"<.*?em.*?>"), "");
      var anchorItem = LiveAnchorItem(
        roomId: item["roomid"].toString(),
        avatar: "https:${item["uface"]}@400w.jpg",
        userName: uname,
        liveStatus: item["is_live"],
      );
      items.add(anchorItem);
    }
    return LiveSearchAnchorResult(hasMore: items.length >= 40, items: items);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    var result = await HttpClient.instance.getJson(
      "https://api.live.bilibili.com/room/v1/Room/get_info",
      queryParameters: {
        "room_id": roomId,
      },
      header: await getHeader(),
    );
    return (asT<int?>(result["data"]["live_status"]) ?? 0) == 1;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) async {
    var result = await HttpClient.instance.getJson(
      "https://api.live.bilibili.com/av/v1/SuperChat/getMessageList",
      queryParameters: {
        "room_id": roomId,
      },
      header: await getHeader(),
    );
    List<LiveSuperChatMessage> ls = [];
    for (var item in result["data"]?["list"] ?? []) {
      var message = LiveSuperChatMessage(
        backgroundBottomColor: item["background_bottom_color"].toString(),
        backgroundColor: item["background_color"].toString(),
        endTime: DateTime.fromMillisecondsSinceEpoch(
          item["end_time"] * 1000,
        ),
        face: "${item["user_info"]["face"]}@200w.jpg",
        message: item["message"].toString(),
        price: item["price"],
        startTime: DateTime.fromMillisecondsSinceEpoch(
          item["start_time"] * 1000,
        ),
        userName: item["user_info"]["uname"].toString(),
      );
      ls.add(message);
    }
    return ls;
  }

  /// 获取 buvid3 和 buvid4
  /// 返回buvid3和buvid4
  /// ``` json
  /// {
  ///   "b_3": "buvid3",
  ///   "b_4": "buvid4",
  /// }
  /// ```
  Future<Map> getBuvid() async {
    try {
      // 原来用 `RegExp(r"buvid3=(.*?);")`，要求尾部必须有分号。
      // 用户粘贴的 cookie 末尾常常没有分号（`...;buvid3=xxx`），
      // 正则匹配不到就返回空串，而 getHeader 只看 contains("buvid3")
      // 就认为「已经有了」不再补全，最终发出 `buvid3=;buvid4=;` 的空指纹，
      // 是另一个会触发风控的来源。这里改用不依赖分号的取值函数。
      final existBuvid3 = cookieValue(cookie, "buvid3");
      if (existBuvid3.isNotEmpty) {
        return {
          "b_3": existBuvid3,
          "b_4": cookieValue(cookie, "buvid4"),
        };
      }

      var result = await HttpClient.instance.getJson(
        "https://api.bilibili.com/x/frontend/finger/spi",
        queryParameters: {},
        header: {
          "user-agent": kDefaultUserAgent,
          "referer": kDefaultReferer,
          if (normalizeCookie(cookie).isNotEmpty)
            "cookie": normalizeCookie(cookie),
        },
      );
      return result["data"] ?? {"b_3": "", "b_4": ""};
    } catch (e) {
      return {
        "b_3": "",
        "b_4": "",
      };
    }
  }

  static String kImgKey = '';
  static String kSubKey = '';
  static const List<int> mixinKeyEncTab = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    16,
    24,
    55,
    40,
    61,
    26,
    17,
    0,
    1,
    60,
    51,
    30,
    4,
    22,
    25,
    54,
    21,
    56,
    59,
    6,
    63,
    57,
    62,
    11,
    36,
    20,
    34,
    44,
    52
  ];
  Future<(String, String)> getWbiKeys({bool forceRefresh = false}) async {
    if (!forceRefresh && kImgKey.isNotEmpty && kSubKey.isNotEmpty) {
      return (kImgKey, kSubKey);
    }
    // 获取最新的 img_key 和 sub_key
    var resp = await HttpClient.instance.getJson(
      'https://api.bilibili.com/x/web-interface/nav',
      header: await getHeader(),
    );

    // nav 在风控/半登录态下可能是 code=-101（未登录）但仍然带 wbi_img，
    // 也可能整个 data 里没有 wbi_img。原来直接下标取值会抛
    // 「type 'Null' is not a subtype of type 'String'」，
    // 用户看到的是一个和真实原因完全无关的报错。这里给出明确信息。
    final navData = resp is Map ? resp["data"] : null;
    final wbiImg = navData is Map ? navData["wbi_img"] : null;
    if (wbiImg is! Map) {
      final code = resp is Map ? resp["code"] : null;
      throw CoreError(
        "哔哩哔哩签名获取失败：nav 接口未返回 wbi_img"
        "${code == null ? "" : "（code=$code）"}",
      );
    }

    final imgUrl = wbiImg["img_url"]?.toString() ?? "";
    final subUrl = wbiImg["sub_url"]?.toString() ?? "";
    if (imgUrl.isEmpty || subUrl.isEmpty) {
      throw CoreError("哔哩哔哩签名获取失败：wbi_img 内 img_url/sub_url 为空");
    }
    final imgKey = imgUrl.substring(imgUrl.lastIndexOf('/') + 1).split('.').first;
    final subKey = subUrl.substring(subUrl.lastIndexOf('/') + 1).split('.').first;
    if (imgKey.isEmpty || subKey.isEmpty) {
      throw CoreError("哔哩哔哩签名获取失败：img_key/sub_key 解析为空");
    }

    kImgKey = imgKey;
    kSubKey = subKey;

    return (imgKey, subKey);
  }

  /// 清掉 WBI 签名缓存
  ///
  /// B 站会不定期轮换 img_key/sub_key，服务端此时对旧签名返回 `code=-352`。
  /// 原来的缓存是**进程级永久缓存**，一旦遇到轮换就只能重启 App 才能恢复，
  /// 表现为「播了一会儿之后所有 B 站直播间都打不开」。所以拿到 -352
  /// 时要能主动失效重取。
  static void clearWbiCache() {
    kImgKey = '';
    kSubKey = '';
  }

  String getMixinKey(String origin) {
    // 对 imgKey 和 subKey 进行字符顺序打乱编码
    return mixinKeyEncTab.fold("", (s, i) => s + origin[i]).substring(0, 32);
  }

  Future<Map<String, String>> getWbiSign(String url) async {
    var (imgKey, subKey) = await getWbiKeys();
    return _signWith(url, imgKey, subKey);
  }

  /// 带签名请求 B 站接口，遇到 -352（签名失效/密钥轮换）自动刷新后重试一次。
  ///
  /// -352 是 B 站对「w_rid 与当前密钥不匹配」的专用返回码，
  /// 唯一正确的处理是重取 img_key/sub_key 再签一次；
  /// 原来的实现把密钥缓存在 static 变量里永不失效，
  /// 一旦 B 站轮换密钥，所有依赖签名的直播间都会打不开，只能重启 App。
  Future<dynamic> getJsonWithWbiSign(
    String baseUrl,
    String signedUrl, {
    Map<String, dynamic>? header,
  }) async {
    var queryParams = await getWbiSign(signedUrl);
    var result = await HttpClient.instance.getJson(
      baseUrl,
      queryParameters: queryParams,
      header: header ?? await getHeader(),
    );
    if (result is Map && result["code"] == -352) {
      CoreLog.d("哔哩哔哩签名已失效（-352），刷新 WBI 密钥后重试");
      clearWbiCache();
      queryParams = await getWbiSign(signedUrl);
      result = await HttpClient.instance.getJson(
        baseUrl,
        queryParameters: queryParams,
        header: header ?? await getHeader(),
      );
    }
    return result;
  }

  Map<String, String> _signWith(String url, String imgKey, String subKey) {
    // 为请求参数进行 wbi 签名
    var mixinKey = getMixinKey(imgKey + subKey);
    var currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    var queryParams = Map<String, String>.from(Uri.parse(url).queryParameters);

    queryParams["wts"] = currentTime.toString(); // 添加 wts 字段

    //按照 key 重排参数
    Map<String, String> map = {};
    var sortedKeys = queryParams.keys.toList()..sort();
    for (var key in sortedKeys) {
      var value = queryParams[key]!;
      // 过滤 value 中的 "!'()*" 字符
      map[key] = value
          .toString()
          .split('')
          .where((c) => "!'()*".contains(c) == false)
          .join('');
    }

    var query = map.keys
        .map((key) => "$key=${Uri.encodeQueryComponent(map[key]!)}")
        .join("&");
    var wbiSign = md5.convert(utf8.encode("$query$mixinKey")).toString();
    queryParams["w_rid"] = wbiSign;
    return queryParams;
  }

  Future<String> getAccessId() async {
    if (accessId.isNotEmpty) {
      return accessId;
    }

    // 获取 access_id
    var resp = await HttpClient.instance.getText(
      "https://live.bilibili.com/lol",
      queryParameters: {},
      header: await getHeader(),
    );
    var id = RegExp(r'"access_id":"(.*?)"')
        .firstMatch(resp)
        ?.group(1)
        ?.replaceAll("\\", "");
    accessId = id ?? "";
    return accessId;
  }
}

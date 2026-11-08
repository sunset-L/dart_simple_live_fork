import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/src/common/core_error.dart';
import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/douyu_danmaku.dart';
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
import 'package:html_unescape/html_unescape.dart';
import 'package:simple_live_core/src/scripts/douyu_sign.dart';

class DouyuSite implements LiveSite {
  @override
  String id = "douyu";

  @override
  String name = "斗鱼直播";

  /// 用户提供的 `dy_auth` 登录票据（可为空）
  ///
  /// 实测（2026-10，见 research/douyu_auth_summary.md）：
  /// - **只有 `dy_auth` 这一个字段起作用**，其余 18 个 cookie 字段
  ///   （含 acf_jwt_token / dy_did）剔除后结果完全不变；
  /// - 带上它请求 `getH5Play`，`rate=0` 才能拿到「原画 + expire=0」，
  ///   匿名状态下 `rate=0` 会被服务端悄悄降成 `rate=4`（蓝光 4M）且 expire=300；
  /// - 它只影响**签名那一刻**，播放阶段 CDN 不再校验 cookie
  ///   （uid 已经嵌进 token），所以播放器侧零改动。
  ///
  /// 注意：这是完整登录票据，等同账号凭证，只存在本地且可随时清除。
  String dyAuth = "";

  /// 取流时统一使用移动端 h5 的 referer / UA
  static const String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43";

  /// 首选 CDN
  ///
  /// 实测 `cdn=hw-h5` 最稳；传空串会被派到 huosa（fcdn=hs），
  /// 该线路出现过 HTTP 400，因此不要排第一。
  static const String kPreferredCdn = "hw-h5";

  /// 构造取流请求头
  ///
  /// 只在 [dyAuth] 非空时附加 `Cookie: dy_auth=xxx`。
  /// 这个 cookie 是**完整登录态**，不要再拼其它字段：
  /// 实测拼接非 HttpOnly 字段（document.cookie 那一堆）
  /// 后反而 120 组对照零效果，徒增泄露面。
  Map<String, dynamic> _playHeaders(String roomId) {
    final headers = <String, dynamic>{
      'referer': 'https://www.douyu.com/$roomId',
      'user-agent': kUserAgent,
    };
    if (dyAuth.isNotEmpty) {
      // dy_auth 是 base64 风格的票据，值里可能带 `+` / `=` / `.`。
      // cookie 头的值不允许出现分号、逗号、空格等分隔符，
      // 用户从 DevTools 复制时也可能带上前后的空格或引号 ——
      // 这些都会让服务端解析不到 dy_auth（表现为「明明填了却没效果」）。
      // 这里只做最小清洗：去掉会破坏 cookie 语法的字符，不改变有效内容。
      var value = dyAuth.trim();
      if (value.endsWith(";")) {
        value = value.substring(0, value.length - 1).trim();
      }
      headers['cookie'] = 'dy_auth=$value';
    }
    return headers;
  }

  @override
  LiveDanmaku getDanmaku() => DouyuDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getJson(
      "https://m.douyu.com/api/cate/list",
    );
    var subCateList = result["data"]["cate2Info"] as List;
    for (var item in result["data"]["cate1Info"]) {
      var cate1Id = item["cate1Id"];
      var cate1Name = item["cate1Name"];
      List<LiveSubCategory> subCategories = [];
      subCateList.where((x) => x["cate1Id"] == cate1Id).forEach((element) {
        subCategories.add(
          LiveSubCategory(
            pic: element["icon"],
            id: element["cate2Id"].toString(),
            parentId: cate1Id.toString(),
            name: element["cate2Name"].toString(),
          ),
        );
      });
      categories.add(
        LiveCategory(
          id: cate1Id.toString(),
          name: cate1Name.toString(),
          children: subCategories,
        ),
      );
    }
    // 根据ID排序
    categories.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));

    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/gapi/rkc/directory/mixList/2_${category.id}/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  /// 读取清晰度列表
  ///
  /// 关键改动（对照 research/douyu_auth_summary.md）：
  /// - 请求带上 `Cookie: dy_auth=xxx`。这决定 `multirates` 里能不能出现
  ///   原画档位：匿名时服务端会把 `rate=0` 悄悄降成 `rate=4`（蓝光 4M），
  ///   列表里就只剩低档，用户根本选不到原画；
  /// - **删掉 `ive=1`**。实测 `ive=1` 是真降级：ffmpeg 实测只有 960×540 /
  ///   1029 kbps，比 `rate=3`（1280×720）还低一整档。
  /// - 这里仍用 `rate=-1` 表示「不指定档位」，目的是拿到完整的
  ///   `multirates` 列表供用户选择；真正取流时才用具体档位。
  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    var data = detail.data.toString();
    // 清晰度列表请求保持原样（`cdn=&rate=-1`）：
    // `rate=-1` 表示「不指定档位」，可以让服务端把完整 multirates 列出来。
    // 这里**不要**改成 `rate=0` —— 指定档位后返回的 multirates
    // 可能只剩该档及其以下，反而让用户看不到其它可选清晰度。
    // 唯一的新增就是带上 Cookie: dy_auth（见 _playHeaders）。
    data += "&cdn=&rate=-1&ver=Douyu_223061205&iar=1&hevc=0&fa=0";
    List<LivePlayQuality> qualities = [];
    var result = await HttpClient.instance.postJson(
      "https://www.douyu.com/lapi/live/getH5Play/${detail.roomId}",
      data: data,
      header: _playHeaders(detail.roomId),
      formUrlEncoded: true,
    );

    var cdns = <String>[];
    for (var item in result["data"]["cdnsWithName"]) {
      cdns.add(item["cdn"].toString());
    }

    // 首选 hw-h5 排第一：实测该线路最稳，
    // 而 scdn* 系列偶发 400，统一沉到末尾。
    cdns.sort((a, b) {
      if (a == kPreferredCdn && b != kPreferredCdn) {
        return -1;
      }
      if (b == kPreferredCdn && a != kPreferredCdn) {
        return 1;
      }
      if (a.startsWith("scdn") && !b.startsWith("scdn")) {
        return 1;
      } else if (!a.startsWith("scdn") && b.startsWith("scdn")) {
        return -1;
      }
      return 0;
    });

    for (var item in result["data"]["multirates"]) {
      qualities.add(
        LivePlayQuality(
          quality: item["name"].toString(),
          data: DouyuPlayData(item["rate"], cdns),
        ),
      );
    }

    // 这里刻意**不根据 multirates 判断授权是否生效**。
    // 文档明确警告：multirates 不可靠（master m3u8 的 BANDWIDTH 严重失真、
    // rate 字段也可能被服务端改写），唯一可信的是 rtmp_live 的流名后缀。
    // 而清晰度列表这一步拿不到可用的流名（rate=-1 时返回的 rtmp_live
    // 未必是最终播放地址），据此推断容易误报，
    // 所以「票据是否生效」统一交给取流流程与 verifyAuth() 判断。

    return qualities;
  }

  /// 上次取流时 `dy_auth` 是否被服务端拒绝
  ///
  /// 取流失败后会自动去掉 cookie 再试一次（回退到原有取流方式），
  /// 只要发生过这种回退就把这里置 true，上层据此提示用户「授权已失效」。
  /// 每次调用 [getPlayUrls] 开头都会重置，所以读到的永远是「本次」的结论。
  bool lastAuthRejected = false;

  /// 上次取流是否被服务端**静默降档**
  ///
  /// 这是比 [lastAuthRejected] 更常见、也更隐蔽的一种失败：
  /// 匿名（或票据已失效）请求 `rate=0` 时，服务端**不会报错**，
  /// 只会把画质压到 `rate=4`（蓝光 4M）并给一个 300 秒过期的地址。
  /// 取流本身是「成功」的，所以过去的回退分支不触发、界面毫无提示，
  /// 用户以为配好了，实际一直在看降级流。
  ///
  /// 判据（与 [verifyAuth] 完全一致，因为这是唯一可信的证据）：
  /// - 请求的是 `rate=0`，返回的流名却带 `_4000` / `_2000` / `_900` 这类数字后缀；
  /// - 或者返回地址的 `expire > 0`（匿名取原画必然 expire=300）。
  bool lastQualityDowngraded = false;

  /// 被降档后服务端实际授予的档位名称（如「蓝光4M」），用于提示文案
  ///
  /// 只在能从流名后缀解析出来时非空；仅因 `expire > 0` 判定降档时为空，
  /// 此时上层用不带档位的措辞。
  String lastDowngradeLabel = "";

  /// 任一渠道发现的「票据未生效」信号
  ///
  /// 两个来源：取流失败后回退（[lastAuthRejected]）、
  /// 以及取流成功但被静默降档（[lastQualityDowngraded]）。
  bool get authNotEffective => lastAuthRejected || lastQualityDowngraded;

  /// 取播放地址
  ///
  /// 只做一件事：按选定的清晰度取流，**不再提供任何降画质的兜底线路**。
  ///
  /// 历史包袱已移除：
  /// - 过去为了绕开 expire=300 的断流，会额外追加一条 `ive=1` 的
  ///   「不过期」线路当最后一道防线。但 `ive=1` 会被服务端压到 960×540，
  ///   比 rate=3 还低，属于「用画质换稳定」。
  /// - 现在的策略是：**任何时候都不降画质**。
  ///   地址快过期时由上层（LiveRoomController）提前主动重签，
  ///   断流了也是重签续播，而不是切到低画质。
  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    lastAuthRejected = false;
    lastQualityDowngraded = false;
    lastDowngradeLabel = "";
    var data = quality.data as DouyuPlayData;
    final args = detail.data.toString();

    var urls = await _fetchUrls(detail.roomId, args, data);

    // 带了 dy_auth 却一条线路都取不到：先怀疑票据失效，
    // 回退到「原有取流方式」（不带 cookie）再试一次，
    // 至少让用户还能看，而不是直接黑屏。
    if (urls.isEmpty && dyAuth.isNotEmpty) {
      CoreLog.d("斗鱼：带 dy_auth 取流失败，回退到普通方式重试");
      lastAuthRejected = true;
      final saved = dyAuth;
      dyAuth = "";
      try {
        urls = await _fetchUrls(detail.roomId, args, data);
      } finally {
        dyAuth = saved;
      }
      // 回退也没取到，说明是签名(detail.data)过期或房间状态问题，
      // 不是票据的锅，撤销这个标记避免误报。
      if (urls.isEmpty) {
        lastAuthRejected = false;
      }
    }

    // 一条线路都没拿到，多半是签名（detail.data）已经过期。
    // 这里抛出明确异常，交给上层重新拉取房间详情后再取流，
    // 而不是返回空列表让界面陷入「无法读取播放地址」的死循环。
    if (urls.isEmpty) {
      throw CoreError("斗鱼取流失败：未获取到任何可用线路");
    }

    return LivePlayUrl(urls: urls);
  }

  Future<List<String>> _fetchUrls(
    String roomId,
    String args,
    DouyuPlayData data,
  ) async {
    final urls = <String>[];
    // 按「hw-h5 优先、scdn 最后」的顺序取流。
    // cdns 列表来自 getPlayQualites，那里已经排过一次，
    // 但列表内容可能不含 hw-h5（服务端按地域下发），
    // 此时顺序不变，仍然按原列表逐条尝试。
    for (var cdn in data.cdns) {
      final url = await getPlayUrl(roomId, args, data.rate, cdn);
      if (url.isNotEmpty && !urls.contains(url)) {
        urls.add(url);
        // 第一条拿到的地址就足以说明服务端实际授予了什么画质，
        // 后面的 cdn 只是同一份授权的不同线路，结论必然相同，
        // 所以只判定一次，不多花开销。
        if (urls.length == 1) {
          _checkDowngraded(url, data.rate);
        }
      }
    }
    return urls;
  }

  /// 判断服务端是否把我们**静默降档**了
  ///
  /// 这是比「取流失败」隐蔽得多的失败模式：匿名请求 `rate=0` 时服务端
  /// 不报错，只是把画质压到 `rate=4`（蓝光 4M）并给个 300 秒过期的地址。
  /// 取流本身是成功的，所以只看「有没有地址」永远发现不了问题。
  ///
  /// 判据与 [verifyAuth] 完全一致 —— 这是唯一可信的证据链：
  /// 流名后缀 `_4000 / _2000 / _900` 就是 CDN 真正要校验的那段码率，
  /// 比 multirates 和返回 JSON 里的 rate 字段都可靠（后者会被服务端改写）。
  ///
  /// 只在请求了 `rate=0`（用户要的是原画）时才判断：
  /// 用户主动选了低档，那本来就不是降档。
  void _checkDowngraded(String url, int requestedRate) {
    if (requestedRate != 0) {
      return;
    }
    final fileName = Uri.decodeComponent(
      url.split('?').first.split('/').last,
    );
    final suffix = RegExp(r'_(\d+)\.(?:flv|m3u8)$').firstMatch(fileName);
    if (suffix != null) {
      lastQualityDowngraded = true;
      lastDowngradeLabel = _rateSuffixLabel(suffix.group(1)!);
      CoreLog.d(
        "斗鱼：请求原画(rate=0)，服务端实际下发 $fileName"
        "（判定为未登录/票据失效导致的降档）",
      );
      return;
    }
    // 无后缀也不一定就是原画：匿名取原画必然 expire=300，
    // 只有 expire=0 才是真正的「永不过期的原画地址」。
    final expire = _parseExpire(url);
    if (expire != null && expire > 0) {
      lastQualityDowngraded = true;
      // 没有后缀就无从得知具体是哪一档，文案交给上层用泛化措辞
      lastDowngradeLabel = "";
      CoreLog.d("斗鱼：请求原画(rate=0)，返回地址 expire=$expire（判定为降档）");
    }
  }

  /// 把流名后缀的数字换成用户看得懂的档位名
  ///
  /// 后缀就是服务端实际授予的码率（单位 kbps）：
  /// `_4000` = 蓝光4M，`_2000` = 超清，`_900` = 高清。
  /// 未知后缀直接显示码率，不要瞎猜档位名。
  static String _rateSuffixLabel(String value) {
    switch (value) {
      case "4000":
        return "蓝光4M";
      case "2000":
        return "超清";
      case "900":
        return "高清";
      default:
        return "${value}kbps";
    }
  }

  /// 把斗鱼的 HTTP-FLV 地址转换成同源的 HLS 地址
  ///
  /// 实测：同一条 cdn、同一份签名下，把路径末尾的 `.flv` 换成 `.m3u8`，
  /// 可以直接拿到标准的 HLS 主播放列表（`application/vnd.apple.mpegurl`），
  /// 分片是 `video/mp2t`，且不需要额外的 referer / cookie。
  ///
  /// 保留这个方法是为了排障和后续可能的画质切换策略，
  /// 注意它**不能**解决 token 到期断流：HLS 与 FLV 共用同一个 token。
  static String? toHlsUrl(String flvUrl) {
    // 只替换路径末尾的 .flv，查询串里的签名必须原样保留
    final match = RegExp(r'\.flv(?=\?|$)').firstMatch(flvUrl);
    if (match == null) {
      return null;
    }
    return flvUrl.replaceRange(match.start, match.end, '.m3u8');
  }

  /// 取单条线路的播放地址
  /// - 任何一条线路失败都不应该影响其它线路，因此这里吞掉异常并返回空串
  Future<String> getPlayUrl(
    String roomId,
    String args,
    int rate,
    String cdn,
  ) async {
    try {
      final query = StringBuffer("$args&cdn=$cdn&rate=$rate");
      var result = await HttpClient.instance.postJson(
        "https://www.douyu.com/lapi/live/getH5Play/$roomId",
        data: query.toString(),
        header: _playHeaders(roomId),
        formUrlEncoded: true,
      );

      final data = result["data"];
      if (data is! Map) {
        return "";
      }
      final rtmpUrl = data["rtmp_url"]?.toString() ?? "";
      final rtmpLive = data["rtmp_live"]?.toString() ?? "";
      if (rtmpUrl.isEmpty || rtmpLive.isEmpty) {
        return "";
      }
      return "$rtmpUrl/${HtmlUnescape().convert(rtmpLive)}";
    } catch (_) {
      return "";
    }
  }

  /// 校验 `dy_auth` 是否真的有效（用于账号页/登录页的即时反馈）
  ///
  /// 文档里最重要的一条：**不要用 www 站的登录态接口判断 cookie 是否有效**，
  /// 它们会误报（member/cp 302 到登录页、follow/list 直接回未登录），
  /// 但 CDN 取流接口认它。唯一可靠的验收标准就是直接请求 `getH5Play`。
  ///
  /// 判据的可靠性分层（这点很关键，不能只看 expire）：
  /// - **能拿到「被降档」的证据 → 明确无效**。
  ///   流名后缀 `_4000` / `_2000` / `_900` 就是服务端实际授予的码率，
  ///   这是 CDN 真正要校验的那一段，比 multirates / rate 字段可靠得多。
  /// - **expire > 0 → 明确无效**。匿名取原画必然 expire=300。
  /// - 剩下「无后缀 + expire=0」只能算**未能证伪**，不能断言成功：
  ///   房间本身只有单档画质时（multirates.length == 1），
  ///   匿名也能拿到 expire=0（实测 30/30、44/44），
  ///   这时返回 true 会骗用户「授权已生效」，实际是房间特殊。
  ///   所以这种模糊情况返回 `null`（无法判断），由调用方措辞为「已保存」。
  ///
  /// 返回：`true` 明确有效 / `false` 明确无效 / `null` 无法判断。
  Future<bool?> verifyAuth(String roomId, {String args = ""}) async {
    if (dyAuth.isEmpty) {
      return false;
    }
    try {
      var result = await HttpClient.instance.postJson(
        "https://www.douyu.com/lapi/live/getH5Play/$roomId",
        data: "$args&cdn=$kPreferredCdn&rate=0",
        header: _playHeaders(roomId),
        formUrlEncoded: true,
      );
      final data = result["data"];
      if (data is! Map) {
        // 接口没给 data：可能是房间没开播 / 参数不对，
        // 这不构成「票据无效」的证据，判为无法判断。
        return null;
      }
      final rtmpLive = data["rtmp_live"]?.toString() ?? "";
      if (rtmpLive.isEmpty) {
        // 同上：可能房间未开播，不能据此断定票据失效
        return null;
      }
      // 流名后缀就是服务端真正授予的码率，比 multirates / rate 字段更可靠
      // 无后缀 = 原画；_4000 / _2000 / _900 = 被降档
      final fileName = Uri.decodeComponent(
        rtmpLive.split('?').first.split('/').last,
      );
      final hasRateSuffix = RegExp(r'_\d+\.(flv|m3u8)$').hasMatch(fileName);
      if (hasRateSuffix) {
        return false;
      }
      // expire 必须为 0 才算完整生效（否则照样会 300 秒断一次）
      final expire = _parseExpire(rtmpLive);
      if (expire != null && expire > 0) {
        return false;
      }
      // 「无后缀 + expire=0」：只有房间存在多档画质时，
      // 这个组合才能真正证明登录态生效（匿名多档必被降到 rate=4）。
      final multirates = data["multirates"];
      if (multirates is List && multirates.length > 1) {
        return true;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  int? _parseExpire(String url) {
    final m = RegExp(r'[?&]expire=(\d+)').firstMatch(url);
    if (m == null) {
      return null;
    }
    return int.tryParse(m.group(1)!);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/weblist/apinc/allpage/6/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    Map roomInfo = await _getRoomInfo(roomId);

    Map h5RoomInfo = await HttpClient.instance.getJson(
      "https://www.douyu.com/swf_api/h5room/$roomId",
      queryParameters: {},
      header: {
        'referer': 'https://www.douyu.com/$roomId',
        'user-agent': kUserAgent,
      },
    );
    String? showTime = h5RoomInfo["data"]?["show_time"]?.toString();

    var jsEncResult = await HttpClient.instance.getText(
      "https://www.douyu.com/swf_api/homeH5Enc?rids=$roomId",
      queryParameters: {},
      header: {
        'referer': 'https://www.douyu.com/$roomId',
        'user-agent': kUserAgent,
      },
    );
    var crptext = json.decode(jsEncResult)["data"]["room$roomId"].toString();

    if (showTime != null && showTime.isNotEmpty) {
      try {
        int startTimeStamp = int.parse(showTime);
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        print('斗鱼直播间 $roomId 开播时长: $formattedDuration');
      } catch (e) {
        print('计算开播时长出错: $e');
      }
    }

    return LiveRoomDetail(
      cover: roomInfo["room_pic"].toString(),
      online: int.tryParse(roomInfo["room_biz_all"]["hot"].toString()) ?? 0,
      roomId: roomInfo["room_id"].toString(),
      title: roomInfo["room_name"].toString(),
      userName: roomInfo["owner_name"].toString(),
      userAvatar: roomInfo["owner_avatar"].toString(),
      introduction: roomInfo["show_details"].toString(),
      notice: "",
      status: roomInfo["show_status"] == 1 && roomInfo["videoLoop"] != 1,
      danmakuData: roomInfo["room_id"].toString(),
      data: DouyuSign.getSign(crptext, roomInfo["room_id"].toString()),
      url: "https://www.douyu.com/$roomId",
      isRecord: roomInfo["videoLoop"] == 1,
      showTime: showTime,
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchShow",
      queryParameters: {"kw": keyword, "page": page, "pageSize": 20},
      header: {
        'User-Agent': kUserAgent,
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
    );
    if (result['error'] != 0) {
      throw Exception(result['msg']);
    }
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["relateShow"]) {
      var roomItem = LiveRoomItem(
        roomId: item["rid"].toString(),
        title: item["roomName"].toString(),
        cover: item["roomSrc"].toString(),
        userName: item["nickName"].toString(),
        online: parseHotNum(item["hot"].toString()),
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["relateShow"].isNotEmpty;
    return LiveSearchRoomResult(hasMore: hasMore, items: items);
  }

  Future<Map> _getRoomInfo(String roomId) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/betard/$roomId",
      queryParameters: {},
      header: {
        'referer': 'https://www.douyu.com/$roomId',
        'user-agent': kUserAgent,
      },
    );
    Map roomInfo;
    if (result is String) {
      roomInfo = json.decode(result)["room"];
    } else {
      roomInfo = result["room"];
    }
    return roomInfo;
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchUser",
      queryParameters: {
        "kw": keyword,
        "page": page,
        "pageSize": 20,
        "filterType": 1,
      },
      header: {
        'User-Agent': kUserAgent,
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
    );

    var items = <LiveAnchorItem>[];
    for (var item in result["data"]["relateUser"]) {
      var liveStatus =
          (int.tryParse(item["anchorInfo"]["isLive"].toString()) ?? 0) == 1;
      var roomType =
          (int.tryParse(item["anchorInfo"]["roomType"].toString()) ?? 0);
      var roomItem = LiveAnchorItem(
        roomId: item["anchorInfo"]["rid"].toString(),
        avatar: item["anchorInfo"]["avatar"].toString(),
        userName: item["anchorInfo"]["nickName"].toString(),
        liveStatus: liveStatus && roomType == 0,
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["relateUser"].isNotEmpty;
    return LiveSearchAnchorResult(hasMore: hasMore, items: items);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    var roomInfo = await _getRoomInfo(roomId);
    return roomInfo["show_status"] == 1 && roomInfo["videoLoop"] != 1;
  }

  int parseHotNum(String hn) {
    try {
      var num = double.parse(hn.replaceAll("万", ""));
      if (hn.contains("万")) {
        num *= 10000;
      }
      return num.round();
    } catch (_) {
      return -999;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({
    required String roomId,
  }) {
    //尚不支持
    return Future.value([]);
  }
}

class DouyuPlayData {
  final int rate;
  final List<String> cdns;
  DouyuPlayData(this.rate, this.cdns);
}

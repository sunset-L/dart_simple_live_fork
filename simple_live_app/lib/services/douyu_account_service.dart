import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 斗鱼账号服务
///
/// 只保存一个东西：`dy_auth`。
///
/// 依据 research/douyu_auth_summary.md 的消融实验结论：
/// 斗鱼取流时「画质被降档」和「300 秒必断流」这两个问题，
/// 只需要 `Cookie: dy_auth=xxx` 一个键值对就能同时解决；
/// 其余 18 个 cookie 字段（含 acf_jwt_token、dy_did）逐个剔除后结果不变，
/// 而只保留其它任意一个字段则完全无效。
///
/// 因此这里刻意**不保存整个 Cookie 串**：字段越少，泄露面越小，
/// 也不会出现「用户从 DevTools 复制了一整行 Cookie，结果某个字段
/// 取值异常导致 dy_auth 反而失效」的情况。
class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  /// dy_auth 票据原文
  var auth = "";

  /// 是否有可用的 dy_auth
  var hasAuth = false.obs;

  /// 票据是否已被验证失效
  ///
  /// 取流时如果发现「带了 dy_auth 却仍然被降档 / expire 不为 0」，
  /// 就把这里置 true，界面据此提示用户重新登录。
  var authInvalid = false.obs;

  @override
  void onInit() {
    auth = LocalStorageService.instance.getValue(
      LocalStorageService.kDouyuAuth,
      "",
    );
    hasAuth.value = auth.isNotEmpty;
    _applyToSite();
    super.onInit();
  }

  /// 把票据同步到 DouyuSite
  void _applyToSite() {
    try {
      final site = Sites.allSites[Constant.kDouyu]?.liveSite;
      if (site is DouyuSite) {
        site.dyAuth = auth;
      }
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 保存 dy_auth
  ///
  /// [value] 允许是以下三种输入，统一从中抽取 `dy_auth` 的值：
  /// - 纯值（推荐，也是网页登录自动写入的形式）
  /// - `dy_auth=xxx`
  /// - 整行 Cookie（`a=1; dy_auth=xxx; b=2`）
  ///
  /// 来自 DevTools 的整行 Cookie 里 dy_auth 是 HttpOnly 的，
  /// 用户直接在 Console 跑 `document.cookie` 是拿不到的，
  /// 所以这里对输入做一个宽容的解析，减少用户操作成本。
  void setAuth(String value) {
    final parsed = parseAuth(value);
    auth = parsed;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyuAuth, parsed);
    hasAuth.value = parsed.isNotEmpty;
    authInvalid.value = false;
    _applyToSite();
  }

  void clearAuth() {
    auth = "";
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyuAuth, "");
    hasAuth.value = false;
    authInvalid.value = false;
    _applyToSite();
  }

  /// 标记票据失效（取流侧发现降档时调用）
  void markInvalid() {
    if (authInvalid.value) {
      return;
    }
    authInvalid.value = true;
  }

  /// 用一个在播房间验证票据是否真的生效
  ///
  /// 依据文档：不要用 www 站的登录态接口判断，它们会误报；
  /// 唯一可靠的判据是直接请求 `getH5Play`，看服务端有没有把画质降档。
  ///
  /// 返回：`true` 明确有效 / `false` 明确无效 / `null` 无法判断。
  Future<bool?> verify({String? anyRoomId}) async {
    if (auth.isEmpty) {
      return false;
    }
    final site = Sites.allSites[Constant.kDouyu]?.liveSite;
    if (site is! DouyuSite) {
      return null;
    }
    try {
      final roomId = anyRoomId ?? await _pickLiveRoomId();
      if (roomId == null || roomId.isEmpty) {
        return null;
      }
      // 校验必须带签名：直接取房间详情拿到 detail.data
      final detail = await site.getRoomDetail(roomId: roomId);
      final result = await site.verifyAuth(
        roomId,
        args: detail.data.toString(),
      );
      if (result == false) {
        authInvalid.value = true;
      } else if (result == true) {
        authInvalid.value = false;
      }
      return result;
    } catch (e) {
      Log.logPrint(e);
      return null;
    }
  }

  /// 随便挑一个在播房间用于校验
  ///
  /// 校验需要一个真实在播的房间，否则服务端不返回 rtmp_live，
  /// 会被误判成「票据无效」。这里取推荐列表里的第一个在播房间。
  Future<String?> _pickLiveRoomId() async {
    try {
      final site = Sites.allSites[Constant.kDouyu]?.liveSite;
      if (site is! DouyuSite) {
        return null;
      }
      final result = await site.getRecommendRooms(page: 1);
      for (final item in result.items) {
        if (item.roomId.isNotEmpty) {
          return item.roomId;
        }
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return null;
  }

  /// 从任意形式的输入里抽取 dy_auth 的值
  static String parseAuth(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return "";
    }
    // 整行 Cookie / 带前缀 两种形式：抓 dy_auth= 后面的值
    final m = RegExp(r'(?:^|[;\s])dy_auth=([^;\s]+)').firstMatch(text);
    if (m != null) {
      return m.group(1)!.trim();
    }
    // 纯值形式：去掉可能残留的引号与尾部分号
    text = text.replaceAll('"', "").replaceAll("'", "").trim();
    if (text.endsWith(";")) {
      text = text.substring(0, text.length - 1).trim();
    }
    return text;
  }
}

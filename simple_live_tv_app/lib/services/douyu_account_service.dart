import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_tv_app/app/constant.dart';
import 'package:simple_live_tv_app/app/log.dart';
import 'package:simple_live_tv_app/app/sites.dart';
import 'package:simple_live_tv_app/services/local_storage_service.dart';

/// 斗鱼账号服务（TV 端）
///
/// 与手机端保持同一套方案：只保存 `dy_auth` 一个值。
///
/// 依据消融实验结论，斗鱼取流时「画质被降档」和「300 秒必断流」这两个问题，
/// 只需要 `Cookie: dy_auth=xxx` 一个键值对就能同时解决；
/// 其余 cookie 字段（含 acf_jwt_token、dy_did）逐个剔除后结果不变。
///
/// TV 端没有 WebView 登录能力（遥控器操作也不适合），
/// 票据来源有两条：
/// 1. 手机端 App 通过局域网同步推送过来（[SyncService] 的 `/sync/account/douyu`）；
/// 2. 在设置页手动粘贴。
class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  /// dy_auth 票据原文
  var auth = "";

  /// 是否有可用的 dy_auth
  var hasAuth = false.obs;

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
  ///
  /// 核心库的 [DouyuSite._playHeaders] 只在 dyAuth 非空时附加
  /// `Cookie: dy_auth=xxx`，所以写在这里就等于全局生效。
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
  /// [value] 允许是纯值、`dy_auth=xxx` 或整行 Cookie，
  /// 统一由 [parseAuth] 抽出真正的值。
  void setAuth(String value) {
    final parsed = parseAuth(value);
    auth = parsed;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyuAuth, parsed);
    hasAuth.value = parsed.isNotEmpty;
    _applyToSite();
  }

  void clearAuth() {
    auth = "";
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyuAuth, "");
    hasAuth.value = false;
    _applyToSite();
  }

  /// 从任意形式的输入里抽取 dy_auth 的值
  ///
  /// DevTools 里 dy_auth 是 HttpOnly 的，`document.cookie` 拿不到，
  /// 用户往往直接复制整行 Cookie，所以这里做宽容解析。
  static String parseAuth(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return "";
    }
    final m = RegExp(r'(?:^|[;\s])dy_auth=([^;\s]+)').firstMatch(text);
    if (m != null) {
      return m.group(1)!.trim();
    }
    text = text.replaceAll('"', "").replaceAll("'", "").trim();
    if (text.endsWith(";")) {
      text = text.substring(0, text.length - 1).trim();
    }
    return text;
  }
}

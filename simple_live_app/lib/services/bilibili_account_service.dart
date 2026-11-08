import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/account/bilibili_user_info_page.dart';
import 'package:simple_live_app/requests/http_client.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class BiliBiliAccountService extends GetxService {
  static BiliBiliAccountService get instance =>
      Get.find<BiliBiliAccountService>();

  var logined = false.obs;

  var cookie = "";
  var uid = 0;
  var name = "未登录".obs;

  /// Cookie 是否已同步到 [BiliBiliSite]
  ///
  /// 用来诊断「界面显示已登录、但取流还是匿名」这类状态不一致。
  var siteSynced = false.obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kBilibiliCookie, "");
    logined.value = cookie.isNotEmpty;
    // 关键：启动时也要把已保存的 Cookie 推给 BiliBiliSite。
    //
    // 原来只有 loadUserInfo() 成功（接口返回 code==0）时才会在内部调
    // setSite()。一旦 loadUserInfo 走了异常分支（断网 / 接口被风控 /
    // Cookie 已失效），site.cookie 就永远是空串，但界面因为
    // logined.value 已置 true 而显示「已登录」。
    // 结果是：用户以为自己在用账号取流，实际所有请求都是匿名发出的，
    // 高清晰度必然拿不到，且现象极难与「登录无效」区分开。
    if (cookie.isNotEmpty) {
      setSite();
    }
    loadUserInfo();
    super.onInit();
  }

  Future loadUserInfo() async {
    if (cookie.isEmpty) {
      return;
    }
    try {
      var result = await HttpClient.instance.getJson(
        "https://api.bilibili.com/x/member/web/account",
        header: {
          "Cookie": normalizeCookie(cookie),
        },
      );
      if (result["code"] == 0) {
        var info = BiliBiliUserInfoModel.fromJson(result["data"]);
        name.value = info.uname ?? "未登录";
        uid = info.mid ?? 0;
        setSite();
      } else {
        SmartDialog.showToast("哔哩哔哩登录已失效，请重新登录");
        logout();
      }
    } catch (e) {
      SmartDialog.showToast("获取哔哩哔哩用户信息失败，可前往账号管理重试");
      // 网络异常不代表 Cookie 失效，此时不能把 site 里的 Cookie 清掉，
      // 否则「网络抖一下」就把可用的登录态弄丢了。
      setSite();
    }
  }

  void setSite() {
    try {
      var site =
          (Sites.allSites[Constant.kBiliBili]!.liveSite as BiliBiliSite);
      site.userId = uid;
      site.cookie = cookie;
      // cookie 变了，之前缓存下来的 buvid 指纹和 WBI 签名密钥都可能不再匹配，
      // 必须清掉让 site 重新取，否则会出现「换了账号还用旧指纹」的串号问题。
      site.buvid3 = "";
      site.buvid4 = "";
      BiliBiliSite.clearWbiCache();
      siteSynced.value = true;
    } catch (e) {
      siteSynced.value = false;
      Log.logPrint(e);
    }
  }

  void setCookie(String cookie) {
    // 从浏览器复制来的 Cookie 几乎必然带多余空白（最典型是
    // `buvid3=xxx ;` 这种分号前的空格）。实测这种值尾部空格会让
    // api.bilibili.com/x/web-interface/nav 返回 HTTP 412，
    // 而 WBI 签名依赖 nav，于是整个 B 站取流链断掉。
    // 所以在**入口处**就规范化，而不是等发请求时再补救。
    final normalized = normalizeCookie(cookie);
    this.cookie = normalized;
    LocalStorageService.instance
        .setValue(LocalStorageService.kBilibiliCookie, normalized);
    logined.value = normalized.isNotEmpty;
    // 补上这行：缺少它会导致「设置完 Cookie 但 site.cookie 仍为空」。
    setSite();
  }

  void logout() async {
    cookie = "";
    uid = 0;
    name.value = "未登录";
    setSite();
    LocalStorageService.instance
        .setValue(LocalStorageService.kBilibiliCookie, "");
    logined.value = false;

    if (Platform.isAndroid || Platform.isIOS) {
      CookieManager cookieManager = CookieManager.instance();
      await cookieManager.deleteAllCookies();
    }
  }
}

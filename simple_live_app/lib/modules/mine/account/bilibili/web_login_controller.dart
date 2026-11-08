import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class BiliBiliWebLoginController extends BaseController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();
  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    webViewController!.loadUrl(
      urlRequest: URLRequest(
        url: WebUri("https://passport.bilibili.com/login"),
      ),
    );
  }

  void toQRLogin() async {
    await Get.toNamed(RoutePath.kBiliBiliQRLogin);
    Get.back();
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) async {
    if (uri == null) {
      return;
    }
    if (uri.host == "m.bilibili.com") {
      logined();
    }
  }

  Future<bool> logined() async {
    try {
      var cookies =
          await cookieManager.getCookies(url: WebUri("https://bilibili.com"));
      if (cookies.isEmpty) {
        // 域名匹配可能落空（页面在 passport./m. 之间跳转），
        // 再按当前页面实际地址取一次，避免「登录成功却读不到 cookie」。
        try {
          final current = await webViewController?.getUrl();
          if (current != null && current.host.contains("bilibili.com")) {
            cookies = await cookieManager.getCookies(url: current);
          }
        } catch (e) {
          Log.logPrint(e);
        }
      }
      if (cookies.isEmpty) {
        return false;
      }
      // 用分号拼接后统一规范化：WebView 里取出的值同样可能带引号/空白，
      // 直接塞进请求头会让 B 站返回 412。
      var cookieStr = normalizeCookie(
        cookies.map((e) => "${e.name}=${e.value}").join(";"),
      );
      Log.i(cookieStr);
      if (cookieStr.isEmpty) {
        return false;
      }
      BiliBiliAccountService.instance.setCookie(cookieStr);
      await BiliBiliAccountService.instance.loadUserInfo();
      Get.back();
      return true;
    } catch (e) {
      return false;
    }
  }
}

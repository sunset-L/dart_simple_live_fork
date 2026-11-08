import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/douyu/web_login_controller.dart';

/// 斗鱼网页登录授权页
///
/// 流程：用户在这个 WebView 里正常登录斗鱼 →
/// 每次页面加载完成都去原生 cookie store 里捞一次 `dy_auth` →
/// 捞到就保存并返回。
///
/// 之所以用网页登录而不是让用户手动粘贴 cookie：
/// `dy_auth` 是 HttpOnly 的，用户在浏览器 Console 里执行
/// `document.cookie` 根本看不到它，唯一稳妥的手动方式是从 DevTools 的
/// Network 面板复制整行 Cookie。那对普通用户门槛太高，
/// 而且一旦复制错（拼了其它字段）反而更难排查。
class DouyuWebLoginPage extends GetView<DouyuWebLoginController> {
  const DouyuWebLoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 登录成功即自动返回上一页（监听注册在 controller.onInit 里，见那里注释）
    return Scaffold(
      appBar: AppBar(
        title: const Text("斗鱼登录授权"),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final ok = await controller.confirmLogin();
              if (!ok) {
                // 把扫描结果带出来，便于用户/我们判断是哪一环没成：
                // 0 条 cookie = WebView 的 cookie 压根没落到原生 store，
                // 有 cookie 但没有 dy_auth = 登录没真正完成。
                final count = controller.lastCookieCount.value;
                SmartDialog.showToast(
                  count == 0
                      ? "未读取到任何斗鱼 Cookie，请确认页面已完全加载并登录"
                      : "已读到 $count 条 Cookie 但无 dy_auth，请确认登录已完成",
                );
              }
            },
            icon: const Icon(Icons.check),
            label: const Text("已完成"),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Text(
              "登录成功后会自动获取授权参数并返回。授权仅保存在本机，可随时在账号管理里清除。",
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: InAppWebView(
              onWebViewCreated: controller.onWebViewCreated,
              onLoadStop: controller.onLoadStop,
              onUpdateVisitedHistory: controller.onUpdateVisitedHistory,
              initialSettings: InAppWebViewSettings(
                // 用桌面端 UA，不用移动端。
                //
                // 原因：移动 UA 下斗鱼会把 www.douyu.com 重定向到 m.douyu.com，
                // 登录态可能只落在移动站域名下。而 Android 的
                // CookieManager.getCookie(url) 是**按域名匹配**的，
                // 域名一旦错位就读不到 dy_auth（表现为「明明登录了却说没登录」）。
                // 桌面端 UA 加上 sec-ch-ua 缺失时斗鱼仍会重定向，
                // 但在 www 与 m 两处都查一遍即可覆盖（见 controller 的候选域名）。
                userAgent:
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43",
                useShouldOverrideUrlLoading: false,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                // 让 WebView 与 CookieManager 共用同一份 cookie store。
                // 不开这个，WebView 内的登录态可能不落到能被 getCookies 读到的地方。
                sharedCookiesEnabled: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

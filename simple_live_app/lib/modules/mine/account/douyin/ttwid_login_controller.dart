import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';

/// 从抖音直播网页的 Cookie 存储中读取访客 ttwid。
class DouyinTtwidLoginController extends BaseController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();
  final detectedTtwid = ''.obs;
  final isReading = false.obs;
  int cookieCount = 0;

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    controller.loadUrl(
      urlRequest: URLRequest(url: WebUri('https://live.douyin.com/')),
    );
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    refreshTtwid(uri: uri);
  }

  void onUpdateVisitedHistory(
    InAppWebViewController controller,
    WebUri? uri,
    bool? isReload,
  ) {
    refreshTtwid(uri: uri);
  }

  Future<void> refreshTtwid({Uri? uri}) async {
    if (isReading.value) return;
    isReading.value = true;
    cookieCount = 0;
    try {
      final urls = <WebUri>[];
      if (uri != null && _isDouyinHost(uri.host)) {
        urls.add(WebUri(uri.toString()));
      }
      urls.addAll([
        WebUri('https://live.douyin.com/'),
        WebUri('https://www.douyin.com/'),
      ]);

      final visited = <String>{};
      for (final url in urls) {
        if (!visited.add(url.toString())) continue;
        final cookies = await cookieManager.getCookies(url: url);
        cookieCount += cookies.length;
        for (final cookie in cookies) {
          if (cookie.name.toLowerCase() == 'ttwid' && cookie.value.isNotEmpty) {
            detectedTtwid.value = cookie.value;
            return;
          }
        }
      }
      detectedTtwid.value = '';
    } catch (_) {
      detectedTtwid.value = '';
    } finally {
      isReading.value = false;
    }
  }

  bool _isDouyinHost(String host) =>
      host == 'douyin.com' || host.endsWith('.douyin.com');

  Future<void> saveTtwid() async {
    if (isReading.value) {
      SmartDialog.showToast('正在读取 Cookie，请稍后再试');
      return;
    }
    await refreshTtwid();
    final value = detectedTtwid.value;
    if (value.isEmpty) {
      SmartDialog.showToast(
        cookieCount == 0
            ? '未读取到抖音 Cookie，请确认页面已加载'
            : '已读取到 $cookieCount 条 Cookie，但没有 ttwid',
      );
      return;
    }
    DouyinAccountService.instance.setCookie('ttwid=$value');
    SmartDialog.showToast('抖音 ttwid 已保存');
    Get.back();
  }
}

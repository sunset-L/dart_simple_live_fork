import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/douyin/ttwid_login_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyinTtwidLoginPage extends GetView<DouyinTtwidLoginController> {
  const DouyinTtwidLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('抖音 ttwid 授权'),
        actions: [
          TextButton.icon(
            onPressed: controller.saveTtwid,
            icon: const Icon(Icons.check),
            label: const Text('保存并返回'),
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
              '页面加载后会自动读取 ttwid。若页面提示登录，可先登录，再点击“保存并返回”。',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: InAppWebView(
              onWebViewCreated: controller.onWebViewCreated,
              onLoadStop: controller.onLoadStop,
              onUpdateVisitedHistory: controller.onUpdateVisitedHistory,
              initialSettings: InAppWebViewSettings(
                userAgent: DouyinSite.kDefaultUserAgent,
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                sharedCookiesEnabled: true,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Obx(
                () => Text(
                  controller.isReading.value
                      ? '正在读取抖音 Cookie…'
                      : controller.detectedTtwid.value.isNotEmpty
                          ? '已检测到 ttwid，点击右上角保存'
                          : '尚未检测到 ttwid，可登录后重试或返回手动填写',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

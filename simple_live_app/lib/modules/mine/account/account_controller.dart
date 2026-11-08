import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class AccountController extends GetxController {
  void bilibiliTap() async {
    if (BiliBiliAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出哔哩哔哩账号吗？", title: "退出登录");
      if (result) {
        BiliBiliAccountService.instance.logout();
      }
    } else {
      //AppNavigator.toBiliBiliLogin();
      bilibiliLogin();
    }
  }

  void bilibiliLogin() {
    Utils.showBottomSheet(
      title: "登录哔哩哔哩",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: Platform.isAndroid || Platform.isIOS,
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text("Web登录"),
              subtitle: const Text("填写用户名密码登录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                Get.toNamed(RoutePath.kBiliBiliWebLogin);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text("扫码登录"),
            subtitle: const Text("使用哔哩哔哩APP扫描二维码登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              Get.toNamed(RoutePath.kBiliBiliQRLogin);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("Cookie登录"),
            subtitle: const Text("手动输入Cookie登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doBiliBiliCookieLogin();
            },
          ),
        ],
      ),
    );
  }

  void doBiliBiliCookieLogin() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "请输入Cookie",
      hintText: "整段粘贴即可，如 SESSDATA=xxx; buvid3=yyy; bili_jct=zzz;",
    );
    if (cookie == null || cookie.isEmpty) {
      return;
    }
    // 入口处先规范化，顺手把明显缺东西的情况挡下来。
    //
    // 少了 buvid3 时请求等价于匿名访问，B 站风控会直接给 412，
    // 表现是「明明填了 Cookie，进直播间还是加载失败」。
    final normalized = normalizeCookie(cookie);
    if (normalized.isEmpty) {
      SmartDialog.showToast("Cookie 格式不正确，请整段复制后粘贴");
      return;
    }
    if (!hasCookieValue(normalized, "SESSDATA")) {
      final go = await Utils.showAlertDialog(
        "未检测到 SESSDATA，这份 Cookie 里没有登录凭证，登录后依然只能看低清晰度。仍要保存吗？",
        title: "Cookie 不完整",
      );
      if (!go) {
        return;
      }
    }
    BiliBiliAccountService.instance.setCookie(normalized);
    await BiliBiliAccountService.instance.loadUserInfo();
    if (BiliBiliAccountService.instance.logined.value &&
        BiliBiliAccountService.instance.name.value != "未登录") {
      SmartDialog.showToast("已登录：${BiliBiliAccountService.instance.name.value}");
    }
  }

  void douyinTap() async {
    if (DouyinAccountService.instance.hasCookie.value) {      var result =
          await Utils.showAlertDialog("确定要清除自定义 ttwid 吗？", title: "清除配置");
      if (result) {
        DouyinAccountService.instance.clearCookie();
        SmartDialog.showToast("已清除自定义 ttwid，将使用默认 ttwid");
      }
    } else {
      doDouyinCookieConfig();
    }
  }

  void doDouyinCookieConfig() {
    // 初始化文本框时，只显示 ttwid 的值部分
    var savedCookie = DouyinAccountService.instance.cookie;
    var displayText = savedCookie;
    if (savedCookie.startsWith('ttwid=')) {
      displayText = savedCookie.substring(6); // 去掉 "ttwid="
    }
    var controller = TextEditingController(text: displayText);

    Get.dialog(
      AlertDialog(
        title: const Text("配置抖音 ttwid"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "默认已内置有效的 ttwid，可观看所有画质（包括蓝光）。\n如有需要可自定义配置。",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: "请粘贴 ttwid 值（留空则使用默认值）",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  // 提取 ttwid 的值部分（去掉 "ttwid=" 前缀）
                  var defaultValue = DouyinSite.kDefaultCookie;
                  if (defaultValue.startsWith('ttwid=')) {
                    defaultValue = defaultValue.substring(6); // 去掉 "ttwid="
                  }
                  controller.text = defaultValue;
                },
                icon: const Icon(Icons.restore),
                label: const Text("恢复默认 ttwid"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              var input = controller.text.trim();
              Get.back();
              if (input.isEmpty) {
                DouyinAccountService.instance.clearCookie();
                SmartDialog.showToast("已清除自定义 Cookie，将使用默认 ttwid");
              } else {
                // 如果用户只输入了 ttwid 值，自动添加 "ttwid=" 前缀
                var cookie = input;
                if (!input.startsWith('ttwid=')) {
                  cookie = 'ttwid=$input';
                }
                DouyinAccountService.instance.setCookie(cookie);
                SmartDialog.showToast("ttwid 已保存");
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 斗鱼账号

  /// 斗鱼账号入口
  ///
  /// 已登录 → 让用户选择「重新授权 / 退出登录」；
  /// 未登录 → 直接进网页授权页。
  void douyuTap() async {
    if (DouyuAccountService.instance.hasAuth.value) {
      Utils.showCompactBottomSheet(
        title: "斗鱼账号",
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text("重新授权"),
                subtitle: const Text("当前授权可能已失效时使用"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Get.back();
                  toDouyuWebLogin();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("手动填写 dy_auth"),
                subtitle: const Text("从浏览器 DevTools 复制"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Get.back();
                  doDouyuAuthInput();
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text("退出登录"),
                subtitle: const Text("清除本机保存的授权参数"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Get.back();
                  var result = await Utils.showAlertDialog(
                      "确定要退出斗鱼账号吗？",
                      title: "退出登录");
                  if (result) {
                    DouyuAccountService.instance.clearAuth();
                    SmartDialog.showToast("已清除斗鱼授权，画质与地址有效期将恢复默认");
                  }
                },
              ),
            ],
          ),
        ),
      );
    } else {
      Utils.showCompactBottomSheet(
        title: "登录斗鱼",
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  "登录后可看原画，且播放地址不再 5 分钟过期。授权仅保存在本机。",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text("网页登录授权"),
                subtitle: const Text("跳转斗鱼网页登录，自动获取授权参数"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Get.back();
                  toDouyuWebLogin();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("手动填写 dy_auth"),
                subtitle: const Text("已从浏览器 DevTools 拿到 Cookie 时使用"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Get.back();
                  doDouyuAuthInput();
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  void toDouyuWebLogin() {
    Get.toNamed(RoutePath.kDouyuWebLogin);
  }

  /// 手动填写 dy_auth
  ///
  /// 保留这个入口是因为网页登录在部分机型上可能碰到 WebView 兼容问题，
  /// 手动粘贴是最后的可行路径。
  /// 输入框允许粘贴整行 Cookie，会自动抽出 `dy_auth` 的值。
  void doDouyuAuthInput() async {
    var input = await Utils.showEditTextDialog(
      "",
      title: "填写 dy_auth",
      hintText: "粘贴 dy_auth 的值，或整行 Cookie",
    );
    if (input == null || input.trim().isEmpty) {
      return;
    }
    var value = DouyuAccountService.parseAuth(input);
    if (value.isEmpty) {
      SmartDialog.showToast("未识别到 dy_auth，请检查输入内容");
      return;
    }
    DouyuAccountService.instance.setAuth(value);
    SmartDialog.showToast("斗鱼授权已保存");
    // 保存后异步校验一次，结果体现在账号页副标题上（不阻塞操作）
    DouyuAccountService.instance.verify().then((verdict) {
      if (verdict == false) {
        SmartDialog.showToast("该 dy_auth 校验未通过，可能已失效");
      } else if (verdict == true) {
        SmartDialog.showToast("斗鱼授权已生效，可观看原画");
      }
    });
  }
}

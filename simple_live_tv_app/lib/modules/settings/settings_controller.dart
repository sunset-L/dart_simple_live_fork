import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_tv_app/app/app_focus_node.dart';
import 'package:simple_live_tv_app/app/controller/base_controller.dart';
import 'package:simple_live_tv_app/app/utils.dart';
import 'package:simple_live_tv_app/routes/app_navigation.dart';
import 'package:simple_live_tv_app/services/bilibili_account_service.dart';
import 'package:simple_live_tv_app/services/douyu_account_service.dart';

class SettingsController extends BaseController
    with GetTickerProviderStateMixin {
  late TabController tabController;
  var tabIndex = 0.obs;

  SettingsController() {
    tabController = TabController(length: 5, vsync: this);
    tabController.animation?.addListener(() {
      var currentIndex = (tabController.animation?.value ?? 0).round();
      if (tabIndex.value == currentIndex) {
        return;
      }
      tabIndex.value = currentIndex;
      if (tabIndex.value == 0) {
        hardwareDecodeFocusNode.requestFocus();
      }
      if (tabIndex.value == 1) {
        danmakuFoucsNode.requestFocus();
      }
      if (tabIndex.value == 2) {
        autoUpdateFollowEnableFocusNode.requestFocus();
      }
      if (tabIndex.value == 3) {
        bilibiliFoucsNode.requestFocus();
      }
      if (tabIndex.value == 4) {
        versionFocusNode.requestFocus();
      }
    });
  }
  var hardwareDecodeFocusNode = AppFocusNode()..isFoucsed.value = true;
  var compatibleModeFocusNode = AppFocusNode();
  var scaleFoucsNode = AppFocusNode();
  var defaultQualityFocusNode = AppFocusNode();
  var danmakuFoucsNode = AppFocusNode();
  var danmakuSizeFoucsNode = AppFocusNode();
  var danmakuSpeedFoucsNode = AppFocusNode();
  var danmakuAreaFoucsNode = AppFocusNode();
  var danmakuOpacityFoucsNode = AppFocusNode();
  var danmakuStorkeFoucsNode = AppFocusNode();

  var autoUpdateFollowEnableFocusNode = AppFocusNode();
  var autoUpdateFollowDurationFocusNode = AppFocusNode();
  var updateFollowThreadFocusNode = AppFocusNode();

  var bilibiliFoucsNode = AppFocusNode();
  var douyuFoucsNode = AppFocusNode();
  var versionFocusNode = AppFocusNode();
  void bilibiliTap() async {
    if (BiliBiliAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出哔哩哔哩账号吗？", title: "退出登录");
      if (result) {
        BiliBiliAccountService.instance.logout();
      }
    } else {
      AppNavigator.toBiliBiliLogin();
    }
  }

  /// 斗鱼账号入口
  ///
  /// 已填写 → 让用户选择「重新填写 / 清除」；
  /// 未填写 → 直接弹输入框。
  ///
  /// TV 端没有 WebView，票据来源是「手机端局域网同步推送」或手动粘贴；
  /// 保存后会写进 [DouyuSite.dyAuth]，取流时自动带上 `Cookie: dy_auth=xxx`。
  void douyuTap() async {
    var service = DouyuAccountService.instance;
    if (service.hasAuth.value) {
      var reinput = await Utils.showAlertDialog(
        "当前已保存斗鱼授权参数。\n\n选择「确定」重新填写，选择「取消」保持现状。",
        title: "斗鱼账号",
        confirm: "重新填写",
      );
      if (!reinput) {
        var logout = await Utils.showAlertDialog(
          "确定要清除本机保存的斗鱼授权吗？\n清除后画质与播放地址有效期将恢复默认。",
          title: "清除授权",
        );
        if (logout) {
          service.clearAuth();
          SmartDialog.showToast("已清除斗鱼授权");
        }
        return;
      }
    }
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
    service.setAuth(value);
    SmartDialog.showToast("斗鱼授权已保存，原画与长效地址已生效");
  }
}

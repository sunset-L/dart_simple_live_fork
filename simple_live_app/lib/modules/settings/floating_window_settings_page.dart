import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/native_player_bridge.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class FloatingWindowSettingsPage extends StatefulWidget {
  const FloatingWindowSettingsPage({super.key});

  @override
  State<FloatingWindowSettingsPage> createState() =>
      _FloatingWindowSettingsPageState();
}

class _FloatingWindowSettingsPageState extends State<FloatingWindowSettingsPage>
    with WidgetsBindingObserver {
  bool _supported = GetPlatform.isAndroid;
  bool? _permission;
  bool _checkingPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshPermission(request: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission({bool request = false}) async {
    if (!_supported || _checkingPermission) return;
    _checkingPermission = true;
    try {
      final native = NativePlayerBridge.instance;
      if (await native.isTvDevice()) {
        if (mounted) setState(() => _supported = false);
        return;
      }
      final granted = await native.hasOverlayPermission();
      if (!mounted) return;
      setState(() => _permission = granted);
      if (request && !granted) {
        await native.requestOverlayPermission();
        final updated = await native.hasOverlayPermission();
        if (mounted) setState(() => _permission = updated);
      }
    } catch (e) {
      Log.logPrint(e);
      if (mounted && request) SmartDialog.showToast("无法打开悬浮窗权限设置");
    } finally {
      _checkingPermission = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsController.instance;
    return Scaffold(
      appBar: AppBar(title: const Text("小窗设置")),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          SettingsCard(
            child: Column(
              children: [
                IgnorePointer(
                  ignoring: !_supported,
                  child: Opacity(
                    opacity: _supported ? 1 : 0.5,
                    child: Obx(
                      () => SettingsSwitch(
                        title: "启用小窗",
                        value: settings.floatingWindowEnable.value,
                        onChanged: (value) {
                          settings.setFloatingWindowEnable(value);
                          if (value) _refreshPermission(request: true);
                        },
                      ),
                    ),
                  ),
                ),
                AppStyle.divider,
                SettingsAction(
                  title: "悬浮窗权限",
                  value: !_supported
                      ? "当前设备不支持"
                      : _permission == null
                          ? "检查中"
                          : _permission!
                              ? "已授权"
                              : "未授权",
                  onTap: _supported
                      ? () => _refreshPermission(request: true)
                      : null,
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsNumber(
                    title: "小窗圆角",
                    value: settings.floatingWindowCornerRadius.value,
                    min: 0,
                    max: 16,
                    unit: "dp",
                    onChanged: settings.setFloatingWindowCornerRadius,
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "小窗贴边",
                    value: settings.floatingWindowDockEnable.value,
                    onChanged: settings.setFloatingWindowDockEnable,
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsNumber(
                    title: "贴边压低音量",
                    subtitle: "贴边后保留的音量比例，100% 不压低，不改变系统音量",
                    value: settings.floatingWindowDockVolumePercent.value,
                    step: 10,
                    min: 10,
                    max: 100,
                    unit: "%",
                    onChanged: settings.setFloatingWindowDockVolumePercent,
                  ),
                ),
                AppStyle.divider,
                SettingsAction(
                  title: "小窗弹幕设置",
                  onTap: () => Get.toNamed(RoutePath.kSettingsFloatingDanmu),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

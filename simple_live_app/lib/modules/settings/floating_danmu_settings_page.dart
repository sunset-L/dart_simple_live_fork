import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

/// 小窗弹幕设置
///
/// 为什么单独一页、单独一套值：
/// 小窗画面只有 240dp 宽、高度一两百 dp，能排下的弹幕轨道只有三四条。
/// 播放器那套参数（字号 16、显示区域 80%、同屏不限条数）搬进来会
/// 直接把画面糊满，两边的最优值差得很远，共用一个配置必然有一边难用。
///
/// 因此这里的每一项都读写 `floatingDanmu*` 前缀的独立存储，
/// 改这里不会影响播放器弹幕，反之亦然。
class FloatingDanmuSettingsPage extends StatelessWidget {
  const FloatingDanmuSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("小窗弹幕设置"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: const [
          FloatingDanmuSettingsView(),
        ],
      ),
    );
  }
}

class FloatingDanmuSettingsView extends GetView<AppSettingsController> {
  const FloatingDanmuSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
          child: Text(
            "基础",
            style: Get.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 小窗是系统悬浮窗，弹幕由原生侧渲染；
              // 关闭时连弹幕连接都不建立，不加载任何数据。
              Obx(
                () => SettingsSwitch(
                  title: "显示弹幕",
                  subtitle: "关闭时不加载弹幕数据，可节省流量与耗电",
                  value: controller.floatingDanmuEnable.value,
                  onChanged: (e) {
                    controller.setFloatingDanmuEnable(e);
                  },
                ),
              ),
              AppStyle.divider,
              // 小窗轨道少，条数一多只能往同一轨上叠（观感是两行字压一起），
              // 所以给出显式上限：超出的直接丢弃，不叠轨。
              Obx(
                () => SettingsNumber(
                  title: "弹幕量",
                  subtitle: "同屏最多显示的条数，过多会互相重叠",
                  value: controller.floatingDanmuAmount.value,
                  min: 2,
                  max: 30,
                  onChanged: (e) {
                    controller.setFloatingDanmuAmount(e);
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
          child: Text(
            "样式",
            style: Get.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 小窗画面小，字号通常需要比播放器大一档，默认 20
              Obx(
                () => SettingsNumber(
                  title: "字号",
                  subtitle: "小窗画面较小，通常需要比播放器字号更大",
                  value: controller.floatingDanmuSize.toInt(),
                  min: 8,
                  max: 48,
                  onChanged: (e) {
                    controller.setFloatingDanmuSize(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "字体粗细",
                  value: controller.floatingDanmuFontWeight.value,
                  min: 1,
                  max: 9,
                  step: 1,
                  displayValue: [
                    "极细",
                    "很细",
                    "细",
                    "正常",
                    "小粗",
                    "偏粗",
                    "粗",
                    "很粗",
                    "极粗"
                  ][controller.floatingDanmuFontWeight.value - 1].toString(),
                  onChanged: (e) {
                    controller.setFloatingDanmuFontWeight(e);
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "不透明度",
                  value: (controller.floatingDanmuOpacity.value * 100).toInt(),
                  min: 10,
                  max: 100,
                  step: 10,
                  unit: "%",
                  onChanged: (e) {
                    controller.setFloatingDanmuOpacity(e / 100.0);
                  },
                ),
              ),
              AppStyle.divider,
              // 小窗高度有限，显示区域默认只占 50%：
              // 铺满会让弹幕盖住主播的脸
              Obx(
                () => SettingsNumber(
                  title: "显示区域",
                  subtitle: "占小窗高度的比例，越小弹幕越集中在顶部",
                  value: (controller.floatingDanmuArea.value * 100).toInt(),
                  min: 10,
                  max: 100,
                  step: 10,
                  unit: "%",
                  onChanged: (e) {
                    controller.setFloatingDanmuArea(e / 100.0);
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "滚动速度",
                  subtitle: "弹幕持续时间(秒)，越小速度越快",
                  value: controller.floatingDanmuSpeed.toInt(),
                  min: 4,
                  max: 20,
                  onChanged: (e) {
                    controller.setFloatingDanmuSpeed(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "顶部边距",
                  subtitle: "小窗贴边时弹幕可能被挡住，可在此下移",
                  value: controller.floatingDanmuTopMargin.toInt(),
                  min: 0,
                  max: 48,
                  step: 4,
                  onChanged: (e) {
                    controller.setFloatingDanmuTopMargin(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "底部边距",
                  value: controller.floatingDanmuBottomMargin.toInt(),
                  min: 0,
                  max: 48,
                  step: 4,
                  onChanged: (e) {
                    controller.setFloatingDanmuBottomMargin(e.toDouble());
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(top: 16),
          child: Text(
            "小窗弹幕与播放器弹幕是两套独立配置，互不影响。"
            "关键词屏蔽两处共用同一套规则。",
            style: Get.textTheme.bodySmall!.copyWith(color: Colors.grey),
          ),
        ),
        AppStyle.vGap24,
      ],
    );
  }
}

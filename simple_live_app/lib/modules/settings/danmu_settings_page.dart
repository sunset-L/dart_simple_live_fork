import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class DanmuSettingsPage extends StatelessWidget {
  const DanmuSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("弹幕设置"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: const [
          DanmuSettingsView(),
        ],
      ),
    );
  }
}

class DanmuSettingsView extends GetView<AppSettingsController> {
  final Function()? onTapDanmuShield;
  final DanmakuController? danmakuController;

  /// 是否显示「小窗弹幕设置」入口
  ///
  /// 只在独立设置页里显示。播放器内的「弹幕配置」面板不显示：
  /// 那里是调当前播放用的，跳走会打断播放。
  final bool showFloatingEntry;
  const DanmuSettingsView({
    this.onTapDanmuShield,
    this.danmakuController,
    this.showFloatingEntry = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
          child: Text(
            "弹幕屏蔽",
            style: Get.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsAction(
                title: "关键词屏蔽",
                onTap: onTapDanmuShield ??
                    () => Get.toNamed(RoutePath.kSettingsDanmuShield),
              ),
              AppStyle.divider,
              // 福袋/抽奖弹幕是平台活动刷屏的主要来源，且没有独立的消息类型，
              // 只能按内容识别。开关只有一份：播放器与小窗共用同一条规则。
              Obx(
                () => SettingsSwitch(
                  title: "屏蔽福袋弹幕",
                  subtitle: "过滤福袋、抽奖、中奖播报等弹幕，对小窗弹幕同样生效",
                  value: controller.danmuShieldFortuneBag.value,
                  onChanged: (e) {
                    controller.setDanmuShieldFortuneBag(e);
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
          child: Text(
            "弹幕设置",
            style: Get.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Obx(
                () => SettingsSwitch(
                  title: "默认开关",
                  value: controller.danmuEnable.value,
                  onChanged: (e) {
                    controller.setDanmuEnable(e);
                  },
                ),
              ),
              AppStyle.divider,
              // 小窗弹幕与播放器弹幕是两套独立配置：
              // 小窗画面小、轨道少，同一套参数必然有一边难用，所以单独一页。
              // 在播放器的「弹幕配置」面板里不显示这个入口——
              // 那里是给当前播放调参用的，跳走会打断播放体验。
              if (showFloatingEntry) ...[
                SettingsAction(
                  title: "小窗弹幕设置",
                  subtitle: "字号、弹幕量、透明度等独立配置",
                  onTap: () => Get.toNamed(RoutePath.kSettingsFloatingDanmu),
                ),
                AppStyle.divider,
              ],
              Obx(
                () => SettingsNumber(
                  title: "显示区域",
                  value: (controller.danmuArea.value * 100).toInt(),
                  min: 10,
                  max: 100,
                  step: 10,
                  unit: "%",
                  onChanged: (e) {
                    controller.setDanmuArea(e / 100.0);
                    updateDanmuOption(
                      danmakuController?.option.copyWith(area: e / 100.0),
                    );
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "不透明度",
                  value: (controller.danmuOpacity.value * 100).toInt(),
                  min: 10,
                  max: 100,
                  step: 10,
                  unit: "%",
                  onChanged: (e) {
                    controller.setDanmuOpacity(e / 100.0);
                    updateDanmuOption(
                      danmakuController?.option.copyWith(opacity: e / 100.0),
                    );
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "字体大小",
                  value: controller.danmuSize.toInt(),
                  min: 8,
                  max: 48,
                  onChanged: (e) {
                    controller.setDanmuSize(e.toDouble());
                    updateDanmuOption(
                      danmakuController?.option
                          .copyWith(fontSize: e.toDouble()),
                    );
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "字体粗细",
                  value: controller.danmuFontWeight.value,
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
                  ][controller.danmuFontWeight.value - 1]
                      .toString(),
                  onChanged: (e) {
                    controller.setDanmuFontWeight(e);
                    updateDanmuOption(
                      danmakuController?.option.copyWith(
                        fontWeight: e,
                      ),
                    );
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "滚动速度",
                  subtitle: "弹幕持续时间(秒)，越小速度越快",
                  value: controller.danmuSpeed.toInt(),
                  min: 4,
                  max: 20,
                  onChanged: (e) {
                    controller.setDanmuSpeed(e.toDouble());
                    updateDanmuOption(
                      danmakuController?.option.copyWith(duration: e.toInt()),
                    );
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "顶部边距",
                  subtitle: "曲面屏显示不全可设置此选项",
                  value: controller.danmuTopMargin.toInt(),
                  min: 0,
                  max: 48,
                  step: 4,
                  onChanged: (e) {
                    controller.setDanmuTopMargin(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "底部边距",
                  subtitle: "曲面屏显示不全可设置此选项",
                  value: controller.danmuBottomMargin.toInt(),
                  min: 0,
                  max: 48,
                  step: 4,
                  onChanged: (e) {
                    controller.setDanmuBottomMargin(e.toDouble());
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void updateDanmuOption(DanmakuOption? option) {
    if (danmakuController == null || option == null) return;
    danmakuController!.updateOption(option);
  }
}
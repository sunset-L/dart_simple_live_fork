import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';

class AppstyleSettingPage extends GetView<AppSettingsController> {
  const AppstyleSettingPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("外观设置"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "显示主题",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Obx(
              () => RadioGroup(
                groupValue: controller.themeMode.value,
                onChanged: (e) {
                  controller.setTheme(e ?? 0);
                },
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<int>(
                      title: Text(
                        "跟随系统",
                      ),
                      visualDensity: VisualDensity.compact,
                      value: 0,
                      contentPadding: AppStyle.edgeInsetsH12,
                    ),
                    RadioListTile<int>(
                      title: Text(
                        "浅色模式",
                      ),
                      visualDensity: VisualDensity.compact,
                      value: 1,
                      contentPadding: AppStyle.edgeInsetsH12,
                    ),
                    RadioListTile<int>(
                      title: Text(
                        "深色模式",
                      ),
                      visualDensity: VisualDensity.compact,
                      value: 2,
                      contentPadding: AppStyle.edgeInsetsH12,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AppStyle.vGap12,
          Padding(
            padding: AppStyle.edgeInsetsA12,
            child: Text(
              "主题颜色",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            // 这里不能套 Obx：外层只是容器，本身不读任何 Rx 值。
            // GetX 的 Obx 一旦在 builder 里没读到 observable 就会直接抛
            // 「improper use of a GetX」异常，整块渲染不出来（表现为一片灰底）。
            // 真正需要响应式的只有下面每个色块里的选中态，它们各自有 Obx。
            child: Padding(
              padding: AppStyle.edgeInsetsA12,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Color>[
                  const Color(0xffEF5350),
                  const Color(0xff3498db),
                  const Color(0xffF06292),
                  const Color(0xff9575CD),
                  const Color(0xff26C6DA),
                  const Color(0xff26A69A),
                  const Color(0xffFFF176),
                  const Color(0xffFF9800),
                ]
                    .map(
                      (e) => GestureDetector(
                        onTap: () {
                          controller.setStyleColor(e.toARGB32());
                          Get.forceAppUpdate();
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: e,
                            borderRadius: AppStyle.radius4,
                            border: Border.all(
                              color: Colors.grey.withAlpha(50),
                              width: 1,
                            ),
                          ),
                          child: Obx(
                            () => Center(
                              child: Icon(
                                Icons.check,
                                color: controller.styleColor.value ==
                                        e.toARGB32()
                                    ? Colors.white
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// extension ColorExt on Color {
//   static int _floatToInt8(double x) {
//     return (x * 255.0).round() & 0xff;
//   }

//   int get v =>
//       _floatToInt8(a) << 24 |
//       _floatToInt8(r) << 16 |
//       _floatToInt8(g) << 8 |
//       _floatToInt8(b) << 0;
// }

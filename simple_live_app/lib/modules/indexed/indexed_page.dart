import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/services/native_player_bridge.dart';

import 'indexed_controller.dart';

class IndexedPage extends GetView<IndexedController> {
  const IndexedPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 首页是根页面，系统默认行为会 finish 掉 Activity，
      // 连带 Flutter 引擎一起销毁——如果此时小窗还在播放，
      // 就变成「小窗活着但 App 已经没了」的状态：
      // 再点小窗只会冷启动 App，回不到原来那个直播页。
      //
      // 这里改成「退到后台」：Activity 与引擎都保留，
      // 小窗和播放器继续活着，点小窗能原样回到前台。
      canPop: false,
      onPopInvokedWithResult: (didPop, r) async {
        if (didPop) {
          return;
        }
        // 小窗在播放时不用特殊处理，退后台后它本来就浮在桌面上；
        // 不在播放时也只是把任务移到后台，用户再点图标即可回来。
        await NativePlayerBridge.instance.moveToBack();
      },
      child: OrientationBuilder(
      builder: (context, orientation) {
        return Scaffold(
          body: Row(
            children: [
              Visibility(
                visible: orientation == Orientation.landscape,
                child: Obx(
                  () => NavigationRail(
                    selectedIndex: controller.index.value,
                    onDestinationSelected: controller.setIndex,
                    labelType: NavigationRailLabelType.none,
                    destinations: controller.items
                        .map(
                          (item) => NavigationRailDestination(
                            icon: Icon(item.iconData),
                            label: Text(item.title),
                            padding: AppStyle.edgeInsetsV8,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              Expanded(
                child: Obx(
                  () => Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: orientation == Orientation.landscape
                            ? BorderSide(
                                color: Colors.grey.withAlpha(50),
                                width: 1,
                              )
                            : BorderSide.none,
                      ),
                    ),
                    child: IndexedStack(
                      index: controller.index.value,
                      children: controller.pages,
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: Visibility(
            visible: orientation == Orientation.portrait,
            child: Obx(
              () => NavigationBar(
                selectedIndex: controller.index.value,
                onDestinationSelected: controller.setIndex,
                height: 56,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                destinations: controller.items
                    .map(
                      (item) => NavigationDestination(
                        icon: Icon(item.iconData),
                        label: item.title,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        );
      },
      ),
    );
  }
}

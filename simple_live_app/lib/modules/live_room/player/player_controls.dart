import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_room_list_panel.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/widgets/swipe_dismissible_panel.dart';

/// 播放器叠层控件
///
/// 直播没有进度概念，因此不含进度条；
/// 只保留：刷新、弹幕开关、弹幕设置、清晰度、线路、全屏、返回、小窗、锁定。
Widget playerControls(LiveRoomController controller) {
  return Stack(
    children: [
      Positioned.fill(
        child: Obx(() {
          if (controller.fullScreenTransitioning.value) {
            return const SizedBox.expand();
          }
          if (controller.fullScreenState.value) {
            return const SizedBox.expand();
          }
          return buildControls(
            MediaQuery.of(Get.context!).orientation == Orientation.portrait,
            controller,
          );
        }),
      ),
    ],
  );
}

Widget buildControls(
  bool isPortrait,
  LiveRoomController controller,
) {
  return Stack(
    children: [
      // 竖屏播放器内不叠加弹幕：
      // 页面下方已经有完整的弹幕列表，播放器里再滚一遍既拥挤又重复。
      // 弹幕只在全屏时显示。

      // 缓冲指示
      Positioned.fill(
        child: IgnorePointer(
          child: Obx(
            () => Visibility(
              visible: controller.buffering.value,
              child: const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          ),
        ),
      ),

      // 手势层：单击显隐控件，双击全屏
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 不注册 onDoubleTap：会拖慢单击响应。
          // 双击在 controller.onTap 内部按时间差自行判定。
          onTap: controller.onTap,
          onVerticalDragStart: controller.onVerticalDragStart,
          onVerticalDragUpdate: controller.onVerticalDragUpdate,
          onVerticalDragEnd: controller.onVerticalDragEnd,
          onVerticalDragCancel: controller.onVerticalDragCancel,
          child: const SizedBox.expand(),
        ),
      ),

      // 底部控件条：左下角刷新/弹幕开关/弹幕设置，右下角全屏
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Obx(
          () => AnimatedSlide(
            offset: controller.showControlsState.value
                ? Offset.zero
                : const Offset(0, 1),
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black87,
                  ],
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: "刷新",
                    onPressed: controller.refreshRoom,
                    icon: const Icon(
                      Remix.refresh_line,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  Obx(
                    () => IconButton(
                      tooltip:
                          controller.showDanmakuState.value ? "关闭弹幕" : "开启弹幕",
                      onPressed: () => controller.showDanmakuState.value =
                          !controller.showDanmakuState.value,
                      // 改用语义明确的系统图标：
                      // 原来那两张 png 都是一样的弹幕框图形，
                      // 只能靠文件名区分，用户看不出开关状态。
                      icon: Icon(
                        controller.showDanmakuState.value
                            ? Icons.subtitles
                            : Icons.subtitles_off,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "弹幕设置",
                    onPressed: controller.showDanmuSettingsSheet,
                    icon: const ImageIcon(
                      AssetImage('assets/icons/icon_danmaku_setting.png'),
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Obx(
                      () => Text(
                        controller.liveDuration.value,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: "全屏",
                    onPressed: controller.enterFullScreen,
                    icon: const Icon(
                      Remix.fullscreen_line,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // 手势提示
      Positioned.fill(
        child: IgnorePointer(
          child: Obx(
            () => Visibility(
              visible: controller.showGestureTip.value,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    controller.gestureTipText.value,
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

void showLinesInfo(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showPlayUrlsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "线路",
    useSystem: true,
    child: Obx(() {
      final playing = controller.playingLineIndex.value;
      final connecting = controller.lineConnecting.value;
      final target = controller.currentLineIndex;
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: controller.effectiveLineCount,
        itemBuilder: (_, i) {
          final hasUrl = i < controller.playUrls.length &&
              controller.playUrls[i].isNotEmpty;
          return ListTile(
            selected: playing == i,
            title: Text(
                connecting && target == i ? "线路${i + 1}（连接中）" : "线路${i + 1}"),
            trailing: hasUrl
                ? Text(controller.playUrls[i].contains(".flv") ? "FLV" : "HLS")
                : null,
            onTap: hasUrl
                ? () {
                    Utils.hideRightDialog();
                    controller.changePlayLine(i);
                  }
                : null,
          );
        },
      );
    }),
  );
}

void showQualitesInfo(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showQualitySheet();
    return;
  }
  Utils.showRightDialog(
    title: "清晰度",
    useSystem: true,
    child: Obx(() {
      final selected = controller.currentQuality;
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: controller.qualites.length,
        itemBuilder: (_, i) {
          var item = controller.qualites[i];
          return ListTile(
            selected: selected == i,
            title: Text(
              item.quality,
              style: const TextStyle(fontSize: 14),
            ),
            minLeadingWidth: 16,
            onTap: () {
              Utils.hideRightDialog();
              controller.changePlayQuality(i);
            },
          );
        },
      );
    }),
  );
}

void showDanmakuSettings(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showDanmuSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "弹幕设置",
    width: 400,
    useSystem: true,
    child: ListView(
      padding: AppStyle.edgeInsetsA12,
      children: const [
        DanmuSettingsView(
          showFloatingEntry: false,
        ),
      ],
    ),
  );
}

void showPlayerSettings(LiveRoomController controller) {
  if (controller.isVertical.value) {
    controller.showPlayerSettingsSheet();
    return;
  }
  Utils.showRightDialog(
    title: "设置",
    width: 320,
    useSystem: true,
    child: Obx(
      () => RadioGroup(
        groupValue: AppSettingsController.instance.scaleMode.value,
        onChanged: (e) {
          AppSettingsController.instance.setScaleMode(e ?? 0);
        },
        child: ListView(
          padding: AppStyle.edgeInsetsV12,
          children: [
            Padding(
              padding: AppStyle.edgeInsetsH16,
              child: Text(
                "画面尺寸",
                style: Get.textTheme.titleMedium,
              ),
            ),
            const RadioListTile(
              value: 0,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("适应"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 1,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("拉伸"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 2,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("铺满"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 3,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("16:9"),
              visualDensity: VisualDensity.compact,
            ),
            const RadioListTile(
              value: 4,
              contentPadding: AppStyle.edgeInsetsH4,
              title: Text("4:3"),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    ),
  );
}

/// 打开「关注 / 历史」双页列表
///
/// 竖屏走底部弹窗，横屏走右侧滑窗——容器不同，内容同一份
/// （见 [PlayerRoomListPanel]）。左右滑动切换关注与历史，
/// 也可以点标题上的「关注 / 历史」直接跳。
void showFollowUser(LiveRoomController controller) {
  // 打开某个房间：**不关弹窗**，直接切。
  //
  // 之前这里会先 `Utils.hideRightDialog()` 再切，理由写的是「切房间会重建
  // 页面树，弹窗挂在旧的 Navigator 上会变成孤儿浮层」。实际上不成立：
  // 这个面板走 `SmartDialog` 且 `useSystem: true`，挂在独立的 system overlay 上，
  // 与 LiveRoomController 所在的页面/路由无关；`resetRoom()` 也只是改
  // rxSite/rxRoomId 并重新取流，不 push/pop 任何路由。所以弹窗可以原地留着，
  // 让用户连续挑下一个房间。
  void open(RoomTarget target) {
    final site = Sites.allSites[target.siteId];
    if (site == null) {
      // 站点已不存在（配置迁移、降级安装）：静默忽略，不能崩
      return;
    }
    controller.resetRoom(site, target.roomId);
  }

  if (!controller.fullScreenState.value) {
    // 竖屏底部弹窗。
    // showHeader: false —— 面板自带标题（关注/历史可点左右翻页），
    // 这里再套一层默认标题行就是两层标题。
    // 关窗用 Get.back：Utils.showBottomSheet 走的是 showModalBottomSheet，
    // 属于全局 Navigator 路由，Get.back 关的就是它。
    Utils.showBottomSheet(
      title: "关注 / 历史",
      showHeader: false,
      dialogBuilder: (child) => SwipeDismissiblePanel(
        onDismiss: Get.back,
        child: child,
      ),
      child: PlayerRoomListPanel(
        controller: controller,
        onOpen: open,
        onClose: Get.back,
        itemPadding: const EdgeInsets.only(left: 12, right: 4),
      ),
    );
    return;
  }

  Utils.showRightDialog(
    title: "关注 / 历史",
    width: 360,
    useSystem: true,
    showHeader: false,
    dialogBuilder: (child) => SwipeDismissiblePanel(
      onDismiss: Utils.hideRightDialog,
      child: child,
    ),
    child: PlayerRoomListPanel(
      controller: controller,
      onOpen: open,
      onClose: Utils.hideRightDialog,
      // 右侧滑窗有圆角，靠边内容容易被切，左右都留一点
      itemPadding: const EdgeInsets.only(left: 12, right: 8),
      headerLeftPadding: 8,
      headerRightPadding: 0,
    ),
  );
}

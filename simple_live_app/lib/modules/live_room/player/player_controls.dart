import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_room_list_panel.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/widgets/superchat_card.dart';
import 'package:simple_live_app/widgets/swipe_dismissible_panel.dart';
import 'dart:async';
import 'package:simple_live_core/simple_live_core.dart';

/// 播放器叠层控件
///
/// 直播没有进度概念，因此不含进度条；
/// 只保留：刷新、弹幕开关、弹幕设置、清晰度、线路、全屏、返回、小窗、锁定。
Widget playerControls(LiveRoomController controller) {
  return Stack(
    children: [
      buildDanmuView(controller),
      Positioned.fill(
        child: Obx(() {
          if (controller.fullScreenState.value) {
            return buildFullControls(controller);
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

/// 全屏底栏的胶囊按钮（清晰度 / 线路）
Widget _fullScreenChipButton({
  required VoidCallback onTap,
  required RxString label,
  required IconData icon,
}) {
  return Obx(
    () => InkWell(
      onTap: onTap,
      borderRadius: AppStyle.radius8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: AppStyle.radius8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            AppStyle.hGap4,
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                label.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget buildFullControls(LiveRoomController controller) {
  final context = Get.context!;
  // 全屏是沉浸式：系统栏已经被 enterFullScreen 隐藏掉了，
  // 这里**不能再按 padding.top / padding.bottom 布局**。
  //
  // 原因：部分机型/系统（尤其 Android 15+ 强制 edge-to-edge）在系统栏
  // 隐藏后仍然上报状态栏、导航栏的高度，于是顶部控件被额外往下压
  // （状态栏高度）、底部控件被额外往上顶（导航栏高度），
  // 表现就是「上下间距都变大了」。
  //
  // 左右方向保留：横屏时挖孔/曲面屏可能遮挡，需要避让。
  var padding = MediaQuery.of(context).padding.copyWith(top: 0, bottom: 0);
  return Stack(
    children: [
      // 左下角SC显示
      Positioned(
        left: 24,
        bottom: 24,
        child: Obx(
          () => Visibility(
            visible: AppSettingsController.instance.playershowSuperChat.value,
            child: PlayerSuperChatOverlay(controller: controller),
          ),
        ),
      ),

      // 缓冲指示
      Positioned.fill(
        child: IgnorePointer(
          child: Obx(
            () => Visibility(
              visible: controller.buffering.value,
              child: const Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          ),
        ),
      ),

      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 与竖屏一致：双击由 onTap 内部按时间差判定，避免单击延迟
          onTap: controller.onTap,
          onLongPress: () {
            if (controller.lockControlsState.value) {
              return;
            }
            showFollowUser(controller);
          },
          onVerticalDragStart: controller.onVerticalDragStart,
          onVerticalDragUpdate: controller.onVerticalDragUpdate,
          onVerticalDragEnd: controller.onVerticalDragEnd,
          onVerticalDragCancel: controller.onVerticalDragCancel,
          child: const SizedBox.expand(),
        ),
      ),

      // 顶部
      Obx(
        () => AnimatedPositioned(
          left: 0,
          right: 0,
          top: (controller.showControlsState.value &&
                  !controller.lockControlsState.value)
              ? 0
              : -48,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 48,
            padding: EdgeInsets.only(
              left: padding.left + 12,
              right: padding.right + 12,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.transparent,
                  Colors.black87,
                ],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    controller.exitFull();
                  },
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                AppStyle.hGap12,
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          controller.detail.value == null
                              ? '正在读取直播信息...'
                              : "${controller.detail.value?.title} - ${controller.detail.value?.userName}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (controller.detail.value != null) ...[
                        AppStyle.hGap8,
                        Semantics(
                          label:
                              '热度 ${Utils.onlineToString(controller.roomPopularity.value)}',
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.whatshot,
                                color: Colors.white70,
                                size: 16,
                              ),
                              AppStyle.hGap4,
                              Text(
                                Utils.onlineToString(
                                  controller.roomPopularity.value,
                                ),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AppStyle.hGap12,
                IconButton(
                  onPressed: () {
                    showFollowUser(controller);
                  },
                  icon: const Icon(
                    Remix.play_list_2_line,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                // TV 端不显示小窗入口
                Obx(
                  () => Visibility(
                    visible: controller.floatingEnabled &&
                        !controller.isFloating.value,
                    child: IconButton(
                      onPressed: () async {
                        final ok = await controller.enterFloatingWindow();
                        if (ok) {
                          Get.back();
                        }
                      },
                      icon: const Icon(
                        Icons.picture_in_picture,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    showPlayerSettings(controller);
                  },
                  icon: const Icon(
                    Icons.more_horiz,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // 底部
      Obx(
        () => AnimatedPositioned(
          left: 0,
          right: 0,
          bottom: (controller.showControlsState.value &&
                  !controller.lockControlsState.value)
              ? 0
              : -(64 + padding.bottom),
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
            // 底部不再额外 +8：那 8dp 会把整排图标从屏幕底边顶起来，
            // 平时不明显，一旦系统栏也被隐藏就会显得「离底边太远」。
            padding: EdgeInsets.only(
              left: padding.left + 12,
              right: padding.right + 12,
              bottom: padding.bottom,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    controller.refreshRoom();
                  },
                  icon: const Icon(
                    Remix.refresh_line,
                    color: Colors.white,
                  ),
                ),
                Obx(
                  () => IconButton(
                    tooltip:
                        controller.showDanmakuState.value ? "关闭弹幕" : "开启弹幕",
                    onPressed: () => controller.showDanmakuState.value =
                        !controller.showDanmakuState.value,
                    icon: Icon(
                      controller.showDanmakuState.value
                          ? Icons.subtitles
                          : Icons.subtitles_off,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    showDanmakuSettings(controller);
                  },
                  icon: const ImageIcon(
                    AssetImage('assets/icons/icon_danmaku_setting.png'),
                    size: 24,
                    color: Colors.white,
                  ),
                ),
                // 播放信息：显示/隐藏当前流的实时播放参数
                Obx(
                  () => IconButton(
                    tooltip: controller.metricsPanelVisible.value
                        ? "隐藏播放信息"
                        : "显示播放信息",
                    onPressed: controller.toggleMetricsPanel,
                    icon: Icon(
                      controller.metricsPanelVisible.value
                          ? Remix.information_fill
                          : Remix.information_line,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
                Obx(
                  () => Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text(
                      controller.liveDuration.value,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ),
                const Expanded(child: Center()),
                // 全屏下右下角补充：清晰度、线路
                _fullScreenChipButton(
                  onTap: controller.showQualitySheet,
                  label: controller.currentQualityInfo,
                  icon: Icons.hd_outlined,
                ),
                AppStyle.hGap4,
                _fullScreenChipButton(
                  onTap: controller.showPlayUrlsSheet,
                  label: controller.currentLineInfo,
                  icon: Icons.switch_video_outlined,
                ),
                AppStyle.hGap8,
                IconButton(
                  tooltip: "退出全屏",
                  onPressed: controller.exitFull,
                  icon: const Icon(
                    Remix.fullscreen_exit_fill,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // 播放参数浮层：叠在底部控件栏上方
      //
      // 必须放在这里（手势层 Positioned.fill 之后），
      // 否则点击会被全屏手势层的 onTap 吃掉，表现为「点了没反应」。
      //
      // Positioned 放在最外层：它是 ParentDataWidget，必须能直接找到
      // 最近的 Stack 祖先。若把 Positioned 包在 Visibility 里面，
      // 定位会失效、面板会跑到左上角。
      Positioned(
        left: padding.left + 12,
        bottom: padding.bottom + 56,
        child: Obx(
          () => Visibility(
            visible: controller.metricsPanelVisible.value,
            child: PlayerMetricsPanel(controller: controller),
          ),
        ),
      ),

      // 右侧锁定
      Obx(
        () => AnimatedPositioned(
          top: 0,
          bottom: 0,
          right: controller.showControlsState.value
              ? padding.right + 12
              : -(64 + padding.right),
          duration: const Duration(milliseconds: 200),
          child: buildLockButton(controller),
        ),
      ),
      Obx(
        () => Offstage(
          offstage: !controller.showGestureTip.value,
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
    ],
  );
}

Widget buildLockButton(LiveRoomController controller) {
  return Center(
    child: InkWell(
      onTap: () {
        controller.setLockState();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: AppStyle.radius8,
        ),
        width: 40,
        height: 40,
        child: Center(
          child: Icon(
            controller.lockControlsState.value
                ? Icons.lock_outline_rounded
                : Icons.lock_open_outlined,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    ),
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

Widget buildDanmuView(LiveRoomController controller) {
  return Positioned.fill(
    child: _PlayerDanmakuLayer(
      key: ObjectKey(controller),
      controller: controller,
    ),
  );
}

class _PlayerDanmakuLayer extends StatefulWidget {
  final LiveRoomController controller;

  const _PlayerDanmakuLayer({required this.controller, super.key});

  @override
  State<_PlayerDanmakuLayer> createState() => _PlayerDanmakuLayerState();
}

class _PlayerDanmakuLayerState extends State<_PlayerDanmakuLayer>
    with WidgetsBindingObserver {
  late final Widget _view;
  late final Worker _fullScreenWorker;
  DanmakuController? _danmakuController;
  final _pauseElapsed = Stopwatch();
  Timer? _resumeTimer;
  bool _paused = false;
  bool _ready = false;
  bool _background = false;

  @override
  void initState() {
    super.initState();
    _background =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused;
    _fullScreenWorker =
        ever(widget.controller.fullScreenState, (_) => _syncPlayback());
    WidgetsBinding.instance.addObserver(this);
    final settings = AppSettingsController.instance;
    _view = DanmakuScreen(
      key: widget.controller.globalDanmuKey,
      createdController: (controller) {
        _danmakuController = controller;
        widget.controller.initDanmakuController(controller);
        // createdController 回调早于库内部动画初始化，帧结束后再暂停/恢复。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _ready = true;
          _syncPlayback();
        });
      },
      option: DanmakuOption(
        fontSize: settings.danmuSize.value,
        area: settings.danmuArea.value,
        duration: settings.danmuSpeed.value.toInt(),
        opacity: settings.danmuOpacity.value,
        fontWeight: settings.danmuFontWeight.value,
      ),
    );
    widget.controller.danmakuView = _view;
  }

  void _syncPlayback() {
    if (!_ready || !mounted) return;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    if (_background || !widget.controller.fullScreenState.value) {
      // 半屏不积攒画面弹幕，保持原来的全屏显示行为，同时保留渲染器状态。
      if (!_paused) {
        _danmakuController?.clear();
        _danmakuController?.pause();
        _paused = true;
        _pauseElapsed
          ..reset()
          ..start();
      }
      return;
    }
    if (!_paused) return;
    // 库的清理循环每 100ms 醒来；快速切换时等旧循环结束再恢复，
    // 避免 pause/resume 之间的短间隔启动两条清理循环。
    final remaining = const Duration(milliseconds: 120) - _pauseElapsed.elapsed;
    if (remaining > Duration.zero) {
      _resumeTimer = Timer(remaining, _resumePlayback);
    } else {
      _resumePlayback();
    }
  }

  void _resumePlayback() {
    if (!mounted ||
        !_ready ||
        _background ||
        !widget.controller.fullScreenState.value) {
      return;
    }
    _paused = false;
    _pauseElapsed.stop();
    _danmakuController?.resume();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _background = true;
      _syncPlayback();
    } else if (state == AppLifecycleState.resumed) {
      _background = false;
      _syncPlayback();
    }
  }

  @override
  void dispose() {
    _ready = false;
    _resumeTimer?.cancel();
    _pauseElapsed.stop();
    _fullScreenWorker.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (identical(widget.controller.danmakuView, _view)) {
      widget.controller.danmakuView = null;
    }
    if (identical(widget.controller.danmakuController, _danmakuController)) {
      widget.controller.danmakuController = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Offstage(
        offstage: !widget.controller.fullScreenState.value ||
            !widget.controller.showDanmakuState.value,
        child: Padding(
          // 全屏只使用用户设置的上下边距，避免系统栏安全区重复占位。
          padding: widget.controller.fullScreenState.value
              ? EdgeInsets.only(
                  top: AppSettingsController.instance.danmuTopMargin.value,
                  bottom:
                      AppSettingsController.instance.danmuBottomMargin.value,
                )
              : EdgeInsets.zero,
          child: _view,
        ),
      ),
    );
  }
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
      children: [
        DanmuSettingsView(
          danmakuController: controller.danmakuController,
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

  if (controller.isVertical.value) {
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

class PlayerSuperChatCard extends StatefulWidget {
  final LiveSuperChatMessage message;
  final VoidCallback onExpire;
  final int duration;
  const PlayerSuperChatCard(
      {required this.message,
      required this.onExpire,
      required this.duration,
      Key? key})
      : super(key: key);
  @override
  State<PlayerSuperChatCard> createState() => _PlayerSuperChatCardState();
}

class _PlayerSuperChatCardState extends State<PlayerSuperChatCard> {
  late Timer timer;
  late int countdown;
  @override
  void initState() {
    super.initState();
    countdown = widget.duration;
    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (countdown <= 1) {
        widget.onExpire();
        timer.cancel();
        return;
      }
      setState(() {
        countdown -= 1;
      });
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.65,
      child: SuperChatCard(
        widget.message,
        onExpire: () {},
        customCountdown: countdown,
      ),
    );
  }
}

class LocalDisplaySC {
  final LiveSuperChatMessage sc;
  final DateTime expireAt;
  final int duration;
  LocalDisplaySC(this.sc, this.expireAt, this.duration);
}

class PlayerSuperChatOverlay extends StatefulWidget {
  final LiveRoomController controller;
  const PlayerSuperChatOverlay({required this.controller, Key? key})
      : super(key: key);
  @override
  State<PlayerSuperChatOverlay> createState() => _PlayerSuperChatOverlayState();
}

class _PlayerSuperChatOverlayState extends State<PlayerSuperChatOverlay> {
  final List<LocalDisplaySC> _displayed = [];
  final Map<LocalDisplaySC, Timer> _timers = {};
  late Worker _worker;

  void _addSC(LiveSuperChatMessage sc, {int? customSeconds}) {
    if (_displayed.any((e) => e.sc == sc)) return;
    int showSeconds = customSeconds ?? 15;
    final expireAt = DateTime.now().add(Duration(seconds: showSeconds));
    final localSC = LocalDisplaySC(sc, expireAt, showSeconds);
    _displayed.add(localSC);
    _timers[localSC] = Timer(Duration(seconds: showSeconds), () {
      setState(() {
        _displayed.remove(localSC);
        _timers.remove(localSC)?.cancel();
      });
    });
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var sc in widget.controller.superChats) {
      int remain = (sc.endTime.millisecondsSinceEpoch - now) ~/ 1000;
      if (remain > 0) {
        _addSC(sc, customSeconds: remain < 15 ? remain : 15);
      }
    }
    _worker =
        ever<List<LiveSuperChatMessage>>(widget.controller.superChats, (list) {
      for (var sc in list) {
        if (!_displayed.any((e) => e.sc == sc)) {
          _addSC(sc);
        }
      }
      _displayed.removeWhere((e) => !list.contains(e.sc));
      setState(() {});
    });
  }

  @override
  void dispose() {
    _worker.dispose();
    for (var t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _displayed.toList()
      ..sort((a, b) => a.sc.endTime.compareTo(b.sc.endTime));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var localSC in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: 240,
              child: PlayerSuperChatCard(
                message: localSC.sc,
                onExpire: () {},
                duration: localSC.duration,
              ),
            ),
          ),
      ],
    );
  }
}

/// 全屏播放参数浮层
///
/// 只负责「显示内容」：开关按钮在底部控件栏里（弹幕配置右侧），
/// 由它调用 controller.toggleMetricsPanel。
/// 关闭时 controller 会停掉原生采集与轮询，
/// 满足「关闭后不在后台继续监听」。
class PlayerMetricsPanel extends StatelessWidget {
  final LiveRoomController controller;

  const PlayerMetricsPanel({required this.controller, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final metrics = controller.playbackMetrics.value;
      return Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: AppStyle.radius8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "播放信息",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppStyle.hGap8,
                Text(
                  controller.currentQualityInfo.value,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            AppStyle.vGap4,
            // 说明这些数字是实测的：
            // 码率/帧率需要采样 2 秒左右才有值，先说清楚避免被当成故障
            const Text(
              "以下为当前流的实测数据",
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
            AppStyle.vGap8,
            if (metrics == null)
              const Text(
                "正在读取…",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              )
            else ...[
              _row("分辨率", metrics.resolutionText),
              _row("帧率", metrics.frameRateText),
              _row("码率", metrics.videoBitrateText),
              if (metrics.videoCodec.isNotEmpty)
                _row("视频编码", metrics.videoCodec.split('.').first),
              _row("音频", metrics.audioText),
              _row("线路", controller.currentLineInfo.value),
            ],
          ],
        ),
      );
    });
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

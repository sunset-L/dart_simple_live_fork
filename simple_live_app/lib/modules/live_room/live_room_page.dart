import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_layout.dart';
import 'package:simple_live_app/modules/live_room/live_room_status_overlay.dart';
import 'package:simple_live_app/modules/live_room/player/player_controls.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';
import 'package:simple_live_app/widgets/superchat_card.dart';
import 'package:simple_live_core/simple_live_core.dart';

class LiveRoomPage extends GetView<LiveRoomController> {
  const LiveRoomPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return buildPageUI(context);
  }

  Widget buildPageUI(BuildContext context) {
    // 子树在全屏 Obx 外创建，全屏状态变化不会重新构建聊天和视频。
    final player = buildMediaPlayer();
    final sidebar = Builder(
      builder: (context) => Obx(
        () => Column(
          children: [
            buildUserProfile(context),
            buildMessageArea(),
          ],
        ),
      ),
    );
    final portraitActions = Builder(builder: buildBottomActions);
    final landscapeActions = Builder(builder: buildLandscapeActions);
    final appBar = AppBar(
      title: Obx(
        () => Text(controller.detail.value?.title ?? "直播间"),
      ),
      actions: buildAppbarActions(context),
    );

    return Obx(
      () => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, r) async {
          if (didPop) return;
          if (controller.fullScreenState.value) {
            controller.exitFull();
          } else {
            await controller.handleBackPressed();
          }
        },
        child: Scaffold(
          backgroundColor:
              controller.fullScreenState.value ? Colors.black : null,
          appBar: controller.fullScreenState.value ? null : appBar,
          body: LiveRoomLayout(
            fullScreen: controller.fullScreenState.value,
            player: player,
            sidebar: sidebar,
            portraitActions: portraitActions,
            landscapeActions: landscapeActions,
          ),
        ),
      ),
    );
  }

  Widget buildLandscapeActions(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
        ),
      ),
      padding: AppStyle.edgeInsetsV4.copyWith(
        bottom: MediaQuery.paddingOf(context).bottom + 4,
      ),
      child: Row(
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 14),
            ),
            onPressed: controller.refreshRoom,
            icon: const Icon(Remix.refresh_line),
            label: const Text("刷新"),
          ),
          AppStyle.hGap4,
          Obx(
            () => controller.followed.value
                ? TextButton.icon(
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                    onPressed: controller.removeFollowUser,
                    icon: const Icon(Remix.heart_fill),
                    label: const Text("取消关注"),
                  )
                : TextButton.icon(
                    style: TextButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 14),
                    ),
                    onPressed: controller.followUser,
                    icon: const Icon(Remix.heart_line),
                    label: const Text("关注"),
                  ),
          ),
          const Expanded(child: Center()),
          TextButton.icon(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 14),
            ),
            onPressed: controller.share,
            icon: const Icon(Remix.share_line),
            label: const Text("分享"),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 14),
            ),
            onPressed: controller.copyUrl,
            icon: const Icon(Remix.file_copy_line),
            label: const Text("复制链接"),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 14),
            ),
            onPressed: controller.copyPlayUrl,
            icon: const Icon(Remix.file_copy_line),
            label: const Text("复制播放直链"),
          ),
        ],
      ),
    );
  }

  Widget buildMediaPlayer() {
    return Stack(
      children: [
        // 视频画面：ExoPlayer 渲染到 Flutter 外部纹理
        // 纹理参与 Flutter 合成，弹幕与控件可以直接叠加；悬浮窗只是换一个输出目标
        //
        // 播放器在全屏和半屏使用同一挂载位置，key 保持纹理子树的身份。
        Positioned.fill(
          child: Container(
            key: controller.globalVideoKey,
            color: Colors.black,
            child: _buildNativeVideo(),
          ),
        ),
        // 弹幕与控件叠在视频之上
        //
        // 必须用 Positioned.fill：
        // playerControls 内部是一个以 Positioned 为主的 Stack，
        // 若按非定位子项参与布局，它会被压缩成一个小方块，
        // 表现为「控件图标看不见、点也点不到」。
        Positioned.fill(child: playerControls(controller)),
        Positioned.fill(child: buildPlaybackStatus()),
      ],
    );
  }

  /// 加载失败与未开播共用播放区内提示，聊天、资料及播放器保持挂载。
  Widget buildPlaybackStatus() {
    return Obx(() {
      final failed = controller.loadError.value;
      final closed =
          controller.detailLoaded.value && !controller.liveStatus.value;
      if (failed || closed) {
        final info = failed ? controller.errorInfo : null;
        return LiveRoomStatusOverlay(
          userName: controller.displayUserName,
          userAvatar: controller.detail.value?.userAvatar ?? '',
          title: info?.title ?? '主播暂未开播',
          description: info?.tip,
          onRefresh: controller.refreshRoom,
          onCopyError: failed ? controller.copyErrorDetail : null,
          onExitFullScreen:
              controller.fullScreenState.value ? controller.exitFull : null,
        );
      }
      // 纹理会保留上一路流的最后一帧，首帧前用不透明黑底遮挡。
      if (!controller.hasRenderedFirstFrame.value) {
        return const IgnorePointer(
          child: ColoredBox(
            key: ValueKey('live-room-loading'),
            color: Colors.black,
            child: Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    });
  }

  /// 原生视频控件
  ///
  /// 画面走 Flutter 外部纹理（Texture 控件），而不是 PlatformView。
  ///
  /// 为什么不用 PlatformView：
  /// 引擎把 SurfaceView 判定为不支持 TLHC，会强制回退到 Hybrid Composition，
  /// 而 HC 是把原生 View 叠在 Flutter 内容之上——弹幕和播放控件会被视频整个盖住。
  /// 另外 HC 首次创建要执行 FlutterView.convertToImageView()，代价很高，
  /// 这正是「点进直播页卡 1-2 秒」的来源。
  ///
  /// 纹理方案下视频帧进入 Flutter 渲染管线，天然支持叠加与裁剪，
  /// 也不会有进入页面时的额外平台视图开销。
  Widget _buildNativeVideo() {
    return ClipRect(
      child: Obx(() {
        final textureId = controller.videoTextureId.value;
        if (textureId < 0) {
          // 纹理还没就绪，先给黑底占位，避免闪白
          return const SizedBox.expand();
        }

        // 优先使用设置里指定的固定比例（16:9 / 4:3），否则跟随视频原始比例
        final fixed = controller.scaleModeAspectRatio;
        var aspect = fixed ?? controller.videoAspectRatio.value;
        // 兜底：这里是高度预算的唯一分母，`height: 1000 / aspect`。
        // 只要 aspect 掉了链子（NaN / 0 / 负数 / 离谱地大），高度就被压成
        // 几个像素，用户看到的就是「画面被压缩成一条」。
        //
        // 控制器的 _applyVideoSize 已经在写入侧做了两道校验，正常情况下
        // 走不到这里。但这里是排版前最后一道关口，且成本只是两次比较，
        // 值得再挡一次：宁可暂时用 16:9 显示（画面轻微变形、但看得见），
        // 也不能让整个播放区塌成一条线。
        if (!aspect.isFinite || aspect < 0.2 || aspect > 4.0) {
          aspect = 16 / 9;
        }

        return SizedBox.expand(
          child: FittedBox(
            fit: controller.scaleModeFit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              // 基准尺寸固定，只按比例改变高度；
              // FittedBox 负责缩放到容器，不涉及任何重建成本高的组件。
              width: 1000,
              height: 1000 / aspect,
              child: Texture(
                textureId: textureId,
                filterQuality: FilterQuality.low,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget buildUserProfile(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
          bottom: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
        ),
      ),
      padding: AppStyle.edgeInsetsA8.copyWith(
        left: 12,
        right: 12,
      ),
      child: Obx(
        () => Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withAlpha(50)),
                borderRadius: AppStyle.radius24,
              ),
              child: NetImage(
                controller.detail.value?.userAvatar ?? "",
                width: 48,
                height: 48,
                borderRadius: 24,
              ),
            ),
            AppStyle.hGap12,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.displayUserName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AppStyle.vGap4,
                  Row(
                    children: [
                      Image.asset(
                        controller.site.logo,
                        width: 20,
                      ),
                      AppStyle.hGap4,
                      Text(
                        controller.site.name,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AppStyle.hGap12,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Remix.fire_fill,
                  size: 20,
                  color: Colors.orange,
                ),
                AppStyle.hGap4,
                Text(
                  Utils.onlineToString(
                    controller.detail.value?.online ?? 0,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBottomActions(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(
            color: Colors.grey.withAlpha(25),
          ),
        ),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Row(
        children: [
          Expanded(
            child: Obx(
              () => controller.followed.value
                  ? TextButton.icon(
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      onPressed: controller.removeFollowUser,
                      icon: const Icon(Remix.heart_fill),
                      label: const Text("取消关注"),
                    )
                  : TextButton.icon(
                      style: TextButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                      onPressed: controller.followUser,
                      icon: const Icon(Remix.heart_line),
                      label: const Text("关注"),
                    ),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 14),
              ),
              onPressed: controller.refreshRoom,
              icon: const Icon(Remix.refresh_line),
              label: const Text("刷新"),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 14),
              ),
              onPressed: controller.share,
              icon: const Icon(Remix.share_line),
              label: const Text("分享"),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildMessageArea() {
    return Expanded(
      child: DefaultTabController(
        length: controller.site.id == Constant.kBiliBili ? 4 : 3,
        child: Column(
          children: [
            TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              labelPadding: EdgeInsets.zero,
              indicatorWeight: 1.0,
              tabs: [
                const Tab(
                  text: "聊天",
                ),
                if (controller.site.id == Constant.kBiliBili)
                  Tab(
                    child: Obx(
                      () => Text(
                        controller.superChats.isNotEmpty
                            ? "SC(${controller.superChats.length})"
                            : "SC",
                      ),
                    ),
                  ),
                const Tab(
                  text: "关注",
                ),
                const Tab(
                  text: "设置",
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Obx(
                    () => Stack(
                      children: [
                        ListView.separated(
                          controller: controller.scrollController,
                          separatorBuilder: (_, i) => Obx(
                            () => SizedBox(
                              // *2与原来的EdgeInsets.symmetric(vertical: )做兼容
                              height: AppSettingsController
                                      .instance.chatTextGap.value *
                                  2,
                            ),
                          ),
                          padding: AppStyle.edgeInsetsA12,
                          // +1：列表第 0 项固定是「直播间标题」，
                          // 之后才是弹幕。标题跟着列表一起滚，
                          // 滚上去之后不再占位，不挤占聊天可视区域。
                          itemCount: controller.messages.length + 1,
                          itemBuilder: (_, i) {
                            if (i == 0) {
                              return buildRoomTitleHeader();
                            }
                            var item = controller.messages[i - 1];
                            return buildMessageItem(item);
                          },
                        ),
                        Visibility(
                          visible: controller.disableAutoScroll.value,
                          child: Positioned(
                            right: 12,
                            bottom: 12,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                controller.disableAutoScroll.value = false;
                                controller.chatScrollToBottom();
                              },
                              icon: const Icon(Icons.expand_more),
                              label: const Text("最新"),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (controller.site.id == Constant.kBiliBili)
                    buildSuperChats(),
                  buildFollowList(),
                  buildSettings(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 聊天列表顶部的「直播间标题」头
  ///
  /// 【为什么放进列表里而不是固定在上面】
  /// 需求是「加入弹幕列表，可随弹幕滚上去」。做成 ListView 的第 0 项，
  /// 它天然参与滚动：弹幕一多就跟着滚出可视区，不长期占着聊天区域。
  /// 如果做成列表上方的固定条，会永久吃掉一行高度，聊天可视范围变小。
  ///
  /// 【为什么用 Obx 单独订阅】
  /// 标题来自异步的 detail，进页面时可能还是 null（详情未返回）。
  /// 局部订阅可以做到「详情一到就显示」，而不是让整页跟着重建。
  Widget buildRoomTitleHeader() {
    return Obx(
      () {
        final d = controller.detail.value;
        // 详情还没回来时占位为零高度，避免先闪一个空行再撑开。
        // 注意用 SizedBox.shrink 而不是 null：ListView 的 item 不能返回 null。
        if (d == null || d.title.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d.title,
              style: TextStyle(
                fontSize: AppSettingsController.instance.chatTextSize.value + 2,
                fontWeight: FontWeight.w600,
                height: 1.4,
                color: Get.theme.textTheme.bodyLarge?.color,
              ),
            ),
            // 主播名 + 房间号：标题区顺带把「这是谁的房间」交代清楚，
            // 用户从关注/历史跳进来时不用再往下翻找。
            AppStyle.vGap4,
            Row(
              children: [
                Image.asset(
                  controller.site.logo,
                  width: 14,
                  height: 14,
                ),
                AppStyle.hGap4,
                Flexible(
                  child: Text(
                    "${d.userName} · ${controller.site.name}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize:
                          AppSettingsController.instance.chatTextSize.value - 2,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            // 一条细分割线，把「房间信息」与「弹幕」视觉上分开。
            // 用下边距而不是 Divider：Divider 自带高度约束，
            // 会和 ListView.separated 的间距叠成两倍空白。
            AppStyle.vGap8,
            Container(
              height: 1,
              color: Get.theme.dividerColor.withAlpha(30),
            ),
          ],
        );
      },
    );
  }

  Widget buildMessageItem(LiveMessage message) {
    if (message.userName == "LiveSysMessage") {
      return Obx(
        () => Text(
          message.message,
          style: TextStyle(
            color: Colors.grey,
            fontSize: AppSettingsController.instance.chatTextSize.value,
          ),
        ),
      );
    }

    return Obx(
      () => AppSettingsController.instance.chatBubbleStyle.value
          ? Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withAlpha(25),
                      //borderRadius: AppStyle.radius8,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    padding:
                        AppStyle.edgeInsetsA4.copyWith(left: 12, right: 12),
                    child: Text.rich(
                      TextSpan(
                        text: "${message.userName}：",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize:
                              AppSettingsController.instance.chatTextSize.value,
                        ),
                        children: [
                          TextSpan(
                            text: message.message,
                            style: TextStyle(
                              color: Get.isDarkMode
                                  ? Colors.white
                                  : AppColors.black333,
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Text.rich(
              TextSpan(
                text: "${message.userName}：",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: AppSettingsController.instance.chatTextSize.value,
                ),
                children: [
                  TextSpan(
                    text: message.message,
                    style: TextStyle(
                      color: Get.isDarkMode ? Colors.white : AppColors.black333,
                    ),
                  )
                ],
              ),
            ),
    );
  }

  Widget buildSuperChats() {
    return KeepAliveWrapper(
      child: Obx(
        () => ListView.separated(
          padding: AppStyle.edgeInsetsA12,
          itemCount: controller.superChats.length,
          separatorBuilder: (_, i) => AppStyle.vGap12,
          itemBuilder: (_, i) {
            var item = controller.superChats[i];
            return SuperChatCard(
              item,
              onExpire: () {
                controller.removeSuperChats();
              },
            );
          },
        ),
      ),
    );
  }

  Widget buildSettings() {
    return ListView(
      padding: AppStyle.edgeInsetsA12,
      children: [
        Obx(
          () => Visibility(
            visible: controller.autoExitEnable.value,
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              visualDensity: VisualDensity.compact,
              title: Text("${parseDuration(controller.countdown.value)}后自动关闭"),
            ),
          ),
        ),
        Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Text(
            "聊天区",
            style: Get.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Obx(
                () => SettingsNumber(
                  title: "文字大小",
                  value:
                      AppSettingsController.instance.chatTextSize.value.toInt(),
                  min: 8,
                  max: 36,
                  onChanged: (e) {
                    AppSettingsController.instance
                        .setChatTextSize(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsNumber(
                  title: "上下间隔",
                  value:
                      AppSettingsController.instance.chatTextGap.value.toInt(),
                  min: 0,
                  max: 12,
                  onChanged: (e) {
                    AppSettingsController.instance.setChatTextGap(e.toDouble());
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsSwitch(
                  title: "气泡样式",
                  value: AppSettingsController.instance.chatBubbleStyle.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setChatBubbleStyle(e);
                  },
                ),
              ),
              AppStyle.divider,
              Obx(
                () => SettingsSwitch(
                  title: "播放器中显示SC",
                  value:
                      AppSettingsController.instance.playershowSuperChat.value,
                  onChanged: (e) {
                    AppSettingsController.instance.setPlayerShowSuperChat(e);
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Text(
            "更多设置",
            style: Get.textTheme.titleSmall,
          ),
        ),
        SettingsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsAction(
                title: "关键词屏蔽",
                onTap: controller.showDanmuShield,
              ),
              AppStyle.divider,
              SettingsAction(
                title: "弹幕设置",
                onTap: controller.showDanmuSettingsSheet,
              ),
              AppStyle.divider,
              SettingsAction(
                title: "定时关闭",
                onTap: controller.showAutoExitSheet,
              ),
              AppStyle.divider,
              SettingsAction(
                title: "画面尺寸",
                onTap: controller.showPlayerSettingsSheet,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildFollowList() {
    return Obx(
      () => Stack(
        children: [
          RefreshIndicator(
            onRefresh: FollowService.instance.loadData,
            child: ListView.builder(
              itemCount: FollowService.instance.liveList.length,
              itemBuilder: (_, i) {
                var item = FollowService.instance.liveList[i];
                return Obx(
                  () => FollowUserItem(
                    item: item,
                    playing: controller.rxSite.value.id == item.siteId &&
                        controller.rxRoomId.value == item.roomId,
                    onTap: () {
                      controller.resetRoom(
                        Sites.allSites[item.siteId]!,
                        item.roomId,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> buildAppbarActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          showMore();
        },
        icon: const Icon(Icons.more_horiz),
      ),
    ];
  }

  /// 右上角「更多」菜单
  ///
  /// 【为什么不用列表 + 滚动视图】
  /// 这里前后换过三种写法都失败：
  /// 1. `constraints.maxHeight` + `SingleChildScrollView`：滚动视图在有界高度下会
  ///    撑满上限，条目少时下方留大片灰色，且能继续上滚；
  /// 2. `Flexible` 包滚动视图：Flexible 在主轴上仍会让滚动视图吃掉剩余空间，
  ///    结果是同样的问题；
  /// 3. 给 Column 套 maxHeight：条目被裁到只剩前几条（用户看到的就是「只有 5 项」）。
  ///
  /// 根因是「滚动视图 + 有界高度」这对组合天生会让高度等于约束上限，
  /// 而弹窗又必须靠内容撑高。所以这里干脆不用滚动视图：
  /// 改成图标网格，行数由条目数算出，弹窗高度 = 行数 × 行高 + 标题，
  /// 既完整展示全部操作，也不会出现空白和滚动。
  void showMore() {
    final actions = <_MoreAction>[
      _MoreAction(Icons.refresh, "刷新", () {
        controller.refreshRoom();
      }),
      _MoreAction(Icons.play_circle_outline, "清晰度", () {
        controller.showQualitySheet();
      }),
      _MoreAction(Icons.switch_video_outlined, "线路", () {
        controller.showPlayUrlsSheet();
      }),
      _MoreAction(Icons.aspect_ratio_outlined, "画面尺寸", () {
        controller.showPlayerSettingsSheet();
      }),
      _MoreAction(Icons.camera_alt_outlined, "截图", () {
        controller.saveScreenshot();
      }),
      // TV 端不提供悬浮小窗
      if (controller.floatingEnabled)
        _MoreAction(Icons.picture_in_picture_alt_outlined, "悬浮小窗", () async {
          final ok = await controller.enterFloatingWindow();
          if (ok) {
            Get.back();
          }
        }),
      _MoreAction(Icons.timer_outlined, "定时关闭", () {
        controller.showAutoExitSheet();
      }),
      _MoreAction(Icons.share_outlined, "分享直播间", () {
        controller.share();
      }),
      _MoreAction(Icons.link, "复制链接", () {
        controller.copyUrl();
      }),
      _MoreAction(Icons.open_in_new, "APP中打开", () {
        controller.openNaviteAPP();
      }),
      _MoreAction(Icons.info_outline_rounded, "播放信息", () {
        controller.showDebugInfo();
      }),
    ];

    showModalBottomSheet(
      context: Get.context!,
      // 必须开：默认上限是屏幕高度的 9/16，横屏时只有 200dp 出头，
      // 网格会被直接裁掉——这正是「只看到前 5 个」的另一种成因。
      // 这里开的是「允许超过默认上限」，并没有引入滚动视图，
      // 所以实际高度仍严格等于网格内容高度。
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MoreActionsSheet(actions: actions),
    );
  }

  String parseDuration(int sec) {
    // 转为时分秒
    var h = sec ~/ 3600;
    var m = (sec % 3600) ~/ 60;
    var s = sec % 60;
    if (h > 0) {
      return "${h.toString().padLeft(2, '0')}小时${m.toString().padLeft(2, '0')}分钟${s.toString().padLeft(2, '0')}秒";
    }
    if (m > 0) {
      return "${m.toString().padLeft(2, '0')}分钟${s.toString().padLeft(2, '0')}秒";
    }
    return "${s.toString().padLeft(2, '0')}秒";
  }
}

/// 「更多」菜单里的一项操作
class _MoreAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MoreAction(this.icon, this.label, this.onTap);
}

/// 「更多」菜单弹窗
///
/// 刻意不使用任何滚动视图，也不使用 ListView/GridView 这类「按约束铺开」的组件：
/// 弹窗高度必须严格等于内容高度，否则就会出现用户反复反馈的
/// 「只剩几条可见 + 下方一大片空白 + 还能继续上滚」。
///
/// 这里用 Wrap 逐行排列图标，行数由可用宽度算出，
/// 总高度 = 行数 × 行高 + 标题栏 + 底部安全区，天然与条目数量挂钩。
class _MoreActionsSheet extends StatelessWidget {
  final List<_MoreAction> actions;

  const _MoreActionsSheet({required this.actions});

  /// 每个图标的最小宽度。
  ///
  /// 实际列数由可用宽度除以它得出，所以：
  /// - 360dp 手机：一行 4 个，11 项 → 3 行；
  /// - 320dp 小屏：一行 3~4 个；
  /// - 横屏/平板：一行 6~7 个，反而更矮。
  ///
  /// 这样无论屏幕多窄，条目都不会被裁掉，弹窗高度始终等于实际行数 × 行高。
  static const double _itemMinWidth = 76;
  static const double _itemHeight = 84;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
            child: Row(
              children: [
                Text(
                  "更多操作",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: Get.back,
                  icon: const Icon(Icons.close, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // 操作网格
          LayoutBuilder(
            builder: (context, constraints) {
              // 左右各 8dp 内边距
              final available = constraints.maxWidth - 16;
              var columns = (available / _itemMinWidth).floor();
              if (columns < 2) {
                columns = 2;
              }
              if (columns > actions.length) {
                columns = actions.length;
              }
              // 均分宽度，避免右侧留下一条不均匀的缝
              final itemWidth = available / columns;

              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Wrap(
                  children: [
                    for (final action in actions)
                      SizedBox(
                        width: itemWidth,
                        height: _itemHeight,
                        child: _MoreActionItem(action: action),
                      ),
                  ],
                ),
              );
            },
          ),
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }
}

class _MoreActionItem extends StatelessWidget {
  final _MoreAction action;

  const _MoreActionItem({required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        Get.back();
        action.onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              action.icon,
              size: 21,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

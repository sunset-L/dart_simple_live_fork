import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/manual_live_status_cache.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_app/widgets/live_status_badge.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/swipe_dismissible_panel.dart';

/// 播放器里的「关注 / 历史」双页列表
///
/// 【为什么把标题一起做进这个组件】
/// 标题上的「关注 / 历史」是要和下面的列表联动的：点标签要翻页，
/// 滑动列表要反向更新标签的高亮。如果标题和列表是两个 widget，
/// 状态就得提到外面再由容器回传，中间多一层就多一处不同步。
/// 做成一个组件，`_index` 是该页唯一的状态源。
///
/// 【为什么用 PageView 而不是自己处理手势】
/// PageView 自带手势、惯性与边界回弹。自己写 GestureDetector 判方向，
/// 会和纵向列表的滚动抢手势——在纵向 ListView 上横滑，
/// 经常被判成纵向拖动，表现为「怎么滑都翻不了页」。
class PlayerRoomListPanel extends StatefulWidget {
  final LiveRoomController controller;

  /// 打开某个房间后的回调（关闭弹窗由调用方负责）
  final ValueChanged<RoomTarget> onOpen;

  /// 解锁后切换房间的关闭回调。由容器决定怎么关：
  /// 底部弹窗用 `Navigator.pop`，右侧滑窗用 `Utils.hideRightDialog`。
  final VoidCallback onClose;

  /// 每个 item 的左右留白。底部弹窗铺满屏宽、右侧滑窗较窄，
  /// 两者需要的边距不一样，所以开放给调用方。
  final EdgeInsets itemPadding;

  /// 标题区左右留白（要避让横屏时的状态栏/挖孔）
  final double headerLeftPadding;
  final double headerRightPadding;

  const PlayerRoomListPanel({
    required this.controller,
    required this.onOpen,
    required this.onClose,
    this.itemPadding = const EdgeInsets.only(left: 16, right: 4),
    this.headerLeftPadding = 4,
    this.headerRightPadding = 4,
    Key? key,
  }) : super(key: key);

  @override
  State<PlayerRoomListPanel> createState() => _PlayerRoomListPanelState();
}

/// 一次「打开房间」动作的目标
class RoomTarget {
  final String siteId;
  final String roomId;
  const RoomTarget(this.siteId, this.roomId);
}

class _PlayerRoomListPanelState extends State<PlayerRoomListPanel> {
  /// 当前页索引。
  ///
  /// 【为什么不用 TabController】
  /// 标题栏是自绘的（图标 + 文字 + 下划线），没有用 TabBar，
  /// 此时 TabController 唯一的用处就是「记住索引」，
  /// 却要额外承担 vsync、dispose、与 PageView 手工双向同步三件事。
  /// 一个 int 加 PageController 就是全部状态，少一层就少一处不同步的可能。
  int _index = 0;

  // 放在本地设置中，不随弹窗销毁；横竖屏与重启应用共用上次选择。
  late bool _locked;

  @override
  void initState() {
    super.initState();
    _locked = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerRoomListLocked,
      true,
    );
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerRoomListLocked,
      _locked,
    );
  }

  late final PageController _pageController = PageController();

  // 打开、切页、切房间和滚动只读缓存，下拉刷新才查询状态。
  final _historyLiveStatus = ManualLiveStatusCache();

  @override
  void dispose() {
    _historyLiveStatus.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 切页：两个方向都指向同一个方法，状态只有一个来源。
  void _switchTo(int index) {
    if (index == _index) {
      return;
    }
    if (_pageController.hasClients) {
      // 点标签时用动画滑过去；滑动切换时 onPageChanged 会先更新 _index，
      // 走到这里 index == _index 直接返回，不会重复驱动。
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    setState(() => _index = index);
  }

  void _openRoom(RoomTarget target) {
    widget.onOpen(target);
    if (!_locked) {
      widget.onClose();
    }
  }

  /// 标题栏：两个标签 + 右侧锁定按钮
  ///
  /// 做成整块可点而不是「只有文字可点」：
  /// 横屏时弹窗只有 360dp 宽，标签本身很窄，
  /// 手指要精确点在两个字上才算命中，体验很差。
  Widget _buildHeader() {
    return SizedBox(
      height: 48,
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.headerLeftPadding,
          right: widget.headerRightPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _tabButton("关注", 0, Remix.heart_3_line),
                  _tabButton("历史", 1, Remix.history_line),
                ],
              ),
            ),
            IconButton(
              tooltip: _locked ? '已锁定，切换直播间保留弹窗' : '已解锁，切换直播间关闭弹窗',
              onPressed: _toggleLock,
              icon: Icon(_locked ? Icons.lock : Icons.lock_open, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, int index, IconData icon) {
    final selected = _index == index;
    final activeColor = Get.theme.colorScheme.primary;
    final idleColor = Get.theme.textTheme.bodyMedium?.color?.withAlpha(150);
    return Expanded(
      child: InkWell(
        onTap: () => _switchTo(index),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? activeColor : idleColor),
            AppStyle.hGap4,
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? activeColor : idleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Divider(
          height: 1,
          color: Get.theme.dividerColor.withAlpha(40),
        ),
        Expanded(
          child: PageView(
            controller: _pageController,
            pageSnapping: false,
            physics: SwipeDismissiblePanel.pagePhysicsOf(context),
            dragStartBehavior: DragStartBehavior.down,
            onPageChanged: (i) => setState(() => _index = i),
            children: [
              _buildFollowList(),
              _buildHistoryList(),
            ],
          ),
        ),
      ],
    );
  }

  /// 关注列表：与原实现一致，直接消费 FollowService.liveList
  Widget _buildFollowList() {
    return Obx(
      () => RefreshIndicator(
        onRefresh: FollowService.instance.loadData,
        child: FollowService.instance.liveList.isEmpty
            ? _buildEmpty("还没有关注的主播\n去「我的 - 关注」添加")
            : ListView.builder(
                itemCount: FollowService.instance.liveList.length,
                itemBuilder: (_, i) {
                  final item = FollowService.instance.liveList[i];
                  return Obx(
                    () => FollowUserItem(
                      item: item,
                      showLiveStatus: false,
                      playing:
                          widget.controller.rxSite.value.id == item.siteId &&
                              widget.controller.rxRoomId.value == item.roomId,
                      onTap: () => _openRoom(
                        RoomTarget(item.siteId, item.roomId),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  /// 弹窗里的历史列表最多显示多少条
  ///
  /// 只限制**这个弹窗**，不动 DBService：全屏时长按列表只是为了
  /// 「快速切到刚看过的房间」，列太长反而难找；
  /// 而「我的 - 历史」是完整记录页，需要看到全部，
  /// WebDAV 备份和局域网同步也要搬全量，数据层不能裁剪。
  static const int kHistoryDisplayLimit = 20;

  /// 取出弹窗要展示的历史（最近 kHistoryDisplayLimit 条）
  ///
  /// 下拉刷新与列表渲染共用同一个取数入口，避免两处各自 take，
  /// 出现「刷新查了 30 条、列表只显示 20 条」的不一致。
  List<History> _visibleHistory() {
    final all = DBService.instance.getHistores();
    if (all.length <= kHistoryDisplayLimit) {
      return all;
    }
    return all.take(kHistoryDisplayLimit).toList();
  }

  Future<void> _refreshHistory() {
    final queries = <String, Future<bool> Function()>{};
    for (final item in _visibleHistory()) {
      final site = Sites.allSites[item.siteId];
      if (site != null) {
        queries[item.id] =
            () => site.liveSite.getLiveStatus(roomId: item.roomId);
      }
    }
    final refresh = _historyLiveStatus.refresh(queries);
    setState(() {});
    return refresh;
  }

  /// 历史列表：自己读历史记录，不依赖 HistoryPage
  ///
  /// 不能用 HistoryController：它是 BasePageController，
  /// 只为整页场景设计（分页、刷新、清空），
  /// 在弹窗里实例化会把整页的那套状态带进来。
  ///
  /// 【为什么每次重建都重新读，而不是 initState 拍快照】
  /// 面板打开后会一直留着（点条目只换房间、不关窗），
  /// 切房间会往历史里写新记录。快照式读法会让列表一直停在
  /// 打开面板那一刻的样子，刚切过去的房间看不见。
  /// 外面这层 Obx 订阅了当前房间，`resetRoom()` 改动 rx 值就会重建并重读。
  Widget _buildHistoryList() {
    return RefreshIndicator(
      onRefresh: _refreshHistory,
      child: Obx(() {
        // 先读一次，把当前房间纳入依赖（下面的 playing 判断也会读，
        // 但显式写在最前面语义更清楚）。
        final currentSiteId = widget.controller.rxSite.value.id;
        final currentRoomId = widget.controller.rxRoomId.value;

        final history = _visibleHistory();
        if (history.isEmpty) {
          return _buildEmpty("还没有观看记录");
        }
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: history.length,
          itemBuilder: (_, i) {
            final item = history[i];
            final site = Sites.allSites[item.siteId];
            if (site == null) {
              // 站点被移除（配置迁移、版本升降级）时不能崩，跳过这条
              return const SizedBox.shrink();
            }
            final playing =
                currentSiteId == item.siteId && currentRoomId == item.roomId;
            return ListTile(
              contentPadding: widget.itemPadding,
              leading: NetImage(
                item.face,
                width: 44,
                height: 44,
                borderRadius: 22,
              ),
              title: Text.rich(
                TextSpan(
                  text: item.userName,
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: FutureBuilder<bool?>(
                        key: ValueKey(item.id),
                        future: _historyLiveStatus[item.id],
                        builder: (_, snapshot) => LiveStatusBadge(
                          status:
                              snapshot.hasData ? (snapshot.data! ? 2 : 1) : 0,
                        ),
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  // 当前正在看的房间高亮，和关注列表的观感保持一致
                  color: playing ? Get.theme.colorScheme.primary : null,
                  fontWeight: playing ? FontWeight.w600 : null,
                ),
              ),
              subtitle: Row(
                children: [
                  Image.asset(site.logo, width: 16),
                  AppStyle.hGap4,
                  Expanded(
                    child: Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              onTap: () => _openRoom(RoomTarget(item.siteId, item.roomId)),
            );
          },
        );
      }),
    );
  }

  Widget _buildEmpty(String text) {
    // 用可滚动容器包一层：RefreshIndicator 需要一个可滚动的孩子，
    // 否则下拉刷新会静默失效（用户以为卡住了）。
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Get.theme.textTheme.bodySmall?.color?.withAlpha(140),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

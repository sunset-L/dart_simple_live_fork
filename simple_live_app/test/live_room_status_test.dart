import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/live_room_page.dart';
import 'package:simple_live_app/modules/live_room/live_room_status_overlay.dart';
import 'package:simple_live_core/simple_live_core.dart';

const _playerKey = ValueKey('status-test-player');
const _tabsKey = ValueKey('status-test-tabs');

class _TestLiveRoomController extends LiveRoomController {
  _TestLiveRoomController()
      : super(
          pSite: Site(
            id: 'test',
            name: '测试直播平台',
            logo: 'assets/images/logo.png',
            liveSite: BiliBiliSite(),
          ),
          pRoomId: '42',
        );

  int refreshes = 0;
  int copiedErrors = 0;

  @override
  void refreshRoom() {
    refreshes++;
    detailLoaded.value = false;
    hasRenderedFirstFrame.value = false;
    error = null;
    loadError.value = false;
  }

  @override
  void copyErrorDetail() {
    copiedErrors++;
  }

  @override
  void exitFull() {
    fullScreenState.value = false;
  }
}

/// 使用正式页面布局和状态提示，仅替换原生视频及依赖平台连接的聊天内容。
class _TestLiveRoomPage extends LiveRoomPage {
  @override
  final LiveRoomController controller;
  final VoidCallback onPlayerCreated;
  final VoidCallback onPlayerDisposed;

  const _TestLiveRoomPage(
    this.controller, {
    required this.onPlayerCreated,
    required this.onPlayerDisposed,
  });

  @override
  Widget buildMediaPlayer() {
    return _PlayerProbe(
      onCreated: onPlayerCreated,
      onDisposed: onPlayerDisposed,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.blue),
          Positioned.fill(child: buildPlaybackStatus()),
        ],
      ),
    );
  }

  @override
  Widget buildMessageArea() {
    final tabs = [
      '聊天',
      if (controller.site.id == Constant.kBiliBili) 'SC',
      '关注',
      '设置',
    ];
    return Expanded(
      child: DefaultTabController(
        length: tabs.length,
        child: Column(
          children: [
            TabBar(
              key: _tabsKey,
              tabs: tabs.map((label) => Tab(text: label)).toList(),
            ),
            Expanded(
              child: TabBarView(
                children: tabs.map((label) => Text('$label内容')).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  List<Widget> buildAppbarActions(BuildContext context) => [];
}

class _PlayerProbe extends StatefulWidget {
  final Widget child;
  final VoidCallback onCreated;
  final VoidCallback onDisposed;

  const _PlayerProbe({
    required this.child,
    required this.onCreated,
    required this.onDisposed,
  });

  @override
  State<_PlayerProbe> createState() => _PlayerProbeState();
}

class _PlayerProbeState extends State<_PlayerProbe> {
  @override
  void initState() {
    super.initState();
    widget.onCreated();
  }

  @override
  void dispose() {
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(key: _playerKey, child: widget.child);
  }
}

LiveRoomDetail _detail({bool status = false}) => LiveRoomDetail(
      roomId: '42',
      title: '测试直播间',
      cover: '',
      userName: '测试主播',
      userAvatar: '',
      online: 0,
      status: status,
      url: 'https://example.invalid/live/42',
    );

Future<_TestLiveRoomController> _showPage(
  WidgetTester tester, {
  bool offline = false,
  VoidCallback? onPlayerCreated,
  VoidCallback? onPlayerDisposed,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = _TestLiveRoomController();
  if (offline) {
    controller.detail.value = _detail();
    controller.detailLoaded.value = true;
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.scrollController.dispose();
    controller.liveDanmaku.stop();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: _TestLiveRoomPage(
        controller,
        onPlayerCreated: onPlayerCreated ?? () {},
        onPlayerDisposed: onPlayerDisposed ?? () {},
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('未开播、封禁及刷新恢复共用播放页，保留聊天标签和播放器挂载', (tester) async {
    var created = 0;
    var disposed = 0;
    final controller = await _showPage(
      tester,
      offline: true,
      onPlayerCreated: () => created++,
      onPlayerDisposed: () => disposed++,
    );
    await tester.pumpAndSettle();
    final scaffold = tester.element(find.byType(Scaffold));
    final playerSize = tester.getSize(find.byKey(_playerKey));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final tabs = DefaultTabController.of(tester.element(find.byKey(_tabsKey)));
    expect(tabs.index, 2);
    expect(find.text('主播暂未开播'), findsOneWidget);

    controller.error = CoreError('主播已被平台封禁');
    controller.loadError.value = true;
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(Scaffold)), same(scaffold));
    expect(tester.getSize(find.byKey(_playerKey)), playerSize);
    expect(find.byType(LiveRoomStatusOverlay), findsOneWidget);
    expect(find.text('直播间暂时无法打开'), findsOneWidget);
    expect(find.text('设置内容'), findsOneWidget);
    expect(tabs.index, 2);
    expect(created, 1);
    expect(disposed, 0);

    await tester.tap(find.descendant(
      of: find.byType(LiveRoomStatusOverlay),
      matching: find.widgetWithText(OutlinedButton, '刷新'),
    ));
    await tester.pump();
    expect(controller.refreshes, 1);
    expect(find.byKey(const ValueKey('live-room-loading')), findsOneWidget);
    expect(find.text('设置内容'), findsOneWidget);
    controller.detail.value = _detail(status: true);
    controller.detailLoaded.value = true;
    controller.liveStatus.value = true;
    controller.hasRenderedFirstFrame.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(LiveRoomStatusOverlay), findsNothing);
    expect(tester.element(find.byType(Scaffold)), same(scaffold));
    expect(created, 1);
    expect(disposed, 0);
  });

  testWidgets('异常未开播与正常未开播复用同一个状态组件，并显示正确房间标识', (tester) async {
    final controller = await _showPage(tester, offline: true);
    await tester.pumpAndSettle();
    final overlay = tester.element(find.byType(LiveRoomStatusOverlay));
    controller.detail.value = null;
    controller.detailLoaded.value = false;
    controller.error = CoreError('该主播未开播');
    controller.loadError.value = true;
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(LiveRoomStatusOverlay)), same(overlay));
    expect(find.text('主播暂未开播'), findsOneWidget);
    expect(find.text('测试直播平台 · 42'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('live-room-loading')), findsNothing);
    await tester.tap(find.byTooltip('复制错误信息'));
    expect(controller.copiedErrors, 1);
  });

  testWidgets('解析和网络异常在播放区域显示中文提示，横屏及全屏可正常返回', (tester) async {
    final controller = await _showPage(tester);
    for (final error in [
      const FormatException('missing room data'),
      TimeoutException('request timed out'),
      Exception('internal technical details'),
    ]) {
      controller.loadError.value = false;
      controller.error = error;
      controller.loadError.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(LiveRoomStatusOverlay), findsOneWidget);
      expect(find.byKey(_tabsKey), findsOneWidget);
      expect(find.byKey(const ValueKey('live-room-loading')), findsNothing);
    }
    expect(find.textContaining('internal technical details'), findsNothing);
    tester.view.physicalSize = const Size(800, 360);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    controller.fullScreenState.value = true;
    await tester.pumpAndSettle();
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    expect(controller.fullScreenState.value, isFalse);
    expect(find.byKey(_tabsKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小播放区域及放大字体下提示不溢出，刷新和复制入口仍可操作', (tester) async {
    var refreshed = 0;
    var copied = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Center(
            child: SizedBox(
              width: 200,
              height: 120,
              child: LiveRoomStatusOverlay(
                userName: '测试直播平台 · 42',
                userAvatar: '',
                title: '直播间暂时无法打开',
                description: '主播可能未开播、已被平台封禁，或该房间已关闭。',
                onRefresh: () => refreshed++,
                onCopyError: () => copied++,
              ),
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final refresh = find.widgetWithText(OutlinedButton, '刷新');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    final copy = find.byTooltip('复制错误信息');
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    expect(refreshed, 1);
    expect(copied, 1);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_layout.dart';

const _playerKey = ValueKey('player');
const _sidebarKey = ValueKey('sidebar');
const _portraitActionsKey = ValueKey('portrait-actions');
const _landscapeActionsKey = ValueKey('landscape-actions');

Widget _page({
  required bool fullScreen,
  required Widget player,
  required Widget sidebar,
}) {
  return MaterialApp(
    home: Scaffold(
      appBar: fullScreen ? null : AppBar(title: const Text('直播间')),
      body: LiveRoomLayout(
        fullScreen: fullScreen,
        player: player,
        sidebar: sidebar,
        portraitActions: const SizedBox(
          key: _portraitActionsKey,
          height: 48,
        ),
        landscapeActions: const SizedBox(
          key: _landscapeActionsKey,
          height: 56,
        ),
      ),
    ),
  );
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

void main() {
  testWidgets('反复切换全屏及旋转保留播放器和聊天标签状态', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _setSize(tester, const Size(360, 800));
    var created = 0;
    var disposed = 0;
    final player = _PlayerProbe(
      onCreated: () => created++,
      onDisposed: () => disposed++,
    );
    final sidebar = DefaultTabController(
      length: 2,
      child: Column(
        key: _sidebarKey,
        children: [
          const TabBar(tabs: [Tab(text: '聊天'), Tab(text: '设置')]),
          Expanded(
            child: TabBarView(
              children: [
                ListView.builder(
                  itemCount: 50,
                  itemExtent: 40,
                  itemBuilder: (_, i) => Text('消息 $i'),
                ),
                const Text('设置内容'),
              ],
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      _page(fullScreen: false, player: player, sidebar: sidebar),
    );
    expect(tester.getSize(find.byKey(_playerKey)), const Size(360, 202.5));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    final tabController = DefaultTabController.of(
      tester.element(find.byType(TabBar)),
    );
    expect(tabController.index, 1);

    for (var i = 0; i < 3; i++) {
      _setSize(tester, const Size(800, 360));
      await tester.pumpWidget(
        _page(fullScreen: true, player: player, sidebar: sidebar),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(_playerKey)), const Size(800, 360));
      expect(find.byKey(_sidebarKey), findsNothing);
      expect(find.byKey(_sidebarKey, skipOffstage: false), findsOneWidget);
      expect(tabController.index, 1);
      expect(tester.takeException(), isNull);

      _setSize(tester, const Size(360, 800));
      await tester.pumpWidget(
        _page(fullScreen: false, player: player, sidebar: sidebar),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(_playerKey)), const Size(360, 202.5));
      expect(find.text('设置内容'), findsOneWidget);
      expect(tabController.index, 1);
      expect(created, 1);
      expect(disposed, 0);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(disposed, 1);
  });

  testWidgets('半屏旋转保留聊天滚动位置并使用原来的 300 宽侧栏', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _setSize(tester, const Size(360, 800));
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    const player = ColoredBox(key: _playerKey, color: Colors.black);
    final sidebar = ListView.builder(
      key: _sidebarKey,
      controller: scrollController,
      itemExtent: 40,
      itemCount: 50,
      itemBuilder: (_, i) => Text('消息 $i'),
    );
    await tester.pumpWidget(
      _page(fullScreen: false, player: player, sidebar: sidebar),
    );
    scrollController.jumpTo(200);
    await tester.pump();
    _setSize(tester, const Size(800, 360));
    await tester.pumpWidget(
      _page(fullScreen: false, player: player, sidebar: sidebar),
    );
    await tester.pump();
    expect(tester.getSize(find.byKey(_playerKey)).width, 500);
    expect(tester.getSize(find.byKey(_sidebarKey)).width, 300);
    expect(scrollController.offset, 200);
    expect(find.byKey(_landscapeActionsKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首次自动全屏正常布局，隐藏的聊天区和操作栏不能获得焦点', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _setSize(tester, const Size(360, 800));
    final focus = FocusNode();
    addTearDown(focus.dispose);
    const player = ColoredBox(key: _playerKey, color: Colors.black);
    final sidebar = Column(
      key: _sidebarKey,
      children: [
        const SizedBox(height: 160),
        TextField(focusNode: focus),
      ],
    );
    await tester.pumpWidget(
      _page(fullScreen: true, player: player, sidebar: sidebar),
    );
    expect(tester.getSize(find.byKey(_playerKey)), const Size(360, 800));
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(_portraitActionsKey), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      _page(fullScreen: false, player: player, sidebar: sidebar),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(
      _page(fullScreen: true, player: player, sidebar: sidebar),
    );
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _PlayerProbe extends StatefulWidget {
  final VoidCallback onCreated;
  final VoidCallback onDisposed;

  const _PlayerProbe({required this.onCreated, required this.onDisposed});

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
    return const ColoredBox(key: _playerKey, color: Colors.black);
  }
}

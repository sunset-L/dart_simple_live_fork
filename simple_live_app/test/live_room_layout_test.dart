import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/live_room_layout.dart';

const _playerKey = ValueKey('player');
const _headerKey = ValueKey('header');
const _sidebarKey = ValueKey('sidebar');
const _portraitActionsKey = ValueKey('portrait-actions');
const _portrait = Size(360, 800);
const _landscape = Size(800, 360);

Widget _page({
  required bool fullScreen,
  bool landscapeFullScreen = true,
  required Widget player,
  required Widget sidebar,
  MediaQueryData? media,
  Size? layoutSize,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(builder: (context) {
        Widget page = LiveRoomLayout(
          fullScreen: fullScreen,
          landscapeFullScreen: landscapeFullScreen,
          appBar: AppBar(key: _headerKey, title: const Text('直播间')),
          player: player,
          sidebar: sidebar,
          portraitActions: const SizedBox(
            key: _portraitActionsKey,
            height: 48,
          ),
        );
        if (layoutSize != null) {
          page = Align(
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(size: layoutSize, child: page),
          );
        }
        return media == null ? page : MediaQuery(data: media, child: page);
      }),
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
    _setSize(tester, _portrait);
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

    for (var i = 0; i < 10; i++) {
      _setSize(tester, _landscape);
      await tester.pumpWidget(
        _page(fullScreen: true, player: player, sidebar: sidebar),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(_playerKey)), _landscape);
      expect(find.byKey(_sidebarKey), findsNothing);
      expect(find.byKey(_sidebarKey, skipOffstage: false), findsOneWidget);
      expect(tabController.index, 1);
      expect(tester.takeException(), isNull);

      _setSize(tester, _portrait);
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

  testWidgets('竖屏内容全屏时隐藏聊天和操作栏并释放焦点', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _setSize(tester, _portrait);
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
    Widget page(bool fullScreen) => _page(
          fullScreen: fullScreen,
          landscapeFullScreen: false,
          player: player,
          sidebar: sidebar,
        );
    await tester.pumpWidget(page(true));
    expect(tester.getSize(find.byKey(_playerKey)), _portrait);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(_portraitActionsKey), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(page(false));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(page(true));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('方向请求先到时保留旧方向布局直到窗口尺寸实际改变', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const player = ColoredBox(key: _playerKey, color: Colors.black);
    Widget page(bool fullScreen) => _page(
          fullScreen: fullScreen,
          player: player,
          sidebar: const SizedBox.expand(key: _sidebarKey),
        );
    _setSize(tester, _portrait);
    await tester.pumpWidget(page(false));
    final inlineRect = tester.getRect(find.byKey(_playerKey));
    await tester.pumpWidget(page(true));
    expect(tester.getRect(find.byKey(_playerKey)), inlineRect);
    expect(find.byKey(_headerKey), findsOneWidget);
    _setSize(tester, _landscape);
    await tester.pump();
    expect(tester.getSize(find.byKey(_playerKey)), _landscape);
    expect(find.byKey(_headerKey), findsNothing);
    await tester.pumpWidget(page(false));
    expect(tester.getSize(find.byKey(_playerKey)), _landscape);
    expect(find.byKey(_headerKey), findsNothing);
    _setSize(tester, _portrait);
    await tester.pump();
    expect(tester.getRect(find.byKey(_playerKey)), inlineRect);
    expect(find.byKey(_headerKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MediaQuery和约束先后变化时只按实际约束布局', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _setSize(tester, const Size(900, 900));
    Future<void> page(Size mediaSize, Size layoutSize) => tester.pumpWidget(
          _page(
            fullScreen: false,
            player: const ColoredBox(key: _playerKey, color: Colors.black),
            sidebar: const SizedBox.expand(key: _sidebarKey),
            media: MediaQueryData(size: mediaSize),
            layoutSize: layoutSize,
          ),
        );

    await page(_portrait, _portrait);
    // MediaQuery先转横屏，当前仍是竖屏约束。
    await page(_landscape, _portrait);
    expect(find.byKey(_headerKey), findsOneWidget);
    expect(tester.getSize(find.byKey(_playerKey)), const Size(360, 202.5));
    await page(_landscape, _landscape);
    // MediaQuery先转竖屏，不能在旧横屏约束里闪回竖屏页。
    await page(_portrait, _landscape);
    expect(find.byKey(_headerKey), findsNothing);
    expect(tester.getSize(find.byKey(_playerKey)), _landscape);
    await page(_portrait, _portrait);
    // 反过来，约束先变时也应立即使用实际布局，不使用旧尺寸布局。
    await page(_portrait, _landscape);
    expect(find.byKey(_headerKey), findsNothing);
    expect(tester.getSize(find.byKey(_playerKey)), _landscape);
    await page(_landscape, _landscape);
    await page(_landscape, _portrait);
    expect(find.byKey(_headerKey), findsOneWidget);
    expect(tester.getSize(find.byKey(_playerKey)), const Size(360, 202.5));
    await page(_portrait, _portrait);
    expect(tester.takeException(), isNull);
  });

  testWidgets('竖屏键盘压缩高度不能被误判成横屏全屏', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    _setSize(tester, _portrait);
    await tester.pumpWidget(_page(
      fullScreen: false,
      player: const ColoredBox(key: _playerKey, color: Colors.black),
      sidebar: const SizedBox.expand(key: _sidebarKey),
      media: const MediaQueryData(
        size: _portrait,
        viewInsets: EdgeInsets.only(bottom: 560),
      ),
      layoutSize: const Size(360, 240),
    ));
    expect(find.byKey(_headerKey), findsOneWidget);
    expect(find.byKey(_portraitActionsKey), findsOneWidget);
    expect(tester.getSize(find.byKey(_playerKey)).height, lessThan(240));
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

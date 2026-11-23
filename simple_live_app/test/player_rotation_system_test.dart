import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/live_room/live_room_layout.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

const _portrait = Size(360, 800);
const _landscape = Size(800, 360);
const _activityChannel = MethodChannel('simple_live/activity');
const _playerChannel = MethodChannel('simple_live/native_player');

class _SystemProbe
    with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin, PlayerSystemMixin {}

Widget _room(_SystemProbe controller) => MaterialApp(
      home: Obx(() => Scaffold(
            body: LiveRoomLayout(
              fullScreen: controller.fullScreenState.value,
              landscapeFullScreen: controller.fullScreenLandscape,
              onWindowLandscapeChanged: controller.onWindowLandscapeChanged,
              appBar: AppBar(title: const Text('直播间')),
              player: const ColoredBox(color: Colors.black),
              sidebar: const SizedBox.expand(),
              portraitActions: const SizedBox(height: 48),
            ),
          )),
    );

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> windowCalls;
  late List<MethodCall> orientationCalls;
  late List<MethodCall> systemUiCalls;
  late bool failNextHide;

  setUp(() {
    windowCalls = [];
    orientationCalls = [];
    systemUiCalls = [];
    failNextHide = false;
    messenger.setMockMethodCallHandler(_activityChannel, (call) async {
      windowCalls.add(call);
      if (failNextHide && call.arguments == true) {
        failNextHide = false;
        throw PlatformException(code: 'window-unavailable');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_playerChannel, (call) async {
      if (call.method == 'getVideoSize') {
        return {'width': 1920, 'height': 1080, 'aspectRatio': 16 / 9};
      }
      if (call.method == 'setScreenOrientation') orientationCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('SystemChrome.setEnabledSystemUI')) {
        systemUiCalls.add(call);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_activityChannel, null);
    messenger.setMockMethodCallHandler(_playerChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('连续手动横竖屏只修改原生系统栏可见性，不切换窗口布局模式', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _SystemProbe();
    _setSize(tester, _portrait);
    await tester.pumpWidget(_room(controller));
    await _flush(tester);

    for (var i = 0; i < 10; i++) {
      final entering = controller.enterFullScreen();
      // 切屏未完成时再次点击不会重复请求方向。
      await controller.enterFullScreen();
      await _flush(tester);
      expect(controller.fullScreenTransitioning.value, isTrue);
      expect(orientationCalls.last.arguments, 'landscape');
      _setSize(tester, _landscape);
      await _flush(tester);
      await entering;
      expect(controller.fullScreenState.value, isTrue);
      expect(controller.fullScreenTransitioning.value, isFalse);

      controller.exitFull();
      controller.exitFull();
      await _flush(tester);
      expect(orientationCalls.last.arguments, 'restore');
      _setSize(tester, _portrait);
      await _flush(tester);
      expect(controller.fullScreenState.value, isFalse);
      expect(controller.fullScreenTransitioning.value, isFalse);
      expect(orientationCalls.last.arguments, 'auto');
      expect(tester.takeException(), isNull);
    }
    expect(systemUiCalls, isEmpty);
    expect(windowCalls.map((e) => e.method).toSet(),
        {'setPlayerSystemBarsHidden'});
    expect(windowCalls.map((e) => e.arguments), [
      for (var i = 0; i < 10; i++) ...[true, false]
    ]);
    expect(orientationCalls.map((e) => e.arguments), [
      for (var i = 0; i < 10; i++) ...['landscape', 'restore', 'auto']
    ]);
  });

  testWidgets('系统自动横屏只隐藏系统栏，不追加横屏方向锁', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _SystemProbe();
    _setSize(tester, _portrait);
    await tester.pumpWidget(_room(controller));
    _setSize(tester, _landscape);
    await _flush(tester);
    expect(controller.fullScreenState.value, isTrue);
    expect(controller.fullScreenTransitioning.value, isFalse);
    expect(orientationCalls, isEmpty);
    expect(windowCalls.map((e) => e.arguments), [true]);
    _setSize(tester, _portrait);
    await _flush(tester);
    expect(controller.fullScreenState.value, isFalse);
    expect(controller.fullScreenTransitioning.value, isFalse);
    expect(orientationCalls.map((e) => e.arguments), ['auto']);
    expect(windowCalls.map((e) => e.arguments), [true, false]);
    expect(systemUiCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统拒绝方向请求后恢复系统栏并释放切屏锁', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _SystemProbe();
    _setSize(tester, _portrait);
    await tester.pumpWidget(_room(controller));
    final entering = controller.enterFullScreen();
    await _flush(tester);
    expect(controller.fullScreenTransitioning.value, isTrue);
    await tester.pump(const Duration(seconds: 2));
    await _flush(tester);
    await entering;
    expect(controller.fullScreenState.value, isFalse);
    expect(controller.fullScreenTransitioning.value, isFalse);
    expect(orientationCalls.map((e) => e.arguments), ['landscape', 'auto']);
    expect(windowCalls.map((e) => e.arguments), [true, false]);
    expect(systemUiCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窗口调用失败不会留下错误全屏状态或永久切屏锁', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _SystemProbe();
    _setSize(tester, _portrait);
    await tester.pumpWidget(_room(controller));
    failNextHide = true;
    final entering = controller.enterFullScreen();
    await _flush(tester);
    await entering;
    expect(controller.fullScreenState.value, isFalse);
    expect(controller.fullScreenTransitioning.value, isFalse);
    expect(orientationCalls.map((e) => e.arguments), ['auto']);
    expect(windowCalls.map((e) => e.arguments), [true, false]);
    expect(systemUiCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

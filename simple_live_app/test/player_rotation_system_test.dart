import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/live_room/live_room_layout.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/services/native_player_bridge.dart';

const _activity = MethodChannel('simple_live/activity');
const _player = MethodChannel('simple_live/native_player');

class _SystemProbe
    with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin, PlayerSystemMixin {
  @override
  Map<String, dynamic> get nativeFullscreenData => {
        'title': '测试直播间',
        'landscape': fullScreenLandscape,
        'danmakuEnabled': showDanmakuState.value,
      };
}

Widget _room(_SystemProbe controller) => MaterialApp(
      home: Obx(() => Scaffold(
            body: LiveRoomLayout(
              fullScreen: controller.fullScreenState.value,
              landscapeFullScreen: controller.fullScreenLandscape,
              appBar: AppBar(title: const Text('直播间')),
              player: const ColoredBox(color: Colors.black),
              sidebar: const SizedBox.expand(),
              portraitActions: const SizedBox(height: 48),
            ),
          )),
    );

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late List<MethodCall> orientation;
  late List<MethodCall> systemUi;
  Completer<void>? showReady;
  Completer<void>? hideReady;
  bool failShow = false;
  bool failHide = false;
  bool vertical = false;

  setUp(() {
    calls = [];
    orientation = [];
    systemUi = [];
    showReady = hideReady = null;
    failShow = failHide = vertical = false;
    messenger.setMockMethodCallHandler(_activity, (call) async {
      calls.add(call);
      if (call.method == 'showPlayerFullscreen') {
        if (failShow) throw PlatformException(code: 'PLAYER_UNAVAILABLE');
        await showReady?.future;
      }
      if (call.method == 'hidePlayerFullscreen') {
        if (failHide) throw PlatformException(code: 'FULLSCREEN_TIMEOUT');
        await hideReady?.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_player, (call) async {
      if (call.method == 'setScreenOrientation') orientation.add(call);
      if (call.method == 'getVideoSize') {
        return vertical
            ? {'width': 1080, 'height': 1920, 'aspectRatio': 9 / 16}
            : {'width': 1920, 'height': 1080, 'aspectRatio': 16 / 9};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('SystemChrome.setEnabledSystemUI')) {
        systemUi.add(call);
      }
      return null;
    });
  });

  tearDown(() {
    NativePlayerBridge.instance.onFullscreenAction = null;
    messenger.setMockMethodCallHandler(_activity, null);
    messenger.setMockMethodCallHandler(_player, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('连续全屏交接只打开关闭原生页，Flutter不再请求旋转或切换系统栏', (tester) async {
    final controller = _SystemProbe();
    await tester.pumpWidget(_room(controller));
    final size = tester.view.physicalSize;
    for (var i = 0; i < 20; i++) {
      await controller.enterFullScreen();
      await _flush(tester);
      expect(controller.fullScreenState.value, isTrue);
      expect((calls.last.arguments as Map)['landscape'], isTrue);
      await controller.exitFull();
      await _flush(tester);
      expect(controller.fullScreenState.value, isFalse);
      expect(controller.fullScreenTransitioning.value, isFalse);
      expect(tester.view.physicalSize, size);
    }
    expect(calls.map((e) => e.method), [
      for (var i = 0; i < 20; i++) ...[
        'showPlayerFullscreen',
        'hidePlayerFullscreen'
      ]
    ]);
    expect(orientation, isEmpty);
    expect(systemUi, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('等待原生交接期间重复点击不会创建第二页或交叉退出', (tester) async {
    final controller = _SystemProbe();
    await tester.pumpWidget(_room(controller));
    showReady = Completer<void>();
    final entering = controller.enterFullScreen();
    await _flush(tester);
    await controller.enterFullScreen();
    await controller.exitFull();
    expect(calls.length, 1);
    expect(controller.fullScreenTransitioning.value, isTrue);
    showReady!.complete();
    await entering;
    hideReady = Completer<void>();
    final exiting = controller.exitFull();
    await _flush(tester);
    await controller.enterFullScreen();
    await controller.exitFull();
    expect(calls.length, 2);
    // 新Surface的首帧必须是内联布局，状态提前恢复，但锁要等原生完成才释放。
    expect(controller.fullScreenState.value, isFalse);
    expect(controller.fullScreenTransitioning.value, isTrue);
    hideReady!.complete();
    await exiting;
    expect(controller.fullScreenTransitioning.value, isFalse);
  });

  testWidgets('原生页未就绪时恢复状态，不退回有问题的Flutter旋转路径', (tester) async {
    final controller = _SystemProbe();
    await tester.pumpWidget(_room(controller));
    failShow = true;
    await controller.enterFullScreen();
    await _flush(tester);
    expect(controller.fullScreenState.value, isFalse);
    expect(controller.fullScreenTransitioning.value, isFalse);
    expect(orientation, isEmpty);
    expect(systemUi, isEmpty);
    failShow = false;
    await controller.enterFullScreen();
    expect(controller.fullScreenState.value, isTrue);
  });

  testWidgets('退出失败保留原生全屏状态，允许再次退出', (tester) async {
    final controller = _SystemProbe();
    await tester.pumpWidget(_room(controller));
    await controller.enterFullScreen();
    failHide = true;
    await controller.exitFull();
    expect(controller.fullScreenState.value, isTrue);
    expect(controller.fullScreenTransitioning.value, isFalse);
    failHide = false;
    await controller.exitFull();
    expect(controller.fullScreenState.value, isFalse);
    expect(orientation, isEmpty);
  });

  testWidgets('竖屏视频传给原生竖屏全屏页，不要求Flutter窗口改尺寸', (tester) async {
    final controller = _SystemProbe();
    await tester.pumpWidget(_room(controller));
    vertical = true;
    await controller.enterFullScreen();
    expect((calls.last.arguments as Map)['landscape'], isFalse);
    await controller.exitFull();
    expect(orientation, isEmpty);
  });

  testWidgets('弹幕仅发送到已开启的原生全屏页，半屏不积攒渲染数据', (tester) async {
    final controller = _SystemProbe();
    await tester.pumpWidget(_room(controller));
    const items = [FloatingDanmakuItem(text: '弹幕', color: 0xffffffff)];
    controller.showDanmakuState.value = true;
    controller.addDanmaku(items);
    expect(calls, isEmpty);
    await controller.enterFullScreen();
    controller.addDanmaku(items);
    await _flush(tester);
    expect(calls.last.method, 'addPlayerFullscreenDanmaku');
    expect(calls.last.arguments, [
      {'text': '弹幕', 'color': 0xffffffff}
    ]);
    controller.showDanmakuState.value = false;
    controller.addDanmaku(items);
    await _flush(tester);
    expect(
        calls.where((e) => e.method == 'addPlayerFullscreenDanmaku').length, 1);
  });
}

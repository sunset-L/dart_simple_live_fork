import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/services/native_player_bridge.dart';

const _activity = MethodChannel('simple_live/activity');
const _player = MethodChannel('simple_live/native_player');

class _SystemProbe
    with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin, PlayerSystemMixin {
  @override
  Map<String, dynamic> get nativePageData => {
        'title': '测试直播间',
        'landscape': fullScreenLandscape,
        'danmakuEnabled': showDanmakuState.value,
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  Completer<void>? ready;
  bool fail = false;
  bool vertical = false;

  setUp(() {
    calls = [];
    ready = null;
    fail = false;
    vertical = false;
    messenger.setMockMethodCallHandler(_activity, (call) async {
      calls.add(call);
      if (call.method == 'setPlayerFullscreen') {
        if (fail) throw PlatformException(code: 'PLAYER_UNAVAILABLE');
        await ready?.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_player, (call) async {
      if (call.method == 'getVideoSize') {
        return vertical
            ? {'width': 1080, 'height': 1920, 'aspectRatio': 9 / 16}
            : {'width': 1920, 'height': 1080, 'aspectRatio': 16 / 9};
      }
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    NativePlayerBridge.instance.onPageAction = null;
    messenger.setMockMethodCallHandler(_activity, null);
    messenger.setMockMethodCallHandler(_player, null);
  });

  test('反复切屏仅请求原生页改变模式，不创建Flutter纹理或重复打开关闭页面', () async {
    final controller = _SystemProbe();
    for (var i = 0; i < 20; i++) {
      await controller.enterFullScreen();
      expect(controller.fullScreenState.value, isTrue);
      await controller.exitFull();
      expect(controller.fullScreenState.value, isFalse);
    }
    expect(calls.map((e) => e.method), everyElement('setPlayerFullscreen'));
    expect(calls.length, 40);
    expect(calls.first.arguments, {'fullscreen': true, 'landscape': true});
    expect(calls.last.arguments, {'fullscreen': false, 'landscape': false});
  });

  test('连续点击不会重入切屏请求', () async {
    final controller = _SystemProbe();
    ready = Completer<void>();
    final first = controller.enterFullScreen();
    await Future<void>.delayed(Duration.zero);
    await controller.enterFullScreen();
    expect(calls.length, 1);
    ready!.complete();
    await first;
    expect(controller.fullScreenTransitioning.value, isFalse);
  });

  test('原生切屏失败释放操作锁并恢复原状态', () async {
    final controller = _SystemProbe();
    fail = true;
    await controller.enterFullScreen();
    expect(controller.fullScreenState.value, isFalse);
    expect(controller.fullScreenTransitioning.value, isFalse);
    fail = false;
    await controller.enterFullScreen();
    fail = true;
    await controller.exitFull();
    expect(controller.fullScreenState.value, isTrue);
    expect(controller.fullScreenTransitioning.value, isFalse);
  });

  test('竖屏视频的全屏模式不请求横屏', () async {
    vertical = true;
    final controller = _SystemProbe();
    await controller.enterFullScreen();
    expect(calls.last.arguments, {'fullscreen': true, 'landscape': false});
  });

  test('聊天与设置走原生页面桥接，不打开Flutter弹窗', () async {
    final bridge = NativePlayerBridge.instance;
    await bridge.openPlayerPage({'title': '测试直播间'});
    await bridge.addPlayerMessages([
      {'userName': '观众', 'message': '你好'}
    ]);
    await bridge.showPlayerDialog('shield', {
      'keywords': ['/测试/']
    });
    await bridge.closePlayerPage();
    expect(calls.map((e) => e.method), [
      'openPlayerPage',
      'addPlayerMessages',
      'showPlayerDialog',
      'closePlayerPage'
    ]);
  });

  test('仅全屏且开启弹幕时发送，竖屏不增加叠加层开销', () async {
    final controller = _SystemProbe();
    const item = FloatingDanmakuItem(text: '测试', color: 0xffffffff);
    controller.addDanmaku([item]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    controller.showDanmakuState.value = true;
    controller.addDanmaku([item]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    controller.fullScreenState.value = true;
    controller.addDanmaku([item]);
    await Future<void>.delayed(Duration.zero);
    expect(
        calls.map((e) => e.method), everyElement('addPlayerFullscreenDanmaku'));
    expect(calls.length, 1);
    controller.showDanmakuState.value = false;
    controller.addDanmaku([item]);
    await Future<void>.delayed(Duration.zero);
    expect(calls.length, 1);
  });
}

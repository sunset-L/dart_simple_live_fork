import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/services/native_player_bridge.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

mixin PlayerMixin {
  /// 原生播放器桥接
  final nativePlayer = NativePlayerBridge.instance;

  /// 视频宽高比的合法下界
  ///
  /// 真实直播流最窄也就到 9:16（约 0.5625），再小的值只可能是脏数据。
  /// 给到 0.2 已经非常宽松，正常内容永远碰不到。
  static const double kMinAspect = 0.2;

  /// 视频宽高比的合法上界
  ///
  /// 这个值的意义是**兜住「画面被压成一条」**：
  /// 布局里播放区宽度固定，高度 = 宽度 / aspect，
  /// aspect 一旦离谱地大（例如 SAR 被错当成 100），
  /// 高度就只剩几个像素，观感就是一条细线。
  /// 超宽银幕上限按 4:1 给，正常内容（16:9、21:9）都远在其内。
  static const double kMaxAspect = 4.0;

  /// 原生 SAR 修正允许偏离 w/h 的最大倍数
  ///
  /// 变形宽银幕流 SAR 常见 1.2~1.4；超过 3 倍说明这个 SAR 是脏数据，
  /// 此时宁可退回 width/height 相除（会轻微失真，但绝不会把画面压扁）。
  static const double kMaxAspectDeviation = 3.0;

  /// 视频画面层的 GlobalKey
  ///
  /// 保留竖屏内联纹理的 key；原生全屏输出交接不重建这个子树。
  GlobalKey globalVideoKey = GlobalKey();

  /// 当前视频宽高比，供 UI 自适应
  RxDouble videoAspectRatio = (16 / 9).obs;

  /// 是否为竖屏直播间
  ///
  /// 声明在 PlayerMixin（而不是 PlayerStateMixin）：
  /// 它的真实来源是原生 `videoSize` 回调与 [_syncVideoSize]，
  /// 两者都在本 mixin 内，放一起才不会出现「值停在构造初值」的情况。
  /// 抖音在控制器构造时把它硬编码成 true（大量竖屏直播），
  /// 一旦复用播放器收不到 videoSize 事件，横屏抖音就会被当成竖屏。
  var isVertical = false.obs;

  /// 当前正在播放的地址
  ///
  /// 直播地址带签名与过期参数，是排障的第一手信息：
  /// 断流时看一眼 `expire=` 还在不在、是哪个 CDN、有没有降档，
  /// 就能判断是签名过期、鉴权失败还是取流降级。
  RxString currentPlayUrl = "".obs;

  // 全屏播放参数面板与采样生命周期由原生页面管理。

  /// Flutter 外部纹理 id，-1 表示尚未创建
  ///
  /// 画面走纹理而非 PlatformView：
  /// PlatformView + SurfaceView 会被引擎强制回退到 Hybrid Composition，
  /// 原生 View 叠在 Flutter 内容之上，弹幕和控件会被视频盖住。
  RxInt videoTextureId = (-1).obs;

  /// 是否电视设备（TV 端禁用悬浮窗）
  bool isTvDevice = false;

  /// 是否已获得悬浮窗权限
  RxBool hasOverlayPermission = false.obs;

  /// 是否已经渲染出第一帧画面
  ///
  /// 纹理在收到首个视频帧之前是空白的，会把底下的黑底透出来，
  /// 用户看到的就是「半黑半灰」。用这个标记盖一层 loading，
  /// 等真正有画面了再撤掉。
  ///
  /// 放在 PlayerMixin（最底层）而不是 PlayerStateMixin：
  /// ensureVideoTexture 位于本 mixin，需要读写它。
  RxBool hasRenderedFirstFrame = false.obs;

  /// 初始化播放器（音量 + 视频纹理）
  Future<void> initializePlayer() async {
    try {
      final volume = AppSettingsController.instance.playerVolume.value;
      // playerVolume 是 0-100，原生侧是 0-1
      await nativePlayer.setVolume(volume / 100);
      // 「按 Home 键自动暂停」的判定在原生 onUserLeaveHint 里，
      // 必须把开关值下发给原生，否则原生侧永远停在默认 false，开关等于无效。
      // 每次进房都同步一次，避免「改了设置但没重启播放器」导致的不一致。
      await nativePlayer.setPauseOnHome(
        AppSettingsController.instance.playerPauseOnHome.value,
      );
    } catch (e) {
      Log.logPrint(e);
    }
    await ensureVideoTexture();
  }

  /// 确保视频纹理已创建，把纹理 id 交给 Texture 控件
  Future<void> ensureVideoTexture() async {
    try {
      if (videoTextureId.value >= 0) {
        // 纹理已存在：说明是复用场景（典型是从悬浮小窗回到页面）。
        // 首帧事件不会再发，必须主动同步一次状态。
        await _syncFirstFrameState();
        return;
      }
      final id = await nativePlayer.initTexture();
      if (id != null && id >= 0) {
        videoTextureId.value = id;
        await _syncFirstFrameState();
      }
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 与原生侧同步首帧状态
  ///
  /// 从悬浮小窗回到页面时纹理是复用的，原生侧的 firstFrame 事件早已发过，
  /// 新页面收不到就会一直卡在 loading（表现为有声音没画面）。
  Future<void> _syncFirstFrameState() async {
    try {
      final rendered = await nativePlayer.hasRenderedFrame();
      if (rendered) {
        hasRenderedFirstFrame.value = true;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    await _syncVideoSize();
  }

  /// 复用播放器可能收不到尺寸变化事件，接管或切屏时主动同步真实比例。
  Future<void> _syncVideoSize() async {
    try {
      final size = await nativePlayer.getVideoSize();
      if (size == null) {
        return;
      }
      _applyVideoSize(
        (size["width"] ?? 0).toInt(),
        (size["height"] ?? 0).toInt(),
        size["aspectRatio"]?.toDouble(),
      );
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 交叉校验 SAR 和分辨率；无效比例保留旧值，不能夹到边界后永久写入。
  void _applyVideoSize(int w, int h, double? aspect) {
    if (w <= 0 || h <= 0) {
      return;
    }
    final raw = w / h;

    // 第一道：以 width/height 相除为基准。
    // SAR 只应带来「轻微」修正（变形宽银幕常见 1.2~1.4），
    // 偏离超过 [kMaxAspectDeviation] 倍说明这个 SAR 不可信。
    var value = raw;
    if (aspect != null && aspect.isFinite && aspect > 0) {
      if (raw > 0 &&
          aspect / raw <= kMaxAspectDeviation &&
          raw / aspect <= kMaxAspectDeviation) {
        value = aspect;
      } else {
        Log.w("视频宽高比异常(aspect=$aspect vs w/h=$raw)，已回退到 w/h");
      }
    }

    // 第二道：连 w/h 都不可信（分辨率本身是脏的）时，直接放弃这次写入。
    // 注意这里 **不 clamp**：夹到边界同样是写入错值，而且会永久粘住。
    if (!value.isFinite || value < kMinAspect || value > kMaxAspect) {
      Log.w("视频宽高比不可信(w=$w, h=$h, aspect=$aspect)，保留上一次的值");
      return;
    }

    if ((videoAspectRatio.value - value).abs() > 0.0001) {
      Log.d("视频宽高比更新：${value.toStringAsFixed(4)}（$w x $h）");
    }
    videoAspectRatio.value = value;
    isVertical.value = h > w;
  }

  /// 检测设备类型与悬浮窗权限
  Future<void> initPlayerEnvironment() async {
    try {
      isTvDevice = await nativePlayer.isTvDevice();
    } catch (_) {
      isTvDevice = false;
    }
    if (!isTvDevice) {
      await refreshOverlayPermission();
    }
  }

  Future<void> refreshOverlayPermission() async {
    try {
      hasOverlayPermission.value = await nativePlayer.hasOverlayPermission();
    } catch (_) {
      hasOverlayPermission.value = false;
    }
  }
}

mixin PlayerStateMixin on PlayerMixin {
  ///音量控制条计时器
  Timer? hidevolumeTimer;

  /// 是否显示弹幕
  RxBool showDanmakuState = false.obs;

  /// 是否显示控制器
  RxBool showControlsState = false.obs;

  /// 是否显示设置窗口
  RxBool showSettingState = false.obs;

  /// 是否显示弹幕设置窗口
  RxBool showDanmakuSettingState = false.obs;

  /// 是否处于锁定控制器状态
  RxBool lockControlsState = false.obs;

  /// 是否处于全屏状态
  RxBool fullScreenState = false.obs;

  /// 切屏动画和系统方向交接期间禁止重复进入、退出。
  RxBool fullScreenTransitioning = false.obs;

  /// 显示手势Tip
  RxBool showGestureTip = false.obs;

  /// 手势Tip文本
  RxString gestureTipText = "".obs;

  /// 显示提示底部Tip
  RxBool showBottomTip = false.obs;

  /// 提示底部Tip文本
  RxString bottomTipText = "".obs;

  /// 自动隐藏控制器计时器
  Timer? hideControlsTimer;

  /// 是否正在缓冲
  RxBool buffering = false.obs;

  /// 隐藏控制器
  void hideControls() {
    showControlsState.value = false;
    hideControlsTimer?.cancel();
  }

  void setLockState() {
    lockControlsState.value = !lockControlsState.value;
    if (lockControlsState.value) {
      showControlsState.value = false;
    } else {
      showControlsState.value = true;
    }
  }

  /// 显示控制器
  void showControls() {
    showControlsState.value = true;
    resetHideControlsTimer();
  }

  /// 开始隐藏控制器计时
  void resetHideControlsTimer() {
    hideControlsTimer?.cancel();

    hideControlsTimer = Timer(
      const Duration(seconds: 5),
      hideControls,
    );
  }

  /// 画面缩放模式：0 适应 1 拉伸 2 铺满 3 16:9 4 4:3
  BoxFit get scaleModeFit {
    switch (AppSettingsController.instance.scaleMode.value) {
      case 1:
        return BoxFit.fill;
      case 2:
        return BoxFit.cover;
      default:
        return BoxFit.contain;
    }
  }

  /// 固定宽高比（3=16:9，4=4:3，其余按视频原始比例）
  double? get scaleModeAspectRatio {
    switch (AppSettingsController.instance.scaleMode.value) {
      case 3:
        return 16 / 9;
      case 4:
        return 4 / 3;
      default:
        return null;
    }
  }
}

mixin PlayerDanmakuMixin on PlayerStateMixin {
  void addDanmaku(List<FloatingDanmakuItem> items) {
    if (!fullScreenState.value || !showDanmakuState.value || items.isEmpty) {
      return;
    }
    unawaited(nativePlayer.addFullscreenDanmaku(items).catchError((e) {
      Log.logPrint(e);
    }));
  }
}

mixin PlayerSystemMixin on PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin {
  bool _systemDisposed = false;
  bool _fullScreenLandscape = true;
  bool get fullScreenLandscape => _fullScreenLandscape;
  bool get isLandscapeVideo => videoAspectRatio.value > 1;
  Worker? _nativeSettingsWorker;
  Future<void>? _inlineReady;

  Map<String, dynamic> get nativeFullscreenData {
    final s = AppSettingsController.instance;
    return {
      'title': '直播间',
      'landscape': _fullScreenLandscape,
      'danmakuEnabled': showDanmakuState.value,
      'scaleMode': s.scaleMode.value,
      'fontSize': s.danmuSize.value,
      'fontWeight': s.danmuFontWeight.value,
      'opacity': s.danmuOpacity.value,
      'area': s.danmuArea.value,
      'duration': s.danmuSpeed.value,
      'topMargin': s.danmuTopMargin.value,
      'bottomMargin': s.danmuBottomMargin.value,
    };
  }

  void syncNativeFullscreen() {
    if (_systemDisposed || !fullScreenState.value) {
      return;
    }
    unawaited(nativePlayer
        .updateFullscreenPlayer(nativeFullscreenData)
        .catchError((e) {
      Log.logPrint(e);
    }));
  }

  void onNativeFullscreenAction(String action, num? value) {
    if (_systemDisposed ||
        !fullScreenState.value ||
        fullScreenTransitioning.value) {
      return;
    }
    if (action == 'exit') {
      exitFull();
      return;
    }
    final s = AppSettingsController.instance;
    switch (action) {
      case 'danmaku':
        showDanmakuState.value = value == 1;
        break;
      case 'scale':
        if (value != null) s.setScaleMode(value.toInt());
        break;
      case 'fontSize':
        if (value != null) s.setDanmuSize(value.toDouble());
        break;
      case 'area':
        if (value != null) s.setDanmuArea(value.toDouble());
        break;
      case 'opacity':
        if (value != null) s.setDanmuOpacity(value.toDouble());
        break;
      case 'duration':
        if (value != null) s.setDanmuSpeed(value.toDouble());
        break;
    }
  }

  void initSystem() async {
    VolumeController.instance.showSystemUI = false;
    showControlsState.value = true;
    resetHideControlsTimer();
    nativePlayer.onFullscreenAction = onNativeFullscreenAction;
    final s = AppSettingsController.instance;
    _nativeSettingsWorker = everAll([
      showDanmakuState,
      s.scaleMode,
      s.danmuSize,
      s.danmuFontWeight,
      s.danmuOpacity,
      s.danmuArea,
      s.danmuSpeed,
      s.danmuTopMargin,
      s.danmuBottomMargin,
      s.playershowSuperChat,
    ], (_) => syncNativeFullscreen());
    // 竖屏业务页不再跟随窗口旋转；方向只在完整原生全屏页可见时切换。
    _inlineReady = nativePlayer.setInlinePlayer(true);
    try {
      await _inlineReady;
      if (!_systemDisposed && s.autoFullScreen.value) await enterFullScreen();
    } catch (e) {
      Log.logPrint(e);
    }
  }

  Future resetSystem() async {
    _systemDisposed = true;
    _nativeSettingsWorker?.dispose();
    nativePlayer.onFullscreenAction = null;
    fullScreenTransitioning.value = false;
    try {
      await nativePlayer.setInlinePlayer(false);
    } catch (e) {
      Log.logPrint(e);
    }
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (e) {
      Log.logPrint(e);
    }
    await WakelockPlus.disable();
  }

  Future<void> enterFullScreen() async {
    if (_systemDisposed ||
        fullScreenState.value ||
        fullScreenTransitioning.value) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    fullScreenTransitioning.value = true;
    try {
      await _inlineReady;
      await _syncVideoSize();
      if (_systemDisposed) return;
      _fullScreenLandscape = isLandscapeVideo;
      fullScreenState.value = true;
      await nativePlayer.showFullscreenPlayer(nativeFullscreenData);
    } catch (e) {
      Log.logPrint(e);
      if (!_systemDisposed) fullScreenState.value = false;
    } finally {
      if (!_systemDisposed) fullScreenTransitioning.value = false;
    }
  }

  Future<void> exitFull() async {
    if (_systemDisposed ||
        !fullScreenState.value ||
        fullScreenTransitioning.value) {
      return;
    }
    fullScreenTransitioning.value = true;
    // 恢复后的 Flutter 首帧必须已经是竖屏内联布局，而不是旧全屏状态。
    fullScreenState.value = false;
    try {
      await nativePlayer.hideFullscreenPlayer();
    } catch (e) {
      Log.logPrint(e);
      if (!_systemDisposed) fullScreenState.value = true;
    } finally {
      if (!_systemDisposed) fullScreenTransitioning.value = false;
    }
  }

  /// 保存截图
  ///
  /// 画面走 Flutter 纹理，可以通过 RepaintBoundary 抓取，
  /// 需要页面把播放器包在带 GlobalKey 的 RepaintBoundary 里。
  Future saveScreenshot() async {
    SmartDialog.showToast("当前版本暂不支持截图");
  }
}

mixin PlayerGestureControlMixin
    on PlayerStateMixin, PlayerMixin, PlayerSystemMixin {
  /// 上一次单击的时间，用于自己实现「双击」判定
  DateTime? _lastTapTime;

  /// 单击显示/隐藏控制器
  ///
  /// 不用 GestureDetector 的 onDoubleTap：它会让每次单击都等待双击超时
  /// （约 300ms）才生效，点一下控件要愣一下才有反应。
  /// 这里自己按时间差判定，单击立即响应。
  void onTap() {
    final now = DateTime.now();
    final last = _lastTapTime;
    _lastTapTime = now;

    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 280)) {
      // 判定为双击：切换全屏
      _lastTapTime = null;
      onDoubleTap(TapDownDetails());
      return;
    }

    if (showControlsState.value) {
      hideControls();
    } else {
      showControls();
    }
  }

  /// 双击全屏/退出全屏
  void onDoubleTap(TapDownDetails details) {
    if (lockControlsState.value) {
      return;
    }
    if (fullScreenState.value) {
      exitFull();
    } else {
      enterFullScreen();
    }
  }

  bool verticalDragging = false;
  bool leftVerticalDrag = false;
  var _currentVolume = 0.0;
  var _currentBrightness = 1.0;
  var verStartPosition = 0.0;
  double _verticalDragRange = 1.0;
  bool _gestureReady = false;
  double? _pendingDragDy;
  Duration? _pendingDragTime;
  double _lastVolume = -1.0;
  int _verticalDragSession = 0;
  int _volumeUpdate = 0;

  SystemVolumeState? _systemVolumeState;
  int _volumeTargetIndex = 0;
  double _volumeStepRemainder = 0.0;
  double _lastVolumeDragDy = 0.0;
  Duration? _lastVolumeDragTime;
  final Stopwatch _volumeGestureClock = Stopwatch();
  int _lastVolumeSampleMicros = 0;
  bool _fastVolumeDrag = false;

  /// 按播放区域而非整屏判定左右侧和滑动幅度，兼容半屏及全屏。
  void onVerticalDragStart(DragStartDetails details) async {
    onVerticalDragCancel();
    if (lockControlsState.value && fullScreenState.value) {
      return;
    }

    final box = globalVideoKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) {
      return;
    }
    final position = box.globalToLocal(details.globalPosition);
    if (!(Offset.zero & box.size).contains(position)) {
      return;
    }

    _lastTapTime = null;
    verStartPosition = details.globalPosition.dy;
    _verticalDragRange = box.size.height * 0.5;
    leftVerticalDrag = position.dx < box.size.width / 2;
    verticalDragging = true;
    _lastVolumeDragDy = details.globalPosition.dy;
    _lastVolumeDragTime = details.sourceTimeStamp;
    _volumeGestureClock
      ..reset()
      ..start();
    _lastVolumeSampleMicros = 0;

    final session = _verticalDragSession;
    try {
      SystemVolumeState? systemVolume;
      if (!leftVerticalDrag && GetPlatform.isAndroid) {
        try {
          systemVolume = await nativePlayer.getSystemVolumeState();
        } catch (e) {
          // 旧原生端或系统服务不可用时，仍可沿用现有音量插件。
          Log.logPrint(e);
        }
        if (!verticalDragging || session != _verticalDragSession) return;
      }
      final value = leftVerticalDrag
          ? await ScreenBrightness.instance.application
          : systemVolume?.volume ?? await VolumeController.instance.getVolume();
      // 读取期间手势可能已结束或重新开始，旧结果不能覆盖新手势。
      if (!verticalDragging || session != _verticalDragSession) return;
      if (!value.isFinite ||
          (lockControlsState.value && fullScreenState.value)) {
        onVerticalDragCancel();
        return;
      }
      final initialValue = value.clamp(0.0, 1.0).toDouble();
      if (leftVerticalDrag) {
        _currentBrightness = initialValue;
        gestureTipText.value = "亮度 ${(initialValue * 100).round()}%";
      } else {
        _currentVolume = initialValue;
        _lastVolume = initialValue;
        _systemVolumeState = systemVolume;
        _volumeTargetIndex = systemVolume?.currentIndex ?? 0;
        gestureTipText.value = "音量 ${(initialValue * 100).round()}%";
      }
      _gestureReady = true;
      showGestureTip.value = true;
      final pendingDy = _pendingDragDy;
      if (pendingDy != null) {
        if (leftVerticalDrag) {
          setGestureBrightness(pendingDy);
        } else {
          setGestureVolume(pendingDy, sourceTimeStamp: _pendingDragTime);
        }
        _pendingDragDy = null;
        _pendingDragTime = null;
      }
    } catch (e) {
      Log.logPrint(e);
      if (session == _verticalDragSession) onVerticalDragCancel();
    }
  }

  void onVerticalDragUpdate(DragUpdateDetails details) {
    if (lockControlsState.value && fullScreenState.value) {
      onVerticalDragCancel();
      return;
    }
    if (!verticalDragging) return;
    if (!_gestureReady) {
      _pendingDragDy = details.globalPosition.dy;
      _pendingDragTime = details.sourceTimeStamp;
      return;
    }

    if (leftVerticalDrag) {
      setGestureBrightness(details.globalPosition.dy);
    } else {
      setGestureVolume(details.globalPosition.dy,
          sourceTimeStamp: details.sourceTimeStamp);
    }
  }

  void setGestureVolume(double dy, {Duration? sourceTimeStamp}) {
    if (!verticalDragging || leftVerticalDrag || !_gestureReady) return;
    final systemVolume = _systemVolumeState;
    if (systemVolume != null) {
      _accumulateSystemVolume(dy, sourceTimeStamp, systemVolume.maxIndex);
      return;
    }

    // 非 Android 或旧原生端保留原有的系统音量插件路径。
    final volume =
        (_currentVolume + (verStartPosition - dy) / _verticalDragRange)
            .clamp(0.0, 1.0)
            .toDouble();
    if (volume == _lastVolume) return;
    _lastVolume = volume;
    unawaited(
        _applyGestureVolume(volume, _verticalDragSession, ++_volumeUpdate));
  }

  void _accumulateSystemVolume(
    double dy,
    Duration? sourceTimeStamp,
    int maxIndex,
  ) {
    final delta = _lastVolumeDragDy - dy;
    final nowMicros = _volumeGestureClock.elapsedMicroseconds;
    final previousTime = _lastVolumeDragTime;
    // 有源时间戳时只使用源时间；重复或倒退的时间戳不改变快慢模式。
    // 只有缺失源时间戳的代理事件才使用处理时钟，避免合并回调造成假高速。
    final elapsedMicros = sourceTimeStamp != null && previousTime != null
        ? (sourceTimeStamp - previousTime).inMicroseconds
        : nowMicros - _lastVolumeSampleMicros;
    _lastVolumeDragDy = dy;
    _lastVolumeDragTime = sourceTimeStamp;
    _lastVolumeSampleMicros = nowMicros;
    if (!delta.isFinite || maxIndex <= 0) return;

    if (elapsedMicros > 0) {
      final speed =
          delta.abs() * Duration.microsecondsPerSecond / elapsedMicros;
      // 两个阈值形成滞回，避免临界速度附近反复切换灵敏度。
      if (speed > 300) {
        _fastVolumeDrag = true;
      } else if (speed < 180) {
        _fastVolumeDrag = false;
      }
    }
    final pixelsPerStep = _fastVolumeDrag
        ? _verticalDragRange / maxIndex
        : math.max(12.0, _verticalDragRange * 2 / maxIndex);
    _volumeStepRemainder += delta / pixelsPerStep;

    // 到上下限后不再累计向外位移，反向滑动无需偿还越界距离。
    if ((_volumeTargetIndex == 0 && _volumeStepRemainder < 0) ||
        (_volumeTargetIndex == maxIndex && _volumeStepRemainder > 0)) {
      _volumeStepRemainder = 0;
      return;
    }
    final steps = _volumeStepRemainder.truncate();
    if (steps == 0) return;
    _volumeStepRemainder -= steps;
    final target = (_volumeTargetIndex + steps).clamp(0, maxIndex).toInt();
    if ((target == 0 && _volumeStepRemainder < 0) ||
        (target == maxIndex && _volumeStepRemainder > 0)) {
      _volumeStepRemainder = 0;
    }
    if (target == _volumeTargetIndex) return;
    _volumeTargetIndex = target;
    // 原生请求立即发出，不引入延时队列；只在真实目标档位变化时设置。
    unawaited(
        _applySystemVolumeIndex(target, _verticalDragSession, ++_volumeUpdate));
  }

  Future<void> _applySystemVolumeIndex(
      int index, int session, int update) async {
    try {
      final state = await nativePlayer.setSystemVolumeIndex(index);
      if (!_isCurrentVolumeUpdate(session, update)) return;
      if (state.currentIndex != index ||
          state.maxIndex != _systemVolumeState?.maxIndex) {
        // 安全音量限制或输出设备切换时，以真实结果重新建立基准。
        _volumeStepRemainder = 0;
      }
      _systemVolumeState = state;
      _volumeTargetIndex = state.currentIndex;
      gestureTipText.value = "音量 ${(state.volume * 100).round()}%";
    } catch (e) {
      Log.logPrint(e);
      if (_isCurrentVolumeUpdate(session, update)) {
        _volumeTargetIndex = _systemVolumeState?.currentIndex ?? 0;
        _volumeStepRemainder = 0;
      }
    }
  }

  bool _isCurrentVolumeUpdate(int session, int update) {
    return verticalDragging &&
        !leftVerticalDrag &&
        session == _verticalDragSession &&
        update == _volumeUpdate;
  }

  Future<void> _applyGestureVolume(
    double volume,
    int session,
    int update,
  ) async {
    try {
      await VolumeController.instance.setVolume(volume);
      final actualVolume = await VolumeController.instance.getVolume();
      if (!_isCurrentVolumeUpdate(session, update)) return;
      // 系统仍按设备档位输出，提示显示实际系统音量而非请求值。
      gestureTipText.value = "音量 ${(actualVolume * 100).round()}%";
    } catch (e) {
      Log.logPrint(e);
    }
  }

  void setGestureBrightness(double dy) {
    final brightness =
        (_currentBrightness + (verStartPosition - dy) / _verticalDragRange)
            .clamp(0.0, 1.0)
            .toDouble();
    gestureTipText.value = "亮度 ${(brightness * 100).round()}%";
    unawaited(_applyGestureBrightness(brightness));
  }

  Future<void> _applyGestureBrightness(double brightness) async {
    try {
      await ScreenBrightness.instance
          .setApplicationScreenBrightness(brightness);
    } catch (e) {
      Log.logPrint(e);
    }
  }

  void onVerticalDragEnd(DragEndDetails details) {
    onVerticalDragCancel();
  }

  /// 取消和正常松手都清理状态，不让异步读取重新显示提示。
  void onVerticalDragCancel() {
    _verticalDragSession++;
    verticalDragging = false;
    leftVerticalDrag = false;
    _gestureReady = false;
    _pendingDragDy = null;
    _pendingDragTime = null;
    _lastVolume = -1.0;
    _systemVolumeState = null;
    _volumeTargetIndex = 0;
    _volumeStepRemainder = 0;
    _lastVolumeDragTime = null;
    _fastVolumeDrag = false;
    _volumeGestureClock.stop();
    showGestureTip.value = false;
  }
}

class PlayerController extends BaseController
    with
        PlayerMixin,
        PlayerStateMixin,
        PlayerDanmakuMixin,
        PlayerSystemMixin,
        PlayerGestureControlMixin {
  @override
  void onInit() {
    initSystem();
    initStream();
    initializePlayer();
    initPlayerEnvironment();
    super.onInit();
  }

  StreamSubscription<NativePlayerEvent>? _playerEventSubscription;

  /// 播放健康度检查定时器
  Timer? _healthCheckTimer;

  /// 连续多少次检查仍在缓冲
  int _stalledCount = 0;

  /// 判定播放停滞需要的连续检查次数（每次 5 秒）
  int stallThreshold = 4;

  /// 播放停滞时的回调，由直播间控制器实现（重新取流）
  void onPlayStalled() {}

  /// 由直播页确认实际加载的线路，并在持续播放后重置恢复计数。
  void onPlaybackPlayingChanged(bool playing) {}

  void initStream() {
    _playerEventSubscription = nativePlayer.events.listen((event) {
      switch (event.type) {
        case NativePlayerEventType.buffering:
          buffering.value = event.boolValue ?? false;
          break;
        case NativePlayerEventType.playing:
          onPlaybackPlayingChanged(event.boolValue == true);
          if (event.boolValue == true) {
            WakelockPlus.enable();
            _stalledCount = 0;
          }
          break;
        case NativePlayerEventType.completed:
          WakelockPlus.disable();
          mediaEnd();
          break;
        case NativePlayerEventType.error:
          Log.d("播放器错误：${event.stringValue}");
          WakelockPlus.disable();
          mediaError(event.stringValue ?? "播放错误");
          break;
        case NativePlayerEventType.videoSize:
          final w = event.width ?? 0;
          final h = event.height ?? 0;
          if (w > 0 && h > 0) {
            // 统一走 _applyVideoSize：那里有 SAR 可信度校验与硬边界，
            // 避免脏 aspect 把画面高度压成一条
            _applyVideoSize(w, h, event.aspectRatio);
          }
          break;
        case NativePlayerEventType.floatingTap:
          onFloatingTap();
          break;
        case NativePlayerEventType.floatingClosed:
          onFloatingClosed();
          break;
        case NativePlayerEventType.firstFrame:
          hasRenderedFirstFrame.value = true;
          break;
        case NativePlayerEventType.floatingRestored:
          // 小窗状态恢复由 FloatingSession 全局处理，页面无需响应
          break;
        case NativePlayerEventType.metrics:
          // 原生全屏面板直接读取指标，Flutter 不再保留第二套面板状态。
          break;
      }
    });
  }

  /// 点击悬浮窗时的回调
  void onFloatingTap() {}

  /// 悬浮窗被关闭时的回调
  void onFloatingClosed() {}

  void disposeStream() {
    _playerEventSubscription?.cancel();
    _playerEventSubscription = null;
    stopHealthCheck();
  }

  void mediaEnd() {
    WakelockPlus.disable();
  }

  void mediaError(String error) {
    WakelockPlus.disable();
  }

  void startHealthCheck() {
    _healthCheckTimer?.cancel();
    _stalledCount = 0;
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      checkHealth();
    });
  }

  void stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _stalledCount = 0;
  }

  void resetHealthCheck() {
    _stalledCount = 0;
  }

  /// 检查播放是否仍在推进
  ///
  /// ExoPlayer 在地址过期时常常既不报错也不 ended，只是长时间停留在 buffering，
  /// 因此用「持续缓冲」作为停滞判据。
  void checkHealth() {
    if (!buffering.value) {
      _stalledCount = 0;
      return;
    }

    _stalledCount++;
    Log.d('持续缓冲（$_stalledCount/$stallThreshold）');

    if (_stalledCount >= stallThreshold) {
      _stalledCount = 0;
      Log.d('检测到播放停滞，触发恢复流程');
      onPlayStalled();
    }
  }

  /// 显示播放信息
  void showDebugInfo() {
    // 打开面板时同步一次真实地址：接管小窗等场景下 Dart 侧可能没记录到，
    // 以原生播放器实际加载的地址为准。
    _syncCurrentPlayUrl();
    Utils.showBottomSheet(
      title: "播放信息",
      child: ListView(
        children: [
          const ListTile(
            title: Text("播放器"),
            subtitle: Text("Android native (ExoPlayer)"),
          ),
          ListTile(
            title: const Text("宽高比"),
            subtitle: Obx(
              () => Text(videoAspectRatio.value.toStringAsFixed(3)),
            ),
          ),
          ListTile(
            title: const Text("缓冲状态"),
            subtitle: Obx(() => Text(buffering.value ? "缓冲中" : "正常")),
          ),
          Obx(() {
            final url = currentPlayUrl.value;
            final empty = url.isEmpty;
            return ListTile(
              title: const Text("播放地址"),
              subtitle: SelectableText(
                empty ? "暂无（尚未取流）" : url,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: empty
                      ? Theme.of(Get.context!).textTheme.bodySmall?.color
                      : null,
                ),
              ),
              isThreeLine: !empty,
              trailing: empty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: "复制地址",
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        SmartDialog.showToast("播放地址已复制");
                      },
                    ),
            );
          }),
        ],
      ),
    );
  }

  /// 从原生播放器同步当前正在播放的地址
  Future<void> _syncCurrentPlayUrl() async {
    try {
      final url = await nativePlayer.getCurrentUrl();
      if (url != null && url.isNotEmpty) {
        currentPlayUrl.value = url;
      }
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 播放器是否被移交给了悬浮窗。
  /// 移交后本控制器不再拥有播放器，销毁时不能释放它。
  bool isPlayerHandedOver = false;

  @override
  void onClose() async {
    onVerticalDragCancel();
    Log.w("播放器关闭");
    disposeStream();
    await resetSystem();
    // 关键：只有「没移交的小窗」才释放播放器。
    // 之前这里是无条件 release，导致返回进入小窗后几秒内被销毁。
    if (!isPlayerHandedOver) {
      try {
        await nativePlayer.exitFloating();
        await nativePlayer.release();
        await nativePlayer.releaseTexture();
      } catch (e) {
        Log.logPrint(e);
      }
      videoTextureId.value = -1;
    }
    super.onClose();
  }
}

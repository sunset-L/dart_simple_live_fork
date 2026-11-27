import 'dart:async';

import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
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

  /// 是否电视设备（TV 端禁用悬浮窗）
  bool isTvDevice = false;

  /// 是否已获得悬浮窗权限
  RxBool hasOverlayPermission = false.obs;

  /// 同步播放器的音量、后台策略及视频尺寸。
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
    await ensureVideoOutput();
  }

  /// 页面输出由原生 PlayerView 创建，Dart 仅同步视频元数据。
  Future<void> ensureVideoOutput() => _syncVideoSize();

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
  RxBool showDanmakuState = false.obs;
  RxBool fullScreenState = false.obs;
  RxBool fullScreenTransitioning = false.obs;
  RxBool buffering = false.obs;
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
  static Object? _activeSession;
  final Object _session = Object();
  bool get noNativePageOwner => _activeSession == null;
  bool get _ownsNativePage => identical(_activeSession, _session);
  bool _systemDisposed = false;
  bool _fullScreenLandscape = true;
  bool get fullScreenLandscape => _fullScreenLandscape;
  bool get isLandscapeVideo => videoAspectRatio.value > 1;
  Worker? _nativeSettingsWorker;
  Future<void>? _pageReady;
  bool _nativePageOpen = false;
  Timer? _nativePageSyncTimer;
  bool _nativePageSyncing = false;
  bool _nativePageDirty = false;
  Map<String, dynamic> _lastNativePageData = {};
  static const _pageDataEquality = DeepCollectionEquality();

  Map<String, dynamic> get nativePageData {
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

  void syncNativePage() {
    if (_systemDisposed || !_nativePageOpen || !_ownsNativePage) return;
    _nativePageDirty = true;
    if (_nativePageSyncing || _nativePageSyncTimer != null) return;
    // 原生页展示时 Flutter Surface 已隐藏，用定时器合并同批状态更新。
    _nativePageSyncTimer = Timer(const Duration(milliseconds: 16), () {
      _nativePageSyncTimer = null;
      unawaited(_flushNativePage());
    });
  }

  Future<void> _flushNativePage() async {
    if (_systemDisposed || !_nativePageOpen || !_ownsNativePage) return;
    _nativePageDirty = false;
    final values = nativePageData;
    final changes = <String, dynamic>{
      for (final entry in values.entries)
        if (!_lastNativePageData.containsKey(entry.key) ||
            !_pageDataEquality.equals(
                _lastNativePageData[entry.key], entry.value))
          entry.key: entry.value,
      for (final key in _lastNativePageData.keys)
        if (!values.containsKey(key)) key: null,
    };
    if (changes.isEmpty) return;
    _nativePageSyncing = true;
    try {
      await nativePlayer.updatePlayerPage(changes);
      if (!_systemDisposed && _ownsNativePage) _lastNativePageData = values;
    } catch (e) {
      // 下次业务状态变化时重发完整状态，不在失败后循环重试。
      _lastNativePageData = {};
      Log.logPrint(e);
    } finally {
      _nativePageSyncing = false;
      if (_nativePageDirty) syncNativePage();
    }
  }

  void onNativePageAction(String action, dynamic value) {
    if (_systemDisposed || !_ownsNativePage) return;
    if (action == 'volume') {
      // 原生已实时应用浮点音量；仅保存基准，切线/重连时不要恢复为旧值。
      if (value is num && value.isFinite) {
        AppSettingsController.instance
            .setPlayerVolume(value.toDouble().clamp(0.0, 100.0));
      }
      return;
    }
    if (fullScreenTransitioning.value) return;
    if (action == 'fullscreen') {
      enterFullScreen();
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
        if (value is num) s.setDanmuSpeed(value.toDouble());
        break;
      case 'fontWeight':
        if (value is num) s.setDanmuFontWeight(value.toInt());
        break;
      case 'topMargin':
        if (value is num) s.setDanmuTopMargin(value.toDouble());
        break;
      case 'bottomMargin':
        if (value is num) s.setDanmuBottomMargin(value.toDouble());
        break;
    }
  }

  void onNativePageOpenFailed(Object error) {}

  void initSystem() async {
    _activeSession = _session;
    nativePlayer.onPageAction = onNativePageAction;
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
    ], (_) => syncNativePage());
    // 竖屏业务页不再跟随窗口旋转；方向只在完整原生全屏页可见时切换。
    _lastNativePageData = nativePageData;
    _pageReady = nativePlayer.openPlayerPage(_lastNativePageData);
    try {
      await _pageReady;
      _nativePageOpen = !_systemDisposed && _ownsNativePage;
      syncNativePage();
      if (_nativePageOpen && s.autoFullScreen.value) await enterFullScreen();
    } catch (e) {
      Log.logPrint(e);
      if (!_systemDisposed) onNativePageOpenFailed(e);
    }
  }

  Future resetSystem() async {
    _systemDisposed = true;
    _nativePageSyncTimer?.cancel();
    _nativePageSyncTimer = null;
    _nativePageDirty = false;
    _lastNativePageData = {};
    _nativeSettingsWorker?.dispose();
    fullScreenTransitioning.value = false;
    if (!_ownsNativePage) return;
    nativePlayer.onPageAction = null;
    try {
      _nativePageOpen = false;
      await nativePlayer.closePlayerPage();
    } catch (e) {
      Log.logPrint(e);
    }
    if (_ownsNativePage) _activeSession = null;
    if (_activeSession == null) await WakelockPlus.disable();
  }

  Future<void> enterFullScreen() async {
    if (_systemDisposed ||
        fullScreenState.value ||
        fullScreenTransitioning.value) {
      return;
    }
    fullScreenTransitioning.value = true;
    try {
      await _pageReady;
      await _syncVideoSize();
      if (_systemDisposed) return;
      _fullScreenLandscape = isLandscapeVideo;
      fullScreenState.value = true;
      await nativePlayer.setPlayerFullscreen(true, _fullScreenLandscape);
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
    // 原生页仅切换布局与方向，Flutter 在整个播放会话期间保持隐藏。
    fullScreenState.value = false;
    try {
      await nativePlayer.setPlayerFullscreen(false, false);
    } catch (e) {
      Log.logPrint(e);
      if (!_systemDisposed) fullScreenState.value = true;
    } finally {
      if (!_systemDisposed) fullScreenTransitioning.value = false;
    }
  }
}

class PlayerController extends BaseController
    with PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin, PlayerSystemMixin {
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

  bool get allowPlaybackWakelock => true;

  void initStream() {
    _playerEventSubscription = nativePlayer.events.listen((event) {
      switch (event.type) {
        case NativePlayerEventType.buffering:
          buffering.value = event.boolValue ?? false;
          break;
        case NativePlayerEventType.playing:
          onPlaybackPlayingChanged(event.boolValue == true);
          if (event.boolValue == true && allowPlaybackWakelock) {
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
  Future<void> showDebugInfo() async {
    try {
      // 小窗接管时旧 Dart URL 可能为空，读取 ExoPlayer 实际加载的地址。
      final url = await nativePlayer.getCurrentUrl() ?? '';
      if (_systemDisposed) return;
      currentPlayUrl.value = url;
      await nativePlayer.showPlayerDialog('playbackInfo', {
        'url': url,
      });
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 播放器是否被移交给了悬浮窗。
  /// 移交后本控制器不再拥有播放器，销毁时不能释放它。
  bool isPlayerHandedOver = false;

  @override
  void onClose() async {
    Log.w("播放器关闭");
    disposeStream();
    await resetSystem();
    // 关键：只有「没移交的小窗」才释放播放器。
    // 之前这里是无条件 release，导致返回进入小窗后几秒内被销毁。
    if (noNativePageOwner && !isPlayerHandedOver) {
      try {
        await nativePlayer.exitFloating();
        if (noNativePageOwner) await nativePlayer.release();
      } catch (e) {
        Log.logPrint(e);
      }
    }
    super.onClose();
  }
}

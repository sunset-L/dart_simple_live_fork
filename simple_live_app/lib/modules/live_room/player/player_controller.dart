import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
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

  GlobalKey globalDanmuKey = GlobalKey();

  /// 视频画面层的 GlobalKey
  ///
  /// 全屏和半屏在同一 Scaffold 中调整播放区尺寸。
  /// 保留稳定的 key，布局或父节点更新时继续复用纹理子树。
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

  // ------------------------------------------------ 播放参数面板
  //
  // 「打开时才采集、关闭就停」的两段式设计：
  // UI 侧只管调 [openMetricsPanel] / [closeMetricsPanel]，
  // 这里负责与原生同步开关，并在关闭时把订阅与定时器都取消掉。

  /// 播放参数面板是否打开
  var metricsPanelVisible = false.obs;

  /// 最新的播放参数
  Rxn<PlaybackMetrics> playbackMetrics = Rxn<PlaybackMetrics>();

  /// 面板期间额外的轮询定时器
  ///
  /// Format 回调只在编码参数**变化**时触发，直播长时间稳定播放时
  /// 不会有新事件；而码率是浮动的，用户看面板时希望看到变化，
  /// 所以面板打开期间补一个低频轮询。关闭面板时立刻取消。
  Timer? _metricsPollTimer;

  /// 打开播放参数面板：开始采集
  Future<void> openMetricsPanel() async {
    if (metricsPanelVisible.value) {
      return;
    }
    metricsPanelVisible.value = true;
    playbackMetrics.value = null;
    // 指标事件统一由 initStream 里那一条常驻订阅接收（见 metrics 分支），
    // 这里不再单独订阅一次：两条订阅会各自收到同一个事件，
    // 关闭面板时还要各自取消，纯属多余。
    // 先主动读一次，覆盖「流已播很久、Format 回调早就不再来」的情况。
    final initial = await nativePlayer.getPlaybackMetrics();
    if (initial != null && metricsPanelVisible.value) {
      playbackMetrics.value = initial;
    }
    await nativePlayer.setMetricsListening(true);
    // 低频补刷。码率/帧率是实测值，会持续变化，1 秒刷一次既跟得上又不费电。
    _metricsPollTimer?.cancel();
    _metricsPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!metricsPanelVisible.value) {
        return;
      }
      final m = await nativePlayer.getPlaybackMetrics();
      if (m != null && metricsPanelVisible.value) {
        playbackMetrics.value = m;
      }
    });
  }

  /// 关闭播放参数面板：彻底停止采集
  ///
  /// 需求明确要求「再次点击关闭显示且不在后台继续监听」，
  /// 所以这里要把原生监听与轮询定时器都停掉，
  /// 而不是只把 UI 藏起来。
  Future<void> closeMetricsPanel() async {
    if (!metricsPanelVisible.value) {
      return;
    }
    metricsPanelVisible.value = false;
    playbackMetrics.value = null;
    _metricsPollTimer?.cancel();
    _metricsPollTimer = null;
    // 原生侧置 false 后，字节统计与帧计数回调全部短路，
    // 等于采样彻底停下，不只是不显示。
    await nativePlayer.setMetricsListening(false);
  }

  /// 切换播放参数面板
  ///
  /// 内部整体包了 try/catch：调用方是 IconButton.onPressed，
  /// 它不会 await 返回的 Future，一旦抛异常会变成未捕获错误
  /// （Flutter 只在控制台打一行红字，用户看到的就是「点了没反应」）。
  void toggleMetricsPanel() {
    () async {
      try {
        if (metricsPanelVisible.value) {
          await closeMetricsPanel();
        } else {
          await openMetricsPanel();
        }
      } catch (e) {
        Log.logPrint(e);
        Log.d("切换播放信息面板失败：$e");
        // 兜底：可能已经开启了原生采集但中途失败，
        // 必须显式关掉，否则会在后台一直采样。
        await nativePlayer.setMetricsListening(false);
        metricsPanelVisible.value = false;
        playbackMetrics.value = null;
      }
    }();
  }

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

  /// 与原生侧同步视频尺寸
  ///
  /// `videoSize` 事件只在**尺寸发生变化**时发射（原生侧用 changed 去重）。
  /// 复用播放器（小窗回到页面、再次进入同一主播）时这条流早就回调过了，
  /// 新页面收不到事件，`videoAspectRatio` 会停在 16/9 的默认值、
  /// `isVertical` 停留在平台猜测值。
  ///
  /// 直接后果就是这次反馈的「抖音横屏视频双击全屏不变横屏」：
  /// 横屏抖音流被当成竖屏，全屏时走了「保持竖屏」分支。
  /// 所以接管时必须主动查一次真实尺寸。
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

  /// 统一的「落地视频尺寸」入口
  ///
  /// 【为什么不能各处自己赋值】
  /// `videoAspectRatio` 直接决定播放画面的高度预算
  /// （见 live_room_page 的 `height: 1000 / aspect`），
  /// 一旦它是一个离谱的值（极大），画面高度就被压成几个像素——
  /// 用户看到的就是「画面被压缩成一条」。
  ///
  /// 而离谱值是真会出现的：
  /// - 原生 `videoAspect` 由 `width * SAR / height` 得到，
  ///   SAR（pixelWidthHeightRatio）在某些转码流里是脏数据；
  /// - 播放器跨房间复用时，上一路流残留的 aspect 会短暂与新的 width/height 错配；
  /// - 切换全屏时页面重建，`Obx` 会拿「此刻」的值重算高度预算。
  ///
  /// 【为什么是「拒绝写入」而不是「夹到边界」】
  /// 原生侧按「值有没有变」去重（见 `onVideoSizeChanged` 的
  /// `sizeChanged || aspectChanged`）。这是关键：
  /// 如果这里把脏值夹到 4.0 再写进去，Dart 侧就是 4.0，
  /// 而原生侧那边 `videoAspect` 已经等于那个脏值、不再算「变了」，
  /// **不会补发一条正确事件**。于是错值一直粘住，直到换个清晰度或重启应用。
  /// 表现为「用一段时间后切全屏画面永远是一条，重启才好」。
  ///
  /// 所以脏值必须**什么都不写**：保留上一个可信值，布局就不会塌。
  /// 万一上一个值也没有，`videoAspectRatio` 仍停在 16/9 的初值，画面正常。
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

  Widget? danmakuView;

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
  /// 弹幕控制器
  DanmakuController? danmakuController;

  void initDanmakuController(DanmakuController e) {
    danmakuController = e;
  }

  void updateDanmuOption(DanmakuOption? option) {
    if (danmakuController == null || option == null) return;
    danmakuController!.updateOption(option);
  }

  void disposeDanmakuController() {
    danmakuController?.clear();
  }

  void addDanmaku(List<DanmakuContentItem> items) {
    if (!showDanmakuState.value) {
      return;
    }
    for (var item in items) {
      danmakuController?.addDanmaku(item);
    }
  }
}

mixin PlayerSystemMixin on PlayerMixin, PlayerStateMixin, PlayerDanmakuMixin {
  /// 初始化一些系统状态
  void initSystem() async {
    VolumeController.instance.showSystemUI = false;

    // 进入页面时先把控件显示出来，让用户知道这里可以操作，
    // 5 秒后按常规逻辑自动隐藏。
    showControlsState.value = true;
    resetHideControlsTimer();

    if (AppSettingsController.instance.autoFullScreen.value) {
      enterFullScreen();
    }
  }

  /// 释放一些系统状态
  Future resetSystem() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );

    await setAutoOrientation();
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (e) {
      Log.logPrint(e);
    }

    await WakelockPlus.disable();
  }

  /// 进入全屏
  ///
  /// 原实现是 `if (!isVertical.value) setLandscapeOrientation()`，
  /// 即「竖屏流横屏时保持竖屏」。这个判断对抖音是错的：
  /// - 抖音在控制器构造函数里被硬编码成 `isVertical = true`（因为抖音大量是竖屏直播），
  ///   而这次 `videoSize` 回调如果因为复用播放器没有触发，`isVertical` 就一直是那个初值；
  /// - 于是看横屏抖音直播时双击全屏，走进 `enterFullScreen` → 被 `!isVertical` 挡掉
  ///   → 只隐藏了状态栏，方向完全没变，用户看到的就是「双击全屏没变横屏」。
  ///
  /// 正确判据应该是**当前视频画面本身**是不是竖的，而不是构造时的平台猜测：
  /// 用 `videoAspectRatio`（由真实 `onVideoSizeChanged` 得来）判断，
  /// 竖屏视频（比例 < 1）全屏时保持竖屏，横屏视频转横屏。
  void enterFullScreen() {
    fullScreenState.value = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    if (isLandscapeVideo) {
      setLandscapeOrientation();
    } else {
      // 竖屏内容全屏：锁死竖屏，转手机也不动。
      //
      // 不能「什么都不做」：上一次看横屏流会把方向留成 SENSOR_LANDSCAPE，
      // 不显式改的话竖屏内容会被强行掰成横屏。
      // 也不能 setAutoOrientation：那会跟随手机转成横屏，
      // 用户明确要求「竖屏不处理，也不要旋转成横屏」。
      setPortraitOrientation();
    }
  }

  /// 当前画面是否是横屏内容（宽 > 高）
  ///
  /// 不用 isVertical 字段：那个值在「复用播放器」时可能停留在构造初值，
  /// 而 videoAspectRatio 来自原生 onVideoSizeChanged 的真实分辨率。
  bool get isLandscapeVideo => videoAspectRatio.value > 1.0;

  /// 退出全屏
  void exitFull() {
    // 退出全屏时参数面板不可见，必须顺手停掉采集，
    // 否则它会以「已打开」的状态继续在后台轮询。
    closeMetricsPanel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values);
    setAutoOrientation();
    fullScreenState.value = false;
  }

  /// 全屏看横屏内容：按手机物理方向横过来
  ///
  /// 走原生 `SENSOR_LANDSCAPE`（不是 Dart 的 `setPreferredOrientations`）。
  /// 原因见 [NativePlayerBridge.setScreenOrientation]：
  /// Flutter 的方向映射表里根本没有 SENSOR 系列，传
  /// `[landscapeLeft, landscapeRight]` 只能得到 USER_LANDSCAPE，
  /// **受系统「旋转锁定」约束**——用户关掉系统自动旋转后画面就不跟着翻了。
  /// 换成 SENSOR_LANDSCAPE 后：
  /// - 手机横着拿（左横或右横）→ 画面按那一侧正过来，与系统旋转锁无关；
  /// - 手机竖着拿 → 仍是横屏，不会把横屏内容掰成竖屏。
  Future setLandscapeOrientation() async {
    await nativePlayer.setScreenOrientation("landscape");
  }

  /// 全屏看竖屏内容：锁死竖屏
  ///
  /// 用 `PORTRAIT`，转手机也不动。需求明确「竖屏不处理」，
  /// 所以这里不跟随传感器。
  Future setPortraitOrientation() async {
    await nativePlayer.setScreenOrientation("portrait");
  }

  /// 恢复「跟随系统自动旋转」的方向策略
  ///
  /// 非全屏页面、退出播放器时都调这个。用 `USER`
  /// 而不是 SENSOR/FULL_USER：必须尊重用户在系统里设的自动旋转开关，
  /// 不能把普通页面的方向也强行交给传感器。
  Future setAutoOrientation() async {
    await nativePlayer.setScreenOrientation("auto");
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
    final sourceElapsed = sourceTimeStamp != null && _lastVolumeDragTime != null
        ? (sourceTimeStamp - _lastVolumeDragTime!).inMicroseconds
        : 0;
    final elapsedMicros =
        sourceElapsed > 0 ? sourceElapsed : nowMicros - _lastVolumeSampleMicros;
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
          // 面板没开时直接丢弃：原生侧已经短路不再采样，
          // 这里再判一次是防御「关闭瞬间仍在管道里的那一两条事件」。
          if (metricsPanelVisible.value && event.metrics != null) {
            playbackMetrics.value = event.metrics;
          }
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
    // 页面销毁时必须停掉播放参数采集，否则原生端口还会继续回调，
    // 相当于在后台白白采集。
    _metricsPollTimer?.cancel();
    _metricsPollTimer = null;
    if (metricsPanelVisible.value) {
      metricsPanelVisible.value = false;
      nativePlayer.setMetricsListening(false);
    }
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
    disposeDanmakuController();
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

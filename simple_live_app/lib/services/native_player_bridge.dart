import 'dart:async';

import 'package:flutter/services.dart';

/// 原生播放器事件
enum NativePlayerEventType {
  buffering,
  playing,
  completed,
  error,
  videoSize,
  floatingTap,
  floatingClosed,

  /// 小窗还在、Dart 侧刚重新订阅：说明是「退到桌面再回来」的场景，
  /// 需要把 FloatingSession 的状态补回来。
  floatingRestored,

  /// 首帧已经渲染到纹理，可以撤掉 loading 遮罩
  firstFrame,

  /// 播放参数更新（分辨率 / 码率 / 帧率等）
  ///
  /// 只有面板打开时原生端才会发这个事件；关闭后不再产生。
  metrics,
}

/// 当前播放流的技术参数
///
/// 数值来自**这条流本身**的实测统计，不是用户选择的清晰度标签：
/// - 分辨率：ExoPlayer 解码出的真实视频尺寸；
/// - 码率：统计 HTTP 实际下载字节 / 时间（含音频与容器开销）；
/// - 帧率：统计实际渲染出的帧数 / 时间。
///
/// 直播流的 Format 里 bitrate/frameRate 基本都是 -1，
/// 所以不能直接读，必须实测——这也是这几个值要等一两秒才出现的原因。
class PlaybackMetrics {
  /// 视频宽（像素）
  final int width;

  /// 视频高（像素）
  final int height;

  /// 实测整条流码率（bps），0 表示还在采样
  final int videoBitrate;

  /// 实测帧率，0 表示还在采样
  final double frameRate;

  /// 视频编码，如 avc1.640028 / hvc1.1.6.L120
  final String videoCodec;

  /// 音频编码
  final String audioCodec;

  /// 声道数
  final int audioChannels;

  /// 音频采样率（Hz）
  final int audioSampleRate;

  /// 码率是否为实测值（false 表示仍是取样中或仅为标称值）
  final bool bitrateMeasured;

  /// 帧率是否为实测值
  final bool frameRateMeasured;

  /// 当前播放地址
  final String url;

  const PlaybackMetrics({
    this.width = 0,
    this.height = 0,
    this.videoBitrate = 0,
    this.frameRate = 0,
    this.videoCodec = "",
    this.audioCodec = "",
    this.audioChannels = 0,
    this.audioSampleRate = 0,
    this.bitrateMeasured = false,
    this.frameRateMeasured = false,
    this.url = "",
  });

  /// 分辨率文案，如 1920×1080
  String get resolutionText {
    if (width <= 0 || height <= 0) {
      return "识别中…";
    }
    return "$width×$height";
  }

  /// 帧率文案
  String get frameRateText {
    if (!frameRateMeasured || frameRate <= 0) {
      return "采样中…";
    }
    if ((frameRate - frameRate.roundToDouble()).abs() < 0.05) {
      return "${frameRate.round()} fps";
    }
    return "${frameRate.toStringAsFixed(1)} fps";
  }

  /// 码率文案
  String get videoBitrateText {
    if (!bitrateMeasured || videoBitrate <= 0) {
      return "采样中…";
    }
    if (videoBitrate >= 1000 * 1000) {
      return "${(videoBitrate / 1000 / 1000).toStringAsFixed(2)} Mbps";
    }
    return "${(videoBitrate / 1000).toStringAsFixed(0)} kbps";
  }

  /// 音频描述，如 AAC / 2 声道 / 48.0 kHz
  String get audioText {
    final parts = <String>[];
    if (audioCodec.isNotEmpty) {
      parts.add(audioCodec.split('.').first);
    }
    if (audioChannels > 0) {
      parts.add("$audioChannels 声道");
    }
    if (audioSampleRate > 0) {
      parts.add("${(audioSampleRate / 1000).toStringAsFixed(1)} kHz");
    }
    if (parts.isEmpty) {
      return "未知";
    }
    return parts.join(" / ");
  }

  static PlaybackMetrics fromMap(Map raw) {
    int asInt(String key) => (raw[key] as num?)?.toInt() ?? 0;
    bool asBool(String key) => raw[key] == true;
    return PlaybackMetrics(
      width: asInt("width"),
      height: asInt("height"),
      videoBitrate: asInt("videoBitrate"),
      frameRate: (raw["frameRate"] as num?)?.toDouble() ?? 0,
      videoCodec: raw["videoCodec"]?.toString() ?? "",
      audioCodec: raw["audioCodec"]?.toString() ?? "",
      audioChannels: asInt("audioChannels"),
      audioSampleRate: asInt("audioSampleRate"),
      bitrateMeasured: asBool("bitrateMeasured"),
      frameRateMeasured: asBool("frameRateMeasured"),
      url: raw["url"]?.toString() ?? "",
    );
  }
}

class NativePlayerEvent {
  final NativePlayerEventType type;
  final bool? boolValue;
  final String? stringValue;
  final int? width;
  final int? height;

  /// 原生侧按 SAR 修正后的真实显示宽高比（仅 [NativePlayerEventType.videoSize] 有值）。
  ///
  /// 布局必须优先用它，而不是 `width / height`：
  /// 变形宽银幕流 `pixelWidthHeightRatio != 1` 时直接相除会明显偏差。
  final double? aspectRatio;

  /// 仅 [NativePlayerEventType.metrics] 有值
  final PlaybackMetrics? metrics;

  const NativePlayerEvent({
    required this.type,
    this.boolValue,
    this.stringValue,
    this.width,
    this.height,
    this.aspectRatio,
    this.metrics,
  });

  static NativePlayerEvent? fromMap(dynamic raw) {
    if (raw is! Map) {
      return null;
    }
    final type = raw["type"]?.toString();
    switch (type) {
      case "buffering":
        return NativePlayerEvent(
          type: NativePlayerEventType.buffering,
          boolValue: raw["value"] == true,
        );
      case "playing":
        return NativePlayerEvent(
          type: NativePlayerEventType.playing,
          boolValue: raw["value"] == true,
        );
      case "completed":
        return const NativePlayerEvent(type: NativePlayerEventType.completed);
      case "error":
        return NativePlayerEvent(
          type: NativePlayerEventType.error,
          stringValue: raw["value"]?.toString() ?? "播放错误",
        );
      case "videoSize":
        final aspect = (raw["aspectRatio"] as num?)?.toDouble();
        return NativePlayerEvent(
          type: NativePlayerEventType.videoSize,
          width: (raw["width"] as num?)?.toInt(),
          height: (raw["height"] as num?)?.toInt(),
          aspectRatio: (aspect != null && aspect > 0) ? aspect : null,
        );
      case "floatingTap":
        return const NativePlayerEvent(type: NativePlayerEventType.floatingTap);
      case "floatingClosed":
        return const NativePlayerEvent(
          type: NativePlayerEventType.floatingClosed,
        );
      case "floatingRestored":
        return const NativePlayerEvent(
          type: NativePlayerEventType.floatingRestored,
        );
      case "firstFrame":
        return const NativePlayerEvent(type: NativePlayerEventType.firstFrame);
      case "metrics":
        return NativePlayerEvent(
          type: NativePlayerEventType.metrics,
          metrics: PlaybackMetrics.fromMap(raw),
        );
      default:
        return null;
    }
  }
}

/// 小窗弹幕条目
///
/// 只保留原生渲染必需的两项：文本与颜色。字号、不透明度、字重、
/// 显示区域、滚动速度等属于**全局样式**，通过
/// [NativePlayerBridge.setFloatingDanmakuOptions] 一次性同步，
/// 不跟每条弹幕重复传输。
class FloatingDanmakuItem {
  const FloatingDanmakuItem({
    required this.text,
    required this.color,
  });

  /// 弹幕文本
  final String text;

  /// 文字颜色，ARGB 整数（与 `Color.value` 一致）
  final int color;
}

/// 设备媒体音量的真实档位，不是播放器内部增益。
class SystemVolumeState {
  const SystemVolumeState({
    required this.currentIndex,
    required this.maxIndex,
  });

  final int currentIndex;
  final int maxIndex;

  double get volume => maxIndex > 0 ? currentIndex / maxIndex : 0.0;

  factory SystemVolumeState.fromMap(Map<String, dynamic>? data) {
    final current = data?["currentIndex"];
    final maximum = data?["maxIndex"];
    if (current is! int ||
        maximum is! int ||
        maximum < 0 ||
        current < 0 ||
        current > maximum) {
      throw const FormatException("系统音量档位无效");
    }
    return SystemVolumeState(currentIndex: current, maxIndex: maximum);
  }
}

/// 原生播放器桥接
///
/// 对应 Android 侧 `NativePlayerManager`。
/// 全应用只有一个原生播放器实例，播放页和悬浮窗共用同一条流，
/// 因此「页面 → 悬浮窗」切换不需要重新取流。
class NativePlayerBridge {
  NativePlayerBridge._();

  static final NativePlayerBridge instance = NativePlayerBridge._();

  static const MethodChannel _method =
      MethodChannel("simple_live/native_player");
  static const EventChannel _event =
      EventChannel("simple_live/native_player/events");

  StreamSubscription<dynamic>? _eventSubscription;

  final _controller = StreamController<NativePlayerEvent>.broadcast();

  /// 原生播放器事件流
  ///
  /// 关键：getter 里必须保证原生 EventChannel 已经订阅上。
  ///
  /// 之前这里只返回 [_controller].stream，而真正的原生订阅
  /// [_ensureListening] 只在 initTexture / open / switchSource 里调。
  /// 「一路返回退到桌面再点小窗」这条路径上，Dart 侧跑完 main() 后
  /// 只会执行 [FloatingSession.init] → 订阅这个 Dart 流，
  /// **没有任何一处会去订阅原生 EventChannel**，
  /// 于是原生侧的 emit 永远送不到 Dart，表现为「点小窗只把 App 打开，
  /// 回不到直播页」。这里让 getter 顺带完成订阅，把这个坑封住。
  Stream<NativePlayerEvent> get events {
    _ensureListening();
    return _controller.stream;
  }

  /// 视频尺寸变化
  int? videoWidth;
  int? videoHeight;

  bool _listening = false;

  /// 重新订阅原生事件流
  ///
  /// 正常情况只需订阅一次。但「一路返回退到桌面」会把 Activity 与
  /// Flutter 引擎一起销毁，再次进入 App 时 Dart 侧是全新的 isolate，
  /// 这个单例也随之重建，所以订阅本身也会重来一遍——不需要额外处理。
  ///
  /// 保留这个方法是为了在「引擎重建但 Dart isolate 复用」的极端情况下
  /// 能强制刷新订阅（旧 EventChannel 绑在已销毁引擎上，收不到任何事件）。
  void restartListening() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _listening = false;
    _ensureListening();
  }

  void _ensureListening() {
    if (_listening) {
      return;
    }
    _listening = true;
    _eventSubscription = _event.receiveBroadcastStream().listen(
      (dynamic raw) {
        final event = NativePlayerEvent.fromMap(raw);
        if (event == null) {
          return;
        }
        if (event.type == NativePlayerEventType.videoSize) {
          videoWidth = event.width;
          videoHeight = event.height;
        }
        if (!_controller.isClosed) {
          _controller.add(event);
        }
      },
      onError: (Object e) {
        // 原生侧未就绪时忽略，页面会自行重试
      },
    );
  }

  /// 初始化视频纹理，返回 Flutter 纹理 id
  ///
  /// 画面不走 PlatformView，而是走 Flutter 外部纹理，
  /// 这样视频帧能进入 Flutter 渲染管线，弹幕与控件才能正常叠加。
  Future<int?> initTexture() async {
    _ensureListening();
    try {
      return await _method.invokeMethod<int>("initTexture");
    } catch (_) {
      return null;
    }
  }

  Future<void> releaseTexture() async {
    try {
      await _method.invokeMethod("releaseTexture");
    } catch (_) {}
  }

  Future<void> open(String url,
      {Map<String, String>? headers, bool forceReload = false}) async {
    _ensureListening();
    await _method.invokeMethod("open", {
      "url": url,
      "headers": headers,
      "forceReload": forceReload,
    });
  }

  Future<void> play() async {
    await _method.invokeMethod("play");
  }

  /// 无缝换源：保留播放器实例与纹理绑定，只替换媒体源
  ///
  /// 与 [open] 的区别：open 会重置首帧标记，Dart 侧随之盖上 loading 遮罩，
  /// 表现为黑屏转圈。switchSource 不做这个重置，画面上上一帧还在，
  /// 用于直播地址签名过期后的续播。
  Future<void> switchSource(String url, {Map<String, String>? headers}) async {
    _ensureListening();
    // 换源失败必须上报，不能让界面误以为已经成功切换。
    await _method.invokeMethod("switchSource", {
      "url": url,
      "headers": headers,
    });
  }

  /// 原生播放器里是否还有一条活着的流
  ///
  /// 从悬浮小窗/同一主播回到播放页时，用它判断能否直接接管画面，
  /// 避免重新取流导致的一次 loading。
  Future<bool> hasActiveStream() async {
    try {
      final result = await _method.invokeMethod<bool>("hasActiveStream");
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> pause() async {
    await _method.invokeMethod("pause");
  }

  /// 「按 Home 键自动暂停」开关
  ///
  /// 判断发生在原生侧（onUserLeaveHint），所以这个开关必须下发到原生，
  /// Dart 侧的 didChangeAppLifecycleState 做不到「区分 Home 与来电」。
  /// 原生侧还会自行排除小窗播放的情况（见 NativePlayerManager.onUserLeaveHint）。
  Future<void> setPauseOnHome(bool enabled) async {
    try {
      await _method.invokeMethod("setPauseOnHome", enabled);
    } catch (_) {
      // 旧原生实现没有这个方法时静默忽略
    }
  }

  /// 播放器全屏方向控制
  ///
  /// 【为什么不直接用 SystemChrome.setPreferredOrientations】
  /// Flutter 引擎把方向列表翻译成一小组固定常量
  /// （`PlatformChannel.decodeOrientations`，值域 -1/0/1/2/8/9/11/12/13），
  /// **不含 SENSOR 系列**。传 landscapeLeft+landscapeRight 只能得到
  /// USER_LANDSCAPE，受系统「旋转锁定」约束：关掉系统自动旋转后，
  /// 全屏画面不会跟着手机翻转。B站/腾讯视频用的是 SENSOR_LANDSCAPE，
  /// 所以它们可以。这里绕到原生直接下发 SENSOR 常量。
  ///
  /// - `landscape`：横屏内容全屏用（SENSOR_LANDSCAPE，左右由传感器决定）
  /// - `auto`：非全屏 / 竖屏内容用（FULL_USER，四向跟随手机）
  Future<void> setScreenOrientation(String mode) async {
    try {
      await _method.invokeMethod("setScreenOrientation", mode);
    } catch (_) {
      // 旧原生实现没有这个方法时静默忽略
    }
  }

  Future<void> stop() async {
    await _method.invokeMethod("stop");
  }

  Future<void> release() async {
    await _method.invokeMethod("release");
  }

  Future<void> setVolume(double volume) async {
    await _method.invokeMethod("setVolume", volume);
  }

  /// 读取 Android 媒体音量的当前档位及最大档位。
  Future<SystemVolumeState> getSystemVolumeState() async {
    final data =
        await _method.invokeMapMethod<String, dynamic>("getSystemVolumeState");
    return SystemVolumeState.fromMap(data);
  }

  /// 设置系统媒体音量并在同一次调用中返回实际结果。
  /// 不显示系统音量条，也不改变播放器内部增益。
  Future<SystemVolumeState> setSystemVolumeIndex(int index) async {
    final data = await _method.invokeMapMethod<String, dynamic>(
        "setSystemVolumeIndex", index);
    return SystemVolumeState.fromMap(data);
  }

  Future<bool> isPlaying() async {
    final result = await _method.invokeMethod<bool>("isPlaying");
    return result ?? false;
  }

  /// 是否已经有画面帧
  ///
  /// 从悬浮小窗回到页面时纹理是复用的，首帧事件不会再发一次，
  /// 需要主动查一下，否则页面会一直卡在 loading。
  Future<bool> hasRenderedFrame() async {
    try {
      final result = await _method.invokeMethod<bool>("hasRenderedFrame");
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 清空页内纹理里残留的上一路流的画面，并复位首帧标记
  ///
  /// 纹理是全局单例复用的，里面始终留着上一路流的最后一帧。
  /// 进入另一个直播间的播放页时，只把 `hasRenderedFirstFrame` 置 false
  /// 并不够——纹理里那一帧照样会被合成出来，用户看到「加载中却显示上一个直播」。
  Future<void> clearTexture() async {
    try {
      await _method.invokeMethod<bool>("clearTexture");
    } catch (_) {
      // 兼容旧原生实现：没有这个方法时静默忽略，
      // 上层仍会用不透明黑底盖住，观感上不会露帧。
    }
  }

  /// 当前视频的真实分辨率
  ///
  /// `videoSize` 事件只在尺寸变化时发射，复用播放器时新页面收不到，
  /// 需要主动查一次，否则宽高比会停在默认 16:9，
  /// 横屏视频双击全屏时不会转横屏。
  Future<Map<String, num>?> getVideoSize() async {
    try {
      final raw = await _method.invokeMethod<Map>("getVideoSize");
      if (raw == null) {
        return null;
      }
      final width = (raw["width"] as num?)?.toInt() ?? 0;
      final height = (raw["height"] as num?)?.toInt() ?? 0;
      if (width <= 0 || height <= 0) {
        return null;
      }
      // aspectRatio 是原生侧按 SAR 修正过的真实显示比例，
      // 变形宽银幕流（pixelWidthHeightRatio != 1）用 width/height 相除会偏，
      // 所以一并返回，由调用方优先使用。
      final aspect = (raw["aspectRatio"] as num?)?.toDouble() ?? 0;
      return {
        "width": width,
        "height": height,
        "aspectRatio": aspect > 0 ? aspect : width / height,
      };
    } catch (_) {
      return null;
    }
  }

  /// 当前正在播放的地址
  ///
  /// 供播放信息面板展示与排障使用。直播地址带有签名/过期参数，
  /// 断流时先看这里能直接判断是哪一类问题（签名过期、鉴权失败、换不到源）。
  Future<String?> getCurrentUrl() async {
    try {
      final result = await _method.invokeMethod<String>("getCurrentUrl");
      if (result == null || result.isEmpty) {
        return null;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  /// 开关播放参数采集
  ///
  /// 面板打开时传 true，原生端开始采集并通过 [events] 推
  /// [NativePlayerEventType.metrics]；传 false 后原生端采集逻辑全部短路，
  /// 不再计算、不再回调——需求要求「关闭后不在后台继续监听」。
  Future<void> setMetricsListening(bool listening) async {
    try {
      await _method.invokeMethod("setMetricsListening", listening);
    } catch (_) {
      // 桌面端 / 旧版本原生实现没有这个通道，静默忽略
    }
  }

  /// 主动读一次播放参数
  ///
  /// 面板刚打开时流可能已经播了很久，Format 回调不会重放，
  /// 必须主动回读一次，否则面板会一直是「未知」。
  ///
  /// 不按「是否为空」过滤：刚打开面板时码率/帧率还在采样，
  /// 此时分辨率可能已经有了，直接丢掉会让面板一直空白到采样完成。
  Future<PlaybackMetrics?> getPlaybackMetrics() async {
    try {
      final raw = await _method.invokeMethod<Map>("getPlaybackMetrics");
      if (raw == null) {
        return null;
      }
      return PlaybackMetrics.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  /// 进入悬浮小窗
  Future<bool> enterFloating({
    int width = 480,
    int height = 270,
  }) async {
    final result = await _method.invokeMethod<bool>("enterFloating", {
      "width": width,
      "height": height,
    });
    return result ?? false;
  }

  Future<void> exitFloating() async {
    await _method.invokeMethod("exitFloating");
  }

  Future<bool> isFloating() async {
    final result = await _method.invokeMethod<bool>("isFloating");
    return result ?? false;
  }

  /// 读取小窗正在播放的房间（原生侧保管）
  ///
  /// 「一路返回退到桌面」会把 Activity 连同 Flutter 引擎一起销毁，
  /// 再进来时 Dart 侧是全新的，FloatingSession 里房间信息全没了，
  /// 但系统级小窗和播放器还活着。这里把房间信息读回来。
  Future<Map<String, String>?> getFloatingRoom() async {
    try {
      final raw = await _method.invokeMethod<Map>("getFloatingRoom");
      if (raw == null) {
        return null;
      }
      final siteId = raw["siteId"]?.toString();
      final roomId = raw["roomId"]?.toString();
      if (siteId == null ||
          siteId.isEmpty ||
          roomId == null ||
          roomId.isEmpty) {
        return null;
      }
      return {"siteId": siteId, "roomId": roomId};
    } catch (_) {
      return null;
    }
  }

  /// 记录小窗正在播放的房间，供引擎重建后恢复
  Future<void> setFloatingRoom({
    required String siteId,
    required String roomId,
  }) async {
    try {
      await _method.invokeMethod("setFloatingRoom", {
        "siteId": siteId,
        "roomId": roomId,
      });
    } catch (_) {}
  }

  // ------------------------------------------------------------ 小窗弹幕
  //
  // 小窗是系统悬浮窗（原生 SurfaceView），进小窗时直播页已 pop，
  // Flutter 的弹幕层不复存在，所以弹幕由原生绘制。
  // 这里只负责把「开关 / 样式 / 内容」送过去。

  /// 开关小窗弹幕显示
  ///
  /// 关闭时原生侧把弹幕层置 GONE 并清空，配合 Dart 侧停止下发数据，
  /// 弹幕整条链路零开销。
  Future<bool> setFloatingDanmakuEnabled(bool enabled) async {
    try {
      final result = await _method.invokeMethod<bool>(
        "setFloatingDanmakuEnabled",
        {"enabled": enabled},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 同步小窗弹幕样式（小窗专属的一套设置，与播放器弹幕互不影响）
  Future<void> setFloatingDanmakuOptions({
    required double fontSize,
    required int fontWeight,
    required double opacity,
    required double area,
    required int duration,
    required double topMargin,
    required double bottomMargin,
    required int maxConcurrent,
  }) async {
    try {
      await _method.invokeMethod("setFloatingDanmakuOptions", {
        "fontSize": fontSize,
        "fontWeight": fontWeight,
        "opacity": opacity,
        "area": area,
        "duration": duration,
        "topMargin": topMargin,
        "bottomMargin": bottomMargin,
        "maxConcurrent": maxConcurrent,
      });
    } catch (_) {}
  }

  /// 批量追加小窗弹幕
  ///
  /// 一次送多条：直播弹幕天然是批量的，每条一次 channel 往返
  /// 会明显增加主线程开销。
  Future<void> addFloatingDanmaku(List<FloatingDanmakuItem> items) async {
    if (items.isEmpty) {
      return;
    }
    try {
      await _method.invokeMethod("addFloatingDanmaku", {
        "items": items
            .map((e) => {"text": e.text, "color": e.color})
            .toList(growable: false),
      });
    } catch (_) {}
  }

  /// 清空小窗弹幕（切换房间、关闭小窗时）
  Future<void> clearFloatingDanmaku() async {
    try {
      await _method.invokeMethod("clearFloatingDanmaku");
    } catch (_) {}
  }

  Future<bool> hasOverlayPermission() async {
    final result = await _method.invokeMethod<bool>("hasOverlayPermission");
    return result ?? false;
  }

  Future<void> requestOverlayPermission() async {
    await _method.invokeMethod("requestOverlayPermission");
  }

  /// 是否电视设备（TV 端禁用悬浮窗）
  Future<bool> isTvDevice() async {
    try {
      final result = await _method.invokeMethod<bool>("isTvDevice");
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 把 App 拉回前台（点击悬浮窗时使用）
  Future<void> bringToFront() async {
    try {
      await _method.invokeMethod("bringToFront");
    } catch (_) {}
  }

  /// 把 App 退到后台，但保留 Activity 与页面实例
  Future<void> moveToBack() async {
    try {
      await _method.invokeMethod("moveToBack");
    } catch (_) {}
  }

  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _listening = false;
  }
}

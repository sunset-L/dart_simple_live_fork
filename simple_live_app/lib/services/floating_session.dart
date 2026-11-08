import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/danmaku_shielder.dart';
import 'package:simple_live_app/services/native_player_bridge.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 悬浮小窗会话（App 级，全局唯一）
///
/// 为什么必须放在 App 级：
/// 返回进小窗后直播页会被正常 pop，页面控制器随之销毁，
/// 此时它已经收不到原生侧的 [NativePlayerEventType.floatingTap] /
/// [NativePlayerEventType.floatingClosed] 事件了。
/// 所以小窗的点击与关闭必须由一个不随页面销毁的全局对象来接管。
///
/// 职责边界：
/// - 视频实例（ExoPlayer）由原生侧持有，这里只负责「页面」这一层的进出。
/// - 小窗播放期间播放器与网络流持续存活，页面重建后直接接管，不重新取流。
class FloatingSession {
  FloatingSession._();

  static final FloatingSession instance = FloatingSession._();

  /// 小窗是否正在播放
  final RxBool isFloating = false.obs;

  /// 小窗正在播的直播间
  Site? _site;
  String? _roomId;

  // 小窗重新绑定、接管或关闭后，异步任务必须丢弃旧会话结果。
  int _sessionRevision = 0;
  int? _refreshingRevision;
  int _danmakuRevision = 0;
  bool _startingDanmaku = false;

  bool get hasSession => _site != null && (_roomId?.isNotEmpty ?? false);

  Site? get site => _site;
  String? get roomId => _roomId;

  StreamSubscription<NativePlayerEvent>? _subscription;

  /// 控制器的「已接管流」标记：点击小窗后置 true，
  /// 新页面据此跳过重新取流，直接接管原生播放器里还在跑的流。
  bool restoredFromFloating = false;

  /// 小窗播放期间的自愈回调
  ///
  /// 直播平台取流地址带时效签名（斗鱼 wsSecret/wsTime 约 10 分钟失效），
  /// 小窗播放时页面控制器已经销毁，没人负责重新取流，小窗就会卡死。
  /// 这里在小窗期间由全局会话持有一次「取流能力」，
  /// 检测到异常时重新请求地址并让原生播放器换流。
  /// 小窗期间持有：当前线路序号与线路总数
  ///
  /// 页面接管已有流时不会重新取流，`playUrls` 是空的，
  /// 「线路」面板就会显示不出来。这里记下小窗当时的线路状态，
  /// 接管后据此还原显示（线路数够用即可，地址本身仍由续期逻辑负责）。
  int _lineIndex = 0;
  int _lineCount = 1;

  int get lineIndex => _lineIndex;
  int get lineCount => _lineCount;

  Future<void> Function()? onRefreshUrl;

  Timer? _healthTimer;
  int _stalledCount = 0;

  /// 小窗期间的主动续期定时器
  ///
  /// 小窗播放时页面控制器已经销毁，它内部的续期定时器也随之取消，
  /// 于是小窗播放到十分钟左右同样会因为签名过期而断流。
  /// 所以续期职责要跟着「取流能力」一起交接过来。
  Timer? _refreshTimer;

  /// 小窗期间记住当前清晰度，续期时要按同一清晰度重新取流
  LivePlayQuality? _quality;
  String _lineUrl = '';
  List<String> _playUrls = [];
  DateTime? _urlFetchedAt;
  DateTime? get urlFetchedAt => _urlFetchedAt;
  int _selfRefreshFailures = 0;
  final Set<String> _failedLines = {};
  Timer? _stablePlaybackTimer;

  String _lineIdentity(String url) {
    final uri = Uri.tryParse(url);
    return uri == null ? url : '${uri.host}${uri.path}';
  }

  void updatePlaybackMetadata({
    LivePlayQuality? quality,
    required int lineIndex,
    required int lineCount,
    required String playUrl,
    List<String>? playUrls,
    DateTime? urlFetchedAt,
  }) {
    if (quality != null) _quality = quality;
    _lineIndex = lineIndex < 0 ? 0 : lineIndex;
    _lineCount = lineCount < 1 ? 1 : lineCount;
    _lineUrl = playUrl;
    if (playUrls != null) _playUrls = List<String>.from(playUrls);
    _urlFetchedAt = urlFetchedAt ?? _urlFetchedAt ?? DateTime.now();
    _startRefreshTimer();
  }

  /// 小窗正在播放的清晰度
  ///
  /// 页面接管已有流时需要它来还原「清晰度」显示，
  /// 否则回到页面后那个位置是空白的。
  LivePlayQuality? get quality => _quality;

  /// 小窗期间自持的续流能力
  ///
  /// onRefreshUrl 由页面控制器注册，页面销毁后就没了。而「退到桌面」
  /// 这种场景下引擎会重建，谁也来不及注册，续期与小窗自愈就全瘫了。
  /// 所以这里用 Site 自带的能力自己续流：重新拉详情拿新签名，
  /// 再按同一清晰度取流，最后交给原生无缝换源。
  Future<void> _refreshBySelf({bool scheduled = false}) async {
    final revision = _sessionRevision;
    final targetSite = _site;
    final targetRoomId = _roomId;
    bool isCurrent() => revision == _sessionRevision && isFloating.value;
    if (!isCurrent() || targetSite == null || targetRoomId == null) return;
    try {
      final native = NativePlayerBridge.instance;
      final actual = await native.getCurrentUrl();
      if (!isCurrent()) return;
      if (actual != null && actual.isNotEmpty) _lineUrl = actual;
      final detail =
          await targetSite.liveSite.getRoomDetail(roomId: targetRoomId);
      if (!isCurrent()) return;
      if (!detail.status) {
        _stopHealthCheck();
        _stopRefreshTimer();
        Log.d("小窗直播已下播，停止自动续流");
        return;
      }
      var quality = _quality;
      if (quality == null) {
        final qualities =
            await targetSite.liveSite.getPlayQualites(detail: detail);
        if (!isCurrent()) return;
        // 引擎重建后通过实际地址找回档位，不擅自切到另一画质。
        final matches = qualities.where((item) =>
            item.data is List &&
            (item.data as List).any((url) =>
                _lineIdentity(url.toString()) == _lineIdentity(_lineUrl)));
        if (matches.isEmpty) throw StateError("无法确认小窗当前画质，请返回直播页重新选择");
        quality = matches.first;
      }
      final fetchedAt = DateTime.now();
      final playUrl = await targetSite.liveSite
          .getPlayUrls(detail: detail, quality: quality);
      if (!isCurrent()) return;
      if (playUrl.urls.isEmpty) throw StateError("直播地址为空");
      final oldUri = Uri.tryParse(_lineUrl);
      final remembered = playUrl.urls.indexWhere((url) {
        final uri = Uri.tryParse(url);
        if (uri == null || oldUri == null || uri.host != oldUri.host) {
          return false;
        }
        return uri.path.contains('.flv') == oldUri.path.contains('.flv') &&
            uri.path.contains('.m3u8') == oldUri.path.contains('.m3u8');
      });
      if (scheduled && remembered < 0) {
        throw StateError("所选小窗线路暂不可用，未自动更换画质或线路");
      }
      var index = remembered >= 0
          ? remembered
          : _lineIndex.clamp(0, playUrl.urls.length - 1);
      if (!scheduled) {
        _failedLines.add(_lineIdentity(_lineUrl));
        var next = -1;
        for (var step = 1; step <= playUrl.urls.length; step++) {
          final candidate = (index + step) % playUrl.urls.length;
          if (!_failedLines.contains(_lineIdentity(playUrl.urls[candidate]))) {
            next = candidate;
            break;
          }
        }
        if (next < 0) {
          _selfRefreshFailures++;
          if (_selfRefreshFailures > 2) throw StateError("小窗所有线路均不可用");
          _failedLines.clear();
          next = 0;
        }
        index = next;
      }
      var url = playUrl.urls[index];
      if (AppSettingsController.instance.playerForceHttps.value) {
        url = url.replaceFirst('http://', 'https://');
      }
      if (!scheduled || url != actual || !await native.isPlaying()) {
        if (!isCurrent()) return;
        Log.d("小窗${scheduled ? '地址续期' : '自动切线'}：线路${index + 1}");
        await native.switchSource(url, headers: playUrl.headers);
        if (!isCurrent()) return;
      }
      updatePlaybackMetadata(
        quality: quality,
        lineIndex: index,
        lineCount: playUrl.urls.length,
        playUrl: url,
        playUrls: playUrl.urls,
        urlFetchedAt: fetchedAt,
      );
    } catch (e) {
      if (!isCurrent()) return;
      _selfRefreshFailures++;
      Log.logPrint(e);
      if (_selfRefreshFailures > 2) {
        _stopHealthCheck();
        _stopRefreshTimer();
        Log.d("小窗续流多次失败，请返回直播页手动刷新");
      }
    }
  }

  Future<void> _refreshUrl({bool scheduled = false}) async {
    final revision = _sessionRevision;
    if (!isFloating.value || _refreshingRevision == revision) return;
    _refreshingRevision = revision;
    try {
      final handler = onRefreshUrl;
      if (!scheduled && handler != null) {
        await handler();
        return;
      }
      if (revision != _sessionRevision || !isFloating.value) return;
      await _refreshBySelf(scheduled: scheduled);
    } catch (e) {
      Log.logPrint(e);
    } finally {
      if (_refreshingRevision == revision) _refreshingRevision = null;
    }
  }

  /// 小窗与直播页使用相同的平台期限，未知期限不猜成固定 7 分钟。
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    if (_site == null || _lineUrl.isEmpty || !isFloating.value) return;
    final fetchedAt = _urlFetchedAt ?? DateTime.now();
    final expiresAt = LiveStreamExpiry.expiresAt(_lineUrl,
        siteId: _site!.id, fetchedAt: fetchedAt);
    if (expiresAt == null) return;
    final lifetime = expiresAt.difference(fetchedAt);
    if (lifetime <= Duration.zero) return;
    final lead = Duration(seconds: (lifetime.inSeconds ~/ 2).clamp(30, 300));
    final delay = expiresAt.subtract(lead).difference(DateTime.now());
    if (delay <= Duration.zero) return;
    _refreshTimer = Timer(delay, () {
      if (isFloating.value) _refreshUrl(scheduled: true);
    });
  }

  Future<void> _confirmNativeLine() async {
    final revision = _sessionRevision;
    final native = NativePlayerBridge.instance;
    final actual = await native.getCurrentUrl();
    if (revision != _sessionRevision || !isFloating.value || actual == null) {
      return;
    }
    final index = _playUrls
        .indexWhere((url) => _lineIdentity(url) == _lineIdentity(actual));
    if (index >= 0) _lineIndex = index;
    _lineUrl = actual;
    _stablePlaybackTimer?.cancel();
    _stablePlaybackTimer = Timer(const Duration(seconds: 30), () {
      if (revision != _sessionRevision ||
          !isFloating.value ||
          _stalledCount > 0) {
        return;
      }
      _selfRefreshFailures = 0;
      _failedLines.clear();
    });
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 小窗期间的健康检查（画面停住就重取流）
  void _startHealthCheck() {
    _stopHealthCheck();
    _stalledCount = 0;
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!isFloating.value) {
        _stopHealthCheck();
        return;
      }
      final revision = _sessionRevision;
      final playing = await NativePlayerBridge.instance.isPlaying();
      if (revision != _sessionRevision || !isFloating.value) return;
      if (playing) {
        _stalledCount = 0;
        return;
      }
      _stalledCount++;
      if (_stalledCount >= 3) {
        _stalledCount = 0;
        Log.d("小窗播放停滞，尝试重新取流");
        await _refreshUrl();
      }
    });
  }

  void _stopHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = null;
    _stalledCount = 0;
  }

  // ---------------------------------------------------------------- 小窗弹幕
  //
  // 【为什么小窗期间要自己建弹幕连接】
  // 进小窗后直播页被 pop，LiveRoomController 的 liveDanmaku 随 onClose 停掉，
  // 而小窗是原生 SurfaceView，Flutter 那层 CanvasDanmaku 也没了。
  // 所以小窗要显示弹幕，必须由这个不随页面销毁的会话自己连一条。
  //
  // 【为什么关闭时连都不连】
  // 用户明确要求：关闭「小窗显示弹幕」时，小窗**不加载弹幕任何数据**，
  // 以免影响性能。所以判断放在最前面，关闭时直接 return，
  // 连 LiveDanmaku 实例都不创建、WebSocket 也不建立。

  /// 小窗期间自持的弹幕连接
  LiveDanmaku? _danmaku;

  /// 小窗弹幕连接是否已启动
  bool get _danmakuActive => _danmaku != null;

  /// 批量发送缓冲：直播弹幕是高频小消息，逐条走 channel 太贵
  final List<FloatingDanmakuItem> _danmakuBuffer = [];

  Timer? _danmakuFlushTimer;

  /// 缓冲刷新间隔。40ms 约等于两帧，观感上完全没有延迟，
  /// 但能把同一瞬间涌进来的十几条合并成一次 channel 调用。
  static const Duration _danmakuFlushInterval = Duration(milliseconds: 40);

  /// 单批上限，避免一次传太大阻塞主线程
  static const int _danmakuBatchMax = 20;

  /// 启动小窗弹幕（仅当设置打开时）
  ///
  /// @param danmakuData 平台弹幕连接需要的参数（通常是房间详情里的 danmakuData）
  Future<void> startDanmakuIfEnabled(dynamic danmakuData) async {
    if (!AppSettingsController.instance.floatingDanmuEnable.value ||
        _danmakuActive ||
        _startingDanmaku) {
      return;
    }
    final targetSite = _site;
    if (targetSite == null) return;
    final sessionRevision = _sessionRevision;
    final revision = ++_danmakuRevision;
    _startingDanmaku = true;
    bool isCurrent() =>
        sessionRevision == _sessionRevision &&
        revision == _danmakuRevision &&
        isFloating.value &&
        AppSettingsController.instance.floatingDanmuEnable.value;
    LiveDanmaku? startedDanmaku;
    try {
      await NativePlayerBridge.instance.setFloatingDanmakuEnabled(true);
      if (!isCurrent()) return;
      await syncDanmakuOptions();
      if (!isCurrent()) return;
      final danmaku = targetSite.liveSite.getDanmaku();
      startedDanmaku = danmaku;
      danmaku.onMessage = _onDanmakuMessage;
      _danmaku = danmaku;
      await danmaku.start(danmakuData);
      if (!isCurrent()) {
        danmaku.onMessage = null;
        await danmaku.stop();
        if (identical(_danmaku, danmaku)) _danmaku = null;
        return;
      }
      Log.d("小窗弹幕已连接");
    } catch (e) {
      Log.logPrint(e);
      if (identical(_danmaku, startedDanmaku)) _danmaku = null;
      if (startedDanmaku != null) {
        startedDanmaku.onMessage = null;
        try {
          await startedDanmaku.stop();
        } catch (stopError) {
          Log.logPrint(stopError);
        }
      }
    } finally {
      if (revision == _danmakuRevision) _startingDanmaku = false;
    }
  }

  /// 停止小窗弹幕并释放连接
  Future<void> stopDanmaku() async {
    final revision = ++_danmakuRevision;
    _startingDanmaku = false;
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    _danmakuBuffer.clear();
    final danmaku = _danmaku;
    _danmaku = null;
    if (danmaku != null) {
      danmaku.onMessage = null;
      try {
        await danmaku.stop();
      } catch (e) {
        Log.logPrint(e);
      }
    }
    if (revision != _danmakuRevision) return;
    await NativePlayerBridge.instance.clearFloatingDanmaku();
    if (revision != _danmakuRevision) return;
    await NativePlayerBridge.instance.setFloatingDanmakuEnabled(false);
  }

  /// 把「小窗弹幕设置」里的样式同步给原生小窗
  ///
  /// 全部属性都取 `floatingDanmu*` 这一套独立值，**不读播放器弹幕的设置**：
  /// 小窗画面小、轨道少，播放器那套参数搬进来普遍过大
  /// （显示区域 80% 会直接把画面糊满）。
  /// 这些属性走这一条通道，不跟每条弹幕重复传输。
  Future<void> syncDanmakuOptions() async {
    final s = AppSettingsController.instance;
    await NativePlayerBridge.instance.setFloatingDanmakuOptions(
      fontSize: s.floatingDanmuSize.value,
      fontWeight: s.floatingDanmuFontWeight.value,
      opacity: s.floatingDanmuOpacity.value,
      area: s.floatingDanmuArea.value,
      duration: s.floatingDanmuSpeed.value.toInt(),
      topMargin: s.floatingDanmuTopMargin.value,
      bottomMargin: s.floatingDanmuBottomMargin.value,
      maxConcurrent: s.floatingDanmuAmount.value,
    );
  }

  /// 设置里改了任一弹幕属性后调用，让小窗弹幕立即跟着变
  ///
  /// 只在「小窗正在播 + 小窗弹幕开着」时才做任何事：
  /// 其他时候连 channel 调用都不发，避免无意义的跨端通信。
  void onDanmakuSettingsChanged() {
    if (!isFloating.value) {
      return;
    }
    if (!AppSettingsController.instance.floatingDanmuEnable.value) {
      // 开关被关掉：立刻停连接并清空已经画出来的弹幕，
      // 不能让「关了但还在跑」的状态留着
      stopDanmaku().catchError((e) => Log.logPrint(e));
      return;
    }
    syncDanmakuOptions().catchError((e) => Log.logPrint(e));
    // 开关从关到开：此时 _danmaku 还是 null，需要补建连接
    if (!_danmakuActive) {
      _restoreDanmakuForCurrent();
    }
  }

  /// 用当前小窗房间重新建立弹幕连接（设置由关变开时用）
  Future<void> _restoreDanmakuForCurrent() async {
    final targetSite = _site;
    final targetRoomId = _roomId;
    if (targetSite == null || targetRoomId == null) {
      return;
    }
    await _restoreDanmaku(targetSite, targetRoomId);
  }

  /// 收到一条弹幕：过滤后进缓冲，由定时器批量下发
  void _onDanmakuMessage(LiveMessage msg) {
    if (msg.type != LiveMessageType.chat) {
      return;
    }
    if (!AppSettingsController.instance.floatingDanmuEnable.value) {
      return;
    }
    // 屏蔽规则与播放器弹幕共用一份实现（关键词 + 福袋），
    // 否则小窗里会冒出播放器里已经被屏蔽的内容
    if (DanmakuShielder.shouldBlock(msg)) {
      return;
    }
    if (msg.message.isEmpty) {
      return;
    }

    _danmakuBuffer.add(
      FloatingDanmakuItem(
        text: msg.message,
        color: (0xFF << 24) |
            (msg.color.r << 16) |
            (msg.color.g << 8) |
            msg.color.b,
      ),
    );
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_danmakuFlushTimer != null) {
      return;
    }
    _danmakuFlushTimer = Timer(_danmakuFlushInterval, () {
      _danmakuFlushTimer = null;
      _flushDanmakuBuffer();
    });
  }

  void _flushDanmakuBuffer() {
    if (_danmakuBuffer.isEmpty) {
      return;
    }
    if (!AppSettingsController.instance.floatingDanmuEnable.value) {
      _danmakuBuffer.clear();
      return;
    }
    // 积压太多说明消费跟不上，丢掉前面的，只留最新一批：
    // 小窗弹幕延迟越来越大比丢弹幕更影响观感
    while (_danmakuBuffer.length > _danmakuBatchMax * 3) {
      _danmakuBuffer.removeAt(0);
    }
    final batch = List<FloatingDanmakuItem>.from(
      _danmakuBuffer.take(_danmakuBatchMax),
    );
    _danmakuBuffer.removeRange(0, batch.length);
    NativePlayerBridge.instance.addFloatingDanmaku(batch).catchError((e) {
      Log.logPrint(e);
    });
    if (_danmakuBuffer.isNotEmpty) {
      _scheduleFlush();
    }
  }

  /// 初始化全局监听（在 main 里调用一次）
  ///
  /// 除了订阅事件，还要做一次「状态恢复」：
  /// 一路返回退到桌面会让 Activity 与 Flutter 引擎一起销毁，
  /// 而系统级小窗和原生播放器都还活着。再次进入 App 时 Dart 侧是全新的，
  /// 这里的状态全部是初值，必须从原生侧把房间信息读回来，
  /// 否则会出现「点小窗回不到播放页」「再点进播放页小窗也不关」。
  void init() {
    _subscription ??= NativePlayerBridge.instance.events.listen((event) {
      switch (event.type) {
        case NativePlayerEventType.playing:
          if (isFloating.value && event.boolValue == true) {
            _confirmNativeLine();
          } else {
            _stablePlaybackTimer?.cancel();
          }
          break;
        case NativePlayerEventType.floatingTap:
          _onTap();
          break;
        case NativePlayerEventType.floatingClosed:
          _onClosed();
          break;
        case NativePlayerEventType.floatingRestored:
          syncFromNative();
          break;
        default:
          break;
      }
    });
    syncFromNative();
  }

  /// 从原生侧把「小窗是否还在、播的是哪个房间」同步回 Dart
  Future<void> syncFromNative() async {
    final revision = _sessionRevision;
    try {
      final floating = await NativePlayerBridge.instance.isFloating();
      if (revision != _sessionRevision || !floating) {
        return;
      }
      final room = await NativePlayerBridge.instance.getFloatingRoom();
      if (revision != _sessionRevision || room == null) {
        return;
      }
      final siteId = room["siteId"]!;
      final roomId = room["roomId"]!;
      final targetSite = Sites.allSites[siteId];
      if (targetSite == null) {
        return;
      }
      // 已经同步过同一个房间就不重复启动定时器
      if (isFloating.value && _site?.id == siteId && _roomId == roomId) {
        return;
      }
      Log.d("恢复小窗会话：$siteId / $roomId");
      _sessionRevision++;
      _site = targetSite;
      _roomId = roomId;
      isFloating.value = true;
      _startHealthCheck();
      _startRefreshTimer();
      // 引擎重建后 Dart 侧是全新的，手里没有原房间的 danmakuData，
      // 得重新拉一次房间详情才能建弹幕连接。
      // 设置关闭时直接跳过，连这个请求都不发。
      if (AppSettingsController.instance.floatingDanmuEnable.value) {
        _restoreDanmaku(targetSite, roomId);
      }
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 引擎重建后恢复小窗弹幕连接
  ///
  /// 只在「小窗显示弹幕」打开时才会被调用 —— 关闭时不发任何请求，
  /// 这是用户明确要求的「不加载弹幕任何数据」。
  Future<void> _restoreDanmaku(Site site, String roomId) async {
    final revision = _sessionRevision;
    if (_danmakuActive) {
      return;
    }
    try {
      final detail = await site.liveSite.getRoomDetail(roomId: roomId);
      if (revision != _sessionRevision || !isFloating.value) {
        // 请求期间用户已经关掉了小窗，不必再连
        return;
      }
      await startDanmakuIfEnabled(detail.danmakuData);
    } catch (e) {
      Log.logPrint(e);
    }
  }

  void bind(
    Site site,
    String roomId, {
    LivePlayQuality? quality,
    int lineIndex = 0,
    int lineCount = 1,
    String playUrl = '',
    List<String>? playUrls,
    DateTime? urlFetchedAt,
    dynamic danmakuData,
  }) {
    _sessionRevision++;
    _site = site;
    _roomId = roomId;
    // 记住清晰度：小窗续期时要按同一画质重新取流，
    // 否则续期后画质会跳回默认档
    if (quality != null) {
      _quality = quality;
    }
    // 记住线路：接管已有流时不会重新取流，界面要靠它显示「线路N」
    _lineIndex = lineIndex;
    _lineCount = lineCount < 1 ? 1 : lineCount;
    _lineUrl = playUrl;
    _playUrls = List<String>.from(playUrls ?? const <String>[]);
    _urlFetchedAt = urlFetchedAt ?? DateTime.now();
    _selfRefreshFailures = 0;
    _failedLines.clear();
    _stablePlaybackTimer?.cancel();
    _startHealthCheck();
    _startRefreshTimer();
    // 小窗弹幕：只有设置打开时才会真正建立连接（见 startDanmakuIfEnabled）
    startDanmakuIfEnabled(danmakuData);
    // 把房间同步给原生侧保管：
    // 退到桌面后 Flutter 引擎会被销毁，Dart 侧这份信息会丢，
    // 但原生小窗和播放器还活着，回来时要靠它恢复。
    NativePlayerBridge.instance
        .setFloatingRoom(
      siteId: site.id,
      roomId: roomId,
    )
        .catchError((e) {
      Log.logPrint(e);
    });
  }

  /// 当前小窗播放的是否就是指定房间
  bool isSameRoom(Site site, String roomId) {
    return _site?.id == site.id && _roomId == roomId;
  }

  /// 页面要独占播放器时调用：只要小窗还开着就关掉它
  ///
  /// 两种场景都必须关，不能只判断「是否同一房间」：
  /// 1. 小窗播着 A 主播，用户又点了 B 主播进直播间；
  /// 2. 小窗播着 A 主播，用户又点了 A 主播进直播间（不是点小窗返回）。
  ///
  /// 原生侧输出优先级是「悬浮窗 > 页内纹理」，小窗只要还在，
  /// 画面就会一直被送进小窗，新页面的播放器拿不到输出，表现为黑屏或有声无画。
  ///
  /// 只有「点击小窗返回」这一条路径例外，它走 [restoredFromFloating] 分支直接接管，
  /// 不会调用本方法。
  ///
  /// 返回 true 表示确实关掉了小窗。
  Future<bool> closeIfPlaying({
    required Site site,
    required String roomId,
  }) async {
    // 判定依据以原生侧为准。
    //
    // isFloating 是 Dart 侧的内存状态，退到桌面再回来时它是初值 false，
    // 但原生小窗其实还开着。只信自己的标记就会出现
    // 「小窗明明还在，这里却认为没事，于是既不关也不接管」。
    bool nativeFloating;
    try {
      nativeFloating = await NativePlayerBridge.instance.isFloating();
    } catch (e) {
      Log.logPrint(e);
      nativeFloating = isFloating.value;
    }

    if (!nativeFloating) {
      isFloating.value = false;
      // 标记已清但会话数据残留（异常退出等），顺手清理，避免脏状态影响下次判断
      if (hasSession) {
        clear();
      }
      return false;
    }
    Log.d(
      isSameRoom(site, roomId) ? "进入正在小窗播放的直播间，关闭悬浮窗" : "进入其他直播间，关闭当前悬浮窗",
    );
    // 等原生侧真正退出，否则随后 open 的画面会被送进还没销毁的小窗
    await NativePlayerBridge.instance.exitFloating().catchError((e) {
      Log.logPrint(e);
    });
    isFloating.value = false;
    restoredFromFloating = false;
    clear();
    return true;
  }

  /// 页面重新接管播放器时调用
  ///
  /// 与 [closeIfPlaying] 的区别：只清理「小窗」这一层的状态，
  /// **不动播放器**。播放器实例、解码器、网络流都保持存活，
  /// 页面直接接管画面，用户完全感知不到重新加载。
  Future<void> detachKeepAlive() async {
    _sessionRevision++;
    isFloating.value = false;
    restoredFromFloating = false;
    // 停止小窗期间的健康检查：回到页面后由页面的 checkHealth 接手，
    // 两边同时跑会重复触发重新取流。
    _stopHealthCheck();
    _stopRefreshTimer();
    // 小窗弹幕一起停：回到页面后由页面自己的 liveDanmaku 接管，
    // 两边都连着同一条弹幕流等于每条弹幕收两遍、白耗一份带宽。
    stopDanmaku().catchError((e) => Log.logPrint(e));
    // 注意：这里不能 clear()。
    // 保留 _site/_roomId，页面销毁再次进入小窗时还能判断是否同一房间。
    onRefreshUrl = null;
  }

  void clear() {
    _sessionRevision++;
    isFloating.value = false;
    _quality = null;
    _lineIndex = 0;
    _lineCount = 1;
    _lineUrl = '';
    _playUrls = [];
    _urlFetchedAt = null;
    _selfRefreshFailures = 0;
    _failedLines.clear();
    _stablePlaybackTimer?.cancel();
    _stopHealthCheck();
    _stopRefreshTimer();
    // clear() 是同步方法，停止弹幕里的 await 不阻塞调用方
    stopDanmaku().catchError((e) => Log.logPrint(e));
    _site = null;
    _roomId = null;
    onRefreshUrl = null;
  }

  /// 轻点小窗：回到直播页
  void _onTap() async {
    // 房间信息可能缺失（退到桌面再回来，Dart 侧是全新的），
    // 先尝试从原生侧补一次，否则下面会把点击直接丢掉，
    // 用户看到的就是「点小窗没反应」。
    if (_site == null || _roomId == null) {
      await syncFromNative();
    }

    final targetSite = _site;
    final targetRoomId = _roomId;
    if (targetSite == null || targetRoomId == null) {
      // 原生侧在发 floatingTap 之前已经 bringAppToFront 了，
      // 这里拿不到房间就到此为止，至少 App 已经回到前台。
      Log.d("点小窗时拿不到房间信息，无法回到播放页");
      return;
    }

    // 已经把 App 拉回前台且正好停在同一个直播间：
    // 只需要把画面输出从悬浮窗切回页内纹理，页面实例完全不动，
    // 这样播放器与解码器全程无感知，是最理想的「无缝续播」。
    if (Get.currentRoute == RoutePath.kLiveRoomDetail &&
        isSameRoom(targetSite, targetRoomId)) {
      isFloating.value = false;
      restoredFromFloating = false;
      _stopHealthCheck();
      _stopRefreshTimer();
      // 小窗弹幕随小窗一起停。注意这里页面实例还在，
      // 它自己的 liveDanmaku 一直是活的，不用也不会重连。
      stopDanmaku().catchError((e) => Log.logPrint(e));
      NativePlayerBridge.instance.exitFloating().catchError((e) {
        Log.logPrint(e);
      });
      return;
    }

    isFloating.value = false;
    restoredFromFloating = true;

    // 注意顺序：先打开直播页，由页面的 _restoreFromFloating 决定如何接管，
    // 再让页面自己调 exitFloating。
    //
    // 这里不能提前 exitFloating：一旦小窗先关掉，页面起来时
    // restoredFromFloating 虽然为 true，但原生侧 isFloating 已经是 false，
    // 接管判断会失败，退化成重新取流（用户看到的就是「又 loading 一次」）。
    _openRoomPage(targetSite, targetRoomId);
  }

  /// 是否正在打开直播页（防止连点小窗开出多个页面）
  bool _openingRoomPage = false;

  /// 打开直播页
  ///
  /// 这里有三个必须处理好的时序问题，任何一个没处理对都会表现为
  /// 「点小窗没反应」或「返回后还在直播页」：
  ///
  /// 1. **导航尚未就绪**
  ///    「一路返回退到桌面」会让引擎重建，Dart 侧从头跑一遍 main()。
  ///    FloatingSession.init() 在 runApp() 之前执行，而原生侧补发的
  ///    floatingTap 会在 Dart 订阅事件流时立刻到达——此时 GetMaterialApp
  ///    还没构建，Get.toNamed 没有 Navigator 可用，只会静默失败。
  ///    所以必须先等导航就绪。
  ///
  /// 2. **连点造成页面堆叠**
  ///    小窗还在时连点两次，会 push 出两个直播页。此时按返回只会退到
  ///    上一个直播页，用户看到的就是「返回了还是在直播页」。
  ///    用一个标志位挡住重复进入。
  ///
  /// 3. **已经停在直播页**
  ///    如果当前路由就是直播页，绝不能再 push 一层，
  ///    否则同样会出现「返回还在直播页」。
  Future<void> _openRoomPage(Site site, String roomId) async {
    if (_openingRoomPage) {
      Log.d("正在打开直播页，忽略重复点击");
      return;
    }
    if (Get.currentRoute == RoutePath.kLiveRoomDetail) {
      // 已在直播页：不再叠加新页面。
      // 画面接管由该页面自己的 _restoreFromFloating 完成。
      Log.d("当前已在直播页，不再重复打开");
      return;
    }

    _openingRoomPage = true;
    try {
      // 等 Navigator 就绪。最多等 8 秒，覆盖冷启动到首帧的耗时。
      final ready = await _waitForNavigator();
      if (!ready) {
        Log.d("导航长时间未就绪，放弃打开直播页");
        return;
      }
      // 等待期间用户可能已经放弃（关掉小窗），不必再开页面
      if (!restoredFromFloating) {
        return;
      }
      await Get.toNamed(
        RoutePath.kLiveRoomDetail,
        arguments: site,
        parameters: {"roomId": roomId},
      );
    } catch (e) {
      Log.logPrint(e);
      Log.d("打开直播页失败：$e");
    } finally {
      _openingRoomPage = false;
    }
  }

  /// 轮询等待 GetX 的 Navigator 可用
  ///
  /// 冷启动时 GetMaterialApp 尚未构建，Get.key.currentState 为 null，
  /// 这时候调 Get.toNamed 只会静默失败。
  Future<bool> _waitForNavigator() async {
    for (var i = 0; i < 40; i++) {
      if (Get.key.currentState != null) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// 点击关闭图标：结束播放，销毁视频实例与页面
  void _onClosed() {
    isFloating.value = false;
    restoredFromFloating = false;
    clear();
    // 用户明确要求：关闭小窗即销毁视频播放实例
    NativePlayerBridge.instance.exitFloating().catchError((e) {
      Log.logPrint(e);
    });
    NativePlayerBridge.instance.release().catchError((e) {
      Log.logPrint(e);
    });
    NativePlayerBridge.instance.releaseTexture().catchError((e) {
      Log.logPrint(e);
    });
    // 若此刻正停在直播页，一并退出该页
    if (Get.currentRoute == RoutePath.kLiveRoomDetail) {
      Get.back();
    }
  }

  void dispose() {
    _stablePlaybackTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
  }
}

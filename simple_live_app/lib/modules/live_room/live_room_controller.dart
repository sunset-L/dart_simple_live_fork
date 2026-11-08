import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/live_room_error.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/danmaku_shielder.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/floating_session.dart';
import 'package:simple_live_app/modules/live_room/auto_exit_dialog.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LiveRoomController extends PlayerController with WidgetsBindingObserver {
  final Site pSite;
  final String pRoomId;
  late LiveDanmaku liveDanmaku;
  LiveRoomController({
    required this.pSite,
    required this.pRoomId,
  }) {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    liveDanmaku = site.liveSite.getDanmaku();
    // 抖音应该默认是竖屏的
    if (site.id == "douyin") {
      isVertical.value = true;
    }
  }

  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  String get displayUserName {
    final name = detail.value?.userName ?? '';
    return name.isNotEmpty ? name : '${site.name} · $roomId';
  }

  var online = 0.obs;

  /// 本次进房或切房加载的热度，不跟随弹幕推送或播放地址续期更新。
  final roomPopularity = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;

  /// 直播间信息是否已经拿到（detail 是否已返回）
  ///
  /// 用来把「还没查到」和「查到了但没开播」区分开。
  /// 只用 [liveStatus] 一个布尔量时，它的初值 false 会被当成「未开播」，
  /// 于是进入页面的瞬间就先闪一下黑底 +「未开播」再变成画面，观感很差。
  var detailLoaded = false.obs;

  /// 列表页带过来的封面地址
  ///
  /// 已不再用于播放器底层垫图（改为黑屏 + loading，见 live_room_page），
  /// 但详情页刷新后会用它覆盖列表页可能过期的封面，留给其它 UI 使用。
  var coverUrl = "".obs;

  RxList<LiveSuperChatMessage> superChats = RxList<LiveSuperChatMessage>();

  /// 滚动控制
  final ScrollController scrollController = ScrollController();

  /// 聊天信息
  RxList<LiveMessage> messages = RxList<LiveMessage>();

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  final _currentQuality = (-1).obs;
  int get currentQuality => _currentQuality.value;
  set currentQuality(int value) => _currentQuality.value = value;
  LivePlayQuality? _requestedQuality;
  _PlaybackLineSelection? _lineSelection;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  Map<String, String>? playHeaders;

  /// 当前线路
  final _currentLineIndex = (-1).obs;
  int get currentLineIndex => _currentLineIndex.value;
  set currentLineIndex(int value) => _currentLineIndex.value = value;

  /// 只有原生播放器确认正在播放后才选中，连接中不冒充已成功切线。
  final playingLineIndex = (-1).obs;
  final lineConnecting = false.obs;
  var currentLineInfo = "".obs;

  /// 退出倒计时
  var countdown = 60.obs;

  Timer? autoExitTimer;

  /// 设置的自动关闭时间（分钟）
  var autoExitMinutes = 60.obs;

  ///是否延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  /// 是否禁用自动滚动聊天栏
  /// - 当用户向上滚动聊天栏时，不再自动滚动
  var disableAutoScroll = false.obs;

  /// 是否处于后台
  var isBackground = false;

  /// 直播间加载失败
  var loadError = false.obs;
  Object? error;

  /// 分类后的错误信息，供播放器内的状态提示展示
  ///
  /// 页面不再直接显示 `error.toString()`：那既解释不了原因，
  /// 也提示不了下一步动作（见 live_room_error.dart 的说明）。
  LiveRoomErrorInfo get errorInfo =>
      describeLiveRoomError(error, siteName: site.name);

  // 开播时长状态变量
  var liveDuration = "00:00:00".obs;
  Timer? _liveDurationTimer;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    if (FollowService.instance.followList.isEmpty) {
      FollowService.instance.loadData();
    }
    initAutoExit();
    showDanmakuState.value = AppSettingsController.instance.danmuEnable.value;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");

    // 从悬浮小窗点回来：原生播放器里那条流还在跑，直接接管画面，
    // 不重新取流、不重置播放器，避免黑一下再重新加载。
    _restoreFromFloating();

    scrollController.addListener(scrollListener);

    super.onInit();
  }

  /// 是否要在页面加载完成后直接接管原生播放器里已经在跑的那条流
  ///
  /// 两种情况都成立：
  /// 1. 点小窗返回（restoredFromFloating）；
  /// 2. 小窗正在播 A 主播，用户又点了 A 主播进播放页。
  ///    此时原生播放器里那条流是好的，没理由重新取流再 loading 一次。
  ///
  /// 一旦在 [loadData] 中消费掉就立即置 false，
  /// 避免后续 refreshRoom 等操作误走接管分支。
  bool _shouldAdoptStream = false;

  void _restoreFromFloating() async {
    // 先把状态与原生侧对齐。
    //
    // 「一路返回退到桌面」会销毁 Flutter 引擎，再次进入 App 时
    // FloatingSession 是全新的，hasSession 为 false、isFloating 为 false，
    // 而原生小窗其实还开着。不同步就会出现
    // 「小窗还在，页面却按普通进入流程重新取流」。
    await FloatingSession.instance.syncFromNative();

    // 小窗是否正在播「同一个房间」
    final sameRoom = FloatingSession.instance.hasSession &&
        FloatingSession.instance.isSameRoom(site, roomId);

    // 只要小窗正在播同一房间，就属于「可以无损接管」的场景，
    // 无论用户是点小窗回来还是主动点进这个主播的播放页。
    if (FloatingSession.instance.isFloating.value && sameRoom) {
      _shouldAdoptStream = true;
    } else if (sameRoom) {
      // 小窗标记已清但会话还在同一房间（例如小窗已被别处关闭），
      // 只要原生播放器还活着，同样直接接管，避免无谓的重载。
      _shouldAdoptStream = await nativePlayer.hasActiveStream();
    }

    FloatingSession.instance.restoredFromFloating = false;

    if (_shouldAdoptStream) {
      // 退出小窗：画面输出从悬浮窗 Surface 切回页内纹理，
      // 播放器实例、解码器、网络连接全部不动，因此没有黑屏与 loading。
      isFloating.value = false;
      isPlayerHandedOver = false;
      await FloatingSession.instance.detachKeepAlive();
      nativePlayer.exitFloating().catchError((e) {
        Log.logPrint(e);
      });
      loadData();
      return;
    }

    // 小窗播的是别人：必须关掉，否则原生侧输出优先级
    // 仍会把画面送进小窗，页面里的播放器拿不到输出。
    await FloatingSession.instance.closeIfPlaying(site: site, roomId: roomId);
    isFloating.value = false;
    isPlayerHandedOver = false;
    // 非小窗进入（普通进入 / 小窗播的是别人）：播放器里可能还留着
    // 上一个直播的最后一帧，必须先重置，否则新页面在 loading 期间
    // 会把这帧显示出来，看起来像进错了房间。
    await _resetPlayerForFreshEntry();
    loadData();
  }

  /// 进入非小窗播放页时重置播放器
  ///
  /// 纹理是全局单例复用的，上一路流的最后一帧会一直留在里面。
  /// 这里做两件事：
  /// 1. 停掉原生播放器里可能还在跑的上一条流（释放解码器与网络连接）；
  /// 2. 清空纹理内容并把首帧标记复位，让页面从「黑屏 + loading」开始。
  ///
  /// 只重置、不释放纹理：纹理 id 保持不变，Dart 侧 Texture 控件不用重建，
  /// 也就不会有额外的闪烁。
  Future<void> _resetPlayerForFreshEntry() async {
    try {
      await nativePlayer.stop();
    } catch (e) {
      Log.logPrint(e);
    }
    // 首帧标记必须在清纹理之前复位，反过来会被 clearTexture 里的
    // 逻辑重新盖成 true（它内部也会复位，但顺序明确更稳妥）。
    hasRenderedFirstFrame.value = false;
    try {
      await nativePlayer.clearTexture();
    } catch (e) {
      Log.logPrint(e);
    }
  }

  void scrollListener() {
    if (scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      disableAutoScroll.value = true;
    }
  }

  /// 初始化自动关闭倒计时
  void initAutoExit() {
    if (AppSettingsController.instance.autoExitEnable.value) {
      autoExitEnable.value = true;
      autoExitMinutes.value =
          AppSettingsController.instance.autoExitDuration.value;
      setAutoExit();
    } else {
      autoExitMinutes.value =
          AppSettingsController.instance.roomAutoExitDuration.value;
    }
  }

  void setAutoExit() {
    if (!autoExitEnable.value) {
      autoExitTimer?.cancel();
      return;
    }
    autoExitTimer?.cancel();
    countdown.value = autoExitMinutes.value * 60;
    autoExitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      countdown.value -= 1;
      if (countdown.value <= 0) {
        timer.cancel();
        showAutoExitPrompt();
      }
    });
  }

  bool _autoExitPromptShowing = false;
  bool _closingLiveRoom = false;

  Future<void> showAutoExitPrompt() async {
    if (_disposed || _closingLiveRoom || _autoExitPromptShowing) {
      return;
    }
    _autoExitPromptShowing = true;
    AutoExitAction? action;
    try {
      action = await showDialog<AutoExitAction>(
        context: Get.context!,
        barrierDismissible: false,
        builder: (_) => const AutoExitDialog(),
      );
    } finally {
      _autoExitPromptShowing = false;
    }
    if (_disposed || _closingLiveRoom) {
      return;
    }
    switch (action) {
      case AutoExitAction.delay:
        delayAutoExit.value = true;
        showAutoExitSheet();
        setAutoExit();
        break;
      case AutoExitAction.closeLive:
        delayAutoExit.value = false;
        await closeLiveRoom();
        break;
      case AutoExitAction.exitApplication:
        await WakelockPlus.disable();
        exit(0);
      case null:
        break;
    }
  }

  Future<void> closeLiveRoom() async {
    if (_disposed || _closingLiveRoom) {
      return;
    }
    _closingLiveRoom = true;
    _playbackGeneration++;
    _stablePlaybackTimer?.cancel();
    autoExitTimer?.cancel();
    _retryTimer?.cancel();
    _cancelUrlRefresh();
    stopHealthCheck();
    liveDanmaku.stop();
    FloatingSession.instance.isFloating.value = false;
    FloatingSession.instance.clear();
    isFloating.value = false;
    isPlayerHandedOver = false;
    if (fullScreenState.value) {
      exitFull();
    }
    try {
      await nativePlayer.exitFloating();
      await nativePlayer.release();
    } catch (e) {
      Log.logPrint(e);
    }
    // 先收起播放器面板，再退出直播路由；不能误把底部面板当成直播页。
    await SmartDialog.dismiss(status: SmartStatus.allCustom);
    if (_disposed) return;
    Get.until((route) =>
        route.settings.name == RoutePath.kLiveRoomDetail || route.isFirst);
    if (Get.currentRoute == RoutePath.kLiveRoomDetail) Get.back();
  }
  // 弹窗逻辑

  void refreshRoom() {
    if (_disposed || _closingLiveRoom) return;
    if (currentQuality >= 0 && currentQuality < qualites.length) {
      _requestedQuality = qualites[currentQuality];
    }
    _rememberCurrentLine();
    _playbackGeneration++;
    //messages.clear();
    superChats.clear();
    liveDanmaku.stop();

    _resetPlaybackRecovery();
    _cancelUrlRefresh();
    // 手动刷新时重置自愈相关的状态
    _retryTimer?.cancel();
    _retryTimer = null;
    _refreshFailCount = 0;
    _refreshingPlayUrl = false;
    mediaErrorRetryCount = 0;
    stopHealthCheck();

    // 复位「已加载」标记：未开播界面会切回 loading 转圈，
    // 让用户看到确实在重新请求，而不是点了没反应。
    // （拿到详情后 loadData 会重新置 true）
    detailLoaded.value = false;

    loadData();
  }

  /// 聊天栏始终滚动到底部
  void chatScrollToBottom() {
    if (scrollController.hasClients) {
      // 如果手动上拉过，就不自动滚动到底部
      if (disableAutoScroll.value) {
        return;
      }
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
    liveDanmaku.onClose = onWSClose;
    liveDanmaku.onReady = onWSReady;
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) {
    if (msg.type == LiveMessageType.chat) {
      if (messages.length > 200 && !disableAutoScroll.value) {
        messages.removeAt(0);
      }

      // 关键词 + 福袋规则统一走 DanmakuShielder，
      // 与小窗弹幕保持同一套判断（含新加的福袋屏蔽）
      if (DanmakuShielder.shouldBlock(msg)) {
        return;
      }

      messages.add(msg);

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => chatScrollToBottom(),
      );
      if (!liveStatus.value || isBackground) {
        return;
      }

      addDanmaku([
        DanmakuContentItem(
          msg.message,
          color: Color.fromARGB(
            255,
            msg.color.r,
            msg.color.g,
            msg.color.b,
          ),
        ),
      ]);
    } else if (msg.type == LiveMessageType.online) {
      online.value = msg.data;
    } else if (msg.type == LiveMessageType.superChat) {
      superChats.add(msg.data);
    }
  }

  /// 添加一条系统消息
  void addSysMsg(String msg) {
    messages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    );
  }

  /// 接收到WebSocket关闭信息
  void onWSClose(String msg) {
    addSysMsg(msg);
  }

  /// WebSocket准备就绪
  void onWSReady() {
    addSysMsg("弹幕服务器连接正常");
  }

  /// 加载直播间信息
  void loadData() async {
    final generation = _playbackGeneration;
    if (!_isPlaybackCurrent(generation)) return;
    try {
      // 不在这里显示全屏 loading：
      // 页面自身已有「未开播」遮罩与骨架，再加一层弹窗会让进入页面时明显卡顿。
      loadError.value = false;
      error = null;
      update();
      addSysMsg("正在读取直播间信息");
      final loadedDetail = await site.liveSite.getRoomDetail(roomId: roomId);
      if (!_isPlaybackCurrent(generation)) return;
      detail.value = loadedDetail;

      if (site.id == Constant.kDouyin) {
        // 1.6.0之前收藏的WebRid
        // 1.6.0收藏的RoomID
        // 1.6.0之后改回WebRid
        if (detail.value!.roomId != roomId) {
          var oldId = roomId;
          rxRoomId.value = detail.value!.roomId;
          if (followed.value) {
            // 更新关注列表
            DBService.instance.deleteFollow("${site.id}_$oldId");
            DBService.instance.addFollow(
              FollowUser(
                id: "${site.id}_$roomId",
                roomId: roomId,
                siteId: site.id,
                userName: detail.value!.userName,
                face: detail.value!.userAvatar,
                addTime: DateTime.now(),
              ),
            );
          } else {
            followed.value =
                DBService.instance.getFollowExist("${site.id}_$roomId");
          }
        }
      }

      getSuperChatMessage();

      addHistory();
      // 确认房间关注状态
      followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
      online.value = detail.value!.online;
      roomPopularity.value = detail.value!.online;
      // 详情里带的封面比列表页的更新，拿到后覆盖
      if (detail.value!.cover.isNotEmpty) {
        coverUrl.value = detail.value!.cover;
      }
      liveStatus.value = detail.value!.status || detail.value!.isRecord;
      // 标记「信息已到手」，页面据此区分「加载中」与「确实未开播」
      detailLoaded.value = true;
      if (liveStatus.value) {
        if (_shouldAdoptStream) {
          // 原生播放器里那条流还在跑：跳过取流，直接接管画面
          _shouldAdoptStream = false;
          await _adoptExistingStream();
        } else {
          getPlayQualites();
        }
      }
      if (!_isPlaybackCurrent(generation)) return;
      if (detail.value!.isRecord) {
        addSysMsg("当前主播未开播，正在轮播录像");
      }
      addSysMsg("开始连接弹幕服务器");
      initDanmau();
      liveDanmaku.start(detail.value?.danmakuData);
      startLiveDurationTimer(); // 启动开播时长定时器
    } catch (e) {
      if (!_isPlaybackCurrent(generation)) return;
      Log.logPrint(e);
      //SmartDialog.showToast(e.toString());
      // 这里不能写成 e as Error：网络异常/解析异常多为 Exception 或 FormatException，
      // 强转失败会抛出新的 TypeError，掩盖真实错误并让页面白屏。
      error = e;
      loadError.value = true;
    }
  }

  /// 接管已有播放或回到前台时恢复保亮，不依赖再次收到 playing 事件。
  Future<void> _restorePlaybackWakelock() async {
    if (_disposed || isBackground || isPlayerHandedOver || isFloating.value) {
      return;
    }
    try {
      final playing = await nativePlayer.isPlaying();
      if (playing &&
          !_disposed &&
          !isBackground &&
          !isPlayerHandedOver &&
          !isFloating.value) {
        await WakelockPlus.enable();
      }
    } catch (e) {
      Log.logPrint(e);
    }
  }

  /// 接管原生播放器里已经在跑的那条流
  ///
  /// 从小窗回到直播页、或小窗正在播同一主播时使用：
  /// 画面输出会自动从悬浮窗 Surface 切回页内纹理，
  /// 播放器实例、解码器、网络连接全都不动，因此不会出现重新加载的空白期。
  ///
  /// 关键补充：跳过取流意味着 `qualites` / `currentQuality` / `playUrls`
  /// 这些**只在取流流程里才会被填充**的字段仍是初值（空列表、-1），
  /// 结果是回到页面后「清晰度」「线路」两处都显示不出来、点开也是空的。
  /// 所以接管完画面后必须把这些元数据补上（见 [_restoreStreamMeta]）。
  Future<void> _adoptExistingStream() async {
    final generation = _playbackGeneration;
    if (!_isPlaybackCurrent(generation)) return;
    await initializePlayer();
    if (!_isPlaybackCurrent(generation)) return;
    await _restorePlaybackWakelock();
    if (!_isPlaybackCurrent(generation)) return;
    // 纹理里上一帧还在，直接标记为「已有画面」，
    // 否则页面会盖一层 loading 遮罩，用户看到的就是「回到页面还在 loading」。
    hasRenderedFirstFrame.value = true;
    resetHealthCheck();
    startHealthCheck();
    // 补齐清晰度/线路等元数据（不重新取流）
    await _restoreStreamMeta();
    if (!_isPlaybackCurrent(generation)) return;
    // 以原生实际地址匹配新线路列表；元数据暂不可用时才沿用小窗记录。
    // 不插入空地址占位，不重开正在播放的流。
    final session = FloatingSession.instance;
    final actualIndex = playUrls.indexWhere(
        (url) => _lineIdentity(url) == _lineIdentity(currentPlayUrl.value));
    currentLineIndex = actualIndex >= 0
        ? actualIndex
        : (session.quality != null ? session.lineIndex : -1);
    adaptedLineCount = session.lineCount;
    _urlFetchedAt = session.urlFetchedAt ?? DateTime.now();
    currentLineInfo.value =
        currentLineIndex >= 0 ? "线路${currentLineIndex + 1}" : "当前线路待确认";
    await _confirmPlayingLine();
    if (!_isPlaybackCurrent(generation)) return;
    _scheduleUrlRefresh();
  }

  /// 接管已有流时的线路条目数
  ///
  /// 接管不会重新取流，`playUrls` 为空，但界面上仍应显示「线路1/线路2」，
  /// 否则用户会觉得线路信息丢了。取两者较大值：一旦真正取过流就以后者为准。
  int get effectiveLineCount {
    if (playUrls.isNotEmpty) {
      return playUrls.length;
    }
    return adaptedLineCount < 1 ? 1 : adaptedLineCount;
  }

  /// 接管时记录下来的线路数（playUrls 为空时用于界面显示）
  int adaptedLineCount = 1;

  /// 补回「清晰度 / 线路」元数据，但不重新取流
  ///
  /// 这些数据平时只在 [getPlayQualites] → [getPlayUrl] 这条链路里被写入。
  /// 接管已有流时整条链路被跳过，于是：
  /// - `qualites` 是空列表 → 清晰度面板打不开 / 显示空；
  /// - `currentQuality` 是 -1 → 无法在地址过期后按当前画质续期；
  /// - `playUrls` 是空、`currentLineIndex` 是 -1 → 线路信息显示不出来。
  ///
  /// 只获取清晰度与线路元数据，不调用播放器换源；
  /// 根据原生实际地址恢复原选择，因此不会打断正在播放的画面。
  Future<void> _restoreStreamMeta() async {
    final generation = _playbackGeneration;
    if (!_isPlaybackCurrent(generation) || detail.value == null) {
      return;
    }
    try {
      final actualSource = await nativePlayer.getCurrentUrl();
      if (!_isPlaybackCurrent(generation)) return;
      if (actualSource != null) currentPlayUrl.value = actualSource;
      final playQualites =
          await site.liveSite.getPlayQualites(detail: detail.value!);
      if (!_isPlaybackCurrent(generation) || playQualites.isEmpty) {
        return;
      }
      qualites.value = playQualites;

      // 画质：优先沿用小窗期间记下的那一档
      final remembered = FloatingSession.instance.quality;
      final followIndex = _defaultQualityIndex(
        playQualites,
        await getQualityLevel(),
      );
      if (!_isPlaybackCurrent(generation)) return;
      bool adoptedRemembered = false;
      if (remembered != null) {
        final idx = playQualites.indexWhere(
          (e) => e.quality == remembered.quality,
        );
        if (idx >= 0) {
          currentQuality = idx;
          adoptedRemembered = true;
        } else {
          currentQuality = -1;
          currentQualityInfo.value = "${remembered.quality}（不可用）";
          throw const _PlaybackSelectionUnavailable("小窗原画质暂不可用，请重新选择，未切换默认画质");
        }
      } else {
        final actual = await nativePlayer.getCurrentUrl();
        if (!_isPlaybackCurrent(generation)) return;
        currentQuality = playQualites.indexWhere((item) =>
            item.data is List &&
            (item.data as List).any((url) =>
                _lineIdentity(url.toString()) == _lineIdentity(actual ?? '')));
        if (currentQuality < 0) {
          currentQualityInfo.value = "当前画质待确认";
          throw const _PlaybackSelectionUnavailable("无法确认小窗当前画质，请手动选择，未切换默认画质");
        }
      }
      if (currentQuality >= 0 && currentQuality < playQualites.length) {
        currentQualityInfo.value = playQualites[currentQuality].quality;
        final urls = await site.liveSite.getPlayUrls(
          detail: detail.value!,
          quality: playQualites[currentQuality],
        );
        final actualUrl = await nativePlayer.getCurrentUrl();
        if (!_isPlaybackCurrent(generation)) return;
        playUrls.value = List<String>.from(urls.urls);
        playHeaders = urls.headers;
        if (actualUrl != null && actualUrl.isNotEmpty) {
          currentPlayUrl.value = actualUrl;
          if (!playUrls
              .any((url) => _lineIdentity(url) == _lineIdentity(actualUrl))) {
            playUrls.add(actualUrl);
          }
        }
      }
      // 沿用的档位低于「按当前设置应取的档位」时提示一次。
      // 否则用户在设置里改成「最高」后，只是从小窗切回来，
      // 画质仍是旧值，表现就是「设置改了但没生效」。
      if (adoptedRemembered && currentQuality > followIndex) {
        _notifyQualityFollowsSetting(playQualites, followIndex);
      }
    } catch (e) {
      // 拿不到清晰度不影响继续播放，只影响面板显示
      Log.logPrint(e);
      Log.d("恢复清晰度列表失败：$e");
    }
  }

  /// 小窗接管后沿用了较低画质时的轻提示
  ///
  /// 只有一次淡入的 toast，不打断播放、不改用户的选择：
  /// 用户可能是有意在低画质下开的小窗，直接强行切档反而更糟。
  /// 所以只告知「可以切到哪一档」，把决定权留给用户。
  void _notifyQualityFollowsSetting(
    List<LivePlayQuality> list,
    int followIndex,
  ) {
    if (_qualityTipShown) {
      return;
    }
    _qualityTipShown = true;
    final current = currentQuality >= 0 && currentQuality < list.length
        ? list[currentQuality].quality
        : "";
    final target = followIndex >= 0 && followIndex < list.length
        ? list[followIndex].quality
        : "";
    if (target.isEmpty || target == current) {
      return;
    }
    SmartDialog.showToast(
      current.isEmpty
          ? "当前画质未跟随设置，可在清晰度中切换到$target"
          : "当前为$current，可在清晰度中切换到$target",
    );
  }

  /// 小窗接管画质提示的防刷屏标记
  bool _qualityTipShown = false;

  /// 按用户设置挑选默认清晰度下标
  ///
  /// [level] 由 [getQualityLevel] 给出：它会按当前网络类型（Wi-Fi / 移动网络）
  /// 在 `qualityLevel` 与 `qualityLevelCellular` 之间切换。
  /// 这里不能直接读 `qualityLevel`，否则小窗回来后的默认画质
  /// 会和正常进入时选的不一致（移动网络下尤其明显）。
  int _defaultQualityIndex(List<LivePlayQuality> list, int level) {
    if (list.isEmpty) {
      return -1;
    }
    if (level == 2) {
      // 最高
      return 0;
    }
    if (level == 0) {
      // 最低
      return list.length - 1;
    }
    // 中间值
    return (list.length / 2).floor().clamp(0, list.length - 1);
  }

  /// 首次进入才使用默认画质；刷新保留用户当前选择。
  void getPlayQualites() async {
    final generation = _playbackGeneration;
    final sourceRevision = _sourceRevision;
    bool isCurrent() =>
        _isPlaybackCurrent(generation) && sourceRevision == _sourceRevision;
    if (!isCurrent() || detail.value == null) return;
    if (currentQuality >= 0 && currentQuality < qualites.length) {
      _requestedQuality = qualites[currentQuality];
    }
    _rememberCurrentLine();
    final requested = _requestedQuality;
    try {
      final list = await site.liveSite.getPlayQualites(detail: detail.value!);
      if (!isCurrent()) return;
      if (list.isEmpty) throw const _PlaybackSelectionUnavailable("当前直播没有可用画质");
      qualites.value = list;
      var index = -1;
      if (requested != null) {
        index = list.indexWhere((item) =>
            item.quality == requested.quality && item.sort == requested.sort);
        if (index < 0) {
          index = list.indexWhere((item) => item.quality == requested.quality);
        }
        if (index < 0) {
          currentQuality = -1;
          currentQualityInfo.value = "${requested.quality}（不可用）";
          playUrls.clear();
          throw _PlaybackSelectionUnavailable(
              "所选${requested.quality}暂不可用，请稍后刷新或手动选择画质");
        }
      } else {
        index = _defaultQualityIndex(list, await getQualityLevel());
        if (!isCurrent()) return;
      }
      qualites.value = list;
      currentQuality = index;
      _requestedQuality = list[index];
      getPlayUrl();
    } catch (e) {
      if (!isCurrent()) return;
      Log.logPrint(e);
      errorMsg.value =
          e is _PlaybackSelectionUnavailable ? e.message : "读取画质失败，请稍后刷新";
      _stopPlaybackRecovery();
    }
  }

  void _rememberCurrentLine() {
    if (currentLineIndex >= 0 && currentLineIndex < playUrls.length) {
      _lineSelection = _PlaybackLineSelection.fromUrl(
          currentLineIndex, playUrls[currentLineIndex]);
    }
  }

  int _resolveSelectedLine(
      List<String> urls, _PlaybackLineSelection? selection) {
    if (urls.isEmpty) return -1;
    if (selection == null) return 0;
    // 列表重排或画质改变时按 CDN + 协议找回，不能让旧下标指向另一条线路。
    if (selection.index >= 0 &&
        selection.index < urls.length &&
        selection.matches(urls[selection.index])) {
      return selection.index;
    }
    return urls.indexWhere(selection.matches);
  }

  void changePlayQuality(int index) {
    if (index < 0 || index >= qualites.length || !_canResumePlayback) return;
    if (index == currentQuality &&
        playingLineIndex.value >= 0 &&
        !_recoveryStopped) {
      return;
    }
    _rememberCurrentLine();
    currentQuality = index;
    _requestedQuality = qualites[index];
    getPlayUrl();
  }

  Future<int> getQualityLevel() async {
    var qualityLevel = AppSettingsController.instance.qualityLevel.value;
    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.first == ConnectivityResult.mobile) {
        qualityLevel =
            AppSettingsController.instance.qualityLevelCellular.value;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return qualityLevel;
  }

  void getPlayUrl() async {
    final generation = _playbackGeneration;
    if (!_isPlaybackCurrent(generation) ||
        detail.value == null ||
        currentQuality < 0 ||
        currentQuality >= qualites.length) {
      return;
    }
    _rememberCurrentLine();
    final selectedLine = _lineSelection;
    final selectedQuality = qualites[currentQuality];
    _requestedQuality = selectedQuality;
    _resetPlaybackRecovery();
    final sourceRevision = _sourceRevision;
    _beginLineConnection();
    playUrls.clear();
    currentQualityInfo.value = qualites[currentQuality].quality;
    try {
      final playUrl = await site.liveSite
          .getPlayUrls(detail: detail.value!, quality: selectedQuality);
      if (!_isPlaybackCurrent(generation) ||
          sourceRevision != _sourceRevision) {
        return;
      }
      if (playUrl.urls.isEmpty) throw StateError("直播地址为空");
      playUrls.value = playUrl.urls;
      playHeaders = playUrl.headers;
      final selectedIndex = _resolveSelectedLine(playUrl.urls, selectedLine);
      if (selectedIndex < 0) {
        currentLineIndex = -1;
        throw const _PlaybackSelectionUnavailable(
            "所选线路暂不支持当前画质，请手动选择线路，画质未自动更改");
      }
      currentLineIndex = selectedIndex;
      //重置错误次数
      mediaErrorRetryCount = 0;
      _refreshFailCount = 0;
      // 从拿到地址的这一刻开始计时，续期定时器必须以此为基准，
      // 否则会按「上次刷新时间」算，首次进入时可能是 null。
      _markUrlRefreshed();
      _notifyIfAuthRejected();
      await initPlaylist();
    } catch (e) {
      if (!_isPlaybackCurrent(generation) ||
          sourceRevision != _sourceRevision) {
        return;
      }
      Log.logPrint(e);
      Log.d("获取播放地址失败：$e");
      // 取不到地址就直接进入退避重试（内部会重新拉房间详情再取一次）。
      //
      // 这里**不再降清晰度兜底**。
      // 原先的逻辑是：当前档取不到就自动降一档再播，
      // 理由是「哔哩哔哩登录后 accept_qn 带了原画但账号没权限」。
      // 但这个兜底有明确的副作用：用户明明选了某个清晰度，
      // 播放器却擅自换成另一档，画质在用户不知情的情况下变差，
      // 而且降档后再也回不去（currentQuality 已被改写）。
      // 现在的策略是：画质只由用户选择决定，播不了就重试/续签，
      // 失败多次再明确报错，让用户自己决定要不要手动换档。
      if (e is _PlaybackSelectionUnavailable) {
        errorMsg.value = e.message;
        _stopPlaybackRecovery();
      } else {
        _onRefreshFailed();
      }
    }
  }

  /// 重新获取播放地址并恢复到当前线路继续播放
  /// - 直播平台的取流地址普遍带时效签名（斗鱼的 wsSecret/wsTime，虎牙的 txSecret 等），
  ///   长时间播放后地址会失效。此时单纯 player.jump() 回到旧地址没有任何意义，
  ///   必须重新请求后端换取新地址。
  /// - [lineIndex] 为恢复后要使用的线路下标，默认沿用当前线路。
  Future<void> refreshPlayUrlAndResume({
    int? lineIndex,
    bool forceReload = false,
  }) async {
    final generation = _playbackGeneration;
    final sourceRevision = _sourceRevision;
    bool isCurrent() =>
        _isPlaybackCurrent(generation) &&
        sourceRevision == _sourceRevision &&
        !_recoveryStopped;
    if (!isCurrent() ||
        _refreshingPlayUrl ||
        detail.value == null ||
        currentQuality < 0 ||
        currentQuality >= qualites.length) {
      return;
    }

    final requestId = ++_refreshRequestId;
    final selectedQuality = qualites[currentQuality];
    final previousUrl =
        currentLineIndex >= 0 && currentLineIndex < playUrls.length
            ? playUrls[currentLineIndex]
            : currentPlayUrl.value;
    _refreshingPlayUrl = true;
    try {
      LivePlayUrl playUrl;
      // 抖音地址存放在详情内，必须重新请求详情，不能重用旧 quality.data。
      if (site.id == Constant.kDouyin) {
        final newDetail = await site.liveSite.getRoomDetail(roomId: roomId);
        if (!isCurrent()) return;
        if (!newDetail.status) {
          liveStatus.value = false;
          errorMsg.value = "主播已下播";
          _stopPlaybackRecovery();
          return;
        }
        detail.value = newDetail;
        playUrl = await site.liveSite.getPlayUrls(
          detail: newDetail,
          quality: selectedQuality,
        );
      } else {
        try {
          playUrl = await site.liveSite.getPlayUrls(
            detail: detail.value!,
            quality: selectedQuality,
          );
          if (playUrl.urls.isEmpty) throw StateError("直播地址为空");
        } catch (_) {
          if (!isCurrent()) return;
          final newDetail = await site.liveSite.getRoomDetail(roomId: roomId);
          if (!isCurrent()) return;
          detail.value = newDetail;
          playUrl = await site.liveSite.getPlayUrls(
            detail: newDetail,
            quality: selectedQuality,
          );
        }
      }
      if (!isCurrent()) return;
      if (playUrl.urls.isEmpty) throw StateError("直播地址为空");
      final selection = _lineSelection ??
          (previousUrl.isNotEmpty
              ? _PlaybackLineSelection.fromUrl(
                  currentLineIndex < 0 ? 0 : currentLineIndex, previousUrl)
              : null);
      final targetLine =
          lineIndex ?? _resolveSelectedLine(playUrl.urls, selection);
      if (targetLine < 0 || targetLine >= playUrl.urls.length) {
        // 保留新候选供用户手动选择，但不擅自更换线路。
        playUrls.value = playUrl.urls;
        playHeaders = playUrl.headers;
        currentLineIndex = -1;
        throw const _PlaybackSelectionUnavailable("所选线路暂不可用，请手动选择其他线路，画质未更改");
      }
      playUrls.value = playUrl.urls;
      playHeaders = playUrl.headers;
      currentLineIndex = targetLine.clamp(0, playUrls.length - 1);
      _notifyIfAuthRejected();
      _markUrlRefreshed();
      _refreshFailCount = 0;
      _retryTimer?.cancel();
      errorMsg.value = "";

      final url = _effectivePlayUrl(playUrls[currentLineIndex]);
      // 定时续期获取到了同一个地址且仍在播放：只更新期限，不重新 prepare。
      // 故障恢复则允许强制重载同地址，不能被这个保护挡住。
      if (!forceReload &&
          url == currentPlayUrl.value &&
          await nativePlayer.isPlaying()) {
        if (!isCurrent()) return;
        _rememberCurrentLine();
        await _confirmPlayingLine();
        if (!isCurrent()) return;
        _scheduleUrlRefresh();
        return;
      }
      if (!isCurrent()) return;
      Log.d("直播换源：${forceReload ? '故障恢复' : '地址续期'}，线路${currentLineIndex + 1}");
      await _switchToCurrentLine();
      if (_isPlaybackCurrent(generation) && requestId == _refreshRequestId) {
        _scheduleUrlRefresh();
      }
    } catch (e) {
      Log.logPrint(e);
      if (isCurrent()) {
        if (e is _PlaybackSelectionUnavailable) {
          errorMsg.value = e.message;
          _stopPlaybackRecovery();
        } else {
          _onRefreshFailed();
        }
      }
    } finally {
      if (requestId == _refreshRequestId) _refreshingPlayUrl = false;
    }
  }

  /// 保留已有画面换源；仍会真实缓冲，不能靠隐藏 loading 冒充恢复成功。
  Future<void> _switchToCurrentLine() =>
      _playCurrentLine(forceReload: true, preserveFrame: true);

  String _effectivePlayUrl(String url) =>
      AppSettingsController.instance.playerForceHttps.value
          ? url.replaceFirst("http://", "https://")
          : url;

  String _lineIdentity(String url) {
    final uri = Uri.tryParse(url);
    return uri == null ? url : '${uri.host}${uri.path}';
  }

  void _beginLineConnection() {
    _stablePlaybackTimer?.cancel();
    playingLineIndex.value = -1;
    lineConnecting.value = true;
    currentLineInfo.value =
        currentLineIndex >= 0 ? "线路${currentLineIndex + 1}（连接中）" : "线路取流中";
  }

  @override
  void onPlaybackPlayingChanged(bool playing) {
    if (!playing) {
      _stablePlaybackTimer?.cancel();
      return;
    }
    _confirmPlayingLine();
  }

  Future<void> _confirmPlayingLine() async {
    final generation = _playbackGeneration;
    final revision = _sourceRevision;
    final index = currentLineIndex;
    final expectedUrl = index >= 0 && index < playUrls.length
        ? _effectivePlayUrl(playUrls[index])
        : currentPlayUrl.value;
    if (index < 0 ||
        expectedUrl.isEmpty ||
        expectedUrl != currentPlayUrl.value ||
        _recoveryStopped) {
      return;
    }
    final actualUrl = await nativePlayer.getCurrentUrl();
    final playing = await nativePlayer.isPlaying();
    if (!_isPlaybackCurrent(generation) ||
        revision != _sourceRevision ||
        actualUrl != expectedUrl ||
        !playing) {
      return;
    }
    playingLineIndex.value = index;
    lineConnecting.value = false;
    currentLineInfo.value = "线路${index + 1}";
    _syncFloatingLine();
    _stablePlaybackTimer?.cancel();
    // 短暂 READY 后马上断流不算恢复，避免重试次数被无限清零。
    _stablePlaybackTimer = Timer(const Duration(seconds: 30), () {
      if (!_isPlaybackCurrent(generation) ||
          revision != _sourceRevision ||
          buffering.value) {
        return;
      }
      mediaErrorRetryCount = 0;
      _recoveryRounds = 0;
      _failedLines.clear();
      _refreshFailCount = 0;
    });
  }

  void _syncFloatingLine() {
    final session = FloatingSession.instance;
    if (session.isSameRoom(site, roomId)) {
      session.updatePlaybackMetadata(
        quality: currentQuality >= 0 && currentQuality < qualites.length
            ? qualites[currentQuality]
            : null,
        lineIndex: currentLineIndex,
        lineCount: playUrls.length,
        playUrl: currentPlayUrl.value,
        playUrls: playUrls.toList(),
        urlFetchedAt: _urlFetchedAt,
      );
    }
  }

  /// 连续刷新失败次数
  int _refreshFailCount = 0;

  /// 斗鱼授权失效提示的防刷屏标记
  bool _authTipShown = false;

  /// 取流时如果斗鱼 `dy_auth` 未被服务端认可，提示一次并标记失效
  ///
  /// 三个触发来源：
  /// - **请求原画却拿到带码率后缀的流**（`_4000` / `_2000` / `_900`）：
  ///   这是最常见也最隐蔽的一种——匿名取流是「成功」的，只是画质被压到
  ///   蓝光4M 且地址只有 300 秒有效期。过去这种情况完全不提示，
  ///   用户以为配好了，实际一直在看降级流。
  /// - **返回地址的 expire > 0**：匿名取原画必然 expire=300。
  /// - 带 cookie 取流失败后回退到普通方式并成功。
  ///
  /// 三种情况用户都**能看**，只是看的是匿名态的画质，
  /// 所以这里只给一个 toast 提示，不打断播放、不弹对话框。
  ///
  /// 只提示一次：地址每次续签都会重新取流，不设标记会变成
  /// 每 2 分钟弹一次「授权失效」，非常烦人。
  void _notifyIfAuthRejected() {
    final site = this.site.liveSite;
    if (site is! DouyuSite) {
      return;
    }
    if (!site.authNotEffective) {
      return;
    }
    DouyuAccountService.instance.markInvalid();
    if (_authTipShown) {
      return;
    }
    _authTipShown = true;
    // 被静默降档时告诉用户「现在是哪一档」，比笼统说「画质受限」有用得多
    final label = site.lastQualityDowngraded ? site.lastDowngradeLabel : "";
    if (label.isNotEmpty) {
      SmartDialog.showToast(
        "斗鱼未登录或票据已失效，当前为$label（登录后可看原画）",
      );
    } else if (site.lastQualityDowngraded) {
      SmartDialog.showToast(
        "斗鱼未登录或票据已失效，画质被降档且地址会定期失效（登录后可看原画）",
      );
    } else {
      SmartDialog.showToast("斗鱼授权已失效，已用普通方式取流（画质与地址有效期会受限）");
    }
  }

  void _onRefreshFailed() {
    if (!_canResumePlayback || _recoveryStopped) return;
    _refreshFailCount++;
    Log.d("重新获取播放地址失败（第$_refreshFailCount次）");

    // 只在前几次给用户反馈，避免长时间挂着页面时反复弹提示
    if (_refreshFailCount <= 3) {
      SmartDialog.showToast("直播地址刷新失败，正在重试");
    }

    // 退避重试：5s、10s、20s……最长 60s，最多再试 6 次
    if (_refreshFailCount > 6) {
      errorMsg.value = "直播地址刷新失败，请稍后刷新或手动选择画质";
      _stopPlaybackRecovery();
      return;
    }
    final delay =
        Duration(seconds: 5 * (1 << (_refreshFailCount - 1)).clamp(1, 12));
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_disposed) {
        return;
      }
      refreshPlayUrlAndResume(forceReload: true);
    });
  }

  Timer? _retryTimer;
  bool _disposed = false;

  // 切房、刷新或主动关闭后，旧请求不能再写回状态或重新起播。
  int _playbackGeneration = 0;
  Future<void> Function()? _floatingRefreshHandler;
  bool _isPlaybackCurrent(int generation) =>
      generation == _playbackGeneration && _canResumePlayback;
  bool get _canResumePlayback =>
      !_closingLiveRoom &&
      (!_disposed ||
          (isPlayerHandedOver &&
              _floatingRefreshHandler != null &&
              FloatingSession.instance.onRefreshUrl ==
                  _floatingRefreshHandler &&
              FloatingSession.instance.isFloating.value &&
              FloatingSession.instance.isSameRoom(site, roomId)));

  /// 是否正在刷新播放地址
  bool _refreshingPlayUrl = false;

  void changePlayLine(int index) {
    if (index < 0 ||
        index >= playUrls.length ||
        !_canResumePlayback ||
        currentQuality < 0 ||
        currentQuality >= qualites.length) {
      return;
    }
    if (index == playingLineIndex.value &&
        !buffering.value &&
        !_recoveryStopped) {
      return;
    }
    _resetPlaybackRecovery();
    currentLineIndex = index;
    startHealthCheck();
    _playCurrentLine(forceReload: true, preserveFrame: true);
  }

  Future<void> initPlaylist() async {
    final generation = _playbackGeneration;
    final sourceRevision = _sourceRevision;
    if (!_isPlaybackCurrent(generation)) return;
    errorMsg.value = "";

    await initializePlayer();
    if (!_isPlaybackCurrent(generation) || sourceRevision != _sourceRevision) {
      return;
    }

    // 用户主动刷新同地址也要重新加载，不能只清首帧标记却被原生去重挡住。
    await _playCurrentLine(forceReload: true);
    if (!_isPlaybackCurrent(generation)) return;

    if (_recoveryStopped) return;
    resetHealthCheck();
    startHealthCheck();
    _scheduleUrlRefresh();
  }

  // ------------------------------------------------------- 播放地址主动续期

  /// 最近一次拿到新播放地址的时间
  DateTime? _urlFetchedAt;

  /// 主动续期定时器
  Timer? _urlRefreshTimer;

  void _markUrlRefreshed() {
    _urlFetchedAt = DateTime.now();
  }

  void _scheduleUrlRefresh() {
    _urlRefreshTimer?.cancel();
    _urlRefreshTimer = null;
    if (_disposed ||
        _closingLiveRoom ||
        _recoveryStopped ||
        !liveStatus.value ||
        detail.value?.isRecord == true ||
        playUrls.isEmpty) {
      return;
    }
    final index = currentLineIndex.clamp(0, playUrls.length - 1);
    final fetchedAt = _urlFetchedAt ?? DateTime.now();
    final expiresAt = LiveStreamExpiry.expiresAt(
      playUrls[index],
      siteId: site.id,
      fetchedAt: fetchedAt,
    );
    if (expiresAt == null) return;
    final lifetime = expiresAt.difference(fetchedAt);
    // 过期或损坏的参数交由真实故障恢复处理，不构造每 20 秒换源的循环。
    if (lifetime <= Duration.zero) {
      Log.d("直播地址期限已过，不安排周期性换源");
      return;
    }
    final lead = Duration(seconds: (lifetime.inSeconds ~/ 2).clamp(30, 300));
    final delay = expiresAt.subtract(lead).difference(DateTime.now());
    if (delay <= Duration.zero) return;
    Log.d(
        "安排 ${delay.inSeconds} 秒后续期，平台=${site.id}，线路${index + 1}，到期=$expiresAt");
    _urlRefreshTimer = Timer(delay, () {
      if (_disposed ||
          _closingLiveRoom ||
          _recoveryStopped ||
          !liveStatus.value) {
        return;
      }
      Log.d("主动续期触发：距上次取流 ${DateTime.now().difference(fetchedAt).inSeconds} 秒");
      refreshPlayUrlAndResume();
    });
  }

  void _cancelUrlRefresh() {
    _urlRefreshTimer?.cancel();
    _urlRefreshTimer = null;
  }

  /// 播放当前线路
  Future<void> _playCurrentLine(
      {bool forceReload = false, bool preserveFrame = false}) async {
    final generation = _playbackGeneration;
    final revision = ++_sourceRevision;
    bool isCurrent() =>
        _isPlaybackCurrent(generation) && revision == _sourceRevision;
    if (!isCurrent() || _recoveryStopped || playUrls.isEmpty) return;
    currentLineIndex = currentLineIndex.clamp(0, playUrls.length - 1);
    final url = _effectivePlayUrl(playUrls[currentLineIndex]);
    _rememberCurrentLine();
    _beginLineConnection();
    resetHealthCheck();
    try {
      if (isPlayerHandedOver) {
        if (!isCurrent()) return;
        currentPlayUrl.value = url;
        await nativePlayer.switchSource(url, headers: playHeaders);
        _syncFloatingLine();
      } else {
        await ensureVideoTexture();
        if (!isCurrent()) return;
        final alive = preserveFrame && await nativePlayer.hasActiveStream();
        if (!isCurrent()) return;
        currentPlayUrl.value = url;
        if (alive) {
          await nativePlayer.switchSource(url, headers: playHeaders);
        } else {
          hasRenderedFirstFrame.value = false;
          await nativePlayer.open(url,
              headers: playHeaders, forceReload: forceReload);
        }
      }
      if (!isCurrent()) return;
      _scheduleUrlRefresh();
      await _confirmPlayingLine();
    } catch (e) {
      Log.logPrint(e);
      if (isCurrent()) _recoverPlayback("换源失败：$e", skipRetry: true);
    }
  }

  Future<void> setPlayer() => _playCurrentLine(forceReload: true);

  int mediaErrorRetryCount = 0;
  int _sourceRevision = 0;
  int _refreshRequestId = 0;
  int _recoveryRevision = 0;
  int? _recoveringRevision;
  int _recoveryRounds = 0;
  bool _recoveryStopped = false;
  String? _pendingRecoveryReason;
  bool _pendingSkipRetry = false;
  final Set<String> _failedLines = {};
  Timer? _stablePlaybackTimer;

  void _resetPlaybackRecovery() {
    _sourceRevision++;
    _refreshRequestId++;
    _recoveryRevision++;
    _refreshingPlayUrl = false;
    _pendingRecoveryReason = null;
    _pendingSkipRetry = false;
    _stablePlaybackTimer?.cancel();
    _retryTimer?.cancel();
    _recoveryStopped = false;
    _recoveryRounds = 0;
    _failedLines.clear();
    mediaErrorRetryCount = 0;
    _refreshFailCount = 0;
    errorMsg.value = "";
  }

  void _stopPlaybackRecovery() {
    _recoveryStopped = true;
    _pendingRecoveryReason = null;
    _stablePlaybackTimer?.cancel();
    _retryTimer?.cancel();
    _cancelUrlRefresh();
    stopHealthCheck();
    playingLineIndex.value = -1;
    lineConnecting.value = false;
    final selected = _lineSelection;
    currentLineInfo.value =
        selected == null ? "线路不可用" : "线路${selected.index + 1}（不可用）";
    // 明确失败后不继续播上一档音频，避免错误提示下仍在播放旧流。
    nativePlayer.pause().catchError((e) => Log.logPrint(e));
  }

  @override
  void mediaEnd() {
    super.mediaEnd();
    if (detail.value?.isRecord == true) return;
    _recoverPlayback("直播流结束");
  }

  @override
  void mediaError(String error) {
    super.mediaError(error);
    _recoverPlayback("播放报错：$error");
  }

  @override
  void onPlayStalled() => _recoverPlayback("持续缓冲约 20 秒", skipRetry: true);

  Future<void> _recoverPlayback(String reason, {bool skipRetry = false}) async {
    final generation = _playbackGeneration;
    final recovery = _recoveryRevision;
    bool isCurrent() =>
        _isPlaybackCurrent(generation) &&
        recovery == _recoveryRevision &&
        !_recoveryStopped;
    if (!isCurrent() || !liveStatus.value) return;
    _stablePlaybackTimer?.cancel();
    _pendingRecoveryReason = reason;
    _pendingSkipRetry = _pendingSkipRetry || skipRetry;
    if (_recoveringRevision == recovery) return;
    _recoveringRevision = recovery;
    try {
      while (isCurrent() && _pendingRecoveryReason != null) {
        final cause = _pendingRecoveryReason!;
        final immediate = _pendingSkipRetry;
        _pendingRecoveryReason = null;
        _pendingSkipRetry = false;
        // 故障事件可能恰好发生在取流请求结束前，串行等它完成，不丢弃事件。
        while (isCurrent() && _refreshingPlayUrl) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!isCurrent()) return;
        Log.d(
            "直播恢复：$cause，线路${currentLineIndex + 1}，重试=$mediaErrorRetryCount，轮次=$_recoveryRounds");
        if (!immediate && playUrls.isNotEmpty && mediaErrorRetryCount < 2) {
          mediaErrorRetryCount++;
          await _switchToCurrentLine();
          continue;
        }
        if (currentLineIndex >= 0 && currentLineIndex < playUrls.length) {
          _failedLines.add(_lineIdentity(playUrls[currentLineIndex]));
        }
        var next = -1;
        for (var step = 1; step <= playUrls.length; step++) {
          final index = (currentLineIndex + step) % playUrls.length;
          final url = playUrls[index];
          final expiry = LiveStreamExpiry.expiresAt(
            url,
            siteId: site.id,
            fetchedAt: _urlFetchedAt ?? DateTime.now(),
          );
          if (!_failedLines.contains(_lineIdentity(url)) &&
              (expiry == null || expiry.isAfter(DateTime.now()))) {
            next = index;
            break;
          }
        }
        if (next >= 0) {
          currentLineIndex = next;
          mediaErrorRetryCount = 0;
          Log.d("自动切换到线路${next + 1}，保持当前画质");
          await _switchToCurrentLine();
          continue;
        }
        _recoveryRounds++;
        if (_recoveryRounds > 2) {
          errorMsg.value = "当前画质的所有线路均不可用，请稍后刷新或手动选择画质";
          _stopPlaybackRecovery();
          return;
        }
        _failedLines.clear();
        mediaErrorRetryCount = 0;
        await refreshPlayUrlAndResume(forceReload: true);
      }
    } finally {
      if (_recoveringRevision == recovery) _recoveringRevision = null;
    }
  }

  // ------------------------------------------------------------------ 悬浮窗

  /// 是否已在悬浮窗中播放
  var isFloating = false.obs;

  /// 是否正在进入悬浮窗（防止重复触发）
  bool _enteringFloating = false;

  /// 悬浮窗功能是否可用（TV 端禁用）
  bool get floatingEnabled => !isTvDevice;

  /// 进入悬浮小窗
  ///
  /// 关键点：不重新取流、不重建播放器，仅把视频输出切到悬浮窗的 Surface，
  /// 因此画面是无缝衔接的。
  Future<bool> enterFloatingWindow() async {
    if (_closingLiveRoom || _disposed) {
      return false;
    }
    if (!floatingEnabled) {
      return false;
    }
    if (_enteringFloating || isFloating.value) {
      return isFloating.value;
    }
    if (loadError.value || !liveStatus.value) {
      return false;
    }

    _enteringFloating = true;
    try {
      // 检查悬浮窗权限
      await refreshOverlayPermission();
      if (_closingLiveRoom || _disposed) return false;
      if (!hasOverlayPermission.value) {
        SmartDialog.showToast("请先授予悬浮窗权限");
        await nativePlayer.requestOverlayPermission();
        return false;
      }

      // 根据视频比例计算小窗尺寸（宽固定 240dp）
      const double widthDp = 240;
      double ratio = videoAspectRatio.value;
      if (ratio <= 0 || ratio.isNaN || ratio.isInfinite) {
        ratio = 16 / 9;
      }
      final heightDp = widthDp / ratio;

      final success = await nativePlayer.enterFloating(
        width: widthDp.round(),
        height: heightDp.round(),
      );

      if (_closingLiveRoom || _disposed) {
        if (success) await nativePlayer.exitFloating();
        return false;
      }
      if (success) {
        isFloating.value = true;
        // 播放器所有权移交给悬浮窗：此后即使控制器被销毁也不能释放播放器
        isPlayerHandedOver = true;
        FloatingSession.instance.bind(
          site,
          roomId,
          quality: (currentQuality >= 0 && currentQuality < qualites.length)
              ? qualites[currentQuality]
              : null,
          lineIndex: currentLineIndex < 0 ? 0 : currentLineIndex,
          lineCount: playUrls.length,
          playUrl: currentPlayUrl.value,
          playUrls: playUrls.toList(),
          urlFetchedAt: _urlFetchedAt,
          // 小窗弹幕需要它才能连上平台的弹幕服务器。
          // 注意这里只是把参数交出去，"是否真的连"由
          // AppSettingsController.floatingDanmuEnable 决定：
          // 关闭时 FloatingSession 会直接跳过，不建立任何连接。
          danmakuData: detail.value?.danmakuData,
        );
        FloatingSession.instance.isFloating.value = true;
        // 页面即将销毁，把取流能力交接给全局会话，
        // 让小窗播放期间地址过期时仍能自愈
        FloatingSession.instance.onRefreshUrl =
            _floatingRefreshHandler = () async {
          await _recoverPlayback("小窗播放故障", skipRetry: true);
        };
      } else {
        SmartDialog.showToast("悬浮窗启动失败");
      }
      return success;
    } catch (e) {
      Log.logPrint(e);
      return false;
    } finally {
      _enteringFloating = false;
    }
  }

  /// 退出悬浮窗，回到页面内播放
  Future<void> exitFloatingWindow() async {
    if (!isFloating.value) {
      return;
    }
    try {
      await nativePlayer.exitFloating();
    } catch (e) {
      Log.logPrint(e);
    }
    isFloating.value = false;
    // 所有权收回控制器，之后销毁页面才允许释放播放器
    isPlayerHandedOver = false;
  }

  /// 点击/关闭小窗由 [FloatingSession] 全局接管
  ///
  /// 因为返回进小窗后本控制器已经被销毁，收不到原生事件，
  /// 所以这里不做实现，避免「页面存活时处理一次、销毁后又处理一次」的重复。
  @override
  void onFloatingTap() {}

  @override
  void onFloatingClosed() {}

  /// 页面返回时的处理
  ///
  /// - 手机端：进入悬浮小窗后正常返回上一页（不是退到桌面），
  ///   视频实例由原生播放器持有，画面继续在小窗里播，不中断。
  /// - TV 端：不启用悬浮窗，直接返回
  Future<void> handleBackPressed() async {
    if (_disposed || _closingLiveRoom) return;
    if (fullScreenState.value) {
      exitFull();
      return;
    }
    if (floatingEnabled && liveStatus.value) {
      final ok = await enterFloatingWindow();
      if (ok) {
        Get.back();
        return;
      }
    }
    Get.back();
  }

  /// 读取SC
  void getSuperChatMessage() async {
    final generation = _playbackGeneration;
    try {
      var sc =
          await site.liveSite.getSuperChatMessage(roomId: detail.value!.roomId);
      if (!_isPlaybackCurrent(generation)) return;
      superChats.addAll(sc);
    } catch (e) {
      if (!_isPlaybackCurrent(generation)) return;
      Log.logPrint(e);
      addSysMsg("SC读取失败");
    }
  }

  /// 移除掉已到期的SC
  void removeSuperChats() async {
    var now = DateTime.now().millisecondsSinceEpoch;
    superChats.value = superChats
        .where((x) => x.endTime.millisecondsSinceEpoch > now)
        .toList();
  }

  /// 添加历史记录
  void addHistory() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    var history = DBService.instance.getHistory(id);
    if (history != null) {
      history.updateTime = DateTime.now();
    }
    history ??= History(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      updateTime: DateTime.now(),
    );

    DBService.instance.addOrUpdateHistory(history);
  }

  /// 关注用户
  void followUser() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    DBService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
      ),
    );
    followed.value = true;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  /// 取消关注用户
  void removeFollowUser() async {
    if (!await Utils.showAlertDialog("确定要取消关注该用户吗？", title: "取消关注")) {
      return;
    }

    var id = "${site.id}_$roomId";
    DBService.instance.deleteFollow(id);
    followed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  void share() {
    if (detail.value == null) {
      return;
    }
    SharePlus.instance.share(ShareParams(uri: Uri.parse(detail.value!.url)));
  }

  void copyUrl() {
    if (detail.value == null) {
      return;
    }
    Utils.copyToClipboard(detail.value!.url);
    SmartDialog.showToast("已复制直播间链接");
  }

  /// 复制新生成的直播流
  void copyPlayUrl() async {
    // 未开播不复制
    if (!liveStatus.value) {
      return;
    }
    try {
      var playUrl = await site.liveSite.getPlayUrls(
          detail: detail.value!, quality: qualites[currentQuality]);
      if (playUrl.urls.isEmpty) {
        SmartDialog.showToast("无法读取播放地址");
        return;
      }
      Utils.copyToClipboard(playUrl.urls.first);
      SmartDialog.showToast("已复制播放直链");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法读取播放地址");
    }
  }

  /// 底部打开播放器设置
  void showDanmuSettingsSheet() {
    Utils.showBottomSheet(
      title: "弹幕设置",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          DanmuSettingsView(
            danmakuController: danmakuController,
            showFloatingEntry: false,
            onTapDanmuShield: () {
              Get.back();
              showDanmuShield();
            },
          ),
        ],
      ),
    );
  }

  void showVolumeSlider(BuildContext targetContext) {
    SmartDialog.showAttach(
      targetContext: targetContext,
      alignment: Alignment.topCenter,
      displayTime: const Duration(seconds: 3),
      maskColor: const Color(0x00000000),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: AppStyle.radius12,
            color: Theme.of(context).cardColor,
          ),
          padding: AppStyle.edgeInsetsA4,
          child: Obx(
            () => SizedBox(
              width: 200,
              child: Slider(
                min: 0,
                max: 100,
                value: AppSettingsController.instance.playerVolume.value,
                onChanged: (newValue) {
                  nativePlayer.setVolume(newValue / 100);
                  AppSettingsController.instance.setPlayerVolume(newValue);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void showQualitySheet() {
    if (qualites.isEmpty) {
      SmartDialog.showToast("清晰度信息还未加载完成");
      return;
    }
    Utils.showCompactBottomSheet(
      title: "切换清晰度",
      child: Obx(
        () => RadioGroup(
          groupValue: currentQuality,
          onChanged: (e) {
            Get.back();
            if (e != null) changePlayQuality(e);
          },
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: qualites.length,
            itemBuilder: (_, i) {
              var item = qualites[i];
              return RadioListTile(
                value: i,
                visualDensity: VisualDensity.compact,
                title: Text(item.quality),
              );
            },
          ),
        ),
      ),
    );
  }

  void showPlayUrlsSheet() {
    if (playUrls.isEmpty) {
      SmartDialog.showToast("线路信息还未加载完成");
      return;
    }
    Utils.showCompactBottomSheet(
      title: "切换线路",
      child: Obx(() {
        final connecting = lineConnecting.value;
        final targetIndex = currentLineIndex;
        return RadioGroup(
          groupValue:
              playingLineIndex.value < 0 ? null : playingLineIndex.value,
          onChanged: (e) {
            Get.back();
            changePlayLine(e ?? 0);
          },
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            // 接管已有流时 playUrls 还没有地址，用小窗记录的数量占位显示
            itemCount: effectiveLineCount,
            itemBuilder: (_, i) {
              // playUrls 为空（接管场景）时不显示 FLV/HLS 标识，避免误导
              final hasUrl = i < playUrls.length && playUrls[i].isNotEmpty;
              return RadioListTile(
                value: i,
                visualDensity: VisualDensity.compact,
                title: Text(connecting && targetIndex == i
                    ? "线路${i + 1}（连接中）"
                    : "线路${i + 1}"),
                secondary: hasUrl
                    ? Text(playUrls[i].contains(".flv") ? "FLV" : "HLS")
                    : null,
              );
            },
          ),
        );
      }),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showCompactBottomSheet(
      title: "画面尺寸",
      child: Obx(
        () => RadioGroup(
          groupValue: AppSettingsController.instance.scaleMode.value,
          onChanged: (e) {
            AppSettingsController.instance.setScaleMode(e ?? 0);
          },
          child: ListView(
            shrinkWrap: true,
            padding: AppStyle.edgeInsetsV12,
            children: const [
              RadioListTile(
                value: 0,
                title: Text("适应"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 1,
                title: Text("拉伸"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 2,
                title: Text("铺满"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 3,
                title: Text("16:9"),
                visualDensity: VisualDensity.compact,
              ),
              RadioListTile(
                value: 4,
                title: Text("4:3"),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showDanmuShield() {
    TextEditingController keywordController = TextEditingController();

    void addKeyword() {
      if (keywordController.text.isEmpty) {
        SmartDialog.showToast("请输入关键词");
        return;
      }

      AppSettingsController.instance
          .addShieldList(keywordController.text.trim());
      keywordController.text = "";
    }

    Utils.showBottomSheet(
      title: "关键词屏蔽",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              hintText: "请输入关键词",
              suffixIcon: TextButton.icon(
                onPressed: addKeyword,
                icon: const Icon(Icons.add),
                label: const Text("添加"),
              ),
            ),
            onSubmitted: (e) {
              addKeyword();
            },
          ),
          AppStyle.vGap12,
          Obx(
            () => Text(
              "已添加${AppSettingsController.instance.shieldList.length}个关键词（点击移除）",
              style: Get.textTheme.titleSmall,
            ),
          ),
          AppStyle.vGap12,
          Obx(
            () => Wrap(
              runSpacing: 12,
              spacing: 12,
              children: AppSettingsController.instance.shieldList
                  .map(
                    (item) => InkWell(
                      borderRadius: AppStyle.radius24,
                      onTap: () {
                        AppSettingsController.instance.removeShieldList(item);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: AppStyle.radius24,
                        ),
                        padding: AppStyle.edgeInsetsH12.copyWith(
                          top: 4,
                          bottom: 4,
                        ),
                        child: Text(
                          item,
                          style: Get.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void showAutoExitSheet() {
    if (AppSettingsController.instance.autoExitEnable.value &&
        !delayAutoExit.value) {
      SmartDialog.showToast("已设置了全局定时关闭");
      return;
    }
    Utils.showBottomSheet(
      title: "定时关闭",
      child: ListView(
        children: [
          Obx(
            () => SwitchListTile(
              title: Text(
                "启用定时关闭",
                style: Get.textTheme.titleMedium,
              ),
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;

                setAutoExit();
                //controller.setAutoExitEnable(e);
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration =
                    Duration(hours: value.hour, minutes: value.minute);
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance
                    .setRoomAutoExitDuration(autoExitMinutes.value);
                //setAutoExitDuration(duration.inMinutes);
                setAutoExit();
              },
            ),
          ),
        ],
      ),
    );
  }

  void openNaviteAPP() async {
    if (detail.value == null) {
      return;
    }
    var naviteUrl = "";
    var webUrl = "";
    if (site.id == Constant.kBiliBili) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyin) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site.id == Constant.kHuya) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyu) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    }
    try {
      await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  void resetRoom(Site site, String roomId) async {
    if (_disposed ||
        _closingLiveRoom ||
        (this.site == site && this.roomId == roomId)) {
      return;
    }

    final generation = ++_playbackGeneration;
    _cancelUrlRefresh();
    rxSite.value = site;
    rxRoomId.value = roomId;

    // 新房间加载失败时，也不能继续展示上一位主播的资料和播放线路。
    detail.value = null;
    roomPopularity.value = 0;
    detailLoaded.value = false;
    liveStatus.value = false;
    coverUrl.value = '';
    followed.value = DBService.instance.getFollowExist('${site.id}_$roomId');
    qualites.clear();
    playUrls.clear();
    currentQuality = -1;
    currentQualityInfo.value = '';
    currentLineIndex = -1;
    currentLineInfo.value = '';
    hasRenderedFirstFrame.value = false;
    error = null;
    loadError.value = false;

    // 清除全部消息
    liveDanmaku.stop();
    messages.clear();
    superChats.clear();
    danmakuController?.clear();

    // 重新设置LiveDanmaku
    liveDanmaku = site.liveSite.getDanmaku();

    _resetPlaybackRecovery();
    playingLineIndex.value = -1;
    lineConnecting.value = false;
    _requestedQuality = null;
    _lineSelection = null;
    // 切换房间时清理自愈状态
    _retryTimer?.cancel();
    _retryTimer = null;
    _refreshFailCount = 0;
    _refreshingPlayUrl = false;
    mediaErrorRetryCount = 0;
    stopHealthCheck();

    // 停止播放
    await nativePlayer.exitFloating();
    if (!_isPlaybackCurrent(generation)) return;
    await _resetPlayerForFreshEntry();
    if (!_isPlaybackCurrent(generation)) return;

    // 刷新信息
    loadData();
  }

  void copyErrorDetail() {
    Utils.copyToClipboard('''直播平台：${rxSite.value.name}
房间号：${rxRoomId.value}
错误信息：
${error?.toString()}
----------------
${error is Error ? (error as Error).stackTrace : ""}''');
    SmartDialog.showToast("已复制错误信息");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      Log.d("进入后台");
      //进入后台，关闭弹幕
      danmakuController?.clear();
      isBackground = true;
    } else
    //返回前台
    if (state == AppLifecycleState.resumed) {
      Log.d("返回前台");
      isBackground = false;

      // 回到前台时 app 可能已经挂起很久，取流地址极可能失效，
      // 直接把健康度基线重置，让后续检查按最新进度判定，
      // 避免把「刚恢复还没起播」误判为停滞。
      resetHealthCheck();
      _restorePlaybackWakelock();
    }
  }

  // 用于启动开播时长计算和更新的函数
  void startLiveDurationTimer() {
    // 如果不是直播状态或者 showTime 为空，则不启动定时器
    if (!(detail.value?.status ?? false) || detail.value?.showTime == null) {
      liveDuration.value = "00:00:00"; // 未开播时显示 00:00:00
      _liveDurationTimer?.cancel();
      return;
    }

    try {
      int startTimeStamp = int.parse(detail.value!.showTime!);
      // 取消之前的定时器
      _liveDurationTimer?.cancel();
      // 创建新的定时器，每秒更新一次
      _liveDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        liveDuration.value = formattedDuration;
      });
    } catch (e) {
      liveDuration.value = "--:--:--"; // 错误时显示 --:--:--
    }
  }

  @override
  void onClose() {
    _disposed = true;
    _stablePlaybackTimer?.cancel();
    _retryTimer?.cancel();
    _cancelUrlRefresh();
    WidgetsBinding.instance.removeObserver(this);
    scrollController.removeListener(scrollListener);
    autoExitTimer?.cancel();

    stopHealthCheck();
    liveDanmaku.stop();
    danmakuController = null;
    _liveDurationTimer?.cancel(); // 页面关闭时取消定时器

    // 进入悬浮窗时，页面销毁不能释放播放器，否则小窗会黑屏。
    // 此时只解绑页面侧的 Surface（由原生 SurfaceView 自己在 dispose 时处理），
    // 播放器与网络流继续存活。
    if (!isFloating.value) {
      nativePlayer.release().catchError((e) {
        Log.logPrint(e);
      });
    }

    super.onClose();
  }
}

/// 不包含签名和画质路径，切画质时保持同一 CDN/传输协议。
class _PlaybackLineSelection {
  final int index;
  final String host;
  final String protocol;
  const _PlaybackLineSelection(this.index, this.host, this.protocol);
  factory _PlaybackLineSelection.fromUrl(int index, String url) {
    final uri = Uri.tryParse(url);
    return _PlaybackLineSelection(index, uri?.host ?? '', _protocol(uri));
  }
  bool matches(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.host == host && _protocol(uri) == protocol;
  }

  static String _protocol(Uri? uri) {
    final path = uri?.path.toLowerCase() ?? '';
    if (path.contains('.flv')) return 'flv';
    if (path.contains('.m3u8')) return 'hls';
    return uri?.scheme ?? '';
  }
}

class _PlaybackSelectionUnavailable implements Exception {
  final String message;
  const _PlaybackSelectionUnavailable(this.message);
  @override
  String toString() => message;
}

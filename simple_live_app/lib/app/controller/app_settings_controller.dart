import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/floating_session.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/native_player_bridge.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppSettingsController extends GetxController {
  static AppSettingsController get instance =>
      Get.find<AppSettingsController>();

  /// 缩放模式
  var scaleMode = 0.obs;

  var themeMode = 0.obs;

  var firstRun = false;

  @override
  void onInit() {
    themeMode.value = LocalStorageService.instance
        .getValue(LocalStorageService.kThemeMode, 0);
    firstRun = LocalStorageService.instance
        .getValue(LocalStorageService.kFirstRun, true);
    danmuSize.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuSize, 16.0);
    danmuOpacity.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuOpacity, 1.0);
    danmuArea.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuArea, 0.8);
    danmuSpeed.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuSpeed, 10.0);
    danmuEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuEnable, true);
    danmuTopMargin.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuTopMargin, 0.0);
    danmuBottomMargin.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuBottomMargin, 0.0);
    danmuFontWeight.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuFontWeight, 4);

    // 小窗弹幕默认关闭：小窗场景优先省电省流量，
    // 用户想在小窗看弹幕需要自己打开。
    floatingDanmuEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingDanmuEnable, false);
    // 小窗弹幕字号默认比播放器大一档：小窗只有 240dp 宽，
    // 直接沿用播放器的 16 在实际观感上明显偏小。
    floatingDanmuSize.value = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingDanmuSize, 20.0);
    // 小窗弹幕其余参数各存一份，与播放器弹幕完全独立
    floatingDanmuFontWeight.value = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingDanmuFontWeight, 4);
    floatingDanmuOpacity.value = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingDanmuOpacity, 1.0);
    floatingDanmuArea.value = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingDanmuArea, 0.5);
    floatingDanmuSpeed.value = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingDanmuSpeed, 8.0);
    floatingDanmuTopMargin.value = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingDanmuTopMargin, 0.0);
    floatingDanmuBottomMargin.value = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingDanmuBottomMargin, 0.0);
    floatingDanmuAmount.value = LocalStorageService.instance
        .getValue(LocalStorageService.kFloatingDanmuAmount, 8);

    chatTextSize.value = LocalStorageService.instance
        .getValue(LocalStorageService.kChatTextSize, 14.0);

    chatTextGap.value = LocalStorageService.instance
        .getValue(LocalStorageService.kChatTextGap, 4.0);

    chatBubbleStyle.value = LocalStorageService.instance.getValue(
      LocalStorageService.kChatBubbleStyle,
      false,
    );

    // 默认「最高」(2)：多档房间下中间值是 (length/2).floor()，
    // 新用户一进来就拿不到原画，而这恰恰是斗鱼被降档时最容易被误认为
    // 「登录没生效」的场景。默认给最高，用户不满意再手动往下调。
    qualityLevel.value = LocalStorageService.instance
        .getValue(LocalStorageService.kQualityLevel, 2);
    qualityLevelCellular.value = LocalStorageService.instance
        .getValue(LocalStorageService.kQualityLevelCellular, 2);

    autoExitEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kAutoExitEnable, false);

    autoExitDuration.value = LocalStorageService.instance
        .getValue(LocalStorageService.kAutoExitDuration, 60);

    roomAutoExitDuration.value = LocalStorageService.instance
        .getValue(LocalStorageService.kRoomAutoExitDuration, 60);

    playerForceHttps.value = LocalStorageService.instance
        .getValue(LocalStorageService.kPlayerForceHttps, false);

    // 「按 Home 键自动暂停」默认关闭：直播场景多数人希望退出去还能听到声音，
    // 或者干脆让它进小窗继续播。想省电/省流的用户自己打开。
    playerPauseOnHome.value = LocalStorageService.instance
        .getValue(LocalStorageService.kPlayerPauseOnHome, false);

    autoFullScreen.value = LocalStorageService.instance
        .getValue(LocalStorageService.kAutoFullScreen, false);

    // ignore: invalid_use_of_protected_member
    shieldList.value = LocalStorageService.instance.shieldBox.values.toSet();

    danmuShieldFortuneBag.value = LocalStorageService.instance
        .getValue(LocalStorageService.kDanmuShieldFortuneBag, false);

    scaleMode.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerScaleMode,
      0,
    );

    playerVolume.value = LocalStorageService.instance.getValue(
      LocalStorageService.kPlayerVolume,
      100.0,
    );
    styleColor.value = LocalStorageService.instance
        .getValue(LocalStorageService.kStyleColor, 0xff3498db);

    bilibiliLoginTip.value = LocalStorageService.instance
        .getValue(LocalStorageService.kBilibiliLoginTip, true);

    logEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kLogEnable, false);
    if (logEnable.value) {
      Log.initWriter();
    }

    autoUpdateFollowEnable.value = LocalStorageService.instance
        .getValue(LocalStorageService.kAutoUpdateFollowEnable, true);

    autoUpdateFollowDuration.value = LocalStorageService.instance
        .getValue(LocalStorageService.kUpdateFollowDuration, 10);

    updateFollowThreadCount.value = LocalStorageService.instance
        .getValue(LocalStorageService.kUpdateFollowThreadCount, 0); // 默认 0 = 自动

    initSiteSort();
    initHomeSort();

    super.onInit();
  }

  void initSiteSort() {
    var sort = LocalStorageService.instance
        .getValue(
          LocalStorageService.kSiteSort,
          Sites.allSites.keys.join(","),
        )
        .split(",");
    //如果数量与allSites的数量不一致，将缺失的添加上
    if (sort.length != Sites.allSites.length) {
      var keys = Sites.allSites.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        if (!sort.contains(keys[i])) {
          sort.add(keys[i]);
        }
      }
    }

    siteSort.value = sort;
  }

  void initHomeSort() {
    var sort = LocalStorageService.instance
        .getValue(
          LocalStorageService.kHomeSort,
          Constant.allHomePages.keys.join(","),
        )
        .split(",");
    //如果数量与allSites的数量不一致，将缺失的添加上
    if (sort.length != Constant.allHomePages.length) {
      var keys = Constant.allHomePages.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        if (!sort.contains(keys[i])) {
          sort.add(keys[i]);
        }
      }
    }

    homeSort.value = sort;
  }

  void setNoFirstRun() {
    LocalStorageService.instance.setValue(LocalStorageService.kFirstRun, false);
  }

  void changeTheme() {
    Get.dialog(
      RadioGroup(
        groupValue: themeMode.value,
        onChanged: (e) {
          Get.back();
          setTheme(e ?? 0);
        },
        child: const SimpleDialog(
          title: Text("设置主题"),
          children: [
            RadioListTile<int>(
              title: Text("跟随系统"),
              value: 0,
            ),
            RadioListTile<int>(
              title: Text("浅色模式"),
              value: 1,
            ),
            RadioListTile<int>(
              title: Text("深色模式"),
              value: 2,
            ),
          ],
        ),
      ),
    );
  }

  void setTheme(int i) {
    themeMode.value = i;
    var mode = ThemeMode.values[i];

    LocalStorageService.instance.setValue(LocalStorageService.kThemeMode, i);
    Get.changeThemeMode(mode);
  }

  var chatTextSize = 14.0.obs;
  void setChatTextSize(double e) {
    chatTextSize.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kChatTextSize, e);
  }

  var chatTextGap = 4.0.obs;
  void setChatTextGap(double e) {
    chatTextGap.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kChatTextGap, e);
  }

  var chatBubbleStyle = false.obs;
  void setChatBubbleStyle(bool e) {
    chatBubbleStyle.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kChatBubbleStyle, e);
  }

  var danmuSize = 16.0.obs;
  void setDanmuSize(double e) {
    danmuSize.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuSize, e);
  }

  var danmuSpeed = 10.0.obs;
  void setDanmuSpeed(double e) {
    danmuSpeed.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuSpeed, e);
  }

  var danmuArea = 0.8.obs;
  void setDanmuArea(double e) {
    danmuArea.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuArea, e);
  }

  var danmuOpacity = 1.0.obs;
  void setDanmuOpacity(double e) {
    danmuOpacity.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuOpacity, e);
  }

  var danmuEnable = true.obs;
  void setDanmuEnable(bool e) {
    danmuEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kDanmuEnable, e);
  }

  var danmuFontWeight = 4.obs;
  void setDanmuFontWeight(int e) {
    danmuFontWeight.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDanmuFontWeight, e);
  }

  /// 小窗是否显示弹幕
  ///
  /// 关闭时小窗**完全不加载弹幕数据**：不建 WebSocket、不解析消息，
  /// 只是播放视频。这是用户明确要求的行为——小窗是省电省流量的降级场景，
  /// 不该为看不见的弹幕付网络与解析开销。
  var floatingDanmuEnable = false.obs;
  void setFloatingDanmuEnable(bool e) {
    floatingDanmuEnable.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kFloatingDanmuEnable, e);
    _notifyFloatingDanmuChanged();
  }

  /// 小窗弹幕字号
  ///
  /// 与播放器弹幕字号 [danmuSize] 相互独立：
  /// 小窗画面只有 240dp 宽，播放器那档字号放进来偏小。
  var floatingDanmuSize = 20.0.obs;
  void setFloatingDanmuSize(double e) {
    floatingDanmuSize.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kFloatingDanmuSize, e);
    _notifyFloatingDanmuChanged();
  }

  /// 小窗弹幕字重（1~9，与播放器同一套档位语义）
  var floatingDanmuFontWeight = 4.obs;
  void setFloatingDanmuFontWeight(int e) {
    floatingDanmuFontWeight.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kFloatingDanmuFontWeight, e);
    _notifyFloatingDanmuChanged();
  }

  /// 小窗弹幕不透明度
  var floatingDanmuOpacity = 1.0.obs;
  void setFloatingDanmuOpacity(double e) {
    floatingDanmuOpacity.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kFloatingDanmuOpacity, e);
    _notifyFloatingDanmuChanged();
  }

  /// 小窗弹幕显示区域（占可用高度的比例）
  ///
  /// 默认 0.5 而不是播放器的 0.8：小窗高度本来就只有一两百 dp，
  /// 铺满 80% 会直接盖住半张脸。
  var floatingDanmuArea = 0.5.obs;
  void setFloatingDanmuArea(double e) {
    floatingDanmuArea.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kFloatingDanmuArea, e);
    _notifyFloatingDanmuChanged();
  }

  /// 小窗弹幕滚动时长（秒），越小越快
  var floatingDanmuSpeed = 8.0.obs;
  void setFloatingDanmuSpeed(double e) {
    floatingDanmuSpeed.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kFloatingDanmuSpeed, e);
    _notifyFloatingDanmuChanged();
  }

  /// 小窗弹幕顶部边距（dp）
  var floatingDanmuTopMargin = 0.0.obs;
  void setFloatingDanmuTopMargin(double e) {
    floatingDanmuTopMargin.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kFloatingDanmuTopMargin, e);
    _notifyFloatingDanmuChanged();
  }

  /// 小窗弹幕底部边距（dp）
  var floatingDanmuBottomMargin = 0.0.obs;
  void setFloatingDanmuBottomMargin(double e) {
    floatingDanmuBottomMargin.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kFloatingDanmuBottomMargin, e);
    _notifyFloatingDanmuChanged();
  }

  /// 小窗弹幕量：同屏最多同时出现的条数
  ///
  /// 小窗轨道很少（240dp × 50% 高度、20 号字只有三四轨），
  /// 条数给多了只能叠在同一轨上，观感是两行字压在一起。
  /// 默认 8：既能让画面有弹幕氛围，又不至于糊住主播。
  var floatingDanmuAmount = 8.obs;
  void setFloatingDanmuAmount(int e) {
    floatingDanmuAmount.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kFloatingDanmuAmount, e);
    _notifyFloatingDanmuChanged();
  }

  /// 弹幕相关设置变化后通知小窗会话
  ///
  /// 小窗是原生悬浮窗、播放页已销毁，它拿不到这里的 Rx 变化，
  /// 只能靠这个回调把新的样式（或开关状态）推过去。
  /// 延迟到下一帧执行：setter 是在 UI 回调里同步调用的，
  /// 立刻发 channel 会在同一帧里叠加一次跨端通信。
  void _notifyFloatingDanmuChanged() {
    Future.microtask(() {
      try {
        FloatingSession.instance.onDanmakuSettingsChanged();
      } catch (_) {
        // 会话还没初始化（极早期调用）时忽略即可
      }
    });
  }

  /// 默认清晰度档位：2=最高，1=中等，0=最低
  ///
  /// 声明初值与 [onInit] 里读存储的兜底值必须一致，否则在
  /// `onInit` 执行完之前读到的值就和最终值不同，会出现短暂闪档。
  var qualityLevel = 2.obs;
  void setQualityLevel(int level) {
    qualityLevel.value = level;
    LocalStorageService.instance
        .setValue(LocalStorageService.kQualityLevel, level);
  }

  /// 移动网络下的默认清晰度档位，默认同样取最高（见 [qualityLevel] 说明）
  var qualityLevelCellular = 2.obs;
  void setQualityLevelCellular(int level) {
    qualityLevelCellular.value = level;
    LocalStorageService.instance
        .setValue(LocalStorageService.kQualityLevelCellular, level);
  }

  var autoExitEnable = false.obs;
  void setAutoExitEnable(bool e) {
    autoExitEnable.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kAutoExitEnable, e);
  }

  var autoExitDuration = 60.obs;
  void setAutoExitDuration(int e) {
    autoExitDuration.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kAutoExitDuration, e);
  }

  var roomAutoExitDuration = 60.obs;
  void setRoomAutoExitDuration(int e) {
    roomAutoExitDuration.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kRoomAutoExitDuration, e);
  }

  var autoFullScreen = false.obs;
  void setAutoFullScreen(bool e) {
    autoFullScreen.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kAutoFullScreen, e);
  }

  var playershowSuperChat = true.obs;
  void setPlayerShowSuperChat(bool e) {
    playershowSuperChat.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kPlayerShowSuperChat, e);
  }

  RxSet<String> shieldList = <String>{}.obs;
  void addShieldList(String e) {
    shieldList.add(e);
    LocalStorageService.instance.shieldBox.put(e, e);
  }

  /// 屏蔽福袋 / 抽奖类弹幕
  ///
  /// 播放器与小窗共用同一个开关：规则只有一份实现（DanmakuShielder），
  /// 两边的过滤都走它，不需要各自配置。
  var danmuShieldFortuneBag = false.obs;
  void setDanmuShieldFortuneBag(bool e) {
    danmuShieldFortuneBag.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDanmuShieldFortuneBag, e);
  }

  void removeShieldList(String e) {
    shieldList.remove(e);
    LocalStorageService.instance.shieldBox.delete(e);
  }

  Future clearShieldList() async {
    shieldList.clear();
    await LocalStorageService.instance.shieldBox.clear();
  }

  void setScaleMode(int value) {
    scaleMode.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerScaleMode,
      value,
    );
  }

  RxList<String> siteSort = RxList<String>();
  void setSiteSort(List<String> e) {
    siteSort.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kSiteSort,
      siteSort.join(","),
    );
  }

  RxList<String> homeSort = RxList<String>();
  void setHomeSort(List<String> e) {
    homeSort.value = e;
    LocalStorageService.instance.setValue(
      LocalStorageService.kHomeSort,
      homeSort.join(","),
    );
  }

  Rx<double> playerVolume = 100.0.obs;
  void setPlayerVolume(double value) {
    playerVolume.value = value;
    LocalStorageService.instance.setValue(
      LocalStorageService.kPlayerVolume,
      value,
    );
  }

  var styleColor = 0xff3498db.obs;
  void setStyleColor(int e) {
    styleColor.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kStyleColor, e);
  }

  var danmuTopMargin = 0.0.obs;
  void setDanmuTopMargin(double e) {
    danmuTopMargin.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDanmuTopMargin, e);
  }

  var danmuBottomMargin = 0.0.obs;
  void setDanmuBottomMargin(double e) {
    danmuBottomMargin.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDanmuBottomMargin, e);
  }

  var bilibiliLoginTip = true.obs;
  void setBiliBiliLoginTip(bool e) {
    bilibiliLoginTip.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kBilibiliLoginTip, e);
  }

  var logEnable = false.obs;
  void setLogEnable(bool e) {
    logEnable.value = e;
    LocalStorageService.instance.setValue(LocalStorageService.kLogEnable, e);
  }

  var autoUpdateFollowEnable = false.obs;
  void setAutoUpdateFollowEnable(bool e) {
    autoUpdateFollowEnable.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kAutoUpdateFollowEnable, e);
  }

  var autoUpdateFollowDuration = 10.obs;
  void setAutoUpdateFollowDuration(int e) {
    autoUpdateFollowDuration.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kUpdateFollowDuration, e);
  }

  var updateFollowThreadCount = 4.obs;
  void setUpdateFollowThreadCount(int e) {
    updateFollowThreadCount.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kUpdateFollowThreadCount, e);
  }

  var playerForceHttps = false.obs;
  void setPlayerForceHttps(bool e) {
    playerForceHttps.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kPlayerForceHttps, e);
  }

  /// 按 Home 键自动暂停
  ///
  /// 【语义边界（用户明确要求）】
  /// 只在「用户主动离开 App」时暂停，也就是按 Home 键 / 最近任务键。
  /// - 来电、锁屏、拉通知栏、跳授权页 → **不暂停**
  /// - 小窗正在播放 → **不暂停**（那正是小窗存在的意义）
  /// - 按返回键进小窗 → 不暂停
  ///
  /// 实现放在原生 `onUserLeaveHint`：那是系统唯一「用户主动离开」的信号，
  /// Dart 侧的 `AppLifecycleState` 分不出 Home 和来电，做到 Flutter 层
  /// 就必然误伤。设 false 时原生侧连判断都跳过。
  var playerPauseOnHome = false.obs;
  void setPlayerPauseOnHome(bool e) {
    playerPauseOnHome.value = e;
    LocalStorageService.instance
        .setValue(LocalStorageService.kPlayerPauseOnHome, e);
    // 立即下发给原生，用户改完开关后不用退回直播间再进一次才生效。
    // 失败静默：原生不支持时只是这次不生效，不影响已存下的配置。
    NativePlayerBridge.instance.setPauseOnHome(e);
  }
}

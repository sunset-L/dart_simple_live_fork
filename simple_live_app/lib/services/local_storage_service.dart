import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/log.dart';

class LocalStorageService extends GetxService {
  static LocalStorageService get instance => Get.find<LocalStorageService>();

  /// 首次运行
  static const String kFirstRun = "FirstRun";

  /// 缩放模式
  static const String kPlayerScaleMode = "ScaleMode";

  /// 播放器关注 / 历史弹窗：切换房间时是否保留弹窗。
  static const String kPlayerRoomListLocked = "PlayerRoomListLocked";

  /// 网站排序
  static const String kSiteSort = "SiteSort";

  /// 首页排序
  static const String kHomeSort = "HomeSort";

  /// 显示模式
  /// * [0] 跟随系统
  /// * [1] 浅色模式
  /// * [2] 深色模式
  static const String kThemeMode = "ThemeMode";

  /// 弹幕大小
  static const String kDanmuSize = "DanmuSize";

  /// 弹幕速度
  static const String kDanmuSpeed = "DanmuSpeed";

  /// 弹幕区域
  static const String kDanmuArea = "DanmuArea";

  /// 弹幕透明度
  static const String kDanmuOpacity = "DanmuOpacity";

  /// 弹幕-顶部边距
  static const String kDanmuTopMargin = "DanmuTopMargin";

  /// 弹幕-底部边距
  static const String kDanmuBottomMargin = "DanmuBottomMargin";

  /// 弹幕开启
  static const String kDanmuEnable = "DanmuEnable";

  /// 弹幕字重
  static const String kDanmuFontWeight = "DanmuFontWeight";

  /// 屏蔽福袋 / 抽奖类弹幕
  ///
  /// 不分播放器与小窗：这是一条内容规则，两边共用
  /// （见 [DanmakuShielder]），所以只有一份开关。
  static const String kDanmuShieldFortuneBag = "DanmuShieldFortuneBag";

  /// 小窗显示弹幕
  ///
  /// 关闭时小窗**不建立弹幕连接、不接收任何弹幕数据**，
  /// 而不只是「收到了不画」——这是用户明确要求的省性能点。
  static const String kFloatingDanmuEnable = "FloatingDanmuEnable";

  /// 小窗弹幕字号
  ///
  /// 独立于播放器弹幕的 [kDanmuSize]：小窗画面只有 240dp 宽，
  /// 播放器那套字号（默认 16）在小窗里太小看不清，需要单独一档。
  static const String kFloatingDanmuSize = "FloatingDanmuSize";

  /// 以下 6 项为小窗弹幕专属，与播放器弹幕的同名设置完全独立。
  ///
  /// 小窗画面只有 240dp 宽、视野极窄，播放器那套值搬过来普遍偏大
  /// （显示区域 80% + 字重正常会让小窗几乎被弹幕糊满），
  /// 所以整套参数各留一份，互不影响。
  static const String kFloatingDanmuFontWeight = "FloatingDanmuFontWeight";
  static const String kFloatingDanmuOpacity = "FloatingDanmuOpacity";
  static const String kFloatingDanmuArea = "FloatingDanmuArea";
  static const String kFloatingDanmuSpeed = "FloatingDanmuSpeed";
  static const String kFloatingDanmuTopMargin = "FloatingDanmuTopMargin";
  static const String kFloatingDanmuBottomMargin = "FloatingDanmuBottomMargin";

  /// 小窗弹幕量：同屏最多同时出现的条数
  ///
  /// 小窗轨道少，条数一多就只能叠在同一轨上（观感是两行字压在一起），
  /// 所以给出一个显式上限：超出的直接丢弃，不叠、不排队。
  static const String kFloatingDanmuAmount = "FloatingDanmuAmount";

  /// 聊天区文字大小
  static const String kChatTextSize = "ChatTextSize";

  /// 聊天区间隔
  static const String kChatTextGap = "ChatTextGap";

  /// 聊天区-气泡样式
  static const String kChatBubbleStyle = "ChatBubbleStyle";

  /// 播放清晰度，0=低，1=中，2=高
  static const String kQualityLevel = "QualityLevel";

  /// 蜂窝网络下播放清晰度，0=低，1=中，2=高
  static const String kQualityLevelCellular = "QualityLevelCellular";

  /// 开启定时关闭
  static const String kAutoExitEnable = "AutoExitEnable";

  /// 定时关闭时间（分钟）
  static const String kAutoExitDuration = "AutoExitDuration";

  /// 房间内定时关闭时间（分钟）
  /// 需要一个不同的 key，因为用户在房间内设置的倒计时和全局的可能不同。
  static const String kRoomAutoExitDuration = "RoomAutoExitDuration";

  /// 播放器强制使用HTTPS
  static const String kPlayerForceHttps = "PlayerForceHttps";

  /// 按 Home 键自动暂停
  ///
  /// 只对「用户主动离开」生效（Home / 最近任务键），
  /// 来电、锁屏、小窗播放都不受影响。实现见原生的 onUserLeaveHint。
  static const String kPlayerPauseOnHome = "PlayerPauseOnHome";

  /// 自动全屏
  static const String kAutoFullScreen = "AutoFullScreen";

  /// 显示SC
  static const String kPlayerShowSuperChat = "PlayerShowSuperChat";

  /// 播放器音量
  static const String kPlayerVolume = "PlayerVolume";

  /// 哔哩哔哩cookie
  static const String kBilibiliCookie = "BilibiliCookie";

  /// 抖音cookie
  static const String kDouyinCookie = "DouyinCookie";

  /// 斗鱼 dy_auth（登录票据，用于取原画 + 不过期地址）
  static const String kDouyuAuth = "DouyuAuth";

  ///主题色
  static const String kStyleColor = "kStyleColor";

  /// 提示哔哩哔哩登录
  static const String kBilibiliLoginTip = "BilibiliLoginTip";

  /// 日志记录
  static const String kLogEnable = "LogEnable";

  /// 开启自动更新关注
  static const String kAutoUpdateFollowEnable = "AutoUpdateFollowEnable";

  /// 定时自动更新关注间隔（分钟）
  static const String kUpdateFollowDuration = "AutoUpdateFollowDuration";

  /// 开启多线程更新关注
  static const String kUpdateFollowThreadCount = "UpdateFollowThreadCount";

  /// WebDAV_服务器地址
  static const String kWebDAVUri = "WebDAVUri";

  /// WebDAV_登录账号
  static const String kWebDAVUser = "WebDAVUser";

  /// WebDAV_登录密码
  static const String kWebDAVPassword = "kWebDAVPassword";

  /// WebDAV_最后一次上传时间
  static const String kWebDAVLastUploadTime = "kWebDAVLastUploadTime";

  /// WebDAV_最后一次备份时间
  static const String kWebDAVLastRecoverTime = "kWebDAVLastRecoverTime";

  late Box settingsBox;
  late Box<String> shieldBox;

  Future init() async {
    settingsBox = await Hive.openBox(
      "LocalStorage",
    );
    shieldBox = await Hive.openBox(
      "DanmuShield",
    );
  }

  T getValue<T>(dynamic key, T defaultValue) {
    try {
      var value = settingsBox.get(key, defaultValue: defaultValue) as T;
      Log.d("Get LocalStorage：$key\r\n$value");
      return value;
    } catch (e) {
      Log.logPrint(e);
      return defaultValue;
    }
  }

  Future setValue<T>(dynamic key, T value) async {
    Log.d("Set LocalStorage：$key\r\n$value");
    return await settingsBox.put(key, value);
  }

  Future removeValue<T>(dynamic key) async {
    Log.d("Remove LocalStorage：$key");
    return await settingsBox.delete(key);
  }
}

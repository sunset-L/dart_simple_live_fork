import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/danmaku_keyword_matcher.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 弹幕屏蔽规则的唯一实现
///
/// 播放器弹幕与小窗弹幕必须走同一份判断：以前两边各抄一遍循环，
/// 新增规则时很容易只改一边，表现就是「播放器里没了，小窗里还在冒」。
/// 以后所有屏蔽规则都加在这里，两边自动一视同仁。
///
/// 只处理内容层面的过滤，与渲染无关；调用方决定丢不丢、画不画。
class DanmakuShielder {
  const DanmakuShielder._();

  static final _keywordMatcher = DanmakuKeywordMatcher(
    onInvalidRegex: (keyword) => Log.d("关键词：$keyword 正则格式错误"),
  );

  /// 这条弹幕是否应该被丢弃
  ///
  /// 顺序是有意的：用户自定义关键词优先（它更精确、也是用户显式意图），
  /// 福袋规则是兜底清理，最后才判断，避免把用户想看的正常弹幕一并吞掉。
  static bool shouldBlock(LiveMessage msg) {
    final settings = AppSettingsController.instance;
    if (_matchesUserKeywords(msg.message, settings.shieldList)) {
      return true;
    }
    if (settings.danmuShieldFortuneBag.value &&
        isFortuneBagDanmaku(msg.message)) {
      return true;
    }
    return false;
  }

  /// 是否命中用户自定义的关键词 / 正则
  ///
  /// 关键词用 `/xxx/` 包裹时按正则处理，其余按纯文本包含匹配。
  /// 正则写错只跳过这一条规则，绝不能因此把所有弹幕都丢掉。
  static bool _matchesUserKeywords(String message, Set<String> shieldList) {
    final keyword = _keywordMatcher.firstMatch(message, shieldList);
    if (keyword != null) {
      Log.d("关键词：$keyword\n已屏蔽消息内容：$message");
      return true;
    }
    return false;
  }

  /// 判断一条弹幕是否属于福袋 / 抽奖类内容
  ///
  /// 为什么要按内容判断：各平台都没有把「福袋弹幕」作为独立消息类型
  /// 交给上层。抖音的福袋开奖走单独的 protobuf 通道，根本进不了聊天流；
  /// 能进到聊天通道的，绝大多数是「福袋」「抽奖」「恭喜xx获得」这类文本，
  /// 以及主播设置的福袋口令。所以只能按文本特征识别。
  ///
  /// 规则刻意偏保守：只用「一说出来就只可能是抽奖」的词，
  /// 不用「中」「领」这种单独出现就歧义很大的字。
  static bool isFortuneBagDanmaku(String message) {
    if (message.isEmpty) {
      return false;
    }
    return _fortuneBagPattern.hasMatch(message);
  }

  static final RegExp _fortuneBagPattern = RegExp(
    // 福袋 / 天选（B站、斗鱼、虎牙都这么叫）
    r'福袋|天选'
    // 抽奖类活动的直接称呼
    r'|抽奖|中奖|开奖|奖品|奖励发放'
    // 中奖播报：「恭喜 XXX 获得/抽中/抢到 ...」
    r'|恭喜.{0,12}(获得|抽中|抢到|中奖|中得)'
    // 领取类引导：「前往领取福袋」「点击领取奖励」
    r'|(领取|领|抢|瓜分).{0,6}(福袋|红包|奖品|奖励|优惠券)'
    // 参与状态播报
    r'|已参与|参与成功|参与抽奖'
    // 口令类：福袋普遍靠「发口令」参与，口令二字一出现基本就是活动弹幕
    r'|(发送|输入|回复).{0,4}口令'
    // 限时/免费诱导
    r'|(免费|限时).{0,6}(领|抽|抢)',
    caseSensitive: false,
  );
}

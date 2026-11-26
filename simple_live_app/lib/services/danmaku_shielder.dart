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
  /// 仅按用户自定义关键词或正则过滤；不再内置福袋屏蔽规则。
  static bool shouldBlock(LiveMessage msg) {
    final settings = AppSettingsController.instance;
    if (_matchesUserKeywords(msg.message, settings.shieldList)) {
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
}

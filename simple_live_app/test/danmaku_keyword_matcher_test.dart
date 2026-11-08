import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/danmaku_keyword_matcher.dart';

void main() {
  test('纯文本、正则、大小写和空规则保持原有匹配语义', () {
    final matcher = DanmakuKeywordMatcher();
    expect(matcher.firstMatch('中文内容', {'中文'}), '中文');
    expect(matcher.firstMatch('room123', {r'/room\d+/'}), r'/room\d+/');
    expect(matcher.firstMatch('ROOM123', {r'/room\d+/'}), isNull);
    expect(matcher.firstMatch('abc//def', {'//'}), '//');
    expect(matcher.firstMatch('任意消息', {''}), '');
    expect(matcher.firstMatch('任意消息', {}), isNull);
  });

  test('无效正则只报告一次，且不会妨碍其他屏蔽规则', () {
    final invalid = <String>[];
    final matcher = DanmakuKeywordMatcher(onInvalidRegex: invalid.add);
    final keywords = {'/[/', '屏蔽'};
    for (var i = 0; i < 100; i++) {
      expect(matcher.firstMatch('这条应当屏蔽', keywords), '屏蔽');
      expect(matcher.firstMatch('正常消息', keywords), isNull);
    }
    expect(invalid, ['/[/']);
  });

  test('原地删除、添加及同数量替换规则后立即生效', () {
    final matcher = DanmakuKeywordMatcher();
    final keywords = {r'/foo\d+/', 'plain'};
    expect(matcher.firstMatch('foo123', keywords), r'/foo\d+/');
    keywords
      ..remove(r'/foo\d+/')
      ..add(r'/bar\d+/');
    expect(matcher.firstMatch('foo123', keywords), isNull);
    expect(matcher.firstMatch('bar123', keywords), r'/bar\d+/');
    keywords.clear();
    expect(matcher.firstMatch('plain bar123', keywords), isNull);
  });

  test('规则顺序变化后仍返回当前顺序的第一个匹配项', () {
    final matcher = DanmakuKeywordMatcher();
    final keywords = {'first', 'second'};
    expect(matcher.firstMatch('first second', keywords), 'first');
    keywords
      ..remove('first')
      ..add('first');
    expect(matcher.firstMatch('first second', keywords), 'second');
  });
}

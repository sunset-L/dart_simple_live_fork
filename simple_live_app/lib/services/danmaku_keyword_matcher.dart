/// 缓存当前屏蔽规则的 Pattern，规则增删时只编译新增的正则。
class DanmakuKeywordMatcher {
  final void Function(String keyword)? onInvalidRegex;
  final _patterns = <String, Pattern?>{};

  DanmakuKeywordMatcher({this.onInvalidRegex});

  String? firstMatch(String message, Set<String> keywords) {
    if (_patterns.length != keywords.length ||
        keywords.any((keyword) => !_patterns.containsKey(keyword))) {
      _patterns.removeWhere((keyword, _) => !keywords.contains(keyword));
      for (final keyword in keywords) {
        _patterns.putIfAbsent(keyword, () => _compile(keyword));
      }
    }

    // 使用当前规则的顺序，编辑、删除规则后立即生效。
    for (final keyword in keywords) {
      final pattern = _patterns[keyword];
      if (pattern != null && message.contains(pattern)) {
        return keyword;
      }
    }
    return null;
  }

  Pattern? _compile(String keyword) {
    if (!keyword.startsWith('/') ||
        !keyword.endsWith('/') ||
        keyword.length <= 2) {
      return keyword;
    }
    try {
      return RegExp(keyword.substring(1, keyword.length - 1));
    } on FormatException {
      onInvalidRegex?.call(keyword);
      return null;
    }
  }
}

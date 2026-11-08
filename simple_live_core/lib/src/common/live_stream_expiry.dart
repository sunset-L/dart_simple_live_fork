/// 按平台解释签名期限，避免把绝对时间戳当成相对有效秒数。
class LiveStreamExpiry {
  static DateTime? expiresAt(
    String url, {
    required String siteId,
    required DateTime fetchedAt,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final Map<String, String> params;
    try {
      params = uri.queryParameters;
    } on FormatException {
      return null;
    }
    final expire = params['expire'];
    if (expire != null) {
      if (expire == '0') return null;
      if (siteId == 'douyin') {
        // 主 CDN 返回 8 位十六进制 Unix 秒；备用 CDN 返回十进制 Unix 秒。
        final radix = expire.length == 8 ? 16 : 10;
        return _timestamp(expire, radix);
      }
      if (siteId == 'douyu' && RegExp(r'^\d+$').hasMatch(expire)) {
        final seconds = int.tryParse(expire);
        // 斗鱼 expire 是相对秒数，不是 Unix 时间戳。
        if (seconds != null && seconds > 0 && seconds <= 86400 * 30) {
          return fetchedAt.add(Duration(seconds: seconds));
        }
      }
      // 未知格式不猜有效期，不安排周期性换源。
      return null;
    }
    if (siteId == 'huya') {
      for (final key in ['wsTime', 'txTime']) {
        final value = params[key];
        if (value != null) return _timestamp(value, 16);
      }
    }
    return null;
  }

  static DateTime? _timestamp(String value, int radix) {
    final pattern = radix == 16 ? r'^[0-9a-fA-F]+$' : r'^\d+$';
    if (!RegExp(pattern).hasMatch(value)) return null;
    final seconds = int.tryParse(value, radix: radix);
    // 只接受合理的 Unix 秒，防止部分匹配、毫秒或损坏参数触发高频刷新。
    if (seconds == null || seconds < 1000000000 || seconds > 4102444800) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}

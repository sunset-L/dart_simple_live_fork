class CoreError extends Error {
  /// 错误码
  final int statusCode;

  /// 错误信息
  final String message;

  CoreError(
    this.message, {
    this.statusCode = 0,
  });
  @override
  String toString() {
    if (statusCode != 0) {
      // 原来的实现在有状态码时**直接丢弃 message**，
      // 只输出「连接服务器失败，请稍后再试(412)」这类泛化文案。
      // 排查时这条信息毫无价值：412 到底是被风控拦了、还是参数不对、
      // 还是接口返回了具体原因，全都被抹掉了。
      // 现在把原始 message 拼在后面（若有），既保留可读文案又不丢线索。
      final desc = statusCodeToString(statusCode);
      final origin = message.trim();
      if (origin.isEmpty || desc.contains(origin)) {
        return desc;
      }
      return "$desc · $origin";
    }

    return message;
  }

  String statusCodeToString(int statusCode) {
    switch (statusCode) {
      case 400:
        return "错误的请求(400)";
      case 401:
        return "无权限访问资源(401)";
      case 403:
        return "无权限访问资源(403)";
      case 404:
        return "服务器找不到请求的资源(404)";
      case 405:
        return "请求方法不被允许(405)";
      case 407:
        return "需要代理身份验证(407)";
      case 412:
        // B 站风控的典型返回码。触发条件里最常见的是
        // Cookie 格式不合法（例如值尾部带空格）或设备指纹异常。
        return "请求被服务器拒绝(412)，请检查账号 Cookie 是否完整或稍后重试";
      case 418:
        return "请求被服务器拦截(418)，请稍后重试";
      case 429:
        return "请求过于频繁(429)，请稍后重试";
      case 500:
        return "服务器出现错误(500)";
      case 502:
        return "服务器出现错误(502)";
      case 503:
        return "服务器出现错误(503)";
      case 504:
        return "服务器响应超时(504)";
      default:
        return "连接服务器失败，请稍后再试($statusCode)";
    }
  }
}

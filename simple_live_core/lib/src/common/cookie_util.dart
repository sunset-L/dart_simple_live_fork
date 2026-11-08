/// Cookie 字符串的规范化工具。
///
/// 用户从浏览器「复制 Cookie」时，几乎必然带着两侧空白：
///
/// ```
/// buvid3=7A1B... ; buvid4=9F8E... ; b_nut=1700000000;
/// ```
///
/// 这在浏览器里没问题（浏览器自己会 trim），但服务端不是——
/// 实测 `api.bilibili.com/x/web-interface/nav` 对 `key=value ` 这种
/// **值尾部带空格**的写法会直接返回 **HTTP 412**（风控拦截），
/// 而 `key= value`（值前有空格）反而正常。
///
/// 这个差异造成的现象极具迷惑性：
/// - 手动填 Cookie「登录成功」，说明 `x/member/web/account` 能过；
/// - 但一进直播间就报「直播间加载失败，错误码 412」，
///   因为 WBI 签名要先请求 `nav` 拿 img_key/sub_key，那一步被拦了。
///
/// 所以所有写入 / 拼装 cookie 的地方都必须先过一遍本工具，
/// 而不是把用户的原样字符串直接塞进请求头。
library;

/// 规范化单条 cookie 的键值对，返回 `null` 表示这条应当丢弃。
String? _normalizePair(String raw) {
  var part = raw.trim();
  if (part.isEmpty) {
    return null;
  }
  final eq = part.indexOf('=');
  if (eq <= 0) {
    // 没有等号（或等号在最前）的不是合法键值对
    return null;
  }
  final key = part.substring(0, eq).trim();
  // 值里允许再出现等号（base64 的 SESSDATA 等），只按第一个等号分割
  var value = part.substring(eq + 1).trim();
  if (key.isEmpty || value.isEmpty) {
    // 空值条目（如 `buvid3=`）会让服务端把整个设备指纹判为无效，直接丢
    return null;
  }
  // 有些人会把值连同引号一起复制过来
  if (value.length >= 2) {
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      value = value.substring(1, value.length - 1).trim();
    }
  }
  if (value.isEmpty) {
    return null;
  }
  return "$key=$value";
}

/// 把任意来源（浏览器复制、接口返回、本地存储）的 cookie 串整理成
/// 服务端能接受的标准形式：`k1=v1;k2=v2;`。
///
/// 处理内容：
/// - 去掉换行、回车、制表符；
/// - 每条按分号切分后对 key / value 分别 trim；
/// - 丢弃空条目、无等号条目、空值条目；
/// - 去掉值两侧的引号；
/// - 同名键保留**最后一次**出现的值（与浏览器行为一致）。
///
/// 传入空串返回空串。
String normalizeCookie(String? raw) {
  if (raw == null || raw.isEmpty) {
    return "";
  }
  var text = raw
      .replaceAll('\r', '')
      .replaceAll('\n', '')
      .replaceAll('\t', '')
      .trim();
  if (text.isEmpty) {
    return "";
  }
  // 末尾补分号，保证最后一段也能被下面的一致逻辑处理
  final pairs = <String, String>{};
  final order = <String>[];
  for (var segment in text.split(';')) {
    final normalized = _normalizePair(segment);
    if (normalized == null) {
      continue;
    }
    final eq = normalized.indexOf('=');
    final key = normalized.substring(0, eq);
    final value = normalized.substring(eq + 1);
    if (!pairs.containsKey(key)) {
      order.add(key);
    }
    pairs[key] = value;
  }
  if (order.isEmpty) {
    return "";
  }
  return '${order.map((k) => "$k=${pairs[k]}").join(';')};';
}

/// 从 cookie 串里取出某个键的值，取不到返回空串。
///
/// 与直接用正则 `key=(.*?);` 相比，这个实现不依赖「尾部必须有分号」，
/// 所以用户粘贴的串末尾少一个分号时也能正确取出。
String cookieValue(String? raw, String key) {
  if (raw == null || raw.isEmpty || key.isEmpty) {
    return "";
  }
  for (var segment in raw.replaceAll('\r', '').replaceAll('\n', '').split(';')) {
    final part = segment.trim();
    final eq = part.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    if (part.substring(0, eq).trim() != key) {
      continue;
    }
    var value = part.substring(eq + 1).trim();
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        value = value.substring(1, value.length - 1).trim();
      }
    }
    return value;
  }
  return "";
}

/// 判断 cookie 串里某个键是否存在且值非空。
///
/// 不能用 `cookie.contains("buvid3")` 代替：那样 `buvid3=;` 也会被判为
/// 「已有」，从而跳过补全逻辑，最终发出空设备指纹。
bool hasCookieValue(String? raw, String key) => cookieValue(raw, key).isNotEmpty;

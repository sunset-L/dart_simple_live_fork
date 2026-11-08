import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';

/// 斗鱼网页登录授权
///
/// 目标只有一个：拿到 `dy_auth`。
///
/// 关键约束（实测确认）：`dy_auth` 是 **HttpOnly** 的，
/// 页面里 `document.cookie` 读不到它 —— 这也是很多方案失败的原因：
/// 用 JS 拼出来的 cookie 串完全不生效（120 组对照零影响）。
///
/// 本方案靠 `CookieManager.getCookies()` 读取，它走的是原生 cookie store，
/// 能拿到 HttpOnly 字段，这也是本项目哔哩哔哩网页登录已经在用的成熟范式。
///
/// ⚠️ 两个必须避开的坑（都已在此处理）：
/// 1. Android 侧 `getCookies(url:)` 走的是 `CookieManager.getCookie(url)`，
///    **只返回域名与传入 URL 匹配的 cookie**；而 `getAllCookies` 在
///    Android 原生端**没有实现**（调用只会 notImplemented）。
///    所以查询域名必须覆盖宽一点，并且优先用「当前页面真实 URL」——
///    用 iPhone UA 打开 www.douyu.com 会被重定向到 m.douyu.com，
///    若 dy_auth 是 host-only 挂在移动站域名下，查 www 永远读不到。
/// 2. 网络校验（verify）耗时可达十几秒，绝不能和「读 cookie」共用一把锁，
///    否则用户在读 cookie 的瞬间点「已完成」会被直接判为未登录。
class DouyuWebLoginController extends BaseController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();

  /// 是否已成功拿到 dy_auth
  var successed = false.obs;

  /// 是否正在读取 cookie（只保护「读」这个快动作，不含网络校验）
  var verifying = false.obs;

  /// 上一次读到的 cookie 条数，用于失败时给用户可诊断的提示
  var lastCookieCount = 0.obs;

  @override
  void onInit() {
    super.onInit();
    // 登录成功后自动返回。
    // 只在这里注册一次（onInit 生命周期内唯一），
    // 不要放到 build 里，否则每次重建都会多挂一个监听，
    // 成功时会连续 Get.back() 把上一页也弹掉。
    ever(successed, (bool ok) {
      if (!ok) {
        return;
      }
      SmartDialog.showToast("斗鱼授权成功");
      Get.back();
    });
  }

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    // 直接进登录页，而不是首页。
    //
    // 首页的登录入口藏在右上角弹窗里，部分 UA 下还会被折叠进汉堡菜单，
    // 用户很容易在首页里绕不出来。登录页是斗鱼长期稳定的入口。
    webViewController!.loadUrl(
      urlRequest: URLRequest(
        url: WebUri("https://www.douyu.com/member/login"),
      ),
    );
  }

  /// 页面加载结束
  ///
  /// 斗鱼登录成功后不一定跳回固定域名（可能停在 www 或 m 站首页），
  /// 所以不能只靠 URL 判断。这里每次加载完成都尝试读一次 cookie。
  void onLoadStop(InAppWebViewController controller, Uri? uri) async {
    if (uri == null) {
      return;
    }
    // 只在斗鱼域名下尝试，避免第三方页面误触发
    if (!uri.host.endsWith("douyu.com")) {
      return;
    }
    // 页面刚加载完时登录可能还没完成（用户这时才开始填表单），
    // 读不到是正常的，靠 onUpdateVisitedHistory 与「已完成」按钮兜住。
    await tryExtract();
  }

  /// 历史记录变化（含 SPA 式跳转）
  ///
  /// 斗鱼登录成功后有一部分流程是前端路由跳转，不会触发 onLoadStop，
  /// 这里补一刀，能显著提高「自动识别登录成功」的命中率。
  void onUpdateVisitedHistory(
    InAppWebViewController controller,
    WebUri? url,
    bool? isReload,
  ) async {
    if (url == null || successed.value) {
      return;
    }
    if (!url.host.endsWith("douyu.com")) {
      return;
    }
    await tryExtract();
  }

  /// 候选查询域名
  ///
  /// Android 的 `getCookie(url)` 按域名匹配，所以要把可能挂载 dy_auth 的
  /// 域名都查一遍再取并集：
  /// - 当前页面真实 URL 优先（host-only cookie 只有它能读到）；
  /// - 再补顶层域与常见的 www / m / passport 子域。
  Future<List<String>> _candidateUrls() async {
    final urls = <String>[];
    // 1. 当前页面真实地址：最关键的一条，能覆盖 host-only cookie
    try {
      final current = await webViewController?.getUrl();
      if (current != null) {
        final s = current.toString();
        if (s.contains("douyu.com")) {
          urls.add(s);
        }
      }
    } catch (e) {
      Log.logPrint(e);
    }
    // 2. 常见域名
    urls.addAll([
      "https://www.douyu.com/",
      "https://m.douyu.com/",
      "https://douyu.com/",
      "https://passport.douyu.com/",
    ]);
    return urls;
  }

  /// 从 cookie store 中提取 dy_auth 并保存
  ///
  /// 返回是否拿到。**只做读 cookie，不做网络校验**，因此很快返回。
  Future<bool> tryExtract() async {
    if (successed.value) {
      return true;
    }
    if (verifying.value) {
      return false;
    }
    verifying.value = true;
    try {
      final urls = await _candidateUrls();
      final seen = <String>{};
      var total = 0;

      // 先用 getCookie(name:) 单条精确查一次。
      // 它和 getCookies 走同一个原生方法但只筛一个名字，
      // 某些 WebView 版本下对 path/domain 的匹配更宽松，能读到
      // getCookies 列表里被过滤掉的条目，成本也很低。
      for (final url in urls) {
        try {
          final one = await cookieManager.getCookie(
            url: WebUri(url),
            name: "dy_auth",
          );
          if (one != null && one.value.toString().isNotEmpty) {
            final value = one.value.toString();
            DouyuAccountService.instance.setAuth(value);
            successed.value = true;
            Log.d("斗鱼 dy_auth 已获取（getCookie 单查，来自 $url，"
                "${value.length} 字符）");
            _verifyInBackground();
            return true;
          }
        } catch (e) {
          Log.logPrint(e);
        }
      }

      for (final url in urls) {
        List<Cookie> cookies;
        try {
          cookies = await cookieManager.getCookies(url: WebUri(url));
        } catch (e) {
          Log.logPrint(e);
          continue;
        }
        total += cookies.length;
        for (final c in cookies) {
          seen.add(c.name);
          if (c.name == "dy_auth" && c.value.toString().isNotEmpty) {
            final value = c.value.toString();
            DouyuAccountService.instance.setAuth(value);
            lastCookieCount.value = total;
            successed.value = true;
            Log.d("斗鱼 dy_auth 已获取（${value.length} 字符，"
                "来自 $url，共扫到 ${cookies.length} 条 cookie）");
            // 网络校验放到后面异步做，不阻塞「已拿到」这个结论。
            _verifyInBackground();
            return true;
          }
        }
      }
      lastCookieCount.value = total;

      // 原生 store 全都没读到，再试一次页面内 JS。
      //
      // 这不是主要手段（dy_auth 是 HttpOnly，JS 读不到它），
      // 但有两个价值：
      // 1. 能确认「WebView 里到底有没有 cookie」——如果 JS 都能读到一串
      //    非 HttpOnly 的斗鱼 cookie，说明登录确实成功了，
      //    只是 dy_auth 还没落盘或被域名隔离；
      // 2. 极端情况下某些机型上 getCookies 返回空，而 JS 能拿到，
      //    这时可以抢救出 dy_auth（如果该机型没按 HttpOnly 处理）。
      final jsAuth = await _readAuthByJs();
      if (jsAuth != null && jsAuth.isNotEmpty) {
        DouyuAccountService.instance.setAuth(jsAuth);
        successed.value = true;
        Log.d("斗鱼 dy_auth 通过页面 JS 获取（${jsAuth.length} 字符）");
        _verifyInBackground();
        return true;
      }

      // 诊断用：把扫到的 cookie 名字打出来（不含值，避免泄露票据）
      Log.d("斗鱼：未找到 dy_auth，已扫描域名 ${urls.length} 个，"
          "cookie 名：${seen.join(',')}");
      return false;
    } catch (e) {
      Log.logPrint(e);
      return false;
    } finally {
      verifying.value = false;
    }
  }

  /// 用页面内 JS 尝试读 dy_auth
  ///
  /// dy_auth 是 HttpOnly，正常情况这里返回 null。
  /// 但顺带把「页面里有多少 cookie」打到日志里，方便定位
  /// 「登录了但读不到」到底卡在哪一步。
  Future<String?> _readAuthByJs() async {
    try {
      final result = await webViewController?.evaluateJavascript(
        source: """
(function(){
  try {
    var raw = document.cookie || '';
    var m = /(?:^|;\\s*)dy_auth=([^;]+)/.exec(raw);
    return JSON.stringify({
      count: raw ? raw.split(';').length : 0,
      names: raw ? raw.split(';').map(function(s){return s.split('=')[0].trim();}) : [],
      auth: m ? decodeURIComponent(m[1]) : ''
    });
  } catch(e) { return JSON.stringify({count:0,names:[],auth:'',err:''+e}); }
})()
""",
      );
      if (result == null) {
        return null;
      }
      final text = result.toString();
      Log.d("斗鱼页面 JS cookie 探测：$text");
      // 解析出 auth 字段
      final m = RegExp(r'"auth"\s*:\s*"([^"]*)"').firstMatch(text);
      if (m == null) {
        return null;
      }
      final auth = m.group(1) ?? "";
      return auth.isEmpty ? null : auth;
    } catch (e) {
      Log.logPrint(e);
      return null;
    }
  }

  /// 后台校验票据是否真的生效（不阻塞 UI）
  void _verifyInBackground() {
    DouyuAccountService.instance.verify().then((verdict) {
      Log.d("斗鱼授权校验结果：$verdict（null 表示无法判断）");
    }).catchError((Object e) {
      Log.logPrint(e);
    });
  }

  /// 手动「我已完成登录」
  ///
  /// 给自动检测兜底用：登录后页面若停在某个不触发 onLoadStop 的状态
  /// （例如纯 JS 跳转），用户点这个按钮即可。
  ///
  /// 这里刻意做**短轮询**：登录请求返回与 cookie 落盘之间可能有几毫秒到
  /// 几百毫秒的差，一次读不到不代表失败，连读几次更稳。
  Future<bool> confirmLogin() async {
    if (successed.value) {
      return true;
    }
    for (var i = 0; i < 5; i++) {
      // 等上一次读 cookie 结束（它很快），但不要因为忙就直接放弃
      var guard = 0;
      while (verifying.value && guard < 20) {
        await Future.delayed(const Duration(milliseconds: 50));
        guard++;
      }
      if (await tryExtract()) {
        return true;
      }
      if (i < 4) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    return false;
  }
}

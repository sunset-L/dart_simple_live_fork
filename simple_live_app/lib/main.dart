import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';
import 'package:simple_live_app/app/app_bootstrap.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/modules/other/debug_log_page.dart';
import 'package:simple_live_app/routes/app_pages.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/floating_session.dart';
import 'package:simple_live_app/widgets/status/app_loadding_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeApp();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  // 全局接管悬浮小窗的点击/关闭事件：
  // 返回进小窗后直播页会被 pop，页面级的监听收不到这些事件
  FloatingSession.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    Color styleColor = Color(AppSettingsController.instance.styleColor.value);
    // 只根据手选的主题色生成 Material 3 色板。
    // 浅色/深色仍然分别由 themeMode 决定，跟随系统的逻辑不变。
    final lightColorScheme = ColorScheme.fromSeed(
      seedColor: styleColor,
      brightness: Brightness.light,
    );
    final darkColorScheme = ColorScheme.fromSeed(
      seedColor: styleColor,
      brightness: Brightness.dark,
    );
    return GetMaterialApp(
      title: "Simple Live",
      theme: _buildTheme(AppStyle.lightTheme, lightColorScheme),
      darkTheme: _buildTheme(AppStyle.darkTheme, darkColorScheme),
      themeMode:
          ThemeMode.values[Get.find<AppSettingsController>().themeMode.value],
      initialRoute: RoutePath.kIndex,
      getPages: AppPages.routes,
      //国际化
      locale: const Locale("zh", "CN"),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale("zh", "CN")],
      logWriterCallback: (text, {bool? isError}) {
        Log.addDebugLog(text, (isError ?? false) ? Colors.red : Colors.grey);
        Log.writeLog(text, (isError ?? false) ? Level.error : Level.info);
      },
      // 升级后Android页面过渡动画似乎有BUG
      defaultTransition: Platform.isAndroid ? Transition.cupertino : null,
      //debugShowCheckedModeBanner: false,
      navigatorObservers: [FlutterSmartDialog.observer],
      builder: FlutterSmartDialog.init(
        loadingBuilder: ((msg) => const AppLoaddingWidget()),
        //字体大小不跟随系统变化
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.0)),
          child: Stack(
            children: [
              child!,

              //查看DEBUG日志按钮
              //只在Debug、Profile模式显示
              Visibility(
                visible: !kReleaseMode,
                child: Positioned(
                  right: 12,
                  bottom: 100 + context.mediaQueryViewPadding.bottom,
                  child: Opacity(
                    opacity: 0.4,
                    child: ElevatedButton(
                      child: const Text("DEBUG LOG"),
                      onPressed: () {
                        Get.bottomSheet(
                          const DebugLogPage(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 统一浅色/深色主题的派生颜色。
  ///
  /// `colorScheme` 是在 `ThemeData` 构造完成之后才 copyWith 进去的，
  /// 而 `scaffoldBackgroundColor` / `cardColor` 在构造时已按旧 scheme 定型，
  /// `copyWith` 不会重算它们。不同步的话，AppBar（读 `colorScheme.surface`）
  /// 与内容区（读 `scaffoldBackgroundColor`）就会是两种颜色。
  /// 同时把 AppBar 的「滚动变色」关掉，让它始终保持与内容区同色。
  static ThemeData _buildTheme(ThemeData base, ColorScheme scheme) {
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      cardColor: scheme.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';

typedef TextValidate = bool Function(String text);

class Utils {
  static late PackageInfo packageInfo;
  static DateFormat dateFormat = DateFormat("MM-dd HH:mm");
  static DateFormat dateFormatWithYear = DateFormat("yyyy-MM-dd HH:mm");
  static DateFormat timeFormat = DateFormat("HH:mm:ss");

  /// 处理时间
  static String parseTime(DateTime? dt) {
    if (dt == null) {
      return "";
    }

    var dtNow = DateTime.now();
    if (dt.year == dtNow.year &&
        dt.month == dtNow.month &&
        dt.day == dtNow.day) {
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }

    if (dt.year == dtNow.year) {
      return dateFormat.format(dt);
    }

    return dateFormatWithYear.format(dt);
  }

  /// 提示弹窗
  /// - `content` 内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容，留空为确定
  /// - `cancel` 取消按钮内容，留空为取消
  static Future<bool> showAlertDialog(
    String content, {
    String title = '',
    String confirm = '',
    String cancel = '',
    bool selectable = false,
    List<Widget>? actions,
  }) async {
    var result = await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Container(
          constraints: const BoxConstraints(
            maxHeight: 400,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: AppStyle.edgeInsetsV12,
              child: selectable ? SelectableText(content) : Text(content),
            ),
          ),
        ),
        actions: [
          ...?actions,
          TextButton(
            onPressed: (() => Get.back(result: false)),
            child: Text(cancel.isEmpty ? "取消" : cancel),
          ),
          TextButton(
            onPressed: (() => Get.back(result: true)),
            child: Text(confirm.isEmpty ? "确定" : confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 提示弹窗
  /// - `content` 内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容，留空为确定
  static Future<bool> showMessageDialog(String content,
      {String title = '', String confirm = '', bool selectable = false}) async {
    var result = await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Padding(
          padding: AppStyle.edgeInsetsV12,
          child: selectable ? SelectableText(content) : Text(content),
        ),
        actions: [
          TextButton(
            onPressed: (() => Get.back(result: true)),
            child: Text(confirm.isEmpty ? "确定" : confirm),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static void showRightDialog({
    required String title,
    Function()? onDismiss,
    required Widget child,
    double width = 320,
    bool useSystem = false,

    /// 是否渲染默认标题行（左侧返回箭头 + 文字）。
    ///
    /// 关掉它的场景：内容自己带标题，且标题要支持点左右翻页
    /// （见播放器的关注/历史面板）。那时外面的标题行是多余的，
    /// 而且会多出一条重复的分隔线。
    bool showHeader = true,
    Widget Function(Widget child)? dialogBuilder,
  }) {
    SmartDialog.show(
      alignment: Alignment.topRight,
      animationBuilder: (controller, child, animationParam) {
        //从右到左
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(controller.view),
          child: child,
        );
      },
      useSystem: useSystem,
      maskColor: Colors.transparent,
      animationTime: const Duration(milliseconds: 200),
      builder: (context) {
        final dialog = Container(
          width: width + MediaQuery.of(context).padding.right,
          padding: EdgeInsets.only(right: MediaQuery.of(context).padding.right),
          decoration: BoxDecoration(
            color: Get.theme.cardColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: SafeArea(
            left: false,
            right: false,
            child: MediaQuery(
              data: const MediaQueryData(padding: EdgeInsets.zero),
              child: Column(
                children: [
                  if (showHeader) ...[
                    ListTile(
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      leading: IconButton(
                        onPressed: () {
                          SmartDialog.dismiss(status: SmartStatus.allCustom)
                              .then(
                            (value) => onDismiss?.call(),
                          );
                        },
                        icon: const Icon(Icons.arrow_back),
                      ),
                      title: Text(
                        title,
                        style: Get.textTheme.titleMedium,
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.grey.withAlpha(25),
                    ),
                  ],
                  Expanded(
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        );
        return dialogBuilder?.call(dialog) ?? dialog;
      },
    );
  }

  static void hideRightDialog() {
    SmartDialog.dismiss(status: SmartStatus.allCustom);
  }

  static Future showBottomSheet({
    required String title,
    required Widget child,
    double maxWidth = 600,

    /// 是否渲染默认标题行。
    ///
    /// 关掉它的场景：内容自己是「带标题的双页列表」，
    /// 标题要做得能点左右翻页（见播放器的关注/历史面板），
    /// 这时再套一个默认标题行就是两层标题。
    bool showHeader = true,
    Widget Function(Widget child)? dialogBuilder,
  }) async {
    var result = await showModalBottomSheet(
      context: Get.context!,
      constraints: BoxConstraints(
        maxWidth: maxWidth,
      ),
      backgroundColor: dialogBuilder == null ? null : Colors.transparent,
      elevation: dialogBuilder == null ? null : 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      builder: (context) {
        final sheet = Column(
          children: [
            if (showHeader)
              ListTile(
                contentPadding: const EdgeInsets.only(
                  left: 12,
                ),
                title: Text(title),
                trailing: IconButton(
                  onPressed: Get.back,
                  icon: const Icon(Remix.close_line),
                ),
              ),
            Expanded(
              child: child,
            ),
            // 底部安全区：底部弹窗贴着屏幕底边，
            // 不补这一条的话最后一项会被导航栏 / 手势条压住。
            // 列表本身可以滚，但滚到底也顶不出来，属于死区。
            SizedBox(height: MediaQuery.of(Get.context!).padding.bottom),
          ],
        );
        if (dialogBuilder == null) {
          return sheet;
        }
        return dialogBuilder(
          Material(
            color: Theme.of(context).bottomSheetTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: sheet,
          ),
        );
      },
    );
    return result;
  }

  /// 内容自适应高度的底部弹窗
  ///
  /// 与 [showBottomSheet] 的区别：不强制撑满屏幕。
  /// 原来的实现用 Expanded 包住内容，弹窗高度永远等于全屏高度，
  /// 选项只有两三条时也是一整块白，观感很差。
  /// 这里用 shrinkWrap 让高度跟着条目数走，超过 [maxHeightRatio] 才滚动。
  static Future showCompactBottomSheet({
    required String title,
    required Widget child,
    double maxWidth = 600,
    double maxHeightRatio = 0.5,
  }) async {
    final screenHeight = Get.height;
    return await showModalBottomSheet(
      context: Get.context!,
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: screenHeight * maxHeightRatio,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.only(left: 12),
            title: Text(title),
            trailing: IconButton(
              onPressed: Get.back,
              icon: const Icon(Remix.close_line),
            ),
          ),
          Flexible(child: child),
          SizedBox(height: MediaQuery.of(Get.context!).padding.bottom),
        ],
      ),
    );
  }

  /// 文本编辑的弹窗
  /// - `content` 编辑框默认的内容
  /// - `title` 弹窗标题
  /// - `confirm` 确认按钮内容
  /// - `cancel` 取消按钮内容
  static Future<String?> showEditTextDialog(
    String content, {
    String title = '',
    String? hintText,
    String confirm = '',
    String cancel = '',
    TextValidate? validate,
  }) async {
    final TextEditingController textEditingController =
        TextEditingController(text: content);
    var result = await Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Padding(
          padding: AppStyle.edgeInsetsT12,
          child: TextField(
            controller: textEditingController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              //prefixText: title,
              contentPadding: AppStyle.edgeInsetsA12,
              hintText: hintText ?? title,
            ),
            // style: TextStyle(
            //     height: 1.0,
            //     color: Get.isDarkMode ? Colors.white : Colors.black),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              if (validate != null && !validate(textEditingController.text)) {
                return;
              }

              Get.back(result: textEditingController.text);
            },
            child: const Text("确定"),
          ),
        ],
      ),
      // barrierColor:
      //     Get.isDarkMode ? Colors.grey.withOpacity(.3) : Colors.black38,
    );
    return result;
  }

  static Future<T?> showOptionDialog<T>(
    List<T> contents,
    T value, {
    String title = '',
  }) async {
    var result = await Get.dialog(
      RadioGroup(
        groupValue: value,
        onChanged: (e) {
          Get.back(result: e);
        },
        child: SimpleDialog(
          title: Text(title),
          children: contents
              .map(
                (e) => RadioListTile<T>(
                  title: Text(e.toString()),
                  value: e,
                ),
              )
              .toList(),
        ),
      ),
    );
    return result;
  }

  /// 多段指引用户内容的弹窗
  /// - `content` 内容：可滚动
  /// - `title` 顶部弹窗标题
  /// - `actions` 底部按钮
  static Future<T?> showInformationHelpDialog<T>({
    required List<Widget> content,
    Widget? title,
    List<Widget>? actions,
  }) async {
    var result = await Get.dialog(
      AlertDialog(
        title: title ?? const Text("帮助"),
        scrollable: true,
        content: SingleChildScrollView(child: ListBody(children: content)),
        actions: actions ??
            [
              TextButton(
                onPressed: Get.back,
                child: const Text("确定"),
              ),
            ],
      ),
    );
    return result;
  }

  static Future showStatement() async {
    var text = await rootBundle.loadString("assets/statement.txt");

    var result = await showAlertDialog(
      text,
      selectable: true,
      title: "免责声明",
      confirm: "已阅读并同意",
      cancel: "退出",
    );
    if (!result) {
      exit(0);
    }
  }

  static Future<T?> showMapOptionDialog<T>(
    Map<T, String> contents,
    T value, {
    String title = '',
  }) async {
    var result = await Get.dialog(
      RadioGroup(
        groupValue: value,
        onChanged: (e) {
          Get.back(result: e);
        },
        child: SimpleDialog(
          title: Text(title),
          children: contents.keys
              .map(
                (e) => RadioListTile<T>(
                  title: Text((contents[e] ?? '-').tr),
                  value: e,
                ),
              )
              .toList(),
        ),
      ),
    );
    return result;
  }

  static int parseVersion(String version) {
    var sp = version.split('.');
    var num = "";
    for (var item in sp) {
      num = num + item.padLeft(2, '0');
    }
    return int.parse(num);
  }

  static String onlineToString(int num) {
    if (num >= 10000) {
      return "${(num / 10000.0).toStringAsFixed(1)}万";
    }
    return num.toString();
  }

  /// 检查相册权限
  static Future<bool> checkPhotoPermission() async {
    try {
      if (!Platform.isIOS) {
        return true;
      }
      var status = await Permission.photos.status;
      if (status == PermissionStatus.granted) {
        return true;
      }
      status = await Permission.photos.request();
      if (status.isGranted) {
        return true;
      } else {
        SmartDialog.showToast(
          "请授予相册访问权限",
        );
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  /// 检查文件权限
  static Future<bool> checkStorgePermission() async {
    try {
      if (!Platform.isAndroid) {
        return true;
      }
      Permission permission = Permission.storage;
      var androidIndo = await deviceInfo.androidInfo;
      if (androidIndo.version.sdkInt >= 33) {
        permission = Permission.manageExternalStorage;
      }

      var status = await permission.status;
      if (status == PermissionStatus.granted) {
        return true;
      }
      status = await permission.request();
      if (status.isGranted) {
        return true;
      } else {
        SmartDialog.showToast(
          "请授予文件访问权限",
        );
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  ///16进制颜色转换
  static Color convertHexColor(String hexColor) {
    hexColor = hexColor.replaceAll("#", "");
    if (hexColor.length == 4) {
      hexColor = "00$hexColor";
    }

    if (hexColor.length == 6) {
      var R = int.parse(hexColor.substring(0, 2), radix: 16);
      var G = int.parse(hexColor.substring(2, 4), radix: 16);
      var B = int.parse(hexColor.substring(4, 6), radix: 16);
      return Color.fromARGB(255, R, G, B);
    }
    if (hexColor.length == 8) {
      var A = int.parse(hexColor.substring(0, 2), radix: 16);
      var R = int.parse(hexColor.substring(2, 4), radix: 16);
      var G = int.parse(hexColor.substring(4, 6), radix: 16);
      var B = int.parse(hexColor.substring(6, 8), radix: 16);

      return Color.fromARGB(A, R, G, B);
    }

    return Colors.white;
  }

  /// 复制内容到剪贴板
  static void copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      SmartDialog.showToast("已复制到剪贴板");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("复制到剪贴板失败: $e");
    }
  }

  /// 获取剪贴板内容
  static Future<String?> getClipboard() async {
    try {
      var content = await Clipboard.getData(Clipboard.kTextPlain);
      if (content == null) {
        SmartDialog.showToast("无法读取剪贴板内容");
        return null;
      }
      return content.text;
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("读取剪切板内容失败：$e");
    }
    return null;
  }

  static bool isRegexFormat(String keyword) {
    return keyword.startsWith('/') &&
        keyword.endsWith('/') &&
        keyword.length > 2;
  }

  static String removeRegexFormat(String keyword) {
    return keyword.substring(1, keyword.length - 1);
  }

  static String parseFileSize(int size) {
    if (size < 1024) {
      return "$size B";
    }
    if (size < 1024 * 1024) {
      return "${(size / 1024).toStringAsFixed(2)} KB";
    }
    if (size < 1024 * 1024 * 1024) {
      return "${(size / 1024 / 1024).toStringAsFixed(2)} MB";
    }
    return "${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
  }
}

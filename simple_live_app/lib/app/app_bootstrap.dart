import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/sync_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

Future<void> initializeApp() async {
  await Future.wait<void>([_loadPackageInfo(), _initializeStorage()]);

  Get.put(AppSettingsController());
  Get.put(BiliBiliAccountService());
  Get.put(DouyinAccountService());
  Get.put(DouyuAccountService());
  Get.put(SyncService());
  Get.put(FollowService());

  _configureCoreLogging();
}

Future<void> _loadPackageInfo() async {
  Utils.packageInfo = await PackageInfo.fromPlatform();
}

Future<void> _initializeStorage() async {
  await Hive.initFlutter();
  Hive.registerAdapter(FollowUserAdapter());
  Hive.registerAdapter(HistoryAdapter());
  Hive.registerAdapter(FollowUserTagAdapter());

  Log.d('Initialize app storage');
  final localStorage = LocalStorageService();
  final database = DBService();
  await Future.wait<void>([localStorage.init(), database.init()]);
  Get.put(localStorage);
  Get.put(database);
}

void _configureCoreLogging() {
  CoreLog.enableLog =
      !kReleaseMode || AppSettingsController.instance.logEnable.value;
  CoreLog.requestLogType = RequestLogType.short;
  CoreLog.onPrintLog = (level, message) {
    switch (level) {
      case Level.debug:
        Log.d(message);
        break;
      case Level.error:
        Log.e(message, StackTrace.current);
        break;
      case Level.info:
        Log.i(message);
        break;
      case Level.warning:
        Log.w(message);
        break;
      default:
        Log.logPrint(message);
    }
  };
}

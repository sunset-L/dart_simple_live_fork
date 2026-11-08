import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/live_room/player/player_room_list_panel.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';

class _TestFollowService extends FollowService {
  @override
  void initTimer() {}
}

class _TestDBService extends DBService {
  @override
  List<History> getHistores() => [];
}

void main() {
  late Directory directory;
  late LocalStorageService storage;
  late LiveRoomController controller;
  var opened = 0;
  var closed = 0;

  setUp(() async {
    Get.testMode = true;
    directory = await Directory.systemTemp.createTemp('player-panel-lock-');
    Hive.init(directory.path);
    storage = LocalStorageService();
    await storage.init();
    Get.put<LocalStorageService>(storage);
    Get.put<DBService>(_TestDBService());
    final follow = Get.put<FollowService>(_TestFollowService());
    follow.liveList.add(FollowUser(
      id: 'test',
      roomId: '42',
      siteId: Constant.kBiliBili,
      userName: '测试主播',
      face: '',
      addTime: DateTime(2026),
    ));
    controller = LiveRoomController(
      pSite: Sites.allSites[Constant.kBiliBili]!,
      pRoomId: '1',
    );
    opened = 0;
    closed = 0;
  });

  tearDown(() async {
    controller.scrollController.dispose();
    await Get.delete<FollowService>(force: true);
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> showPanel(WidgetTester tester, {double width = 360}) async {
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(
          body: Center(
              child: SizedBox(
        width: width,
        height: 400,
        child: PlayerRoomListPanel(
          controller: controller,
          onOpen: (_) => opened++,
          onClose: () => closed++,
        ),
      ))),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> toggleLock(WidgetTester tester, IconData icon) async {
    // Hive 写磁盘运行在真实异步区，避免 FakeAsync 把 flush/close 挂住。
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(icon));
      await storage.settingsBox.flush();
    });
    await tester.pump();
  }

  testWidgets('首次仍默认锁定，切换房间不关闭弹窗', (tester) async {
    await showPanel(tester);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    await tester.tap(find.text('测试主播'));
    expect(opened, 1);
    expect(closed, 0);
  });

  testWidgets('解锁后关闭重开与切换布局仍解锁，选房间会关闭', (tester) async {
    await showPanel(tester);
    await toggleLock(tester, Icons.lock);
    await tester.pump();
    expect(storage.getValue(LocalStorageService.kPlayerRoomListLocked, true),
        isFalse);
    await dismiss(tester);
    await showPanel(tester, width: 520);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    await tester.tap(find.text('测试主播'));
    expect(opened, 1);
    expect(closed, 1);
  });

  testWidgets('重新锁定后重开保持锁定，切换房间不关闭', (tester) async {
    await tester.runAsync(() =>
        storage.setValue(LocalStorageService.kPlayerRoomListLocked, false));
    await showPanel(tester);
    await toggleLock(tester, Icons.lock_open);
    await tester.pump();
    await dismiss(tester);
    await showPanel(tester);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    await tester.tap(find.text('测试主播'));
    expect(opened, 1);
    expect(closed, 0);
  });

  testWidgets('关闭并重新打开 Hive 后仍恢复上次选择', (tester) async {
    await showPanel(tester);
    await toggleLock(tester, Icons.lock);
    await tester.pump();
    await dismiss(tester);
    await tester.runAsync(() async {
      await storage.settingsBox.flush();
      await Hive.close();
      await Get.delete<LocalStorageService>(force: true);
      storage = LocalStorageService();
      await storage.init();
      Get.put<LocalStorageService>(storage);
    });
    await showPanel(tester);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
  });

  testWidgets('切到历史页后重开仍保持相同锁状态', (tester) async {
    await showPanel(tester);
    await toggleLock(tester, Icons.lock);
    await tester.tap(find.text('历史'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
    await dismiss(tester);
    await showPanel(tester);
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
  });
}

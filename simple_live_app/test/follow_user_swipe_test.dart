import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_controller.dart';
import 'package:simple_live_app/modules/follow_user/follow_user_page.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/filter_button.dart';

final _pager = find.byKey(const ValueKey('follow-tag-pager'));
Finder _page(String id) =>
    find.byKey(ValueKey('follow-tag-page-$id'), skipOffstage: false);

class _TestFollowService extends FollowService {
  @override
  void initTimer() {}
}

class _TestFollowUserController extends FollowUserController {
  int refreshCount = 0;

  @override
  Future<void> refreshData() async {
    refreshCount++;
    filterData();
  }
}

Future<void> _finishAnimations(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

Future<void> _resetDependencies() async {
  await Get.delete<FollowUserController>(force: true);
  await Get.delete<FollowService>(force: true);
  Get.reset();
}

Future<_TestFollowUserController> _showPage(
  WidgetTester tester, {
  int customTagCount = 0,
  int followUserCount = 0,
}) async {
  Get.testMode = true;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _resetDependencies();
  });
  final service = Get.put<FollowService>(_TestFollowService());
  service.followList.assignAll(List.generate(followUserCount, (index) {
    final user = FollowUser(
      id: 'user-$index',
      roomId: '$index',
      siteId: Constant.kBiliBili,
      userName: '测试主播$index',
      face: '',
      addTime: DateTime(2026),
    );
    user.liveStatus.value = index.isEven ? 2 : 1;
    return user;
  }));
  service.filterData();
  service.followTagList.assignAll(List.generate(
    customTagCount,
    (index) => FollowUserTag(
      id: 'custom-$index',
      tag: '自定义标签${index + 1}',
      userId: [],
    ),
  ));
  final controller = _TestFollowUserController();
  Get.put<FollowUserController>(controller);
  controller.updateTagList();
  await tester.pumpWidget(
    const GetMaterialApp(home: FollowUserPage()),
  );
  await _finishAnimations(tester);
  return controller;
}

Future<void> _swipe(WidgetTester tester, double distance) async {
  await tester.drag(_pager, Offset(distance, 0));
  await _finishAnimations(tester);
}

void main() {
  testWidgets('空列表左右滑动与点击标签同步选中状态', (tester) async {
    final controller = await _showPage(tester, customTagCount: 1);
    expect(
      tester
          .widget<FilterButton>(
            find.widgetWithText(FilterButton, '全部'),
          )
          .selected,
      isTrue,
    );

    await _swipe(tester, -260);
    expect(controller.filterMode.value.tag, '直播中');
    expect(
      tester
          .widget<FilterButton>(
            find.widgetWithText(FilterButton, '直播中'),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.text('未开播'));
    await _finishAnimations(tester);
    await _swipe(tester, -260);
    expect(controller.filterMode.value.id, 'custom-0');
    await _swipe(tester, 260);
    expect(controller.filterMode.value.tag, '未开播');
  });

  testWidgets('首尾不越界，快速轻扫每次只切换一个标签', (tester) async {
    final controller = await _showPage(tester);
    await _swipe(tester, 260);
    expect(controller.filterMode.value.tag, '全部');
    await tester.fling(_pager, const Offset(-80, 0), 1500);
    await _finishAnimations(tester);
    expect(controller.filterMode.value.tag, '直播中');
    await _swipe(tester, -260);
    await _swipe(tester, -260);
    expect(controller.filterMode.value.tag, '未开播');
  });

  testWidgets('慢滑可以切换，短距离、上下滑动和取消手势不误切', (tester) async {
    final controller = await _showPage(tester);
    await tester.timedDrag(
      _pager,
      const Offset(-260, 0),
      const Duration(seconds: 1),
    );
    await _finishAnimations(tester);
    expect(controller.filterMode.value.tag, '直播中');

    await tester.timedDrag(
      _pager,
      const Offset(-35, 0),
      const Duration(seconds: 1),
    );
    await tester.drag(_pager, const Offset(0, -150));
    final gesture = await tester.startGesture(
      tester.getCenter(_pager),
    );
    await gesture.moveBy(const Offset(-120, 0));
    await gesture.cancel();
    await _finishAnimations(tester);
    expect(controller.filterMode.value.tag, '直播中');
  });

  testWidgets('连续切换自定义标签时自动滚动标签栏显示当前标签', (tester) async {
    final controller = await _showPage(tester, customTagCount: 6);
    for (var index = 0; index < 8; index++) {
      await _swipe(tester, -260);
    }
    expect(controller.filterMode.value.id, 'custom-5');
    final selectedButton = find.widgetWithText(FilterButton, '自定义标签6');
    final rect = tester.getRect(selectedButton);
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(tester.widget<FilterButton>(selectedButton).selected, isTrue);
  });

  testWidgets('自定义标签改名和重排后继续按当前标签切换，删除后回到全部', (tester) async {
    final controller = await _showPage(tester, customTagCount: 2);
    final service = FollowService.instance;
    controller.setFilterMode(controller.tagList[3]);
    final renamed = service.followTagList.first.copyWith(tag: '已改名标签');
    service.followTagList.assignAll([service.followTagList.last, renamed]);
    controller.updateTagList();
    await _finishAnimations(tester);
    expect(controller.filterMode.value, same(renamed));
    await _swipe(tester, 260);
    expect(controller.filterMode.value.id, 'custom-1');
    service.followTagList.removeWhere((tag) => tag.id == 'custom-1');
    controller.updateTagList();
    await _finishAnimations(tester);
    expect(controller.filterMode.value.tag, '全部');
  });

  test('从空标签切到有内容的标签时清除空页面状态', () {
    Get.testMode = true;
    addTearDown(_resetDependencies);
    final service = Get.put<FollowService>(_TestFollowService());
    final controller =
        Get.put<FollowUserController>(_TestFollowUserController());
    final follow = FollowUser(
      id: 'test-room',
      roomId: '1',
      siteId: 'test',
      userName: '测试主播',
      face: '',
      addTime: DateTime(2026),
    );
    service.liveList.add(follow);
    controller.filterData();
    controller.setFilterMode(controller.tagList[2]);
    expect(controller.pageEmpty.value, isTrue);
    controller.switchTag(-1);
    expect(controller.list, [follow]);
    expect(controller.pageEmpty.value, isFalse);
  });

  testWidgets('列表跟随手指位移，相邻页同时展示，松手后继续动画翻页', (tester) async {
    final controller = await _showPage(tester, followUserCount: 30);
    final refreshes = controller.refreshCount;
    final origin = tester.getTopLeft(_page('0'));
    final width = tester.getSize(_pager).width;
    final gesture = await tester.startGesture(tester.getCenter(_pager));
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();
    expect(tester.getTopLeft(_page('0')).dx, closeTo(origin.dx - 90, 1));
    expect(
        tester.getTopLeft(_page('1')).dx, closeTo(origin.dx + width - 90, 1));
    expect(controller.tagPageController.page, closeTo(0.25, 0.01));
    expect(controller.filterMode.value.id, '0');
    expect(controller.usersForTag(controller.tagList[0]).length, 30);
    expect(controller.usersForTag(controller.tagList[1]).length, 15);
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    expect(controller.filterMode.value.id, '1');
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(controller.tagPageController.page, greaterThan(210 / width));
    expect(controller.tagPageController.page, lessThan(1));
    await _finishAnimations(tester);
    expect(controller.tagPageController.page, 1);
    expect(controller.refreshCount, refreshes);
  });

  testWidgets('未拖过半页时松手平滑回弹，首尾也有回弹效果', (tester) async {
    final controller = await _showPage(tester);
    final gesture = await tester.startGesture(tester.getCenter(_pager));
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(controller.tagPageController.page, greaterThan(0));
    expect(controller.tagPageController.page, lessThan(0.25));
    await _finishAnimations(tester);
    expect(controller.tagPageController.page, 0);
    final origin = tester.getTopLeft(_page('0'));
    final edgeGesture = await tester.startGesture(tester.getCenter(_pager));
    await edgeGesture.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(tester.getTopLeft(_page('0')).dx, greaterThan(origin.dx));
    await edgeGesture.up();
    await _finishAnimations(tester);
    expect(tester.getTopLeft(_page('0')).dx, closeTo(origin.dx, 1));
    expect(controller.filterMode.value.id, '0');
  });

  testWidgets('点击标签有过渡动画，路过中间页时保持目标标签高亮', (tester) async {
    final controller = await _showPage(tester);
    await tester.tap(find.text('未开播'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(controller.tagPageController.page, greaterThan(0));
    expect(controller.tagPageController.page, lessThan(2));
    expect(controller.filterMode.value.id, '2');
    await _finishAnimations(tester);
    expect(controller.tagPageController.page, 2);
    expect(controller.filterMode.value.id, '2');
  });

  testWidgets('手指可以接管点击标签的过渡动画，不会被拉回原目标页', (tester) async {
    final controller = await _showPage(tester);
    await tester.tap(find.text('未开播'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final before = controller.tagPageController.page!;
    final gesture = await tester.startGesture(tester.getCenter(_pager));
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    expect(controller.tagPageController.page, closeTo(before - 0.25, 0.01));
    await gesture.moveBy(const Offset(90, 0));
    await gesture.up();
    await _finishAnimations(tester);
    final page = controller.tagPageController.page!.round();
    expect(page, lessThan(2));
    expect(controller.filterMode.value.id, controller.tagList[page].id);
  });

  testWidgets('各标签保留独立滚动位置，切换不重复刷新，回顶和下拉刷新可用', (tester) async {
    final controller = await _showPage(tester, followUserCount: 40);
    final refreshes = controller.refreshCount;
    final allGrid = find.descendant(
      of: _page('0'),
      matching: find.byType(MasonryGridView),
    );
    final allScroll = tester.widget<MasonryGridView>(allGrid).controller!;
    await tester.drag(allGrid, const Offset(0, -400));
    await _finishAnimations(tester);
    final allOffset = allScroll.offset;
    expect(allOffset, greaterThan(300));
    expect(controller.tagPageController.page, 0);
    await _swipe(tester, -260);
    final liveGrid = find.descendant(
      of: _page('1'),
      matching: find.byType(MasonryGridView),
    );
    final liveScroll = tester.widget<MasonryGridView>(liveGrid).controller!;
    expect(liveScroll.offset, 0);
    expect(liveScroll, isNot(same(allScroll)));
    await tester.drag(liveGrid, const Offset(0, -220));
    await _finishAnimations(tester);
    expect(liveScroll.offset, greaterThan(100));
    await _swipe(tester, 260);
    expect(allScroll.offset, closeTo(allOffset, 1));
    expect(controller.refreshCount, refreshes);
    controller.scrollToTopOrRefresh();
    await _finishAnimations(tester);
    expect(allScroll.offset, 0);
    controller.scrollToTopOrRefresh();
    await _finishAnimations(tester);
    expect(controller.refreshCount, refreshes + 1);
  });

  testWidgets('空标签也可以下拉刷新，不触发横向翻页', (tester) async {
    final controller = await _showPage(tester);
    final refreshes = controller.refreshCount;
    await tester.drag(_pager, const Offset(0, 260));
    await _finishAnimations(tester);
    expect(controller.refreshCount, refreshes + 1);
    expect(controller.tagPageController.page, 0);
  });
}

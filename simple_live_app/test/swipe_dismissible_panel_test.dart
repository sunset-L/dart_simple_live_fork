import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/widgets/swipe_dismissible_panel.dart';

const _surfaceKey = ValueKey('panel-surface');
const _pagerKey = ValueKey('panel-pager');

Future<PageController> _showPanel(
  WidgetTester tester,
  VoidCallback onDismiss, {
  int initialPage = 0,
}) async {
  final controller = PageController(initialPage: initialPage);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerLeft,
          child: SwipeDismissiblePanel(
            onDismiss: onDismiss,
            child: SizedBox(
              key: _surfaceKey,
              width: 400,
              height: 300,
              child: Material(
                color: Colors.white,
                child: Column(
                  children: [
                    const SizedBox(height: 48, child: Text('关注 / 历史')),
                    Expanded(
                      child: Builder(
                        builder: (context) => PageView(
                          key: _pagerKey,
                          controller: controller,
                          pageSnapping: false,
                          physics: SwipeDismissiblePanel.pagePhysicsOf(context),
                          dragStartBehavior: DragStartBehavior.down,
                          children: List.generate(
                            2,
                            (page) => ListView.builder(
                              itemCount: 30,
                              itemExtent: 50,
                              itemBuilder: (_, index) =>
                                  Text('$page: 房间 $index'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  testWidgets('弹窗跟随右滑，未超过半宽松手后回到原位', (tester) async {
    var dismissals = 0;
    await _showPanel(tester, () => dismissals++);
    final origin = tester.getTopLeft(find.byKey(_surfaceKey));
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(_pagerKey)) + const Offset(40, 80),
    );
    await gesture.moveBy(const Offset(160, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_surfaceKey)).dx, origin.dx + 160);
    expect(dismissals, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_surfaceKey)), origin);
    expect(dismissals, 0);
  });

  testWidgets('超过半宽仍不立即关闭，松手后关闭一次', (tester) async {
    var dismissals = 0;
    await _showPanel(tester, () => dismissals++);
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(_pagerKey)) + const Offset(40, 80),
    );
    await gesture.moveBy(const Offset(260, 0));
    await tester.pump();
    expect(dismissals, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dismissals, 1);
  });

  testWidgets('未超过半宽时快速右滑，松手后惯性关闭一次', (tester) async {
    var dismissals = 0;
    await _showPanel(tester, () => dismissals++);
    await tester.fling(find.byKey(_pagerKey), const Offset(120, 0), 1500);
    await tester.pumpAndSettle();
    expect(dismissals, 1);
  });

  testWidgets('超过半宽后滑回去，松手不关闭', (tester) async {
    var dismissals = 0;
    await _showPanel(tester, () => dismissals++);
    final origin = tester.getTopLeft(find.byKey(_surfaceKey));
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(_pagerKey)) + const Offset(40, 80),
    );
    await gesture.moveBy(const Offset(280, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-220, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_surfaceKey)).dx, origin.dx + 60);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_surfaceKey)), origin);
    expect(dismissals, 0);
  });

  testWidgets('刚好半宽松手不关闭', (tester) async {
    var dismissals = 0;
    await _showPanel(tester, () => dismissals++);
    await tester.drag(find.byKey(_pagerKey), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(dismissals, 0);
  });

  testWidgets('取消拖动会回弹，即使已超过半宽', (tester) async {
    var dismissals = 0;
    await _showPanel(tester, () => dismissals++);
    final origin = tester.getTopLeft(find.byKey(_surfaceKey));
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(_pagerKey)) + const Offset(40, 80),
    );
    await gesture.moveBy(const Offset(260, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_surfaceKey)), origin);
    expect(dismissals, 0);
  });

  testWidgets('历史页右滑只翻回关注页', (tester) async {
    var dismissals = 0;
    final controller = await _showPanel(
      tester,
      () => dismissals++,
      initialPage: 1,
    );
    final origin = tester.getTopLeft(find.byKey(_surfaceKey));
    await tester.drag(find.byKey(_pagerKey), const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(tester.getTopLeft(find.byKey(_surfaceKey)), origin);
    expect(dismissals, 0);
  });

  testWidgets('历史页快速右滑仍只翻回关注页', (tester) async {
    var dismissals = 0;
    final controller = await _showPanel(
      tester,
      () => dismissals++,
      initialPage: 1,
    );
    final origin = tester.getTopLeft(find.byKey(_surfaceKey));
    await tester.fling(find.byKey(_pagerKey), const Offset(120, 0), 1500);
    await tester.pumpAndSettle();
    expect(controller.page, 0);
    expect(tester.getTopLeft(find.byKey(_surfaceKey)), origin);
    expect(dismissals, 0);
  });

  testWidgets('快速左滑翻到历史页，不关闭弹窗', (tester) async {
    var dismissals = 0;
    final controller = await _showPanel(tester, () => dismissals++);
    final origin = tester.getTopLeft(find.byKey(_surfaceKey));
    await tester.fling(find.byKey(_pagerKey), const Offset(-120, 0), 1500);
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    expect(tester.getTopLeft(find.byKey(_surfaceKey)), origin);
    expect(dismissals, 0);
  });

  testWidgets('左滑翻到历史页，上下滚动不拖动弹窗', (tester) async {
    var dismissals = 0;
    final controller = await _showPanel(tester, () => dismissals++);
    final origin = tester.getTopLeft(find.byKey(_surfaceKey));
    await tester.drag(find.byKey(_pagerKey), const Offset(0, -140));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(_surfaceKey)), origin);
    await tester.drag(find.byKey(_pagerKey), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    expect(dismissals, 0);
  });
}

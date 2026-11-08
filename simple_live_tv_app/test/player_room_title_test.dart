import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_tv_app/modules/live_room/player/player_room_title.dart';

Future<void> pumpTitle(
  WidgetTester tester,
  Widget child, {
  double width = 600,
}) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(1920, 1080),
      builder: (context, child) => MaterialApp(
        home: Scaffold(
          body: SizedBox(width: width, child: child),
        ),
      ),
      child: child,
    ),
  );
}

void main() {
  testWidgets('直播信息加载时不显示热度', (tester) async {
    await pumpTitle(tester, const PlayerRoomTitle(title: null, online: 0));

    expect(find.text('正在读取直播信息...'), findsOneWidget);
    expect(find.byIcon(Icons.whatshot), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('标题后显示火焰图标和热度数值', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpTitle(
        tester,
        const PlayerRoomTitle(title: '测试直播间', online: 1234),
      );

      expect(find.text('测试直播间'), findsOneWidget);
      expect(find.byIcon(Icons.whatshot), findsOneWidget);
      expect(find.text('1234'), findsOneWidget);
      expect(find.bySemanticsLabel('热度 1234'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byIcon(Icons.whatshot)).dx,
        greaterThan(tester.getTopRight(find.text('测试直播间')).dx),
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('热度为零时显示零', (tester) async {
    await pumpTitle(tester, const PlayerRoomTitle(title: '测试直播间', online: 0));

    expect(find.byIcon(Icons.whatshot), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('较大的热度沿用万单位格式', (tester) async {
    await pumpTitle(
      tester,
      const PlayerRoomTitle(title: '测试直播间', online: 123456),
    );

    expect(find.text('12.3万'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长标题省略后仍保留热度且不溢出', (tester) async {
    final title = List.filled(30, '这是一个很长的直播间标题').join();
    await pumpTitle(
      tester,
      PlayerRoomTitle(title: title, online: 123456),
      width: 240,
    );

    final titleWidget = tester.widget<Text>(find.text(title));
    expect(titleWidget.maxLines, 1);
    expect(titleWidget.overflow, TextOverflow.ellipsis);
    expect(find.text('12.3万'), findsOneWidget);
    expect(
      tester.getTopRight(find.text('12.3万')).dx,
      lessThanOrEqualTo(240),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换直播间后显示新的标题和热度', (tester) async {
    await pumpTitle(
      tester,
      const PlayerRoomTitle(title: '原直播间', online: 1234),
    );
    await pumpTitle(
      tester,
      const PlayerRoomTitle(title: '新直播间', online: 56789),
    );

    expect(find.text('原直播间'), findsNothing);
    expect(find.text('1234'), findsNothing);
    expect(find.text('新直播间'), findsOneWidget);
    expect(find.text('5.7万'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

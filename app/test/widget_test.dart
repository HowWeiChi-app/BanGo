// 測試畫面元件。執行：flutter test

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hsnu_notice/models.dart';
import 'package:hsnu_notice/notice_list.dart';

const _exam = Notice(
  title: '第二次期中考考試範圍',
  date: '2026-11-16 15:16',
  url: 'https://www.hs.ntnu.edu.tw/content?a=1',
  source: '重要公告',
  categories: ['教務'],
  topics: ['考試'],
);

const _teacher = Notice(
  title: '教師增能研習',
  date: '2026-11-16 09:55',
  url: 'https://www.hs.ntnu.edu.tw/content?a=2',
  source: '來文公告',
  forStudents: false,
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('公告顯示標題、時間和標籤', (tester) async {
    await tester.pumpWidget(_wrap(const NoticeTile(notice: _exam)));
    expect(find.text('第二次期中考考試範圍'), findsOneWidget);
    expect(find.text('2026-11-16 15:16 · 重要公告'), findsOneWidget);
    expect(find.text('教務'), findsOneWidget);
    expect(find.text('#考試'), findsOneWidget);
  });

  testWidgets('跟學生無關的公告有標示', (tester) async {
    await tester.pumpWidget(_wrap(const NoticeTile(notice: _teacher)));
    expect(find.text('跟學生無關'), findsOneWidget);
  });

  testWidgets('全部公告：預設隱藏跟學生無關的，點主題可以篩選', (tester) async {
    const data = NoticeData(
      updated: '2026-11-17 13:06',
      categories: ['教務', '學務'],
      topics: ['考試'],
      notices: [_exam, _teacher],
    );
    await tester.pumpWidget(_wrap(AllNoticesView(data: data, onRefresh: () async {})));

    expect(find.text('第二次期中考考試範圍'), findsOneWidget);
    expect(find.text('教師增能研習'), findsNothing);

    // 打開「也顯示跟學生無關的公告」
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('教師增能研習'), findsOneWidget);

    // 點「學務」：兩則都不是學務
    await tester.tap(find.widgetWithText(ChoiceChip, '學務'));
    await tester.pumpAndSettle();
    expect(find.text('沒有符合的公告'), findsOneWidget);
  });
}

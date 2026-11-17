// 模擬使用者操作整個 App：打開、切換分頁、改訂閱設定、網路斷掉。
// 用假的資料來源，不會真的連網路。執行：flutter test

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hsnu_notice/main.dart';
import 'package:hsnu_notice/models.dart';
import 'package:hsnu_notice/repository.dart';
import 'package:hsnu_notice/subscriptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _data = NoticeData(
  updated: '2026-11-17 13:06',
  categories: ['教務', '學務', '輔導', '獎學金', '比賽'],
  topics: ['考試'],
  notices: [
    Notice(
      title: '第二次期中考考試範圍',
      date: '2026-11-16 15:16',
      url: 'https://www.hs.ntnu.edu.tw/content?a=1',
      source: '重要公告',
      categories: ['教務'],
      topics: ['考試'],
    ),
    Notice(
      title: '校內獎學金得獎名單',
      date: '2026-11-16 09:59',
      url: 'https://www.hs.ntnu.edu.tw/content?a=2',
      source: '學生',
      categories: ['獎學金'],
    ),
  ],
);

/// 假的資料來源：可以指定要不要模擬網路失敗
class FakeRepository extends NoticeRepository {
  FakeRepository({this.fail = false});

  final bool fail;

  @override
  Future<NoticeData?> loadCached() async => null;

  @override
  Future<NoticeData> fetch() async {
    if (fail) throw Exception('沒有網路');
    return _data;
  }
}

Finder _navTab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('預設訂閱只看到考試公告；打開獎學金後就看得到', (tester) async {
    await tester.pumpWidget(NoticeApp(repository: FakeRepository(), subscriptions: Subscriptions()));
    await tester.pumpAndSettle();

    // 預設訂閱：教務、學務、#考試
    expect(find.text('第二次期中考考試範圍'), findsOneWidget);
    expect(find.text('校內獎學金得獎名單'), findsNothing);

    // 「全部公告」兩則都有
    await tester.tap(_navTab('全部公告'));
    await tester.pumpAndSettle();
    expect(find.text('校內獎學金得獎名單'), findsOneWidget);

    // 到設定打開「獎學金」
    await tester.tap(_navTab('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '獎學金'));
    await tester.pumpAndSettle();

    // 「最後一次有新公告」在設定頁下面，要先捲下去才看得到
    final updated = find.textContaining('2026-11-17 13:06');
    await tester.scrollUntilVisible(updated, 200);
    expect(updated, findsOneWidget);

    // 回「我的公告」，獎學金公告出現了
    await tester.tap(_navTab('我的公告'));
    await tester.pumpAndSettle();
    expect(find.text('校內獎學金得獎名單'), findsOneWidget);

    // 設定有存到手機上
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('subscribed'), contains('獎學金'));
  });

  testWidgets('上次的訂閱設定，下次打開 App 還在', (tester) async {
    SharedPreferences.setMockInitialValues({
      'subscribed': ['獎學金'],
    });
    await tester.pumpWidget(NoticeApp(repository: FakeRepository(), subscriptions: Subscriptions()));
    await tester.pumpAndSettle();

    expect(find.text('校內獎學金得獎名單'), findsOneWidget);
    expect(find.text('第二次期中考考試範圍'), findsNothing);
  });

  testWidgets('第一次打開就沒網路：顯示錯誤和重試按鈕', (tester) async {
    await tester.pumpWidget(
        NoticeApp(repository: FakeRepository(fail: true), subscriptions: Subscriptions()));
    await tester.pumpAndSettle();

    expect(find.text('重試'), findsOneWidget);
    expect(find.textContaining('更新失敗'), findsOneWidget);
  });
}

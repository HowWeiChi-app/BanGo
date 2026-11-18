// 模擬使用者操作整個 App：打開、從時間軸點進公告、回到側邊欄換分類、改訂閱、網路斷掉。
// 用假的資料來源，不會真的連網路。執行：flutter test

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hsnu_notice/main.dart';
import 'package:hsnu_notice/router.dart';
import 'package:hsnu_notice/settings.dart';
import 'package:hsnu_notice/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 這學期的資料（日期用現在往前推，測試不會過了學期就壞掉）
String _json() {
  String ago(Duration d) {
    final t = DateTime.now().toUtc().add(const Duration(hours: 8)).subtract(d);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  return jsonEncode({
    'updated': ago(Duration.zero),
    'categories': ['教務', '學務', '輔導', '獎學金', '比賽'],
    'topics': ['考試', '停課'],
    'notices': [
      {'title': '第二次期中考考試範圍', 'date': ago(const Duration(hours: 3)), 'url': 'https://example.test/1',
        'source': '重要公告', 'categories': ['教務'], 'topics': ['考試'], 'for_students': true, 'content': '考試範圍如附件。'},
      {'title': '校內獎學金得獎名單', 'date': ago(const Duration(hours: 5)), 'url': 'https://example.test/2',
        'source': '學生', 'categories': ['獎學金'], 'topics': [], 'for_students': true, 'content': '恭喜得獎同學。'},
    ],
  });
}

Future<(NoticeStore, AppRouter)> _start(WidgetTester tester, {bool fail = false}) async {
  SharedPreferences.setMockInitialValues({});
  await AppSettings.shared.load();
  final store = NoticeStore(fetcher: (_) async => fail ? throw Exception('offline') : _json());
  await store.load();
  final router = AppRouter();
  await tester.pumpWidget(NoticeApp(store: store, router: router));
  await tester.pumpAndSettle();
  return (store, router);
}

void main() {
  testWidgets('打開就是「我的公告」，只有訂閱的類別', (tester) async {
    await _start(tester);
    expect(find.text('我的公告'), findsWidgets);
    expect(find.text('第二次期中考考試範圍'), findsOneWidget);
    expect(find.text('校內獎學金得獎名單'), findsNothing); // 預設沒訂閱獎學金
  });

  testWidgets('點公告打開內頁，按返回回到時間軸', (tester) async {
    final (_, router) = await _start(tester);
    await tester.tap(find.text('第二次期中考考試範圍'));
    await tester.pumpAndSettle();
    expect(router.depth, Depth.article);
    expect(find.text('考試範圍如附件。'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('返回'));
    await tester.pumpAndSettle();
    expect(router.depth, Depth.timeline);
    expect(router.article, isNull);
    await tester.pump(const Duration(seconds: 1)); // 等內頁預先排版的計時器跑完
  });

  testWidgets('回到側邊欄，打開「全部公告」', (tester) async {
    final (_, router) = await _start(tester);
    await tester.tap(find.bySemanticsLabel('側邊欄'));
    await tester.pumpAndSettle();
    expect(router.depth, Depth.sidebar);
    await tester.tap(find.text('全部公告'));
    await tester.pumpAndSettle();
    expect(router.filter, NoticeFilter.all);
    expect(find.text('校內獎學金得獎名單'), findsOneWidget);
  });

  testWidgets('訂閱獎學金後「我的公告」多一則', (tester) async {
    final (store, _) = await _start(tester);
    store.setSubscribed('獎學金', true);
    await tester.pumpAndSettle();
    expect(find.text('校內獎學金得獎名單'), findsOneWidget);
  });

  testWidgets('沒網路又沒有備份：顯示錯誤和重試', (tester) async {
    await _start(tester, fail: true);
    expect(find.text('無法載入公告'), findsOneWidget);
    expect(find.text('重試'), findsOneWidget);
  });
}

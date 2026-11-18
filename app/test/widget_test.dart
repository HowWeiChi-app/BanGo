// 這個檔案要留著：tool/prepare_android.sh 跑 flutter create 時，test/widget_test.dart 不存在的話
// 會產生一個預設的計數器測試（測的是不存在的按鈕，一定失敗）。這裡放一個簡單的元件測試。

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bango/settings.dart';
import 'package:bango/widgets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('每個主題在淺色、深色模式下，來源都有 5 個看得出差別的顏色', () {
    for (final theme in AppTheme.all) {
      for (final dark in [false, true]) {
        final colors = Palette(theme, dark).sources;
        expect(colors.length, 5);
        expect(colors.toSet().length, 5);
      }
    }
  });

  test('每間學校的資料網址都在 GitHub 上的 scraper/data', () {
    for (final s in School.all) {
      expect(s.dataUrl.toString(), startsWith('https://raw.githubusercontent.com/HowWeiChi-app/BanGo/main/scraper/data/'));
    }
    expect(School.all.map((s) => s.cacheKey).toSet().length, School.all.length);
  });

  testWidgets('Groove 是兩條 1px 的線', (tester) async {
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Theme(
      data: ThemeData(extensions: [Palette(AppTheme.all.first, false)]),
      child: const Center(child: SizedBox(width: 100, child: Groove())),
    )));
    expect(tester.getSize(find.byType(Groove)).height, 2);
  });

  testWidgets('淺色模式工具列的硬邊：亮線是亮的、暗線很淡，不是一條黑線', (tester) async {
    final key = GlobalKey();
    final palette = Palette(AppTheme.all.first, false);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: ThemeData(extensions: [palette]),
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 400, child: ColoredBox(color: palette.paper, child: const TopBar(solid: true))),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData();
      image.dispose();
      return data!;
    });
    int red(int y) => bytes!.getUint8((y * 400 + 200) * 4);
    expect(red(TopBar.height.toInt()), greaterThan(240)); // 亮線
    expect(red(TopBar.height.toInt() + 1), inInclusiveRange(200, 230)); // 暗線：紙張上疊 15% 黑
  });
}

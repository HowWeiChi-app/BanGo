// 設定頁，照 iPhone 版 SettingsView.swift：從側邊欄左上角打開，左上角 X 關閉；
// 米白底、每一行是灰色圖示加粗體文字，沒有白色卡片，分組之間用刻痕分隔線。
// 訂閱的類別和主題、顯示跟學生無關的公告、語言、字體、顏色主題、關於。

import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'settings.dart';
import 'widgets.dart';

const repoUrl = 'https://github.com/cyy-615/hsnu-notice';

void showSettings(BuildContext context) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, _, _) => const SettingsPage(),
    // 從下面滑上來的彈出頁
    transitionsBuilder: (_, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final s = _scroll.offset > 1;
      if (s != _scrolled) setState(() => _scrolled = s);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final settings = scope.settings;
    final p = context.palette;

    Widget row(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10), child: child);
    Widget header(String text) => row(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(text, style: AppText.title3.copyWith(fontWeight: FontWeight.w700, color: p.ink)),
        ));
    Widget note(String text) => row(Text(text, style: AppText.footnote.copyWith(color: p.inkSecondary)));
    Widget divider() => row(const Groove(length: double.infinity));
    Widget label(String title, IconData icon, {String? detail}) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 30, child: Icon(icon, size: 22, color: p.inkSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.headline.copyWith(color: p.ink)),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(detail, style: AppText.subheadline.copyWith(fontWeight: FontWeight.w400, color: p.inkSecondary)),
              ],
            ]),
          ),
        ]);
    Widget toggle(String title, IconData icon, bool on, ValueChanged<bool> change) => MergeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => change(!on),
            child: row(Row(children: [
              Expanded(child: label(title, icon)),
              Switch(value: on, onChanged: change, activeTrackColor: p.brand),
            ])),
          ),
        );
    Widget picker<T>(String title, IconData icon, T value, List<(T, String)> options, ValueChanged<T> change) => row(Row(children: [
          Expanded(child: label(title, icon)),
          PopupMenuButton<T>(
            initialValue: value,
            onSelected: change,
            color: Color.lerp(p.paper, Colors.white, p.dark ? 0.08 : 0.6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            itemBuilder: (_) => [
              for (final (v, name) in options)
                CheckedPopupMenuItem<T>(value: v, checked: v == value, child: Text(name, style: AppText.body.copyWith(color: p.ink))),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Text(options.firstWhere((o) => o.$1 == value).$2, style: AppText.body.copyWith(color: p.inkSecondary)),
                Icon(Icons.unfold_more, size: 18, color: p.inkSecondary),
              ]),
            ),
          ),
        ]));

    // 外面要包一層 Material：彈出頁不在主畫面的 Scaffold 裡，沒有它的話文字拿不到 App 的字型
    // （換字體沒反應），還會套上 Flutter 的「找不到樣式」預設樣子：黃色雙底線
    return Material(
      color: p.paper,
      child: Stack(children: [
        ListView(
          controller: _scroll,
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + TopBar.height + 4, bottom: 40 + MediaQuery.paddingOf(context).bottom),
          children: [
            row(Text(L('設定', 'Settings'), style: AppText.largeTitle.copyWith(color: p.ink))),
            header(L('類別', 'Categories')),
            for (final c in store.categories)
              toggle(TagName.display(c), tagIcon(c), store.isSubscribed(c), (on) => store.setSubscribed(c, on)),
            note(L('依公告是哪個處室、哪種事情分類。', 'Grouped by office and type of notice.')),
            divider(),
            header(L('主題', 'Topics')),
            for (final t in store.topics)
              toggle('#${TagName.display(t)}', tagIcon(t), store.isSubscribed(t), (on) => store.setSubscribed(t, on)),
            note(L('比類別更細，把同一件事的公告收在一起。#停課 是緊急公告，建議保持開啟。',
                'Narrower than categories: notices about the same thing, together. #停課 is for emergencies, so keep it on.')),
            divider(),
            header(L('顯示', 'Display')),
            toggle(L('顯示跟學生無關的公告', 'Show notices not for students'), Icons.visibility_outlined, store.showUnrelated,
                store.setShowUnrelated),
            note(L('例如教師研習、標案。打開後會出現在「全部公告」，顏色比較淡。', 'Like teacher training and tenders. They appear faded in All Notices.')),
            divider(),
            header(L('外觀', 'Appearance')),
            picker(L('語言', 'Language'), Icons.language, settings.language, const [('zh', '中文'), ('en', 'English')],
                (v) => settings.language = v),
            picker(L('字體', 'Font'), Icons.text_fields, settings.fontStyle,
                [for (final (i, f) in FontOption.all.indexed) (i, L(f.name, f.englishName))], (v) => settings.fontStyle = v),
            row(_ThemeGrid(selected: settings.themeID, onSelect: (id) => settings.themeID = id)),
            note(L('公告內容是校網的原文，不會翻譯。', 'Notices are shown as posted on the school site and aren’t translated.')),
            divider(),
            header(L('關於', 'About')),
            row(label(L('推播通知', 'Push Notifications'), Icons.notifications_off_outlined,
                detail: L('還沒有，請打開 App 下拉更新。想即時收到，可以先加入 Discord 公告頻道。',
                    'Not yet. Open the app and pull to refresh, or join the Discord channel for instant updates.'))),
            if (store.data?.updated.isNotEmpty ?? false)
              row(label(L('最後一次有新公告', 'Last New Notice'), Icons.schedule, detail: store.data!.updated)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openWeb(repoUrl),
              child: row(label(L('原始碼', 'Source Code'), Icons.code, detail: 'github.com/cyy-615/hsnu-notice')),
            ),
            note(L('只讀取各校校網的公開公告，不需要登入，也不會收集任何個人資料。大約每 10 分鐘檢查一次校網。',
                'Only reads public notices from school websites. No sign-in, no personal data collected. Sites are checked about every 10 minutes.')),
          ],
        ),
        TopBar(
          solid: _scrolled,
          leading: GlassPill(
            circle: true,
            child: PillButton(icon: Icons.close, label: L('關閉', 'Close'), onTap: () => Navigator.of(context).pop()),
          ),
        ),
      ]),
    );
  }
}

/// 顏色主題：一排圓形色票，選中的外面一圈
class _ThemeGrid extends StatelessWidget {
  const _ThemeGrid({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(width: 30, child: Icon(Icons.palette_outlined, size: 22, color: p.inkSecondary)),
        const SizedBox(width: 12),
        Text(L('顏色', 'Color'), style: AppText.headline.copyWith(color: p.ink)),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 14, runSpacing: 14, children: [
        for (final t in AppTheme.all)
          Semantics(
            button: true,
            selected: t.id == selected,
            label: t.displayName,
            child: GestureDetector(
              onTap: () => onSelect(t.id),
              child: SizedBox(
                width: 58,
                child: Column(children: [
                  Container(
                    width: 46,
                    height: 46,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: t.id == selected ? p.ink : Colors.transparent, width: 2),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.paper(p.dark),
                        border: Border.all(color: p.edgeDark),
                      ),
                      child: Center(
                        child: Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: t.accent(p.dark))),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ExcludeSemantics(
                    child: Text(t.displayName, maxLines: 1, style: AppText.footnote.copyWith(color: p.inkSecondary)),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    ]);
  }
}

// 側邊欄：最上面是「我的公告」和「全部公告」，下面是可以收合的「類別」「主題」「來源」。
// 左上角打開設定，右上角切換學校。點一項就打開那一類的時間軸。

import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'store.dart';
import 'widgets.dart';

class SidebarPage extends StatefulWidget {
  const SidebarPage({super.key});

  @override
  State<SidebarPage> createState() => _SidebarPageState();
}

class _SidebarPageState extends State<SidebarPage> {
  final _collapsed = <String>{};
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final scrolled = _scroll.offset > 1;
      if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
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
    final p = context.palette;
    final top = MediaQuery.paddingOf(context).top + TopBar.height + 20; // 工具列跟第一行之間留空

    Widget row(NoticeFilter filter, String label, IconData icon) => _SidebarRow(
          filter: filter,
          count: store.notices(filter).length,
          child: Row(children: [
            SizedBox(width: 30, child: Icon(icon, size: 22, color: p.inkSecondary)),
            const SizedBox(width: 12),
            Flexible(child: Text(label, style: AppText.headline.copyWith(color: p.ink), overflow: TextOverflow.ellipsis)),
          ]),
        );

    List<Widget> section(String title, List<Widget> Function() content) {
      final collapsed = _collapsed.contains(title);
      return [
        Semantics(
          button: true,
          value: collapsed ? L('已收合', 'Collapsed') : L('已展開', 'Expanded'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => collapsed ? _collapsed.remove(title) : _collapsed.add(title)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 24, 6),
              child: Row(children: [
                Expanded(child: Text(title, style: AppText.title3.copyWith(fontWeight: FontWeight.w700, color: p.ink))),
                AnimatedRotation(
                  turns: collapsed ? -0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, color: p.inkSecondary),
                ),
              ]),
            ),
          ),
        ),
        if (!collapsed) ...content(),
      ];
    }

    return Paper(
      child: Stack(children: [
        ListView(
          controller: _scroll,
          padding: EdgeInsets.only(top: top, bottom: 40 + MediaQuery.paddingOf(context).bottom),
          children: [
            _SidebarRow(
              filter: NoticeFilter.mine,
              child: Row(children: [
                SizedBox(width: 30, child: Icon(Icons.star_rounded, size: 28, color: p.brand)), // 我的公告：自己訂閱、在意的
                const SizedBox(width: 12),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(L('我的公告', 'My Notices'), style: AppText.title2.copyWith(color: p.ink)),
                    Text(store.subtitle(NoticeFilter.mine), style: AppText.subheadline.copyWith(color: p.inkSecondary)),
                  ]),
                ),
              ]),
            ),
            row(NoticeFilter.all, L('全部公告', 'All Notices'), Icons.all_inbox_outlined),
            const SizedBox(height: 4),
            ...section(L('類別', 'Categories'),
                () => [for (final c in store.categories) row(NoticeFilter.tag(c), TagName.display(c), tagIcon(c))]),
            ...section(L('主題', 'Topics'),
                () => [for (final t in store.topics) row(NoticeFilter.tag(t), '#${TagName.display(t)}', tagIcon(t))]),
            ...section(L('來源', 'Sources'), () => [
                  for (final s in store.sources)
                    _SidebarRow(
                      filter: NoticeFilter.source(s),
                      count: store.notices(NoticeFilter.source(s)).length,
                      child: Row(children: [
                        SourceAvatar(source: s, size: 30),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(TagName.display(SourceStyle.name(s)),
                              style: AppText.headline.copyWith(color: p.ink), overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                ]),
          ],
        ),
        TopBar(
          solid: _scrolled,
          leading: GlassPill(
            circle: true,
            child: PillButton(icon: Icons.settings_outlined, label: L('設定', 'Settings'), onTap: () => showSettings(context)),
          ),
          trailing: const GlassPill(circle: true, child: _SchoolMenu()),
        ),
      ]),
    );
  }
}

/// 右上角：切換學校，點了跳出學校清單
class _SchoolMenu extends StatelessWidget {
  const _SchoolMenu();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final p = context.palette;
    return Semantics(
      label: L('切換學校', 'Switch School'),
      value: scope.settings.school.displayName,
      child: PopupMenuButton<String>(
        tooltip: L('切換學校', 'Switch School'),
        color: Color.lerp(p.paper, Colors.white, p.dark ? 0.08 : 0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        position: PopupMenuPosition.under,
        icon: Icon(Icons.account_balance_outlined, color: p.ink, size: 22),
        onSelected: (id) {
          if (id == scope.settings.schoolID) return;
          scope.settings.schoolID = id;
          // 換學校：時間軸回到「我的公告」（舊學校的分類在新學校可能沒有），載入那間學校的公告
          scope.router.schoolChanged();
          scope.store.schoolChanged();
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false,
            height: 32,
            child: Text(L('切換學校', 'Switch School'), style: AppText.footnote.copyWith(color: p.inkSecondary)),
          ),
          for (final s in School.all)
            CheckedPopupMenuItem<String>(
              value: s.id,
              checked: s.id == scope.settings.schoolID,
              child: Text(s.displayName, style: AppText.body.copyWith(color: p.ink)),
            ),
        ],
      ),
    );
  }
}

/// 側邊欄的一行：左邊是內容，右邊是則數的小膠囊；目前看的那一項有立體的卡片底
class _SidebarRow extends StatelessWidget {
  const _SidebarRow({required this.filter, required this.child, this.count});
  final NoticeFilter filter;
  final Widget child;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final p = context.palette;
    final selected = scope.router.filter == filter;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => scope.router.openFilter(filter), // 已經在時間軸（或正在過去）就不會再開一次
        child: Stack(children: [
          if (selected) const Positioned.fill(child: GlassCard(radius: 14)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32), // 有數字和沒數字的一樣高
              child: Row(children: [
                Expanded(child: child),
                if (count != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: p.paperChip, borderRadius: BorderRadius.circular(100)),
                    child: Text('$count', style: AppText.footnote.copyWith(fontWeight: FontWeight.w600, color: p.inkSecondary)),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

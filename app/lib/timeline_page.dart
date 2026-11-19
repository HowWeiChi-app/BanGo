// 公告時間軸，照 iPhone 版 NoticeListView.swift：
//   - 左上角膠囊：側邊欄按鈕 ｜ 標題、副標、箭頭；捲下去之後點標題會跳出「捲動到」選單，在最上面時點了沒反應
//   - 右上角膠囊：重新整理（轉完那一圈之前不能按）、搜尋
//   - 每則公告：圓形來源頭像 + 來源 + 分類，右上角相對時間，下面粗體標題、灰色摘要、圖片
//   - 最後看的那則用立體的卡片標出來；長按跳出選單（閱讀原文、複製連結、分享）

import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'images.dart';
import 'models.dart';
import 'router.dart';
import 'settings.dart';
import 'store.dart';
import 'widgets.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key, required this.filter});
  final NoticeFilter filter;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  final _scroll = ScrollController();
  final _rowKeys = <String, GlobalKey>{};
  bool _atTop = true;
  int _handledScroll = -1;
  late AppRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppScope.of(context, listen: false).router;
    _handledScroll = _router.scrollRequest;
    _router.addListener(_routerChanged);
    _scroll.addListener(() {
      final top = _scroll.offset < 1;
      if (top != _atTop) setState(() => _atTop = top);
    });
  }

  @override
  void dispose() {
    _router.removeListener(_routerChanged);
    _scroll.dispose();
    super.dispose();
  }

  /// 打開公告、或在內頁往左滑換到上面那則時：把那則捲到中間，跟內頁滑進來同時進行
  void _routerChanged() {
    if (_router.scrollRequest == _handledScroll) return;
    _handledScroll = _router.scrollRequest;
    if (_router.depth > Depth.timeline) _scrollToLastOpened();
  }

  List<Notice> _shown(NoticeStore store, AppRouter router) {
    final notices = store.notices(widget.filter);
    final q = router.searching ? router.searchQuery.trim().toLowerCase() : '';
    if (q.isEmpty) return notices;
    return notices.where((n) => n.title.toLowerCase().contains(q) || n.content.toLowerCase().contains(q)).toList();
  }

  GlobalKey _keyFor(String id) => _rowKeys.putIfAbsent(id, GlobalKey.new);

  /// 捲到上次看的那則（放在畫面中間）。那一行還沒排出來的話，先用平均高度估一個位置捲過去，排出來了再對準
  Future<void> _scrollToLastOpened() async {
    final id = _router.lastOpened;
    if (id == null || !_scroll.hasClients) return;
    final scope = AppScope.of(context, listen: false);
    final list = _shown(scope.store, _router);
    final index = list.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final row = _rowKeys[id]?.currentContext;
    if (row != null && row.mounted) {
      await Scrollable.ensureVisible(row, alignment: 0.5, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      return;
    }
    final position = _scroll.position;
    final average = list.isEmpty ? 300.0 : (position.maxScrollExtent + position.viewportDimension) / list.length;
    final guess = (average * index - position.viewportDimension / 2).clamp(0.0, position.maxScrollExtent);
    await _scroll.animateTo(guess, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    final built = _rowKeys[id]?.currentContext;
    if (built != null && built.mounted) {
      await Scrollable.ensureVisible(built, alignment: 0.5, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  /// 捲到最上面：滑動中也有效（animateTo 會先停下慣性）
  void _scrollToTop() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final router = scope.router;
    final visible = _shown(store, router);
    final p = context.palette;
    final top = MediaQuery.paddingOf(context).top + TopBar.height + 6;

    return Paper(
      child: Stack(children: [
        RefreshIndicator(
          edgeOffset: top,
          color: p.ink,
          backgroundColor: Color.lerp(p.paper, Colors.white, p.dark ? 0.1 : 0.6),
          onRefresh: store.refresh,
          child: NotificationListener<ScrollStartNotification>(
            // 往下捲就收鍵盤，方便看結果
            onNotification: (n) {
              if (n.dragDetails != null) FocusManager.instance.primaryFocus?.unfocus();
              return false;
            },
            child: ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: top, bottom: 30 + MediaQuery.paddingOf(context).bottom),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final notice = visible[i];
                return KeyedSubtree(
                  key: _keyFor(notice.id),
                  child: _TimelineRow(
                    notice: notice,
                    highlighted: notice.id == router.lastOpened || notice.id == router.rowMenu?.notice.id,
                    onTap: () {
                      if (router.rowMenu != null) return; // 剛長按打開選單，放開時不要換頁
                      FocusManager.instance.primaryFocus?.unfocus();
                      router.openNotice(notice, visible);
                    },
                  ),
                );
              },
            ),
          ),
        ),
        Positioned.fill(child: _placeholder(context, store, router, visible.isEmpty)),
        TopBar(
          solid: !_atTop || router.searching,
          center: router.searching ? const _SearchBar() : null,
          leading: GlassPill(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              PillButton(icon: Icons.view_sidebar_outlined, label: L('側邊欄', 'Sidebar'), onTap: router.back),
              const Groove(vertical: true, length: 26),
              _ScrollToMenu(
                enabled: !_atTop,
                title: store.title(widget.filter),
                subtitle: store.subtitle(widget.filter),
                canGoToLast: visible.any((n) => n.id == router.lastOpened),
                onLast: _scrollToLastOpened,
                onTop: _scrollToTop,
              ),
            ]),
          ),
          trailing: GlassPill(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const RefreshButton(),
              PillButton(icon: Icons.search, label: L('搜尋', 'Search'), onTap: () => router.setSearching(true)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _placeholder(BuildContext context, NoticeStore store, AppRouter router, bool isEmpty) {
    final p = context.palette;
    Widget message(IconData icon, String title, String text, {Widget? action}) => IgnorePointer(
        ignoring: action == null, // 只有「重試」要能按，其他的提示不擋住下拉更新
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 44, color: p.inkTertiary),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: AppText.title3.copyWith(color: p.ink)),
              const SizedBox(height: 6),
              Text(text, textAlign: TextAlign.center, style: AppText.callout.copyWith(color: p.inkSecondary)),
              if (action != null) ...[const SizedBox(height: 16), action],
            ]),
          ),
        ));
    if (store.data == null && store.isLoading) {
      return IgnorePointer(child: Center(child: CircularProgressIndicator(color: p.inkSecondary, strokeWidth: 2.5)));
    }
    if (store.data == null && store.errorMessage != null) {
      return message(Icons.wifi_off, L('無法載入公告', 'Can’t Load Notices'), store.errorMessage!,
            action: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: p.brand),
              onPressed: store.refresh,
              child: Text(L('重試', 'Retry')),
            ));
    }
    if (store.data != null && isEmpty) {
      final q = router.searching ? router.searchQuery.trim() : '';
      if (q.isNotEmpty) return message(Icons.search_off, L('找不到「$q」', 'No Results for “$q”'), L('換個關鍵字試試', 'Try another keyword'));
      final mine = widget.filter == NoticeFilter.mine;
      return message(
        Icons.inbox_outlined,
        mine && store.subscribed.isEmpty ? L('還沒有訂閱任何類別', 'No Subscriptions Yet') : L('沒有符合的公告', 'No Matching Notices'),
        mine ? L('到「設定」打開想看的類別', 'Turn on categories in Settings') : L('下拉可以重新整理', 'Pull down to refresh'),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 標題和箭頭：捲下去之後點了跳出「捲動到」選單（上次讀到的地方／最上面）
class _ScrollToMenu extends StatelessWidget {
  const _ScrollToMenu({
    required this.enabled,
    required this.title,
    required this.subtitle,
    required this.canGoToLast,
    required this.onLast,
    required this.onTop,
  });
  final bool enabled;
  final String title;
  final String subtitle;
  final bool canGoToLast;
  final VoidCallback onLast;
  final VoidCallback onTop;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    PopupMenuItem<int> item(int value, IconData icon, String title, String text, bool on) => PopupMenuItem<int>(
          value: value,
          enabled: on,
          child: Row(children: [
            Icon(icon, size: 20, color: on ? p.ink : p.inkTertiary),
            const SizedBox(width: 12),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: AppText.body.copyWith(color: on ? p.ink : p.inkTertiary)),
                Text(text, style: AppText.footnote.copyWith(color: p.inkTertiary)),
              ]),
            ),
          ]),
        );
    return Semantics(
      button: true,
      enabled: enabled,
      label: L('捲動到', 'Scroll To'),
      child: IgnorePointer(
        ignoring: !enabled, // 已經在最上面：點了沒反應
        child: PopupMenuButton<int>(
          tooltip: '',
          position: PopupMenuPosition.under,
          color: Color.lerp(p.paper, Colors.white, p.dark ? 0.08 : 0.6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          onSelected: (v) => v == 0 ? onLast() : onTop(),
          itemBuilder: (_) => [
            PopupMenuItem<int>(
              enabled: false,
              height: 30,
              child: Text(L('捲動到', 'Scroll To'), style: AppText.footnote.copyWith(color: p.inkSecondary)),
            ),
            item(0, Icons.subdirectory_arrow_right, L('上次讀到的地方', 'Where I Left Off'),
                L('回到剛剛看的那則', 'Back to the last notice you read'), canGoToLast),
            item(1, Icons.vertical_align_top, L('最上面', 'Top'), L('回到最新的公告', 'Back to the newest notice'), true),
          ],
          child: Padding(
            padding: const EdgeInsets.only(left: 11, right: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.headline.copyWith(color: p.ink, height: 1.15)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppText.footnote.copyWith(fontWeight: FontWeight.w500, color: p.inkSecondary, height: 1.15)),
                ]),
              ),
              const SizedBox(width: 10),
              // 在最上面時是淡灰色，捲下去才變深
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.arrow_circle_up_outlined,
                    key: ValueKey(enabled), size: 22, color: enabled ? p.ink : p.inkTertiary),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 一則公告。按下去立刻亮起卡片，按住超過 0.2 秒才往下沉；長按 0.4 秒跳出選單
class _TimelineRow extends StatefulWidget {
  const _TimelineRow({required this.notice, required this.highlighted, required this.onTap});
  final Notice notice;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_TimelineRow> createState() => _TimelineRowState();
}

class _TimelineRowState extends State<_TimelineRow> {
  bool _pressed = false;
  bool _sunk = false;
  int _pressId = 0;

  void _down() {
    final id = ++_pressId;
    setState(() => _pressed = true);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted && _pressed && _pressId == id) setState(() => _sunk = true);
    });
  }

  void _up() {
    if (_pressed || _sunk) setState(() => _pressed = _sunk = false);
  }

  void _longPress() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    HapticFeedback.mediumImpact();
    final origin = box.localToGlobal(Offset.zero);
    AppScope.of(context, listen: false).router.showRowMenu(RowMenuRequest(widget.notice, origin & box.size));
    _up();
  }

  @override
  Widget build(BuildContext context) {
    final card = _pressed || widget.highlighted;
    return Semantics(
      button: true,
      customSemanticsActions: {
        CustomSemanticsAction(label: L('更多', 'More')): _longPress,
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _down(),
        onTapUp: (_) => _up(),
        onTapCancel: _up,
        onTap: widget.onTap,
        onLongPress: _longPress,
        onLongPressEnd: (_) => _up(),
        // 每一則外面留 14、卡片裡面再留 16，文字離螢幕邊 30；分隔線在兩則正中間，離螢幕邊 32
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: AnimatedScale(
              scale: _sunk ? 0.97 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: Stack(children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: card ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const GlassCard(),
                  ),
                ),
                Padding(padding: const EdgeInsets.all(16), child: NoticeRow(notice: widget.notice)),
              ]),
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Groove(length: double.infinity)),
        ]),
      ),
    );
  }
}

/// 一則公告的內容：頭像、來源、分類、時間、標題、摘要、圖片
class NoticeRow extends StatelessWidget {
  const NoticeRow({super.key, required this.notice});
  final Notice notice;

  String get _subtitle {
    final parts = notice.tags.map(TagName.displayTag).toList();
    if (notice.isUrgent) parts.insert(0, L('緊急', 'Urgent'));
    if (!notice.forStudents) parts.add(L('跟學生無關', 'Not for students'));
    return parts.isEmpty ? AppSettings.shared.school.displayName : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Opacity(
      opacity: notice.forStudents ? 1 : 0.5, // 跟學生無關的公告整則淡一點
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SourceAvatar(source: notice.source, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(TagName.display(SourceStyle.name(notice.source)), style: AppText.headline.copyWith(color: p.ink)),
                const SizedBox(height: 1),
                Text(_subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.subheadline.copyWith(color: p.inkTertiary)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(notice.relativeTime(), style: AppText.subheadline.copyWith(color: p.inkTertiary)),
          ),
        ]),
        const SizedBox(height: 12),
        Text(notice.title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppText.headline.copyWith(color: notice.isUrgent ? Colors.red : p.ink)),
        if (notice.summary.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(notice.summary, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppText.bodyMedium.copyWith(color: p.inkSecondary)),
        ],
        if (notice.imageUri != null) ...[
          const SizedBox(height: 12),
          NoticeImage(url: notice.imageUri!, cropTall: true),
        ],
      ]),
    );
  }
}

/// 右上角的重新整理：更新中箭頭一直轉，更新完轉完這一圈才停；停好之前都不能按，箭頭變淡
class RefreshButton extends StatefulWidget {
  const RefreshButton({super.key});

  @override
  State<RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<RefreshButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _finishing = false; // 更新完了，箭頭還在轉最後那一圈
  bool _wasLoading = false;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _sync(bool loading) {
    if (loading == _wasLoading) return;
    _wasLoading = loading;
    if (loading) {
      _finishing = true; // 開始轉就鎖住
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      // 不要一下跳回原位：從現在的角度轉完這一圈，慢慢停下來
      final rest = 1 - _spin.value;
      _spin
          .animateTo(1, duration: Duration(milliseconds: math.max(150, (rest * 900 * 1.4).round())), curve: Curves.easeOut)
          .whenComplete(() {
        if (!mounted) return;
        _spin.value = 0;
        setState(() => _finishing = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final p = context.palette;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(store.isLoading);
    });
    final locked = store.isLoading || _finishing;
    return IgnorePointer(
      ignoring: locked,
      child: PillButton(
        icon: Icons.refresh,
        label: L('重新整理', 'Refresh'),
        onTap: locked ? null : store.refresh,
        child: RotationTransition(
          turns: _spin,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(Icons.refresh, key: ValueKey(locked), size: 24, color: locked ? p.inkTertiary : p.ink),
          ),
        ),
      ),
    );
  }
}

/// 搜尋列：蓋在工具列的位置（工具列的按鈕這時候收起來了），列表完全不動
class _SearchBar extends StatefulWidget {
  const _SearchBar();

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  late final _controller = TextEditingController(text: AppScope.of(context, listen: false).router.searchQuery);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = AppScope.of(context).router;
    final p = context.palette;
    // 從搜尋結果點進公告就收鍵盤：不然回來時鍵盤又跳出來
    if (router.depth != Depth.timeline && _focus.hasFocus) _focus.unfocus();
    return Row(children: [
      Expanded(
        child: GlassPill(
          child: Row(children: [
            const SizedBox(width: 14),
            Icon(Icons.search, color: p.inkSecondary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                cursorColor: p.brand,
                style: AppText.body.copyWith(color: p.ink),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: L('搜尋標題和內文', 'Search titles and text'),
                  hintStyle: AppText.body.copyWith(color: p.inkTertiary),
                ),
                onChanged: router.setQuery,
              ),
            ),
            if (router.searchQuery.isNotEmpty)
              PillButton(
                icon: Icons.cancel,
                label: L('清除', 'Clear'),
                child: Icon(Icons.cancel, size: 20, color: p.inkTertiary),
                onTap: () {
                  _controller.clear();
                  router.setQuery('');
                },
              )
            else
              const SizedBox(width: 14),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      GlassPill(
        circle: true,
        child: PillButton(
          icon: Icons.close,
          label: L('關閉搜尋', 'Close Search'),
          onTap: () {
            _focus.unfocus(); // 先收鍵盤再收搜尋列
            router.setSearching(false);
          },
        ),
      ),
    ]);
  }
}

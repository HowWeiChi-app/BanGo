// 蓋在整個 App 上面的兩層：長按公告的選單、短暫出現的提示（照 iPhone 版 RowMenu.swift）

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'app_scope.dart';
import 'models.dart';
import 'router.dart';
import 'settings.dart';
import 'widgets.dart';

/// 長按公告跳出的選單：閱讀原文、複製連結、分享。放在那則公告的下面（下面放不下就放上面）
class RowMenuLayer extends StatefulWidget {
  const RowMenuLayer({super.key});

  @override
  State<RowMenuLayer> createState() => _RowMenuLayerState();
}

class _RowMenuLayerState extends State<RowMenuLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  RowMenuRequest? _shown;

  static const _gap = 8.0;
  static const _width = 240.0;
  static const _height = 3 * 46.0 + 2;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _close([VoidCallback? then]) {
    if (_t.status == AnimationStatus.reverse || _t.isDismissed) return;
    final router = AppScope.of(context, listen: false).router;
    _t.animateBack(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut).whenComplete(() {
      router.showRowMenu(null);
      then?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = AppScope.of(context).router;
    final menu = router.rowMenu;
    if (menu != null && !identical(menu, _shown)) {
      _shown = menu;
      _t.animateTo(1, duration: const Duration(milliseconds: 350), curve: Curves.easeOutBack);
    }
    if (menu == null) {
      _shown = null;
      return const SizedBox.shrink();
    }
    final size = MediaQuery.sizeOf(context);
    final below = menu.rect.bottom + _gap + _height < size.height - 40;
    final x = (menu.rect.left + 14).clamp(16.0, size.width - _width - 16);
    final y = below ? menu.rect.bottom + _gap : menu.rect.top - _gap - _height;

    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value;
        return Stack(children: [
          // 手指一碰到選單外面就收（不用等放開）
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _close(),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.12 * t.clamp(0.0, 1.0))),
            ),
          ),
          Positioned(
            left: x,
            top: y,
            width: _width,
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.3 + 0.7 * t,
                alignment: below ? Alignment.topLeft : Alignment.bottomLeft,
                child: _panel(context, menu.notice),
              ),
            ),
          ),
        ]);
      },
    );
  }

  Widget _panel(BuildContext context, Notice notice) {
    final p = context.palette;
    final router = AppScope.of(context, listen: false).router;
    final url = Uri.tryParse(notice.url);
    Widget item(String title, IconData icon, VoidCallback action) => _MenuItem(
          title: title,
          icon: icon,
          onTap: () => _close(action),
        );
    Widget divider() => Padding(padding: const EdgeInsets.only(left: 16), child: Container(height: 1, color: p.edgeDark));
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: Color.lerp(p.paper, Colors.white, p.dark ? 0.1 : 0.7),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.edgeDark),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            item(L('閱讀原文', 'Open Original'), Icons.explore_outlined, () => openWeb(notice.url)),
            divider(),
            item(L('複製連結', 'Copy Link'), Icons.link, () {
              Clipboard.setData(ClipboardData(text: notice.url));
              router.showToast(L('已複製連結', 'Link Copied'));
            }),
            divider(),
            item(L('分享…', 'Share…'), Icons.ios_share, () {
              if (url != null) SharePlus.instance.share(ShareParams(uri: url, subject: notice.title));
            }),
          ]),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.title, required this.icon, required this.onTap});
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      highlightColor: p.ink.withValues(alpha: 0.08),
      splashColor: Colors.transparent,
      child: SizedBox(
        height: 46,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Text(title, style: AppText.body.copyWith(color: p.ink))),
            Icon(icon, size: 20, color: p.inkSecondary),
          ]),
        ),
      ),
    );
  }
}

/// 畫面下面短暫出現的提示（例如「已複製連結」）：一顆膠囊從下面浮上來，1.5 秒後收回去
class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final router = AppScope.of(context).router;
    final p = context.palette;
    final text = router.toast;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: 12 + MediaQuery.paddingOf(context).bottom),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(a), child: child),
            ),
            child: text == null
                ? const SizedBox.shrink()
                : GlassPill(
                    key: ValueKey(text),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle, size: 20, color: p.ink),
                        const SizedBox(width: 8),
                        Text(text, style: AppText.subheadline.copyWith(fontWeight: FontWeight.w600, color: p.ink)),
                      ]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

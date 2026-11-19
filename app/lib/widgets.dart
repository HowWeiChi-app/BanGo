// 各頁共用的小元件：字級、刻痕分隔線、玻璃卡片、工具列的玻璃膠囊、來源頭像、工具列、提示。
// 樣子照 iPhone 版（Theme.swift）：米白紙張、像刻出來的分隔線、立體的選取卡片。

import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'settings.dart';

/// 字級，照 iOS 的動態字級（App 一律用這幾種，換字體時一起換）
abstract final class AppText {
  static const largeTitle = TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.2);
  static const title2 = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  static const title3 = TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
  static const headline = TextStyle(fontSize: 17, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 17, fontWeight: FontWeight.w400);
  static const bodyMedium = TextStyle(fontSize: 17, fontWeight: FontWeight.w500);
  static const callout = TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
  static const subheadline = TextStyle(fontSize: 15, fontWeight: FontWeight.w500);
  static const footnote = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
}

/// 分隔線：1px 暗線 + 1px 亮線，看起來像在紙上刻了一道溝
class Groove extends StatelessWidget {
  const Groove({super.key, this.vertical = false, this.length});
  final bool vertical;
  final double? length;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lines = [Container(color: p.edgeDark), Container(color: p.grooveLight)];
    return ExcludeSemantics(
      child: vertical
          ? SizedBox(width: 2, height: length, child: Row(children: [for (final l in lines) SizedBox(width: 1, child: l)]))
          : SizedBox(height: 2, width: length, child: Column(children: [for (final l in lines) SizedBox(height: 1, child: l)])),
    );
  }
}

/// 選中的卡片：比底色亮一點，外圈 1px 暗線、內圈 1px 亮線（左下角淡掉），外面一圈很淡的陰影
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, this.radius = 18});
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return CustomPaint(painter: _GlassCardPainter(p, radius));
  }
}

class _GlassCardPainter extends CustomPainter {
  _GlassCardPainter(this.p, this.radius);
  final Palette p;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(outer.shift(const Offset(0, 1)),
        Paint()..color = Colors.black.withValues(alpha: 0.08)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(outer, Paint()..color = p.cardFill);
    // 內圈亮線：只有左下角那一塊變暗
    final inner = outer.deflate(1.5);
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.radial(rect.bottomLeft, 90, [p.cardFill, p.cardHighlight], [10 / 90, 1]),
    );
    canvas.drawRRect(outer.deflate(0.5), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = p.edgeDark);
  }

  @override
  bool shouldRepaint(_GlassCardPainter old) => old.p != p || old.radius != radius;
}

/// 工具列上的玻璃膠囊（Android 沒有 iOS 的 Liquid Glass，用模糊 + 半透明紙張色 + 細邊做出接近的樣子）
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.child, this.circle = false});
  final Widget child;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(circle ? 100 : 22);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.dark ? 0.35 : 0.08), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 44,
            constraints: const BoxConstraints(minWidth: 44),
            decoration: BoxDecoration(
              color: Color.lerp(p.paper, p.dark ? Colors.white : Colors.white, p.dark ? 0.08 : 0.5)!.withValues(alpha: 0.82),
              borderRadius: radius,
              border: Border.all(color: p.dark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.06)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 膠囊裡的一顆圖示按鈕
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.icon, required this.label, this.onTap, this.dimmed = false, this.child});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool dimmed;
  final Widget? child; // 自己畫的圖示（例如轉圈的箭頭）

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: child ?? Icon(icon, size: 22, color: dimmed ? p.inkTertiary : p.ink)),
        ),
      ),
    );
  }
}

/// 圓形的來源頭像，像 RSS 閱讀器裡每個網站的小 icon
class SourceAvatar extends StatelessWidget {
  const SourceAvatar({super.key, required this.source, this.size = 40});
  final String source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.dark ? Color.lerp(p.paper, Colors.white, 0.1) : Colors.white,
          border: Border.all(color: p.ink.withValues(alpha: 0.08)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), offset: const Offset(0, 1))],
        ),
        child: Icon(SourceStyle.icon(source), size: size * 0.48, color: SourceStyle.color(context, source)),
      ),
    );
  }
}

/// 每一頁最上面的工具列：左右兩顆玻璃膠囊，浮在內容上面。
/// 捲下去後，工具列後面是一條模糊的紙張底，下緣有硬邊的光影（亮線、暗線、往下淡掉的陰影）
class TopBar extends StatelessWidget {
  const TopBar({super.key, this.leading, this.trailing, this.solid = false, this.center});
  final Widget? leading;
  final Widget? trailing;
  final Widget? center; // 搜尋時蓋住整排
  final bool solid; // 內容捲到工具列底下了：畫出模糊底和硬邊

  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final top = MediaQuery.paddingOf(context).top;
    return SizedBox(
      height: top + height + 14,
      child: Stack(
        children: [
          // 模糊底和硬邊
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: top + height + 14,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: solid ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Column(
                  children: [
                    SizedBox(
                      height: top + height,
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(color: Color.lerp(p.paper, Colors.black, p.dark ? 0.2 : 0)!.withValues(alpha: 0.85)),
                        ),
                      ),
                    ),
                    // 亮線、暗線、陰影，到左右兩邊淡掉，像光從上面打下來
                    // dstIn：漸層只決定透明度。預設的 modulate 會把顏色也乘上黑色，亮線就變成一條黑線
                    ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (r) => const LinearGradient(
                        colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                        stops: [0, 0.16, 0.84, 1],
                      ).createShader(r),
                      child: Column(children: [
                        Container(height: 1, color: p.grooveLight),
                        Container(height: 1, color: p.edgeShadow),
                        Container(
                          height: 11,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black.withValues(alpha: p.dark ? 0.23 : 0.06), Colors.transparent],
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: top + 8,
            height: 44,
            child: center ??
                Row(children: [
                  if (leading != null) leading!,
                  const Spacer(),
                  if (trailing != null) trailing!,
                ]),
          ),
        ],
      ),
    );
  }
}

/// 在 App 裡打開網頁（Chrome 自訂分頁）；不行的話用外部瀏覽器
Future<void> openWeb(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 公告列表、內頁的紙張底色（不透明：換頁時才蓋得住後面那頁）
class Paper extends StatelessWidget {
  const Paper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(color: context.palette.paper, child: child);
}

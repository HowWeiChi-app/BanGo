// 三層頁面左右並排的容器：側邊欄 ｜ 時間軸 ｜ 內頁。跟 iPhone 版 PageStack.swift 同一套規則（照 Reeder 做的）：
//   - 同一個左右拖曳手勢處理兩個方向：往右拉，上面那頁跟著手指滑走，露出上一層；
//     往左拉（側邊欄，或內頁有比較新的那則時），下一頁從右邊跟著手指拉進來。
//   - 被蓋住的那頁往左移 30%、變暗一點；移動中的那頁有圓角、外面一圈 1px 的邊、陰影。
//   - 放手時，拉的距離加上甩的速度超過畫面三分之一就換頁，不然彈回去。
//
// 位置用一個數字 pos 表示：1 = 停在時間軸，1.5 = 時間軸往右拉開一半，2.3 = 內頁上面那則拉進來 30%。

import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'article_page.dart';
import 'router.dart';
import 'settings.dart';
import 'sidebar_page.dart';
import 'timeline_page.dart';

class PageStack extends StatefulWidget {
  const PageStack({super.key});

  @override
  State<PageStack> createState() => _PageStackState();
}

class _PageStackState extends State<PageStack> with SingleTickerProviderStateMixin {
  late final AnimationController _pos;
  late AppRouter _router;
  int _shownDepth = Depth.timeline; // pos 現在要停的那一層
  String? _shownArticle;

  // 拖曳中
  int? _direction; // 1 = 往右拉（回上一層），-1 = 往左拉（下一頁）
  bool _ignoreDrag = false; // 這次拖曳的方向不能拉，整次不理
  double _translation = 0;
  bool _settling = false;
  bool _preload = false; // 內頁上面那則先排好了沒

  @override
  void initState() {
    super.initState();
    _router = AppScope.of(context, listen: false).router;
    _pos = AnimationController.unbounded(vsync: this, value: _router.depth.toDouble());
    _shownDepth = _router.depth;
    _router.addListener(_routerChanged);
  }

  @override
  void dispose() {
    _router.removeListener(_routerChanged);
    _pos.dispose();
    super.dispose();
  }

  /// 不是拖曳造成的換頁（點了公告、按返回）：用動畫滑到新的那一層，不彈跳，跟 Reeder 一樣乾脆
  void _routerChanged() {
    final articleId = _router.article?.id;
    if (articleId != _shownArticle) {
      _shownArticle = articleId;
      // 上面那則等換頁動畫跑完才排：不然動畫一開始要同時排兩則內文，會卡一下
      _preload = false;
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted && _router.article?.id == articleId) setState(() => _preload = true);
      });
    }
    if (_router.depth != _shownDepth && !_settling && _direction == null) {
      _shownDepth = _router.depth;
      _pos.animateTo(_shownDepth.toDouble(), duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic)
          .whenComplete(() => _router.pageSettled());
    }
    setState(() {});
  }

  // MARK: 拖曳

  void _dragStart(DragStartDetails d) {
    _direction = null;
    _ignoreDrag = _settling || _router.zoomed != null || _router.rowMenu != null;
    _translation = 0;
  }

  void _dragUpdate(DragUpdateDetails d, double width) {
    if (_ignoreDrag) return;
    _translation += d.delta.dx;
    if (_direction == null) {
      if (_translation == 0) return;
      final towardRight = _translation > 0;
      // 方向在開始時就決定了：往右要有上一層，往左要有下一頁
      if (towardRight ? _router.depth <= Depth.sidebar : !_router.hasForward) {
        _ignoreDrag = true;
        return;
      }
      _direction = towardRight ? 1 : -1;
      if (!towardRight) setState(() {}); // 往左：把上面那則排出來
    }
    final depth = _router.depth.toDouble();
    // 拉過頭到另一邊就停在 0
    _pos.value = _direction == 1
        ? depth - (_translation / width).clamp(0.0, 1.0)
        : depth + (-_translation / width).clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails d, double width) {
    final direction = _direction;
    _direction = null;
    if (_ignoreDrag || direction == null) return;
    final projected = _translation + d.velocity.pixelsPerSecond.dx * 0.15;
    final change = direction == 1 ? projected > width / 3 : -projected > width / 3;
    final depth = _router.depth;
    final target = change ? depth - direction : depth;
    _settling = true;
    _pos.animateTo(target.toDouble(), duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic).whenComplete(() {
      // 頁面已經在新的位置上了，換成新的那一層時位置不變，所以看不出有換
      if (change) {
        if (direction == 1) {
          _router.settle(depth - 1);
        } else {
          _router.settleForward();
        }
      }
      _shownDepth = _router.depth;
      _pos.value = _router.depth.toDouble();
      _settling = false;
      setState(() {});
    });
  }

  // MARK: 位置

  /// 第 index 層的水平位置
  static double _x(int index, double pos, double width) =>
      index <= pos ? -0.3 * width * (pos - index).clamp(0.0, 1.0) : width * (index - pos).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final router = AppScope.of(context).router;
    final article = router.article;
    final newer = router.newer;
    final showIncoming = article != null && newer != null && (_preload || _direction == -1);

    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final pages = <(int, Widget)>[
        (Depth.sidebar, const SidebarPage(key: ValueKey('sidebar'))),
        (Depth.timeline, TimelinePage(key: ValueKey(('timeline', router.filter)), filter: router.filter)),
        // 內頁用公告的網址當身分：往左拉進來的那則放手換過去時，是同一個畫面，不會重排
        if (article != null) (Depth.article, ArticlePage(key: ValueKey(article.id), notice: article)),
        if (showIncoming) (Depth.article + 1, ArticlePage(key: ValueKey(newer.id), notice: newer)),
      ];
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _dragStart,
        onHorizontalDragUpdate: (d) => _dragUpdate(d, width),
        onHorizontalDragEnd: (d) => _dragEnd(d, width),
        onHorizontalDragCancel: () => _dragEnd(DragEndDetails(), width),
        child: AnimatedBuilder(
          animation: _pos,
          builder: (context, _) {
            final pos = _pos.value;
            final moving = _pos.isAnimating || _direction != null || _settling;
            // 整個被蓋住、或整個在右邊外面的頁面不畫（狀態留著，回來時捲動位置都還在）
            final hiddenBelow = pos == pos.floorToDouble() ? pos : pos.ceilToDouble() - 1;
            return Stack(children: [
              for (final (index, page) in pages)
                _PageFrame(
                  key: page.key,
                  x: _x(index, pos, width),
                  width: width,
                  hidden: index < hiddenBelow,
                  interactive: index == router.depth && !moving,
                  child: page,
                ),
            ]);
          },
        ),
      );
    });
  }
}

/// 把一頁放到 x 的位置。移動中的頁面：直角、外面一圈 1px 的邊、陰影；被蓋住的頁面變暗
class _PageFrame extends StatelessWidget {
  const _PageFrame({super.key, required this.x, required this.width, required this.hidden, required this.interactive, required this.child});
  final double x;
  final double width;
  final bool hidden;
  final bool interactive;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final moving = x > 0.5 && x < width - 0.5;
    final offscreen = x >= width - 0.5 || hidden;
    final dim = x < 0 ? 0.1 * (-x / (0.3 * width)).clamp(0.0, 1.0) : 0.0;

    Widget page = IgnorePointer(ignoring: !interactive, child: child);
    if (dim > 0) {
      page = Stack(fit: StackFit.expand, children: [
        page,
        IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: dim))),
      ]);
    }
    if (moving) {
      // 陰影：沿著整個頁面一圈（Reeder：深色黑 40%、淺色黑 15%，半徑 5）；1px 的邊畫在最外圈
      page = Container(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: p.pageShadow, blurRadius: 5)]),
        foregroundDecoration: BoxDecoration(border: Border.all(color: p.pageRim)),
        child: page,
      );
    }
    return Positioned.fill(
      child: Offstage(
        offstage: offscreen,
        child: Transform.translate(
          // 對齊螢幕像素：慢慢拉的時候位移停在像素和像素之間，文字會一格一格地抖
          offset: Offset((x * ratio).roundToDouble() / ratio, 0),
          child: ExcludeSemantics(excluding: !interactive, child: page),
        ),
      ),
    );
  }
}

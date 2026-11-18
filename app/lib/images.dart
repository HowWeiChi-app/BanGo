// 公告裡的圖片，和點了放大的那一層（照 iPhone 版 ImageViews.swift）：
//   - 時間軸上太長的直式圖最多顯示到 3:4，下面多的裁掉；內頁顯示完整的圖
//   - 點了從原本的位置放大到整個畫面；好幾張（PDF 的每一頁）時左右滑換張，上面顯示「2 / 5」
//   - 兩指放大、雙擊放大；點一下或往下拉就關掉，縮回原本的位置

import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'router.dart';
import 'settings.dart';
import 'widgets.dart';

/// 把 ZoomImage（網路圖片或畫好的 PDF 頁）畫出來
Widget zoomImageWidget(ZoomImage image, {BoxFit fit = BoxFit.contain, Alignment alignment = Alignment.center}) {
  final raw = image.raw;
  if (raw is ui.Image) return RawImage(image: raw, fit: fit, alignment: alignment, filterQuality: FilterQuality.medium);
  return Image(
    image: image.provider! as ImageProvider,
    fit: fit,
    alignment: alignment,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
  );
}

/// 一張網路圖片：圓角、細邊，點了放大
class NoticeImage extends StatefulWidget {
  const NoticeImage({super.key, required this.url, this.cropTall = false});
  final Uri url;
  final bool cropTall;

  @override
  State<NoticeImage> createState() => _NoticeImageState();
}

class _NoticeImageState extends State<NoticeImage> {
  static final _ratios = <String, double>{}; // 量過的寬高比：回到時間軸時不用等圖載完才知道多高

  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _failed = false;

  ImageProvider get _preview => ResizeImage(NetworkImage(widget.url.toString()), width: 1200, policy: ResizeImagePolicy.fit);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ratios.containsKey(widget.url.toString()) || _stream != null) return;
    _stream = _preview.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      final r = info.image.width / info.image.height;
      if (mounted && r > 0) setState(() => _ratios[widget.url.toString()] = r);
    }, onError: (_, _) {
      if (mounted) setState(() => _failed = true);
    });
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  void _zoom() {
    final ratio = _ratios[widget.url.toString()];
    final box = context.findRenderObject() as RenderBox?;
    if (ratio == null || box == null) return;
    final full = NetworkImage(widget.url.toString());
    AppScope.of(context, listen: false).router.zoom(ZoomRequest(
          pages: [ZoomPage(ratio: ratio, preview: ZoomImage(provider: _preview), large: () async => ZoomImage(provider: full))],
          start: 0,
          from: box.localToGlobal(Offset.zero) & box.size,
          sourceId: this,
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink(); // 圖片壞掉就不顯示，不留一個空框
    final p = context.palette;
    final router = AppScope.of(context).router;
    final ratio = _ratios[widget.url.toString()];
    final shown = ratio == null ? 16 / 9 : (widget.cropTall && ratio < 3 / 4 ? 3 / 4 : ratio);
    return Semantics(
      image: true,
      button: true,
      label: L('圖片', 'Image'),
      child: GestureDetector(
        onTap: _zoom,
        child: Opacity(
          opacity: router.zoomed?.sourceId == this ? 0 : 1, // 放大時把原本的藏起來，看起來像圖片被拿起來
          child: AspectRatio(
            aspectRatio: shown,
            child: Container(
              foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.edgeDark)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: p.paperChip,
                  child: ratio == null
                      ? const SizedBox.expand()
                      : Image(image: _preview, fit: BoxFit.cover, alignment: Alignment.topCenter, width: double.infinity),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 放大的那一層：蓋在所有頁面上面
class ZoomLayer extends StatefulWidget {
  const ZoomLayer({super.key});

  @override
  State<ZoomLayer> createState() => _ZoomLayerState();
}

class _ZoomLayerState extends State<ZoomLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  ZoomRequest? _request;
  PageController? _pages;
  int _index = 0;
  double _drag = 0; // 往下拉關掉
  bool _closing = false;
  final _zoomedIn = ValueNotifier(false); // 有放大時不能左右換張、不能往下拉

  @override
  void dispose() {
    _t.dispose();
    _pages?.dispose();
    _zoomedIn.dispose();
    super.dispose();
  }

  void _open(ZoomRequest request) {
    _request = request;
    _index = request.start;
    _pages?.dispose();
    _pages = PageController(initialPage: request.start);
    _drag = 0;
    _closing = false;
    _t.forward(from: 0);
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    final router = AppScope.of(context, listen: false).router;
    _t.reverse().whenComplete(() {
      if (!mounted) return;
      _request = null;
      _closing = false; // 關好了：下一次點圖片才打得開（沒清掉的話，之後點圖片只會把原圖藏起來，放大層不出現）
      router.zoom(null);
    });
    setState(() {});
  }

  /// 飛出來／飛回去的那張圖。分成兩個框一起變：
  ///   - 看得到的範圍：從列表裡那個框（時間軸上太長的圖只顯示上面 3:4）變成全螢幕上的位置
  ///   - 圖片本身：一直保持原本的寬高比，從「寬度跟列表裡一樣、貼齊上緣」變成全螢幕上的大小
  /// 這樣縮回去的最後一格，跟列表裡的樣子一模一樣，不會跳一下。往下拉關掉的，從手放開的位置開始縮
  Widget _flyingImage(ZoomRequest shown, ZoomPage page, Size screen, double t) {
    final from = shown.from;
    final target = _fitted(page.ratio, screen).shift(Offset(0, _drag));
    final clip = Rect.lerp(from, target, t)!;
    final image = Rect.lerp(Rect.fromLTWH(from.left, from.top, from.width, from.width / page.ratio), target, t)!;
    return Stack(children: [
      Positioned.fromRect(
        rect: clip,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12 * (1 - t)),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fromRect(
              rect: image.shift(-clip.topLeft),
              child: ColoredBox(
                color: Colors.white,
                child: page.preview == null ? const SizedBox.expand() : zoomImageWidget(page.preview!, fit: BoxFit.fill),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  /// 圖片在畫面上放到最大（保持寬高比）的位置
  static Rect _fitted(double ratio, Size screen) {
    var w = screen.width, h = w / ratio;
    if (h > screen.height) {
      h = screen.height;
      w = h * ratio;
    }
    return Rect.fromLTWH((screen.width - w) / 2, (screen.height - h) / 2, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final router = AppScope.of(context).router;
    final request = router.zoomed;
    if (request != null && !identical(request, _request) && !_closing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _open(request));
      });
    }
    final shown = _request;
    if (shown == null) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        // 打開和關閉都是一開始快、最後慢慢停好（關閉時不能直接倒著播，不然會越縮越快、最後撞回原位）
        final t = _closing ? 1 - Curves.easeOutCubic.transform(1 - _t.value) : Curves.easeOutCubic.transform(_t.value);
        final dragFade = (1 - _drag.abs() / 400).clamp(0.0, 1.0);
        final flying = _t.isAnimating && _index == shown.start; // 從原本的位置飛出來／飛回去
        final page = shown.pages[_index];
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _close,
              child: ColoredBox(color: Colors.black.withValues(alpha: t * dragFade)),
            ),
          ),
          if (flying)
            Positioned.fill(child: _flyingImage(shown, page, screen, t))
          else
            Positioned.fill(
              child: Opacity(
                opacity: _closing ? t : 1, // 換到別張再關：直接淡掉
                child: Transform.translate(
                  offset: Offset(0, _drag),
                  child: GestureDetector(
                    onVerticalDragUpdate: (d) {
                      if (!_zoomedIn.value) setState(() => _drag += d.delta.dy);
                    },
                    onVerticalDragEnd: (d) {
                      if (_drag.abs() > 120 || d.velocity.pixelsPerSecond.dy.abs() > 900) {
                        _close();
                      } else {
                        setState(() => _drag = 0);
                      }
                    },
                    child: ValueListenableBuilder(
                      valueListenable: _zoomedIn,
                      builder: (context, zoomedIn, _) => PageView.builder(
                        controller: _pages,
                        physics: zoomedIn ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                        itemCount: shown.pages.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (context, i) => _GalleryPage(
                          page: shown.pages[i],
                          onTap: _close,
                          onZoomChanged: (z) => _zoomedIn.value = z,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (shown.pages.length > 1)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 12,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: t * dragFade,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(100)),
                      child: Text('${_index + 1} / ${shown.pages.length}',
                          style: AppText.subheadline.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

/// 相簿的一張：先顯示小圖，清楚的大圖好了再換上去；兩指或雙擊放大
class _GalleryPage extends StatefulWidget {
  const _GalleryPage({required this.page, required this.onTap, required this.onZoomChanged});
  final ZoomPage page;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  final _controller = TransformationController();
  ZoomImage? _large;
  TapDownDetails? _doubleTap;

  @override
  void initState() {
    super.initState();
    widget.page.large().then((image) {
      if (mounted && image != null) setState(() => _large = image);
    });
    _controller.addListener(() => widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.01));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_controller.value.getMaxScaleOnAxis() > 1.01) {
      _controller.value = Matrix4.identity();
    } else {
      final at = _doubleTap?.localPosition ?? Offset.zero;
      _controller.value = Matrix4.identity()
        ..translateByDouble(-at.dx * 1.5, -at.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _large ?? widget.page.preview;
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTap = d,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _controller,
        maxScale: 5,
        child: Center(
          child: AspectRatio(
            aspectRatio: widget.page.ratio,
            child: ColoredBox(
              color: Colors.white,
              child: image == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : SizedBox.expand(child: zoomImageWidget(image)),
            ),
          ),
        ),
      ),
    );
  }
}

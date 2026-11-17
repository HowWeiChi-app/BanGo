// 公告裡的圖片：照原比例顯示、點了直接在畫面上放大。
//
// 放大不是打開新畫面：App 最上層蓋一層（ImageOverlay），黑底淡入，
// 圖片從它在列表裡的位置和大小，用動畫變大到全螢幕；關閉時再縮回原位。

import ImageIO
import SwiftUI
import UIKit

/// 下載、縮小、暫存公告圖片。
///
/// 校網的圖片很大（例如 2481×3508 像素，完整解開要 35MB 記憶體），直接顯示會讓捲動很卡。所以：
///   - 列表只用縮小版（最長邊 1400 像素），用 ImageIO 在背景執行緒「邊解邊縮」，不會先解開整張大圖
///   - 高解析度的圖只有放大時才在背景解開，看完就丟掉，不佔暫存
///   - 每張圖的寬高比記在手機上：圖片還沒下載好也能先用正確的比例佔位，圖片出現時版面不會跳
final class ImageCache {
    static let shared = ImageCache()

    private let thumbnails = NSCache<NSURL, UIImage>()  // 縮小版（已經解開，可以直接顯示）
    private let files = NSCache<NSURL, NSData>()         // 下載的原始檔（壓縮過的，小很多）
    private var ratios: [String: Double]                 // 圖片網址 → 寬除以高
    private var loading: [URL: Task<UIImage?, Never>] = [:]  // 正在下載的圖：同一張不會同時下載兩次
    private static let ratiosKey = "imageRatios"

    init() {
        thumbnails.totalCostLimit = 120 * 1024 * 1024  // 縮小版一張約 5MB，大約可以放 20 張
        files.totalCostLimit = 40 * 1024 * 1024
        ratios = UserDefaults.standard.dictionary(forKey: Self.ratiosKey) as? [String: Double] ?? [:]
    }

    /// 已經做好的縮小版；沒有就是 nil（不會去下載）
    func cachedThumbnail(_ url: URL) -> UIImage? { thumbnails.object(forKey: url as NSURL) }

    /// 寬除以高；這張圖從來沒下載過就是 nil
    func ratio(_ url: URL) -> CGFloat? { ratios[url.absoluteString].map { CGFloat($0) } }

    /// 列表和內頁用的縮小版
    func thumbnail(_ url: URL) async -> UIImage? {
        if let image = cachedThumbnail(url) { return image }
        if let task = loading[url] { return await task.value }  // 已經在下載了：等同一個
        // 下載不跟著畫面取消：很快捲過去又捲回來時，接著用同一個下載，不會從頭再下載一次
        let task = Task { () -> UIImage? in
            defer { loading[url] = nil }
            guard let data = await file(url),
                  let decoded = await Self.decode(data, maxPixelSize: 1400) else { return nil }
            thumbnails.setObject(decoded.image, forKey: url as NSURL, cost: decoded.bytes)
            remember(decoded.ratio, for: url)
            return decoded.image
        }
        loading[url] = task
        return await task.value
    }

    /// 放大用的高解析度圖（最長邊 4096 像素），不放進暫存
    func largeImage(_ url: URL) async -> UIImage? {
        guard let data = await file(url) else { return nil }
        return await Self.decode(data, maxPixelSize: 4096)?.image
    }

    private func file(_ url: URL) async -> Data? {
        if let data = files.object(forKey: url as NSURL) { return data as Data }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        files.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }

    private func remember(_ ratio: Double, for url: URL) {
        guard ratios[url.absoluteString] != ratio else { return }
        ratios[url.absoluteString] = ratio
        UserDefaults.standard.set(ratios, forKey: Self.ratiosKey)
    }

    nonisolated struct Decoded: Sendable {
        let image: UIImage
        let ratio: Double
        let bytes: Int
    }

    /// 在背景執行緒（@concurrent）把圖片檔解成最長邊不超過 maxPixelSize 的圖。
    /// ImageIO 會一邊解一邊縮，不會先把整張大圖解開放在記憶體裡。
    @concurrent
    nonisolated private static func decode(_ data: Data, maxPixelSize: Int) async -> Decoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,  // 照相片的方向資訊轉正
            kCGImageSourceShouldCacheImmediately: true,        // 在這裡就解開，不要等到畫到螢幕上才解（那時會卡）
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Decoded(
            image: UIImage(cgImage: cgImage),
            ratio: Double(cgImage.width) / Double(max(cgImage.height, 1)),
            bytes: cgImage.bytesPerRow * cgImage.height
        )
    }
}

/// 正在放大的圖片：哪一張、從畫面上哪個位置放大
struct ZoomedImage {
    let sourceID: UUID    // 被點的那個圖片元件，放大時把它藏起來，看起來像圖片被拿起來
    let url: URL?         // 網路上的圖；PDF 附件的頁面沒有網址
    let preview: UIImage  // 列表上的縮小版：放大動畫先用它，高解析度的圖在背景載入
    let from: CGRect      // 圖片在螢幕上的位置（整個螢幕的座標）
    /// 不是網路圖片時（PDF 的頁面），放大後怎麼拿高解析度的版本
    var loadLarge: (@Sendable () async -> UIImage?)? = nil
    /// 好幾張可以左右滑的（PDF 的每一頁）；空的就是只有這一張
    var gallery: [GalleryPage] = []
    var startIndex = 0
}

/// 相簿裡的一張：列表上已經畫好的縮圖（可能還沒有）、寬高比、怎麼拿高解析度的
struct GalleryPage: @unchecked Sendable {
    let preview: UIImage?
    let ratio: CGFloat
    let load: @Sendable () async -> UIImage?
}

/// 記住圖片的大小。用 class 存，改了不會讓畫面重畫
final class SizeBox {
    var value: CGSize = .zero
}

/// 公告裡的圖片，照原比例顯示，點了就地放大。
/// cropTall = true（時間軸）：太長的直式圖最多顯示到 3:4，下面多的裁掉；內頁則顯示完整圖片。
struct NoticeImage: View {
    @Environment(Router.self) private var router
    let url: URL
    var cropTall = false

    @State private var image: UIImage?
    @State private var failed = false
    @State private var size = SizeBox()
    @State private var id = UUID()

    init(url: URL, cropTall: Bool = false) {
        self.url = url
        self.cropTall = cropTall
        // 已經做好縮小版的直接拿來用：捲回來時第一個畫面就有圖，不會先閃灰色
        _image = State(initialValue: ImageCache.shared.cachedThumbnail(url))
    }

    /// 顯示的寬高比：知道原圖比例就照原比例，還不知道先用 4:3 佔位
    private var shownRatio: CGFloat {
        guard let ratio = ImageCache.shared.ratio(url) else { return 4.0 / 3.0 }
        return cropTall ? max(ratio, 3.0 / 4.0) : ratio
    }

    var body: some View {
        if !failed {
            Color.paperChip
                .aspectRatio(shownRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .top) {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .clipShape(.rect(cornerRadius: 12))
                // 放大的時候原位置的圖片先藏起來
                .opacity(router.zoomed?.sourceID == id ? 0 : 1)
                // 只在大小改變時記一次（捲動時大小不變，不會一直觸發）
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size.value = $0 }
                .contentShape(.rect)
                // 用 highPriorityGesture：圖片在可以點的公告裡面，點圖片時只放大，不要進到內頁
                .highPriorityGesture(tap)
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(L("公告圖片", "Notice image"))
                .accessibilityHint(L("放大圖片", "Zoom image"))
                .accessibilityAction { zoom(from: CGRect(origin: .zero, size: size.value)) }
                .task(id: url) {
                    guard image == nil else { return }
                    image = await ImageCache.shared.thumbnail(url)
                    failed = image == nil
                }
        }
    }

    /// 點圖片放大。圖片在螢幕上的位置 = 點的地方在螢幕上的座標 − 點的地方在圖片裡的座標。
    /// 這樣只有點的那一刻才算位置，捲動時完全不用追蹤。
    private var tap: some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .simultaneously(with: SpatialTapGesture(coordinateSpace: .global))
            .onEnded { value in
                guard let local = value.first?.location, let global = value.second?.location else { return }
                zoom(from: CGRect(origin: CGPoint(x: global.x - local.x, y: global.y - local.y), size: size.value))
            }
    }

    private func zoom(from frame: CGRect) {
        guard let image else { return }  // 還在下載就先不放大
        router.zoomed = ZoomedImage(sourceID: id, url: url, preview: image, from: frame)
    }
}

/// 放大圖片的那一層，蓋在整個 App 最上面（導覽列也在它下面）。
/// 單獨拆成一個畫面：打開、關閉放大時只有這一層重畫，後面的列表和導覽列不會跟著重畫。
struct ZoomLayer: View {
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            if let zoomed = router.zoomed {
                ImageOverlay(zoomed: zoomed) { router.zoomed = nil }
            }
        }
        .statusBarHidden(router.zoomed != nil)
        .persistentSystemOverlays(router.zoomed != nil ? .hidden : .automatic)
    }
}

/// 放大中的圖片：蓋在整個 App 最上面，只有圖片和純黑底。
/// 兩指縮放、點兩下放大；點一下或往下拉就縮回原位。
/// 有好幾張（PDF 的每一頁）時左右滑換張，下面顯示第幾張；換到別張再關閉就淡出（不知道別張在列表上的位置）。
struct ImageOverlay: View {
    let zoomed: ZoomedImage
    let onClosed: () -> Void

    @State private var current = 0          // 相簿現在在第幾張
    @State private var fading = false       // 換過張再關閉：整層淡出

    @State private var expanded = false     // false = 在列表裡的位置，true = 全螢幕
    @State private var interactive = false  // 放大動畫結束後才換成可以縮放的版本
    @State private var pull: CGFloat = 0    // 往下拉了多少，黑底跟著變淡
    @State private var large: UIImage?      // 高解析度的圖，載入好就換上去

    var body: some View {
        GeometryReader { geo in
            let target = fitted(zoomed.preview.size, in: geo.size).offsetBy(dx: 0, dy: pull)
            let rect = expanded ? target : zoomed.from

            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(expanded ? 1 - min(abs(pull) / 400, 0.6) : 0)

                if interactive && zoomed.gallery.count > 1 {
                    TabView(selection: $current) {
                        ForEach(zoomed.gallery.indices, id: \.self) { i in
                            GalleryPageView(page: zoomed.gallery[i],
                                            first: i == zoomed.startIndex ? (large ?? zoomed.preview) : nil,
                                            onTap: close, onPull: { pull = $0 }, onPullRelease: close)
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .overlay(alignment: .bottom) {
                        Text("\(current + 1) / \(zoomed.gallery.count)")
                            .font(.app(.footnote, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.15), in: .capsule)
                            .padding(.bottom, 44)
                            .opacity(pull == 0 ? 1 : 0)
                    }
                } else if interactive {
                    ZoomableImage(image: large ?? zoomed.preview, onTap: close, onPull: { pull = $0 }, onPullRelease: close)
                } else {
                    // 動畫用的圖片：位置、大小、圓角從列表裡的樣子變成全螢幕
                    Image(uiImage: zoomed.preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: rect.width, height: rect.height, alignment: .top)
                        .clipShape(.rect(cornerRadius: expanded ? 0 : 12))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .ignoresSafeArea()
        .opacity(fading ? 0 : 1)
        .accessibilityAction(.escape) { close() }  // 用 VoiceOver 時兩指畫 Z 關閉
        .onAppear {
            current = zoomed.startIndex
            withAnimation(.spring(duration: 0.38, bounce: 0.12)) {
                expanded = true
            } completion: {
                interactive = true
            }
        }
        .task {
            if let load = zoomed.loadLarge { large = await load() }
            else if let url = zoomed.url { large = await ImageCache.shared.largeImage(url) }
        }
    }

    private func close() {
        // 換到別張了：縮回去的位置不對，直接淡出
        if current != zoomed.startIndex {
            withAnimation(.easeOut(duration: 0.22)) { fading = true } completion: { onClosed() }
            return
        }
        interactive = false
        withAnimation(.spring(duration: 0.32)) {
            expanded = false
            pull = 0
        } completion: {
            onClosed()
        }
    }

    /// 照原比例塞進螢幕的大小，置中
    private func fitted(_ size: CGSize, in screen: CGSize) -> CGRect {
        let scale = min(screen.width / max(size.width, 1), screen.height / max(size.height, 1))
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: (screen.width - w) / 2, y: (screen.height - h) / 2, width: w, height: h)
    }
}

/// 相簿的一張：先用縮圖（有的話），高解析度的畫好再換上去
private struct GalleryPageView: View {
    let page: GalleryPage
    let first: UIImage?   // 一開始點的那張：放大動畫已經有圖了，直接用
    let onTap: () -> Void
    let onPull: (CGFloat) -> Void
    let onPullRelease: () -> Void

    @State private var large: UIImage?

    var body: some View {
        Group {
            if let image = large ?? first ?? page.preview {
                ZoomableImage(image: image, onTap: onTap, onPull: onPull, onPullRelease: onPullRelease)
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard large == nil else { return }
            large = await page.load()
        }
    }
}

/// 可以縮放的圖片。用系統的 UIScrollView 做縮放，手感跟「照片」App 一樣。
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onTap: () -> Void
    let onPull: (CGFloat) -> Void
    let onPullRelease: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView(image: image)
        view.delegate = context.coordinator
        view.onSingleTap = onTap
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {
        // 高解析度的圖載入好了：換上去。比例一樣，所以位置和縮放都不用動
        if view.imageView.image !== image {
            view.imageView.image = image
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let parent: ZoomableImage
        init(parent: ZoomableImage) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.setNeedsLayout()
        }

        private func pulled(_ scrollView: UIScrollView) -> CGFloat {
            guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else { return 0 }
            return -(scrollView.contentOffset.y + scrollView.contentInset.top)
        }

        /// 沒放大時往上下拉，告訴外面拉了多少（黑底跟著變淡）
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onPull(pulled(scrollView))
        }

        /// 放手時拉得夠遠（或甩得夠快）就縮回原位
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                       targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let distance = pulled(scrollView)
            if abs(distance) > 90 || (scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 && abs(velocity.y) > 1.8) {
                parent.onPullRelease()
            }
        }
    }
}

private final class ZoomScrollView: UIScrollView {
    let imageView: UIImageView
    var onSingleTap: () -> Void = {}
    private var lastBoundsSize: CGSize = .zero

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        minimumZoomScale = 1
        maximumZoomScale = 5
        alwaysBounceVertical = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        backgroundColor = .clear
        scrollsToTop = false  // 點狀態列時讓後面的公告列表回到最上面，不是這裡

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        // 點一下關閉；要等確定不是點兩下才算點一下
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    required init?(coder: NSCoder) { fatalError("不支援從 storyboard 建立") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 沒放大時，把圖片縮到剛好塞進螢幕（照原比例）
        if zoomScale == minimumZoomScale && bounds.size != lastBoundsSize, let image = imageView.image {
            lastBoundsSize = bounds.size
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            imageView.frame = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
            contentSize = imageView.frame.size
        }
        // 圖片比螢幕小的方向置中
        let horizontal = max(0, (bounds.width - imageView.frame.width) / 2)
        let vertical = max(0, (bounds.height - imageView.frame.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func handleSingleTap() { onSingleTap() }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            // 以點的位置為中心放大 2.5 倍
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }
}

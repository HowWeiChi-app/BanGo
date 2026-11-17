// 公告裡的圖片：照原比例顯示、點了直接在畫面上放大。
//
// 系統的 AsyncImage 拿不到圖片原本的寬高，所以自己下載：拿到 UIImage 就知道寬高比，
// 下載過的圖片存在記憶體裡，列表和內頁共用，不會重複下載。
//
// 放大不是打開新畫面：App 最上層蓋一層（ImageOverlay），黑底淡入，
// 圖片從它在列表裡的位置和大小，用動畫變大到全螢幕；關閉時再縮回原位。

import SwiftUI
import UIKit

/// 一張下載好的圖片：放大用的原圖，和列表用的縮小版
final class LoadedImage {
    let full: UIImage       // 原圖（已經解壓好，放大時直接用）
    let thumbnail: UIImage  // 縮小到寬 1000 像素，列表和內頁用

    init(full: UIImage, thumbnail: UIImage) {
        self.full = full
        self.thumbnail = thumbnail
    }

    /// 寬除以高
    var ratio: CGFloat { full.size.width / max(full.size.height, 1) }
}

/// 下載過的圖片暫存在記憶體（App 關掉就清掉）。
///
/// 校網的圖片很大（例如 2481×3508 像素，解壓後一張 35MB），直接顯示會讓捲動很卡。
/// 所以下載後在背景執行緒先解壓好，再做一張縮小版給列表用，主執行緒只負責顯示。
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, LoadedImage>()

    init() {
        cache.totalCostLimit = 150 * 1024 * 1024  // 最多佔 150MB 記憶體，超過會自動丟掉舊的
    }

    func cached(_ url: URL) -> LoadedImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> LoadedImage? {
        if let loaded = cached(url) { return loaded }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let loaded = await Self.decode(data) else { return nil }
        let pixels = loaded.full.size.width * loaded.full.size.height * loaded.full.scale * loaded.full.scale
        cache.setObject(loaded, forKey: url as NSURL, cost: Int(pixels) * 4)
        return loaded
    }

    /// 在背景執行緒解壓圖片、做縮小版（@concurrent：不要在主執行緒跑）
    @concurrent
    nonisolated private static func decode(_ data: Data) async -> LoadedImage? {
        guard let image = UIImage(data: data) else { return nil }
        let full = image.preparingForDisplay() ?? image
        let width = image.size.width * image.scale
        let thumbnail: UIImage
        if width > 1000 {
            let size = CGSize(width: 1000, height: image.size.height * image.scale * 1000 / width)
            thumbnail = image.preparingThumbnail(of: size) ?? full
        } else {
            thumbnail = full
        }
        return LoadedImage(full: full, thumbnail: thumbnail)
    }
}

/// 記住圖片在螢幕上的位置。用 class 存，改了不會讓畫面重畫（捲動時位置每一幀都在變）
final class FrameTracker {
    var rect: CGRect = .zero
}

/// 正在放大的圖片：哪一張、從畫面上哪個位置放大
struct ZoomedImage {
    let sourceID: UUID      // 被點的那個圖片元件，放大時把它藏起來，看起來像圖片被拿起來
    let image: UIImage
    let from: CGRect        // 圖片在螢幕上的位置（整個螢幕的座標）
}

/// 公告裡的圖片，照原比例顯示，點了就地放大。
/// cropTall = true（時間軸）：太長的直式圖最多顯示到 3:4，下面多的裁掉；內頁則顯示完整圖片。
struct NoticeImage: View {
    @Environment(Router.self) private var router
    let url: URL
    var cropTall = false

    @State private var image: LoadedImage?
    @State private var failed = false
    @State private var tracker = FrameTracker()  // 目前在螢幕上的位置，放大時從這裡開始
    @State private var id = UUID()

    var body: some View {
        Group {
            if let image {
                let ratio = image.ratio
                // 先用原比例（或裁切後的比例）佔好位置，圖片疊在上面、從上面對齊，多的裁掉
                Color.paperChip
                    .aspectRatio(cropTall ? max(ratio, 3.0 / 4.0) : ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .top) {
                        Image(uiImage: image.thumbnail).resizable().scaledToFill()
                    }
                    .clipShape(.rect(cornerRadius: 12))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tracker.rect = $0 }
                    // 放大的時候原位置的圖片先藏起來
                    .opacity(router.zoomed?.sourceID == id ? 0 : 1)
                    .contentShape(.rect)
                    // 用 highPriorityGesture：圖片在可以點的公告裡面，點圖片時只放大，不要進到內頁
                    .highPriorityGesture(TapGesture().onEnded {
                        router.zoomed = ZoomedImage(sourceID: id, image: image.full, from: tracker.rect)
                    })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("公告圖片，點兩下放大")
            } else if !failed {
                // 下載中：灰色底
                Color.paperChip
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(.rect(cornerRadius: 12))
            }
            // 下載失敗就整塊不顯示
        }
        .task(id: url) {
            if let cached = ImageCache.shared.cached(url) {
                image = cached
            } else {
                image = await ImageCache.shared.load(url)
                failed = image == nil
            }
        }
    }
}

/// 放大中的圖片：蓋在整個 App 最上面，只有圖片和純黑底。
/// 兩指縮放、點兩下放大；點一下或往下拉就縮回原位。
struct ImageOverlay: View {
    let zoomed: ZoomedImage
    let onClosed: () -> Void

    @State private var expanded = false     // false = 在列表裡的位置，true = 全螢幕
    @State private var interactive = false  // 放大動畫結束後才換成可以縮放的版本
    @State private var pull: CGFloat = 0    // 往下拉了多少，黑底跟著變淡

    var body: some View {
        GeometryReader { geo in
            let target = fitted(zoomed.image.size, in: geo.size).offsetBy(dx: 0, dy: pull)
            let rect = expanded ? target : zoomed.from

            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(expanded ? 1 - min(abs(pull) / 400, 0.6) : 0)

                if interactive {
                    ZoomableImage(image: zoomed.image, onTap: close, onPull: { pull = $0 }, onPullRelease: close)
                } else {
                    // 動畫用的圖片：位置、大小、圓角從列表裡的樣子變成全螢幕
                    Image(uiImage: zoomed.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: rect.width, height: rect.height, alignment: .top)
                        .clipShape(.rect(cornerRadius: expanded ? 0 : 12))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityAction(.escape) { close() }  // 用 VoiceOver 時兩指畫 Z 關閉
        .onAppear {
            withAnimation(.spring(duration: 0.38, bounce: 0.12)) {
                expanded = true
            } completion: {
                interactive = true
            }
        }
    }

    private func close() {
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
        let scale = min(screen.width / size.width, screen.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: (screen.width - w) / 2, y: (screen.height - h) / 2, width: w, height: h)
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

    func updateUIView(_ view: ZoomScrollView, context: Context) {}

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

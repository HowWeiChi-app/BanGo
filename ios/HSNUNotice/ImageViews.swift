// 公告裡的圖片：照原比例顯示、點了全螢幕放大。
//
// 系統的 AsyncImage 拿不到圖片原本的寬高，所以自己下載：拿到 UIImage 就知道寬高比，
// 下載過的圖片存在記憶體裡，列表和內頁、放大畫面共用，不會重複下載。

import SwiftUI
import UIKit

/// 下載過的圖片暫存在記憶體（App 關掉就清掉）
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        // 放大畫面打開時，圖片通常已經下載過了，直接拿暫存的
        if let image = cached(url) { return image }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// 要放大的圖片（給 fullScreenCover 用，需要 Identifiable）。
/// namespace 是被點的那張圖片自己的，放大畫面要用同一個，系統才知道要從哪裡放大、縮回哪裡。
struct ZoomedImage: Identifiable {
    let url: URL
    let namespace: Namespace.ID
    var id: URL { url }
}

/// 公告裡的圖片，照原比例顯示，點了全螢幕放大。
/// cropTall = true（時間軸）：太長的直式圖最多顯示到 3:4，下面多的裁掉；內頁則顯示完整圖片。
struct NoticeImage: View {
    @Environment(Router.self) private var router
    let url: URL
    var cropTall = false

    @State private var image: UIImage?
    @State private var failed = false
    @Namespace private var zoom

    var body: some View {
        Group {
            if let image {
                let ratio = image.size.width / max(image.size.height, 1)
                // 先用原比例（或裁切後的比例）佔好位置，圖片疊在上面、從上面對齊，多的裁掉
                Color.paperChip
                    .aspectRatio(cropTall ? max(ratio, 3.0 / 4.0) : ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .top) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                    .clipShape(.rect(cornerRadius: 12))
                    // 官方的縮放轉場：點了之後圖片從這個位置直接放大成全螢幕，關掉時縮回這裡
                    .matchedTransitionSource(id: url, in: zoom) { $0.clipShape(.rect(cornerRadius: 12)) }
                    .contentShape(.rect)
                    // 用 highPriorityGesture：圖片在可以點的公告裡面，點圖片時只放大，不要進到內頁
                    .highPriorityGesture(TapGesture().onEnded {
                        router.zoomed = ZoomedImage(url: url, namespace: zoom)
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

/// 全螢幕看圖：黑底，可以兩指縮放、點兩下放大，往下拉或按 X 關閉。
/// 打開和關閉的動畫是系統的 zoom 轉場（在 ContentView 設定），不是從下面彈出的卡片。
struct ImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    init(url: URL) {
        self.url = url
        // 先拿暫存的圖片，放大動畫一開始就有圖，不會先閃一下轉圈圈
        _image = State(initialValue: ImageCache.shared.cached(url))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let image {
                ZoomableImage(image: image) { dismiss() }
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("關閉")
                Spacer()
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
            }
            .buttonStyle(.glass)  // 官方的 Liquid Glass 按鈕
            .tint(.white)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .statusBarHidden()
        .task { if image == nil { image = await ImageCache.shared.load(url) } }
    }
}

/// 可以縮放的圖片。用系統的 UIScrollView 做縮放，手感跟「照片」App 一樣。
private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView(image: image)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: ZoomScrollView, context: Context) {}

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.setNeedsLayout()
        }

        /// 沒有放大時往下拉超過一段距離（或往下甩）就關閉
        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                       targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let pulledDown = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            if scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 && (pulledDown < -90 || velocity.y < -1.8) {
                onDismiss()
            }
        }
    }
}

private final class ZoomScrollView: UIScrollView {
    let imageView: UIImageView
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

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
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

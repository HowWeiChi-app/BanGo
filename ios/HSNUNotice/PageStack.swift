// 三層頁面左右並排的容器：側邊欄 ｜ 時間軸 ｜ 內頁。照 Reeder 自己寫的導覽（CoreNavigation）做：
//
//   - 每一頁包在自己的 NavigationStack 裡，只用來放那一頁的工具列和搜尋框。
//     工具列屬於那一頁，換頁時跟著頁面一起滑，不會像系統導覽列那樣在兩頁之間變形。
//   - 同一個左右拖曳手勢處理兩個方向：往右拉，上面那頁跟著手指滑走，露出上一層；
//     往左拉（只有側邊欄可以），時間軸從右邊跟著手指拉進來。
//   - 被蓋住的那頁往左移 30%、變暗一點；移動中的那頁有螢幕形狀的圓角，外面一圈 1pt 亮邊，左邊緣有陰影。
//     亮邊畫在頁面「外面」（Reeder 是把邊框放在 CGRectInset(頁面, -1, -1)），不是貼在內側。
//   - 陰影照 Reeder 的設定：深色模式黑色 40%、淺色模式黑色 15%，半徑 5。

import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass  // 子類別要自己設定 state

struct PageStack: View {
    @Environment(Router.self) private var router
    @State private var drag: CGFloat = 0    // 正數：往右拉回上一層拉了多少；負數：往左拉進下一層
    @State private var settling = false     // 放手後的動畫還在跑，這時候不能再拉
    @State private var width: CGFloat = 0
    @State private var preload = false      // 上面那則先排好了沒

    /// 內頁要排的頁面。上面那則等點進來的換頁動畫跑完才排：不然動畫一開始要同時排兩則內文，會卡一下
    private var articlePages: [Notice] {
        guard let article = router.article else { return [] }
        guard preload || drag < 0, let newer = router.newer else { return [article] }
        return [article, newer]
    }

    var body: some View {
        ZStack {
            page(Router.Depth.sidebar) {
                NavigationStack { SidebarView() }
            }
            page(Router.Depth.timeline) {
                NavigationStack { NoticeTimeline(filter: router.filter) }
                    .id(router.filter)  // 換了分類就是新的時間軸，從最上面開始
                    // 搜尋列蓋在工具列的位置：NavigationStack 的最上緣就是工具列那一排的上緣
                    .overlay(alignment: .top) { SearchBar() }
            }
            // 內頁：目前這則，加上停在右邊外面、等著被往左拉進來的上面那則（比較新的）。
            // 用公告的 id 當身分：放手換過去時，拉進來那頁就是同一個畫面，不會重排、文字不會跳
            ForEach(articlePages) { notice in
                let incoming = notice.id != router.article?.id
                page(incoming ? Router.Depth.article + 1 : Router.Depth.article) {
                    NoticeDetailView(notice: notice)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .gesture(PagePanGesture(canBegin: canBegin, onChanged: dragged, onEnded: released))
        .task(id: router.article?.id) {
            preload = false
            try? await Task.sleep(for: .milliseconds(450))
            preload = true
        }
    }

    /// 一層頁面：算出它現在該在哪裡、要不要變暗
    private func page<Content: View>(_ index: Int, @ViewBuilder content: () -> Content) -> some View {
        let (x, dim) = position(of: index)
        let isTop = index == router.depth
        return content()
            // 鍵盤出來時頁面不要縮短讓位（搜尋列在最上面，用不到）：
            // 縮短再拉長的那一下，圓角裁切的範圍跟不上，底下會露出黑邊、背景亂跳
            .ignoresSafeArea(.keyboard)
            .modifier(PageFrame(x: x, dim: dim, width: width))
            .allowsHitTesting(isTop && drag == 0 && !settling)
            .accessibilityHidden(!isTop)
            .zIndex(Double(index))
    }

    /// 第 index 層的水平位置（點）和變暗的程度
    private func position(of index: Int) -> (CGFloat, CGFloat) {
        let depth = router.depth
        let covered = -0.3 * width  // 被蓋住的頁面往左移 30%
        let x: CGFloat
        if drag < 0 {
            // 往左拉：下一層從右邊進來，這一層往左退
            x = index == depth + 1 ? width + drag
              : index == depth ? 0.3 * drag
              : index < depth ? covered : width
        } else {
            // 往右拉（或沒在拉）：這一層往右滑走，上一層從左邊回來
            x = index == depth ? drag
              : index == depth - 1 ? covered + 0.3 * drag
              : index < depth ? covered : width
        }
        // 被完全蓋住、看不到的頁面停在 covered，不移除，回來時捲動位置都還在。
        // 被蓋住越多越暗，最多暗 10%
        let dim = width > 0 && x < 0 ? 0.1 * min(-x / (0.3 * width), 1) : 0
        return (x, dim)
    }

    // MARK: - 拖曳

    private func canBegin(_ towardRight: Bool) -> Bool {
        guard !settling, router.zoomed == nil else { return false }
        return towardRight ? router.depth > Router.Depth.sidebar : router.hasForward
    }

    private func dragged(_ translation: CGFloat, _ towardRight: Bool) {
        // 方向在開始時就決定了；拉過頭到另一邊就停在 0
        drag = towardRight ? min(max(translation, 0), width) : max(min(translation, 0), -width)
    }

    /// 放手：拉的距離加上甩的速度超過畫面三分之一，就換頁；不然彈回去
    private func released(_ translation: CGFloat, _ velocity: CGFloat, _ towardRight: Bool) {
        let projected = translation + velocity * 0.15
        let change = towardRight ? projected > width / 3 : -projected > width / 3
        let target: CGFloat = change ? (towardRight ? width : -width) : 0
        settling = true
        withAnimation(.spring(duration: 0.3, bounce: 0)) {
            drag = target
        } completion: {
            // 頁面已經在新的位置上了，換成新的那一層時位置不變，所以看不出有換
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if change {
                    if towardRight { router.settle(at: router.depth - 1) } else { router.settleForward() }
                }
                drag = 0
            }
            settling = false
        }
    }
}

/// 把一頁放到 x 的位置。移動中的頁面（x > 0，也就是被拉開、露出下面那頁）：
/// 螢幕形狀的圓角、外面一圈 1pt 亮邊、左邊緣的陰影。
/// 做成 Animatable：點按鈕換頁時，動畫的每一格都會用「當下」的位置判斷要不要畫圓角和亮邊
struct PageFrame: ViewModifier, Animatable {
    var x: CGFloat
    var dim: CGFloat
    /// 畫面寬度：頁面整個推到螢幕右邊外面（x ≥ 寬度）時就不畫亮邊和陰影，
    /// 不然停在右邊外面的時間軸，外圈 1pt 的亮邊和陰影會貼著側邊欄的右邊露出來
    var width: CGFloat
    @Environment(\.displayScale) private var scale
    @State private var safeArea = EdgeInsets()

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, dim) }
        set { x = newValue.first; dim = newValue.second }
    }

    /// 實際螢幕的圓角：每台不一樣（iPhone 16 Pro 是 62，15 Pro 是 55），跟系統問；問不到用 55
    static let screenCorner: CGFloat = {
        let value = (UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat) ?? 0
        return value > 0 ? value : 55
    }()

    func body(content: Content) -> some View {
        let moving = x > 0.5 && x < width - 0.5
        let shape = RoundedRectangle(cornerRadius: moving ? Self.screenCorner : 0, style: .continuous)
        content
            .overlay {
                Color.black.opacity(dim).ignoresSafeArea().allowsHitTesting(false)
            }
            // 裁圓角：不能用 mask —— 外面那層（三層頁面）跟裡面那層（內頁換則）都用 mask 疊在一起時，
            // 被拉進來的那則內文不會畫出來，只看得到工具列。
            // 用 clipShape，但裁切範圍往上下延伸到狀態列、底部橫條那塊（不然那兩塊會被切成黑邊）
            .clipShape(ScreenShape(radius: moving ? Self.screenCorner : 0,
                                   top: safeArea.top, bottom: safeArea.bottom))
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
            .background {
                if moving {
                    // 陰影：沿著整個圓角頁面一圈（Reeder：深色黑 40%、淺色黑 15%，半徑 5）。
                    // 用系統圖層的陰影，固定好形狀（shadowPath），換頁移動時不會每一格重算
                    PageShadow(radius: Self.screenCorner)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if moving {
                    // 外圈 1pt 的邊，在頁面外面一圈，跟著圓角轉
                    shape.inset(by: -1).strokeBorder(Color.pageRim, lineWidth: 1)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            // 對齊螢幕像素：慢慢拉的時候位移會停在像素和像素之間，文字會一格一格地抖
            .offset(x: (x * scale).rounded() / scale)
    }
}

/// 移動中頁面的陰影。只畫陰影本身（view 是透明的），形狀跟頁面一樣是螢幕圓角
struct PageShadow: UIViewRepresentable {
    var radius: CGFloat

    func makeUIView(context: Context) -> ShadowView { ShadowView() }
    func updateUIView(_ view: ShadowView, context: Context) {
        view.radius = radius
        view.setNeedsLayout()
    }

    final class ShadowView: UIView {
        var radius: CGFloat = 55

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowRadius = 5
            layer.shadowOffset = .zero
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ShadowView, _: UITraitCollection) in
                view.updateOpacity()
            }
            updateOpacity()
        }
        required init?(coder: NSCoder) { fatalError() }

        private func updateOpacity() {
            layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.4 : 0.15
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // UIBezierPath 的圓角就是 iOS 那種連續曲線，跟 SwiftUI 的 .continuous 一樣
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
        }
    }
}

/// 螢幕形狀的圓角矩形，上下往外延伸 top / bottom（把狀態列、底部橫條那塊也包進來）
struct ScreenShape: Shape {
    var radius: CGFloat
    var top: CGFloat
    var bottom: CGFloat

    func path(in rect: CGRect) -> Path {
        let full = CGRect(x: rect.minX, y: rect.minY - top, width: rect.width, height: rect.height + top + bottom)
        return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: full)
    }
}

/// 左右拖曳的手勢。手指一開始明顯上下動，就馬上放棄，讓列表、內文去捲動
struct PagePanGesture: UIGestureRecognizerRepresentable {
    /// 要不要開始：參數是「往右拉」
    var canBegin: (Bool) -> Bool
    var onChanged: (CGFloat, Bool) -> Void              // 拉了多少（往右為正）、是不是往右
    var onEnded: (CGFloat, CGFloat, Bool) -> Void        // 放手時拉了多少、速度、是不是往右；被取消時都是 0

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> HorizontalPan {
        let pan = HorizontalPan()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ pan: HorizontalPan, context: Context) {
        context.coordinator.canBegin = canBegin
    }

    func handleUIGestureRecognizerAction(_ pan: HorizontalPan, context: Context) {
        let right = context.coordinator.towardRight
        switch pan.state {
        case .began, .changed:
            onChanged(pan.translation(in: pan.view).x, right)
        case .ended:
            onEnded(pan.translation(in: pan.view).x, pan.velocity(in: pan.view).x, right)
        case .cancelled, .failed:
            onEnded(0, 0, right)
        default:
            break
        }
    }

    /// 只認左右的拖曳：還沒開始前，上下比左右多就放棄
    final class HorizontalPan: UIPanGestureRecognizer {
        private var start: CGPoint?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            start = touches.first?.location(in: view)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            if state == .possible, let start, let point = touches.first?.location(in: view) {
                let dx = point.x - start.x, dy = point.y - start.y
                if abs(dy) > abs(dx) + 2 {
                    state = .failed
                    return
                }
            }
            super.touchesMoved(touches, with: event)
        }

        override func reset() {
            super.reset()
            start = nil
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canBegin: (Bool) -> Bool = { _ in false }
        var towardRight = true

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) * 1.2 else { return false }
            towardRight = velocity.x > 0
            return canBegin(towardRight)
        }

        // 列表、內文的上下捲動，要等這個手勢確定不是左右拉才開始
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

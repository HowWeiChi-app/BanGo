// 長按時間軸上的一則公告，跳出來的選單。
// 不用系統的 contextMenu（整則放大浮起來、背景整片模糊）。自己畫
// （彈出框貼著那一則）：
//   - 那一則亮起選中的玻璃卡片，不會浮起來，後面的列表也不模糊
//   - 一片玻璃選單從那一則的下緣（下面放不下就上緣）長出來
//   - 點選單外面任何地方就收回去
// 選單有「閱讀原文」「複製連結」，後面的畫面會稍微壓暗一點。

import SwiftUI
import UIKit

/// 正在跳出選單的那一則，和它在螢幕上的位置
struct RowMenu: Equatable {
    let notice: Notice
    let frame: CGRect

    static func == (a: RowMenu, b: RowMenu) -> Bool { a.notice.id == b.notice.id && a.frame == b.frame }
}

/// 掛在每一則上：記住自己在螢幕上的位置，長按就打開選單
struct RowMenuTrigger: ViewModifier {
    let notice: Notice
    @Environment(Router.self) private var router
    /// 這一則在螢幕上的位置：長按那一刻才去問（FrameReader）。
    /// 不用 onGeometryChange 一直追：那樣捲動時每一格、每一則都要重算一次位置，捲動會卡
    @State private var reader = FrameReader.Box()

    func body(content: Content) -> some View {
        content
            .background(FrameReader(box: reader))
            // 用 simultaneousGesture：一則公告本身是按鈕，直接掛 onLongPressGesture 會被按鈕吃掉，長按沒反應。
            // 長按完放開時按鈕也會收到「點一下」，時間軸那邊看到選單開著就不換頁
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                router.rowMenu = RowMenu(notice: notice, frame: reader.frame)
            })
            .sensoryFeedback(.impact(weight: .medium), trigger: router.rowMenu?.notice.id == notice.id) { _, open in open }
    }
}

/// 放在一則公告後面的透明 UIView，要的時候才算出自己在螢幕上的位置
struct FrameReader: UIViewRepresentable {
    final class Box {
        weak var view: UIView?
        /// 在整個螢幕上的位置（跟 SwiftUI 的 .global 一樣）
        @MainActor var frame: CGRect {
            guard let view, let window = view.window else { return .zero }
            return view.convert(view.bounds, to: window.screen.coordinateSpace)
        }
    }

    let box: Box

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        box.view = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { box.view = view }
}

/// 選單那一層，蓋在整個 App 上面（跟放大圖片一樣）
struct RowMenuLayer: View {
    @Environment(Router.self) private var router
    @State private var shown = false

    private static let gap: CGFloat = 8
    private static let width: CGFloat = 240

    var body: some View {
        GeometryReader { geo in
            if let menu = router.rowMenu {
                let below = menu.frame.maxY + Self.gap + 170 < geo.size.height - 40
                let x = min(max(menu.frame.minX + 14, 16), geo.size.width - Self.width - 16)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(shown ? 0.12 : 0)
                        .contentShape(.rect)
                        // 手指一碰到選單外面就收（不用等放開）
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in close() })

                    panel(menu.notice)
                        .scaleEffect(shown ? 1 : 0.3, anchor: below ? .topLeading : .bottomLeading)
                        .opacity(shown ? 1 : 0)
                        .blur(radius: shown ? 0 : 6)
                        .frame(maxWidth: .infinity, maxHeight: below ? .infinity : menu.frame.minY - Self.gap,
                               alignment: below ? .topLeading : .bottomLeading)
                        .padding(.top, below ? menu.frame.maxY + Self.gap : 0)
                        .padding(.leading, x)
                }
                .task(id: menu.notice.id) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { shown = true }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(router.rowMenu != nil)  // 沒打開時不擋到下面的列表
    }

    private func panel(_ notice: Notice) -> some View {
        let url = URL(string: notice.url)
        return VStack(spacing: 0) {
            item(L("閱讀原文", "Open Original"), symbol: "safari") { if let url { SafariPage.open(url) } }
            Divider().padding(.leading, 16)
            item(L("複製連結", "Copy Link"), symbol: "link") {
                UIPasteboard.general.url = url
                router.showToast(L("已複製連結", "Link Copied"))
            }
            Divider().padding(.leading, 16)
            item(L("分享…", "Share…"), symbol: "square.and.arrow.up") { if let url { SharePage.open(url) } }
        }
        .disabled(url == nil)
        .frame(width: Self.width)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func item(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            close(then: action)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: symbol).foregroundStyle(Color.inkSecondary)
            }
            .font(.app(.body))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(.rect)
        }
        .buttonStyle(MenuItemPressStyle())
    }

    private func close(then action: (() -> Void)? = nil) {
        guard shown else { return }
        withAnimation(.spring(duration: 0.25, bounce: 0)) { shown = false } completion: {
            router.rowMenu = nil
            action?()
        }
    }
}

/// 選單的一項：按住時底下亮一點
private struct MenuItemPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
    }
}

/// 系統的分享面板，從最上面那個畫面打開
enum SharePage {
    static func open(_ url: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        top.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }
}

/// 畫面上方短暫出現的提示（例如「已複製連結」）：一顆玻璃膠囊從下面浮上來，1.5 秒後收回去，同時輕震一下
struct ToastLayer: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack {
            if let text = router.toast {
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.app(.subheadline, .semibold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(text)
            }
        }
        // 放在下面：放上面會疊在工具列上
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 12)
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: router.toast)
        .sensoryFeedback(.success, trigger: router.toast) { _, new in new != nil }
    }
}

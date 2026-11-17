// 左右滑換頁的兩個手勢。所有頁面左右排成一排（設定 ← 側邊欄 → 時間軸 → 內頁），
// 往右滑回到左邊那一頁，往左滑到右邊那一頁。
//
// 一、往右滑返回（swipeBackEnabled）
// 側邊欄、時間軸照 Reeder 把左上角的返回鍵換成別的按鈕；系統看到「這頁沒有返回鍵」，就會關掉往右滑返回。
// 以前的做法是把系統的手勢判斷整個換掉，結果手勢會跟列表捲動、按鈕搶觸控，有時候滑了沒反應。
// 現在只換掉「要不要開始」這一個判斷：有上一頁、畫面不是正在切換、而且是往右滑，就開始。
// 其他判斷（這次觸控要不要給它、跟捲動和按鈕怎麼搭配）全部交還給系統原本的代理。
//
// 二、往左滑（LeftSwipeGesture）
// 內頁往左滑換到上面那則（比較新的），設定往左滑回到側邊欄。

import ObjectiveC
import SwiftUI
import UIKit

extension View {
    /// 讓這一頁可以往右滑回上一頁，就算左上角沒有返回鍵
    func swipeBackEnabled() -> some View {
        background(SwipeBackProbe().frame(width: 0, height: 0))
    }
}

/// 看不見的小元件：被放進畫面時，往上找到所在的導覽控制器，把返回手勢裝好
private struct SwipeBackProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder {
                if let navigation = current as? UINavigationController {
                    SwipeBackDelegate.install(on: navigation)
                    return
                }
                responder = current.next
            }
        }
    }
}

/// 包在系統原本的返回手勢代理外面
private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    private static var key = 0
    /// 系統原本的代理。用強參照留著：轉給它的方法，它一定要在
    nonisolated(unsafe) private let original: (any UIGestureRecognizerDelegate)?
    private weak var navigation: UINavigationController?

    private init(original: (any UIGestureRecognizerDelegate)?, navigation: UINavigationController) {
        self.original = original
        self.navigation = navigation
    }

    /// 裝到兩個返回手勢上：從螢幕左邊緣滑（interactivePop），和 iOS 26 從畫面任何地方往右滑（interactiveContentPop）。
    /// 裝過的不會再裝一次。
    static func install(on navigation: UINavigationController) {
        for gesture in [navigation.interactivePopGestureRecognizer, navigation.interactiveContentPopGestureRecognizer] {
            guard let gesture, !(gesture.delegate is SwipeBackDelegate) else { continue }
            let delegate = SwipeBackDelegate(original: gesture.delegate, navigation: navigation)
            // 手勢只用 weak 記住代理，所以讓手勢本身留著它
            objc_setAssociatedObject(gesture, &key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            gesture.delegate = delegate
        }
    }

    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let navigation,
              navigation.viewControllers.count > 1,      // 已經在最左邊（設定），沒有上一頁
              navigation.transitionCoordinator == nil    // 畫面正在切換：這時候返回會讓畫面卡住
        else { return false }
        // 從螢幕左邊緣滑一定是返回；從畫面中間滑只有「往右」才是返回，
        // 往左滑留給「到右邊那頁」，上下滑是捲動
        guard !(gesture is UIScreenEdgePanGestureRecognizer), let pan = gesture as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return velocity.x > 0 && velocity.x > abs(velocity.y)
    }

    // 其他代理方法全部轉給系統原本的代理
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}

/// 往左滑的手勢（系統的 UIPanGestureRecognizer）。
/// 只有往左、而且明顯比上下多的時候才開始；上下捲動要等確定不是往左滑才開始，所以兩個不會搶。
struct LeftSwipeGesture: UIGestureRecognizerRepresentable {
    var isEnabled = true
    var onChanged: (CGFloat) -> Void = { _ in }            // 往左拉了多少（點）
    var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }  // 放手時拉了多少、往左甩的速度（每秒幾點）；被取消時都是 0

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        // 不用 pan.isEnabled：拉到一半被關掉會直接取消手勢。改成只在「要不要開始」時看
        context.coordinator.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed:
            onChanged(-pan.translation(in: pan.view).x)
        case .ended:
            onEnded(-pan.translation(in: pan.view).x, -pan.velocity(in: pan.view).x)
        case .cancelled:
            onEnded(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = true

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard isEnabled, let pan = gesture as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x < 0 && -velocity.x > abs(velocity.y) * 1.2
        }

        // 列表、內文的上下捲動，要等這個手勢確定不是往左滑才開始
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}

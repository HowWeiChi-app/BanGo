// 往右滑回上一頁。
//
// 時間軸照 Reeder 把左上角的返回鍵換成側邊欄按鈕；系統看到「這頁沒有返回鍵」，就會關掉往右滑返回。
// 以前的做法是把系統的手勢判斷整個換掉，結果手勢會跟列表捲動、按鈕搶觸控，有時候滑了沒反應。
// 現在只在系統的判斷外面包一層：
//   - 系統本來就同意的（例如內頁有返回鍵），照系統的
//   - 系統因為「沒有返回鍵」而拒絕的：只要是往右滑、而且畫面不是正在切換，就放行
// 其他判斷（這次觸控要不要給它、跟捲動和按鈕怎麼搭配）全部交還給系統原本的代理。

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
              navigation.viewControllers.count > 1,      // 已經在第一層，沒有上一頁
              navigation.transitionCoordinator == nil    // 畫面正在切換：這時候返回會讓畫面卡住
        else { return false }
        if original?.gestureRecognizerShouldBegin?(gesture) == true { return true }  // 系統同意就照系統的
        // 系統不同意（這頁沒有返回鍵）：從左邊緣滑一律放行；從畫面中間滑只有「往右」才算，上下捲動、往左滑都不算
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

// 主畫面：照 Reeder 的結構，沒有下方分頁列，一層一層點進去：
//   側邊欄 → 公告時間軸 → 公告內頁
// 打開 App 時直接停在「我的公告」的時間軸，按左上角的側邊欄按鈕回到側邊欄。
// 導覽列、工具列的 Liquid Glass 都是系統內建的。

import SwiftUI

/// 記住目前點到第幾層；任何畫面都可以往裡面加一頁
@Observable
final class Router {
    var path: NavigationPath

    init() {
        // 打開 App 時直接停在「我的公告」
        path = NavigationPath()
        path.append(NoticeFilter.mine)
    }
}

struct ContentView: View {
    @State private var store = NoticeStore()
    @State private var router = Router()
    @State private var selected: NoticeFilter = .mine

    var body: some View {
        NavigationStack(path: $router.path) {
            SidebarView(path: $router.path, selected: $selected)
        }
        .tint(Color.brand)
        .environment(store)
        .environment(router)
        .task { await store.refresh() }
    }
}

// 時間軸把返回鍵換成側邊欄按鈕後，系統會關掉「往右滑回上一頁」的手勢，這裡把它打開。
// iOS 26 有兩個：從螢幕左邊緣滑（interactivePop），和從畫面任何地方往右滑（interactiveContentPop）。
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactiveContentPopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard viewControllers.count > 1 else { return false }  // 已經在最上層，沒有上一頁
        // 只有「往右」滑才返回；上下捲動、往左滑都不算，免得捲列表時不小心跳回去
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: view)
            return velocity.x > 0 && velocity.x > abs(velocity.y)
        }
        return true
    }
}

#Preview {
    ContentView()
}

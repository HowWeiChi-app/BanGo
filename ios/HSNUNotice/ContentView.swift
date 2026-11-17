// 主畫面：照 Reeder 的結構，沒有下方分頁列，一層一層點進去：
//   側邊欄 → 公告時間軸 → 公告內頁
// 打開 App 時直接停在「我的公告」的時間軸，按左上角的側邊欄按鈕回到側邊欄。
// 導覽列、工具列的 Liquid Glass 都是系統內建的。

import SwiftUI

struct ContentView: View {
    @State private var store = NoticeStore()
    @State private var path = ContentView.startPath
    @State private var selected: NoticeFilter = .mine

    private static var startPath: NavigationPath {
        var path = NavigationPath()
        path.append(NoticeFilter.mine)
        return path
    }

    var body: some View {
        NavigationStack(path: $path) {
            SidebarView(path: $path, selected: $selected)
        }
        .tint(Color.brand)
        .environment(store)
        .task { await store.refresh() }
    }
}

// 時間軸把返回鍵換成側邊欄按鈕後，系統會關掉「從左邊滑回上一頁」的手勢，這裡把它打開
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

#Preview {
    ContentView()
}

// 主畫面：照 Reeder 的結構，沒有下方分頁列，一層一層點進去：
//   側邊欄 → 公告時間軸 → 公告內頁 → 原文（App 裡的 Safari）
// 打開 App 時直接停在「我的公告」的時間軸，按左上角的側邊欄按鈕回到側邊欄。
// 導覽列、工具列的 Liquid Glass 都是系統內建的。

import SwiftUI

/// 記住目前點到第幾層；任何畫面都可以往裡面加一頁
@Observable
final class Router {
    var path: NavigationPath
    var zoomed: ZoomedImage?  // 正在放大的圖片，任何頁面點圖片都設定這個

    init() {
        // 打開 App 時直接停在「我的公告」
        path = NavigationPath()
        path.append(NoticeFilter.mine)
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = NoticeStore()
    @State private var router = Router()
    @State private var selected: NoticeFilter = .mine

    var body: some View {
        ZStack {
            NavigationStack(path: $router.path) {
                SidebarView(path: $router.path, selected: $selected)
            }
            // 點圖片放大：直接蓋在 App 最上面，不是打開新畫面
            ZoomLayer()
        }
        .tint(Color.brand)
        .environment(store)
        .environment(router)
        .task { await store.refreshIfStale() }
        // 從背景回到 App 也更新（跟 Reeder 一樣）；10 分鐘內更新過就不重複下載
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshIfStale() } }
        }
    }
}

#Preview {
    ContentView()
}

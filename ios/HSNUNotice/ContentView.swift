// 主畫面：照 Reeder 的結構，沒有下方分頁列，所有頁面左右排成一排：
//   設定 ← 側邊欄 → 公告時間軸 → 公告內頁 → 原文（App 裡的 Safari）
// 往右滑回到左邊那一頁，往左滑到右邊那一頁（設定 → 側邊欄；內頁 → 上面那則比較新的公告）。
// 打開 App 時直接停在「我的公告」的時間軸。
// 導覽列、工具列的 Liquid Glass 都是系統內建的。

import SwiftUI

/// 記住目前點到第幾層；任何畫面都可以往裡面加一頁
@Observable
final class Router {
    /// 每一頁在第幾層（path 裡有幾個）：設定是最底層 0，側邊欄 1，時間軸 2，內頁 3
    enum Depth {
        static let settings = 0, sidebar = 1, timeline = 2, article = 3
    }

    var path: NavigationPath
    var zoomed: ZoomedImage?               // 正在放大的圖片，任何頁面點圖片都設定這個
    var lastOpened: Notice.ID?             // 最後看的那則公告：時間軸上用灰色卡片標出來
    var readingList: [Notice] = []         // 點進內頁時那個時間軸上的公告（由新到舊），內頁往左滑換到上面那則用
    var collapsedSections: Set<String> = []  // 側邊欄收起來的段落。側邊欄每次回來都會重建，所以記在這裡

    init() {
        // 打開 App 時直接停在「我的公告」；往右滑一次是側邊欄，再一次是設定
        path = NavigationPath()
        path.append(SidebarRoute())
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
                // 設定是最底層，其他頁都推在它上面
                SettingsView()
                    .navigationDestination(for: SidebarRoute.self) { _ in
                        SidebarView(path: $router.path, selected: $selected)
                    }
                    .navigationDestination(for: NoticeFilter.self) { NoticeTimeline(filter: $0) }
                    .navigationDestination(for: Notice.self) { NoticeDetailView(notice: $0) }
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

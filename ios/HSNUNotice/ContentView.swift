// 主畫面：下方三個分頁。
//
// iOS 26 的 TabView 用 Tab(...) 寫法，系統會自動畫成 Liquid Glass 分頁列。
// 分頁列固定不縮小（tabBarMinimizeBehavior(.never)），捲動時一直都看得到三個分頁。

import SwiftUI

struct ContentView: View {
    @State private var store = NoticeStore()

    var body: some View {
        TabView {
            Tab("我的公告", systemImage: "bell") {
                MyNoticesView()
            }
            Tab("全部公告", systemImage: "list.bullet") {
                AllNoticesView()
            }
            Tab("設定", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.never)
        .tint(Color.brand)
        .environment(store)
        .task { await store.refresh() }
    }
}

/// 「我的公告」：只顯示訂閱的類別和主題
struct MyNoticesView: View {
    @Environment(NoticeStore.self) private var store

    var body: some View {
        NavigationStack {
            NoticeTimeline(
                title: "我的公告",
                subtitle: "訂閱 \(store.subscribed.count) 個類別",
                notices: store.myNotices,
                emptyTitle: store.subscribed.isEmpty ? "還沒有訂閱任何類別" : "目前沒有符合的公告",
                emptyMessage: "到「設定」打開想看的類別"
            )
        }
    }
}

#Preview {
    ContentView()
}

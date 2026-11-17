// 設定頁：選擇要訂閱的類別和主題。
// 照 Reeder：設定是最左邊的一頁，在側邊欄的左邊。在側邊欄往右滑（或按左上角）設定就從左邊滑出來；
// 在設定往左滑（或按右上角）回到側邊欄。
// 米白底色、大標題，每一行是灰色圖示加粗體文字，沒有白色卡片，分組之間用細線隔開。
//
// 注意：不用 List 的 Section 標題。純列表樣式的段落標題會黏在上方，而且自帶白色底，
// 在米白背景上會變成一條白條；所以標題、說明文字都當成普通的一行。

import SwiftUI

struct SettingsView: View {
    @Environment(NoticeStore.self) private var store
    @Environment(Router.self) private var router
    private let repoURL = URL(string: "https://github.com/cyy-615/hsnu-notice")!

    var body: some View {
        List {
            header("類別")
            ForEach(store.categories, id: \.self) { toggle($0, label: $0) }
            note("依公告是哪個處室、哪種事情分類。")
            divider

            header("主題")
            ForEach(store.topics, id: \.self) { toggle($0, label: "#\($0)") }
            note("比類別更細，把同一件事的公告收在一起。#停課 是緊急公告，建議保持開啟。")
            divider

            header("顯示")
            row {
                Toggle(isOn: Binding(get: { store.showUnrelated }, set: { store.showUnrelated = $0 })) {
                    label("顯示跟學生無關的公告", symbol: "eye")
                }
                .tint(Color.brand)
            }
            note("例如教師研習、標案。打開後會出現在「全部公告」，顏色比較淡。")
            divider

            header("關於")
            row {
                label("推播通知", symbol: "bell.slash",
                      detail: "還沒有，請打開 App 下拉更新。想即時收到，可以先加入 Discord 公告頻道。")
            }
            if let updated = store.data?.updated, !updated.isEmpty {
                // 這個時間只有公告有變動才會更新，好幾天沒變不代表壞掉
                row { label("最後一次有新公告", symbol: "clock", detail: updated) }
            }
            row {
                Link(destination: repoURL) {
                    label("原始碼", symbol: "chevron.left.forwardslash.chevron.right", detail: "github.com/cyy-615/hsnu-notice")
                }
            }
            note("只讀取師大附中校網的公開公告，不需要登入，也不會收集任何個人資料。每 30 分鐘檢查一次校網。")
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .paperBackground()
        .foregroundStyle(Color.ink)
        .gesture(LeftSwipeGesture(onChanged: { _ in openSidebar() }))  // 往左滑：回到右邊的側邊欄
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { openSidebar() } label: { Image(systemName: "chevron.forward") }
                    .tint(Color.ink)
                    .accessibilityLabel("回到側邊欄")
            }
        }
    }

    /// 回到右邊的側邊欄。滑的時候會一直被呼叫，只有還停在設定時才推一次
    private func openSidebar() {
        guard router.path.count == Router.Depth.settings else { return }
        router.path.append(SidebarRoute())
    }

    // MARK: - 每一行的樣式（都是普通的一行，沒有白色底、沒有分隔線）

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowBackground(Color.paper)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 10, leading: 22, bottom: 10, trailing: 22))
    }

    private func header(_ text: String) -> some View {
        row {
            Text(text)
                .font(.title3.bold())
                .padding(.top, 8)
        }
    }

    private func note(_ text: String) -> some View {
        row {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// 分組之間的細線
    private var divider: some View {
        row {
            Rectangle().fill(Color.paperChip).frame(height: 1)
        }
    }

    private func label(_ title: String, symbol: String, detail: String? = nil) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color.ink)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }

    private func toggle(_ name: String, label text: String) -> some View {
        row {
            Toggle(isOn: Binding(
                get: { store.isSubscribed(name) },
                set: { store.setSubscribed(name, $0) }
            )) {
                label(text, symbol: TagStyle.symbol(name))
            }
            .tint(Color.brand)
        }
    }
}

// 設定頁：選擇要訂閱的類別和主題。用系統的 Form，導覽列的玻璃效果由系統自動處理。

import SwiftUI

struct SettingsView: View {
    @Environment(NoticeStore.self) private var store
    private let repoURL = URL(string: "https://github.com/cyy-615/hsnu-notice")!

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.categories, id: \.self) { toggle($0, label: $0) }
                } header: {
                    Text("類別")
                } footer: {
                    Text("依公告是哪個處室、哪種事情分類。")
                }

                Section {
                    ForEach(store.topics, id: \.self) { toggle($0, label: "#\($0)") }
                } header: {
                    Text("主題")
                } footer: {
                    Text("比類別更細，把同一件事的公告收在一起。#停課 是緊急公告，建議保持開啟。")
                }

                Section {
                    Label {
                        Text("推播通知還沒有，請打開 App 下拉更新。想即時收到通知，可以先加入班上的 Discord 公告頻道。")
                    } icon: {
                        Image(systemName: "bell.slash")
                    }
                    if let updated = store.data?.updated, !updated.isEmpty {
                        // 這個時間只有公告有變動才會更新，好幾天沒變不代表壞掉
                        LabeledContent("最後一次有新公告", value: updated)
                    }
                    Link(destination: repoURL) {
                        Label("原始碼", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("關於")
                } footer: {
                    Text("只讀取師大附中校網的公開公告，不需要登入，也不會收集任何個人資料。每 30 分鐘檢查一次校網。")
                }
            }
            .navigationTitle("設定")
        }
    }

    private func toggle(_ name: String, label: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { store.isSubscribed(name) },
            set: { store.setSubscribed(name, $0) }
        ))
    }
}

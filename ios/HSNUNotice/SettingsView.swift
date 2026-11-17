// 設定頁：選擇要訂閱的類別和主題。
// 照 Reeder：從側邊欄左上角打開的彈出頁，左上角 X 關閉；米白底色、大標題，
// 每一行是灰色圖示加粗體文字，沒有白色卡片。

import SwiftUI

struct SettingsView: View {
    @Environment(NoticeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let repoURL = URL(string: "https://github.com/cyy-615/hsnu-notice")!

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.categories, id: \.self) { toggle($0, label: $0) }
                } header: {
                    header("類別")
                } footer: {
                    footer("依公告是哪個處室、哪種事情分類。")
                }

                Section {
                    ForEach(store.topics, id: \.self) { toggle($0, label: "#\($0)") }
                } header: {
                    header("主題")
                } footer: {
                    footer("比類別更細，把同一件事的公告收在一起。#停課 是緊急公告，建議保持開啟。")
                }

                Section {
                    Toggle(isOn: Binding(get: { store.showUnrelated }, set: { store.showUnrelated = $0 })) {
                        Label {
                            Text("顯示跟學生無關的公告").font(.headline)
                        } icon: {
                            Image(systemName: "eye").foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.brand)
                    .listRowBackground(Color.paper)
                    .listRowSeparator(.hidden)
                } header: {
                    header("顯示")
                } footer: {
                    footer("例如教師研習、標案。打開後會出現在「全部公告」，顏色比較淡。")
                }

                Section {
                    item("推播通知", symbol: "bell.slash",
                         detail: "還沒有，請打開 App 下拉更新。想即時收到，可以先加入 Discord 公告頻道。")
                    if let updated = store.data?.updated, !updated.isEmpty {
                        // 這個時間只有公告有變動才會更新，好幾天沒變不代表壞掉
                        item("最後一次有新公告", symbol: "clock", detail: updated)
                    }
                    Link(destination: repoURL) {
                        item("原始碼", symbol: "chevron.left.forwardslash.chevron.right", detail: "github.com/cyy-615/hsnu-notice")
                    }
                    .listRowBackground(Color.paper)
                } header: {
                    header("關於")
                } footer: {
                    footer("只讀取師大附中校網的公開公告，不需要登入，也不會收集任何個人資料。每 30 分鐘檢查一次校網。")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .foregroundStyle(Color.ink)
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(Color.ink)
                        .accessibilityLabel("關閉")
                }
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .foregroundStyle(Color.ink)
            .textCase(nil)
            .padding(.top, 12)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func toggle(_ name: String, label: String) -> some View {
        Toggle(isOn: Binding(
            get: { store.isSubscribed(name) },
            set: { store.setSubscribed(name, $0) }
        )) {
            Label {
                Text(label).font(.headline)
            } icon: {
                Image(systemName: TagStyle.symbol(name)).foregroundStyle(.secondary)
            }
        }
        .tint(Color.brand)
        .listRowBackground(Color.paper)
        .listRowSeparator(.hidden)
    }

    private func item(_ title: String, symbol: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color.ink)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
        .listRowBackground(Color.paper)
        .listRowSeparator(.hidden)
    }
}

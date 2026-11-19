// 設定頁：選擇要訂閱的類別和主題，還有外觀（語言、字體、顏色，比照 JuanGo）。
// 從側邊欄左上角打開的彈出頁，左上角 X 關閉；米白底色、大標題，
// 每一行是灰色圖示加粗體文字，沒有白色卡片，分組之間用細線隔開。
//
// 注意：不用 List 的 Section 標題。純列表樣式的段落標題會黏在上方，而且自帶白色底，
// 在米白背景上會變成一條白條；所以標題、說明文字都當成普通的一行。

import SwiftUI

struct SettingsView: View {
    @Environment(NoticeStore.self) private var store
    @Bindable private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    private let repoURL = URL(string: "https://github.com/HowWeiChi-app/BanGo")!

    var body: some View {
        NavigationStack {
            List {
                header(L("類別", "Categories"))
                ForEach(store.categories, id: \.self) { toggle($0, label: TagName.display($0)) }
                note(L("依公告是哪個處室、哪種事情分類。", "Grouped by office and type of notice."))
                divider

                header(L("主題", "Topics"))
                ForEach(store.topics, id: \.self) { toggle($0, label: "#\(TagName.display($0))") }
                note(L("比類別更細，把同一件事的公告收在一起。#停課 是緊急公告，建議保持開啟。", "Narrower than categories: notices about the same thing, together. #停課 is for emergencies, so keep it on."))
                divider

                header(L("顯示", "Display"))
                row {
                    Toggle(isOn: Binding(get: { store.showUnrelated }, set: { store.showUnrelated = $0 })) {
                        label(L("顯示跟學生無關的公告", "Show notices not for students"), symbol: "eye")
                    }
                    .tint(Color.brand)
                }
                note(L("例如教師研習、標案。打開後會出現在「全部公告」，顏色比較淡。", "Like teacher training and tenders. They appear faded in All Notices."))
                divider

                header(L("外觀", "Appearance"))
                row {
                    Picker(selection: $settings.language) {
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    } label: {
                        label(L("語言", "Language"), symbol: "globe")
                    }
                    .tint(Color.inkSecondary)
                }
                row {
                    Picker(selection: $settings.fontStyle) {
                        ForEach(Array(AppFont.options.enumerated()), id: \.offset) { i, o in
                            Text(settings.isEnglish ? o.englishName : o.name).tag(i)
                        }
                    } label: {
                        label(L("字體", "Font"), symbol: "textformat")
                    }
                    .tint(Color.inkSecondary)
                }
                row { ThemeGrid(selection: $settings.themeID) }
                if let d = AppFont.shared.downloading {
                    note(L("正在下載\(d)…", "Downloading \(d)…"))
                } else if let f = AppFont.shared.failed {
                    note(L("\(f)下載失敗，連上網路後再選一次。", "\(f) failed to download. Connect to the internet and choose it again."))
                } else {
                    note(L("選單和提示視窗是系統字體。公告內容是校網的原文，不會翻譯。",
                           "Menus and alerts use the system font. Notices are shown as posted on the school site and aren’t translated."))
                }
                divider

                header(L("關於", "About"))
                row {
                    label(L("推播通知", "Push Notifications"), symbol: "bell.slash",
                          detail: L("還沒有，請打開 App 下拉更新。想即時收到，可以先加入 Discord 公告頻道。", "Not yet. Open the app and pull to refresh, or join the Discord channel for instant updates."))
                }
                if let lastChecked = store.lastChecked {
                    // App 最後一次成功向伺服器確認的時間，公告沒變動也會更新
                    row { label(L("最後一次檢查更新", "Last Update Check"), symbol: "clock", detail: lastChecked) }
                }
                row {
                    Link(destination: repoURL) {
                        label(L("原始碼", "Source Code"), symbol: "chevron.left.forwardslash.chevron.right", detail: "github.com/HowWeiChi-app/BanGo")
                    }
                }
                note(L("只讀取各校校網的公開公告，不需要登入，也不會收集任何個人資料。大約每 10 分鐘檢查一次校網。", "Only reads public notices from school websites. No sign-in, no personal data collected. Sites are checked about every 10 minutes."))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .paperBackground()
            .foregroundStyle(Color.ink)
            .navigationTitle(L("設定", "Settings"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(Color.ink)
                        .accessibilityLabel(L("關閉", "Close"))
                }
            }
        }
        .presentationBackground(Color.paper)  // 彈出頁本身的底色也改成米白，不然邊緣會露出白色
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
                .font(.app(.title3, .bold))
                .padding(.top, 8)
        }
    }

    private func note(_ text: String) -> some View {
        row {
            Text(text)
                .font(.app(.footnote))
                .foregroundStyle(Color.inkSecondary)
        }
    }

    /// 分組之間的細線
    private var divider: some View {
        row {
            Groove()  // 跟時間軸一樣的立體分隔線
        }
    }

    private func label(_ title: String, symbol: String, detail: String? = nil) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(.headline)).foregroundStyle(Color.ink)
                if let detail {
                    Text(detail).font(.app(.subheadline)).foregroundStyle(Color.inkSecondary)
                }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.inkSecondary)
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

/// 選顏色：每一格是紙張顏色的小方塊，下面一條主色寫著名字（照 JuanGo 的 ThemeGrid）。
/// 色票跟 App 實際的顏色一樣，深色模式就顯示深色的紙和深色模式的主色
struct ThemeGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(AppTheme.all) { t in
                Button { selection = t.id } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Aa").font(.app(.title3, .bold)).foregroundStyle(t.accent)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        Spacer(minLength: 0)
                        HStack {
                            // 字用紙張的顏色：深色模式主色調亮了，白字會看不清楚
                            Text(t.displayName).font(.app(.caption, .bold)).foregroundStyle(t.swatch)
                            Spacer()
                            if selection == t.id {
                                Image(systemName: "checkmark").font(.app(.caption, .bold)).foregroundStyle(t.swatch)
                            }
                        }
                        .padding(.horizontal, 10).frame(height: 28).background(t.accent)
                    }
                    .frame(height: 76)
                    .background(t.swatch)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selection == t.id ? Color.ink : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == t.id ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

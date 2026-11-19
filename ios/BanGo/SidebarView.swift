// 側邊欄：排版參考 RSS 閱讀器的側邊欄。
//
// 最上面是「我的公告」（首頁）和「全部公告」，
// 下面是類別、主題、來源三段，段落標題右邊的箭頭可以收合，右邊的數字是有幾則。
// 點任何一項就進到那一種公告的時間軸；往左拉回到上次看的分類（時間軸跟著手指從右邊拉進來，PageStack.swift），
// 跟從時間軸往右拉回來剛好相反。
// 左上角是設定（從下面彈出），右上角是加號（打開設定加訂閱）。

import SwiftUI

/// 側邊欄點進去要看哪一種公告
enum NoticeFilter: Hashable {
    case mine             // 我的公告（符合訂閱的）
    case all              // 全部公告
    case tag(String)      // 類別或主題
    case source(String)   // 來源，例如「重要公告」
}

struct SidebarView: View {
    @Environment(NoticeStore.self) private var store
    @Environment(Router.self) private var router
    @State private var collapsed: Set<String> = []
    @State private var showSettings = false
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        List {
            // 第一段：我的公告、全部公告
            Group {
                SidebarRow(filter: .mine, selected: selected, open: open) {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")  // 我的公告：自己訂閱、在意的
                            .font(.app(.title2))
                            .foregroundStyle(Color.brand)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("我的公告", "My Notices")).font(.app(.title2, .bold))
                            Text(store.subtitle(.mine))
                                .font(.app(.subheadline, .medium))
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
                }
                row(.all, label: L("全部公告", "All Notices"), symbol: "tray.full")
            }
            .padding(.bottom, 4)

            section(L("類別", "Categories")) {
                ForEach(store.categories, id: \.self) { row(.tag($0), label: TagName.display($0), symbol: TagStyle.symbol($0)) }
            }

            section(L("主題", "Topics")) {
                ForEach(store.topics, id: \.self) { row(.tag($0), label: "#\(TagName.display($0))", symbol: TagStyle.symbol($0)) }
            }

            section(L("來源", "Sources")) {
                ForEach(store.sources, id: \.self) { source in
                    SidebarRow(filter: .source(source), selected: selected, count: store.notices(.source(source)).count, open: open) {
                        HStack(spacing: 12) {
                            SourceAvatar(source: source, size: 30)
                            Text(TagName.display(SourceStyle.name(source))).font(.app(.headline))
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        // 工具列跟第一行「我的公告」之間留空，不要貼著工具列
        .contentMargins(.top, 20, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .paperBackground()
        .foregroundStyle(Color.ink)
        .navigationTitle(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "BanGo")  // 跟主畫面的名稱一樣，依系統語言
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .tint(Color.ink)
                .accessibilityLabel(L("設定", "Settings"))
            }
            // 右上角：切換學校，點了跳出學校清單
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $settings.schoolID) {
                        ForEach(School.all) { Text($0.displayName).tag($0.id) }
                    } label: {
                        Text(L("切換學校", "Switch School"))
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: "building.columns")
                }
                .tint(Color.ink)
                .accessibilityLabel(L("切換學校", "Switch School"))
                .accessibilityValue(settings.school.displayName)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // 換學校：時間軸回到「我的公告」（舊學校的分類在新學校可能沒有），載入那間學校的公告
        .onChange(of: settings.schoolID) {
            router.schoolChanged()
            store.schoolChanged()
        }
    }

    /// 目前在看的分類（灰色卡片標出來）
    private var selected: NoticeFilter { router.filter }

    private func open(_ filter: NoticeFilter) {
        router.open(filter)  // 已經在時間軸（或正在過去）就不會再開一次
    }

    private func row(_ filter: NoticeFilter, label: String, symbol: String) -> some View {
        SidebarRow(filter: filter, selected: selected, count: store.notices(filter).count, open: open) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.app(.title3))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(width: 30)
                Text(label).font(.app(.headline))
            }
        }
    }

    /// 可以收合的一段：粗體標題 + 右邊的箭頭
    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let isCollapsed = collapsed.contains(title)
        Button {
            withAnimation(.snappy) {
                if isCollapsed { collapsed.remove(title) } else { collapsed.insert(title) }
            }
        } label: {
            HStack {
                Text(title).font(.app(.title3, .bold))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.app(.headline))
                    .foregroundStyle(Color.inkSecondary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.paper)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 6, trailing: 24))
        .accessibilityValue(isCollapsed ? L("已收合", "Collapsed") : L("已展開", "Expanded"))

        if !isCollapsed {
            content()
        }
    }
}

/// 側邊欄的一行：左邊是內容，右邊是則數的小膠囊；目前看的那一項有灰色底
private struct SidebarRow<Content: View>: View {
    let filter: NoticeFilter
    let selected: NoticeFilter
    var count: Int?
    let open: (NoticeFilter) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button {
            open(filter)
        } label: {
            HStack {
                content
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.app(.subheadline, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.paperChip, in: .capsule)
                }
            }
            // 每一行一樣高：有數字膠囊、沒有數字的、來源頭像，選中的卡片都一樣大
            .frame(minHeight: 32)
        }
        .buttonStyle(SidebarPressStyle(selected: filter == selected))
        .listRowBackground(Color.paper)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
    }
}

/// 側邊欄的點擊效果：按下去或是目前在看的那一項，背後出現立體的玻璃卡片
private struct SidebarPressStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                // 跟時間軸一樣的立體玻璃卡片
                GlassCard(cornerRadius: 16)
                    .opacity(configuration.isPressed || selected ? 1 : 0)
            }
            .contentShape(.rect(cornerRadius: 16))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

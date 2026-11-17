// 側邊欄：App 的第一層，照 Reeder 的側邊欄排版。
//
// 最上面是「我的公告」（像 Reeder 的 Home）和「全部公告」，
// 下面是類別、主題、來源三段，段落標題右邊的箭頭可以收合，右邊的數字是有幾則。
// 點任何一項就進到那一種公告的時間軸；左上角是設定，右上角是重新整理。

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
    @Binding var path: NavigationPath
    @Binding var selected: NoticeFilter
    @State private var collapsed: Set<String> = []
    @State private var showSettings = false

    var body: some View {
        List {
            // 第一段：我的公告、全部公告
            Group {
                SidebarRow(filter: .mine, selected: selected, open: open) {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill")
                            .font(.title2)
                            .foregroundStyle(Color.brand)
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("我的公告").font(.title2.bold())
                            Text(store.subtitle(.mine))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                row(.all, label: "全部公告", symbol: "tray.full")
            }
            .padding(.bottom, 4)

            section("類別") {
                ForEach(store.categories, id: \.self) { row(.tag($0), label: $0, symbol: TagStyle.symbol($0)) }
            }

            section("主題") {
                ForEach(store.topics, id: \.self) { row(.tag($0), label: "#\($0)", symbol: TagStyle.symbol($0)) }
            }

            section("來源") {
                ForEach(store.sources, id: \.self) { source in
                    SidebarRow(filter: .source(source), selected: selected, count: store.notices(.source(source)).count, open: open) {
                        HStack(spacing: 12) {
                            SourceAvatar(source: source, size: 30)
                            Text(SourceStyle.name(source)).font(.headline)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .paperBackground()
        .foregroundStyle(Color.ink)
        .navigationTitle("附中公告")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: {
                    Image(systemName: "switch.2")
                }
                .tint(Color.ink)
                .accessibilityLabel("設定")
            }
            ToolbarItem(placement: .topBarTrailing) {
                RefreshButton()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .navigationDestination(for: NoticeFilter.self) { filter in
            NoticeTimeline(
                title: store.title(filter),
                subtitle: store.subtitle(filter),
                notices: store.notices(filter),
                emptyTitle: filter == .mine && store.subscribed.isEmpty ? "還沒有訂閱任何類別" : "沒有符合的公告",
                emptyMessage: filter == .mine ? "到「設定」打開想看的類別" : "下拉可以重新整理"
            )
        }
        .navigationDestination(for: Notice.self) { NoticeDetailView(notice: $0) }
    }

    private func open(_ filter: NoticeFilter) {
        // 側邊欄是最底層。已經推進時間軸（或正在推進去）就不再推：連點兩下不會疊出兩個時間軸
        guard path.isEmpty else { return }
        selected = filter
        path.append(filter)
    }

    private func row(_ filter: NoticeFilter, label: String, symbol: String) -> some View {
        SidebarRow(filter: filter, selected: selected, count: store.notices(filter).count, open: open) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                Text(label).font(.headline)
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
                Text(title).font(.title3.bold())
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.paper)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 24, leading: 20, bottom: 6, trailing: 24))
        .accessibilityValue(isCollapsed ? "已收合" : "已展開")

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
                        .font(.subheadline.bold())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.paperChip, in: .capsule)
                }
            }
        }
        .buttonStyle(SidebarPressStyle(selected: filter == selected))
        .listRowBackground(Color.paper)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
    }
}

/// 側邊欄的點擊效果：按下去或是目前在看的那一項，背後出現灰色圓角底
private struct SidebarPressStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.paperChip.opacity(configuration.isPressed ? 1 : selected ? 0.7 : 0))
            }
            .contentShape(.rect(cornerRadius: 16))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

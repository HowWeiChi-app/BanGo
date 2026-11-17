// 「全部公告」：參考 Reeder 的側邊欄。
//
// 最上面是「全部公告」，下面分成類別、主題、來源三段，右邊的數字是有幾則。
// 點任何一項就進到那一種公告的時間軸。左上角的按鈕可以切換要不要顯示跟學生無關的公告。

import SwiftUI

/// 側邊欄點進去要看哪一種公告
enum NoticeFilter: Hashable {
    case all
    case tag(String)      // 類別或主題
    case source(String)   // 來源，例如「重要公告」
}

struct AllNoticesView: View {
    @Environment(NoticeStore.self) private var store
    @State private var path = NavigationPath()
    @State private var showUnrelated = false    // 是否顯示跟學生無關的公告

    private var visible: [Notice] {
        (store.data?.notices ?? []).filter { showUnrelated || $0.forStudents }
    }

    private var sources: [String] {
        var seen: [String] = []
        for notice in store.data?.notices ?? [] where !seen.contains(notice.source) {
            seen.append(notice.source)
        }
        return seen
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    SidebarRow(filter: .all, path: $path) {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.fill")
                                .font(.title2)
                                .foregroundStyle(Color.brand)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("全部公告").font(.title2.bold())
                                Text(showUnrelated ? "所有公告" : "跟學生有關的公告")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("類別") {
                    ForEach(store.categories, id: \.self) { name in
                        row(.tag(name), label: name, symbol: TagStyle.symbol(name))
                    }
                }

                Section("主題") {
                    ForEach(store.topics, id: \.self) { name in
                        row(.tag(name), label: "#\(name)", symbol: TagStyle.symbol(name))
                    }
                }

                Section("來源") {
                    ForEach(sources, id: \.self) { source in
                        SidebarRow(filter: .source(source), path: $path, count: count(.source(source))) {
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
            .background(Color.paper)
            .foregroundStyle(Color.ink)
            .navigationTitle("全部公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("顯示跟學生無關的公告", isOn: $showUnrelated)
                    } label: {
                        Image(systemName: "switch.2")
                    }
                    .accessibilityLabel("顯示選項")
                    .tint(Color.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    RefreshButton()
                }
            }
            .navigationDestination(for: NoticeFilter.self) { filter in
                NoticeTimeline(
                    title: title(filter),
                    subtitle: "\(notices(filter).count) 則公告",
                    notices: notices(filter),
                    emptyTitle: "沒有符合的公告"
                )
            }
        }
    }

    private func row(_ filter: NoticeFilter, label: String, symbol: String) -> some View {
        SidebarRow(filter: filter, path: $path, count: count(filter)) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                Text(label).font(.headline)
            }
        }
    }

    private func notices(_ filter: NoticeFilter) -> [Notice] {
        switch filter {
        case .all: visible
        case .tag(let name): visible.filter { $0.has(name) }
        case .source(let source): visible.filter { $0.source == source }
        }
    }

    private func count(_ filter: NoticeFilter) -> Int { notices(filter).count }

    private func title(_ filter: NoticeFilter) -> String {
        switch filter {
        case .all: "全部公告"
        case .tag(let name): store.topics.contains(name) ? "#\(name)" : name
        case .source(let source): SourceStyle.name(source)
        }
    }
}

/// 側邊欄的一行：左邊是內容，右邊是則數的小膠囊，整行可以點
private struct SidebarRow<Content: View>: View {
    let filter: NoticeFilter
    @Binding var path: NavigationPath
    var count: Int?
    @ViewBuilder let content: Content

    var body: some View {
        Button {
            path.append(filter)
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.paper)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}

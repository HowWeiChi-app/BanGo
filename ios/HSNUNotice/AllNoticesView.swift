// 「全部公告」：上方一排 Liquid Glass 篩選按鈕，點類別或主題只看那一種。
//
// 用的是官方 API：
//   GlassEffectContainer — 讓一排玻璃按鈕一起算光影，靠近時會融在一起
//   .glassEffect(.regular.tint(...).interactive(), in: .capsule) — 選中的按鈕帶顏色，按下去有回饋
// 篩選列用 safeAreaInset 放在列表上方，公告捲動時會從玻璃底下穿過。

import SwiftUI

struct AllNoticesView: View {
    @Environment(NoticeStore.self) private var store
    @State private var filter: String?          // nil = 全部
    @State private var showUnrelated = false    // 是否顯示跟學生無關的公告

    private var notices: [Notice] {
        (store.data?.notices ?? [])
            .filter { showUnrelated || $0.forStudents }
            .filter { filter == nil || $0.has(filter!) }
    }

    var body: some View {
        NavigationStack {
            NoticeListView(notices: notices, emptyTitle: "沒有符合的公告", emptyMessage: "換一個類別看看")
                .safeAreaInset(edge: .top, spacing: 0) { filterBar }
                .navigationTitle("全部公告")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Toggle("顯示跟學生無關的公告", isOn: $showUnrelated)
                        } label: {
                            Label("顯示選項", systemImage: "line.3.horizontal.decrease")
                        }
                    }
                }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip("全部", value: nil)
                    ForEach(store.categories, id: \.self) { chip($0, value: $0) }
                    ForEach(store.topics, id: \.self) { chip("#\($0)", value: $0) }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ label: String, value: String?) -> some View {
        let selected = filter == value
        return Button {
            withAnimation(.snappy) { filter = selected ? nil : value }
        } label: {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
    }
}

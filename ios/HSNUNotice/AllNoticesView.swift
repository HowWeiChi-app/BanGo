// 「全部公告」：參考 Reeder，篩選放在標題選單裡，不另外佔一排空間。
//
// 點上方標題（或右上角的篩選按鈕）會跳出選單，選類別或主題就只看那一種，
// 標題會變成選到的名稱，例如「#考試」。導覽列和選單的玻璃效果都是系統內建的。

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

    private var title: String {
        guard let filter else { return "全部公告" }
        return store.topics.contains(filter) ? "#\(filter)" : filter
    }

    var body: some View {
        NavigationStack {
            NoticeListView(notices: notices, emptyTitle: "沒有符合的公告", emptyMessage: "換一個類別看看")
                .navigationTitle(title)
                .toolbarTitleMenu { filterMenu }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu { filterMenu } label: {
                            Label("篩選", systemImage: "line.3.horizontal.decrease")
                        }
                    }
                }
        }
    }

    @ViewBuilder private var filterMenu: some View {
        Picker("篩選", selection: $filter) {
            Text("全部公告").tag(String?.none)
            Section("類別") {
                ForEach(store.categories, id: \.self) { Text($0).tag(Optional($0)) }
            }
            Section("主題") {
                ForEach(store.topics, id: \.self) { Text("#\($0)").tag(Optional($0)) }
            }
        }
        Divider()
        Toggle("顯示跟學生無關的公告", isOn: $showUnrelated)
    }
}

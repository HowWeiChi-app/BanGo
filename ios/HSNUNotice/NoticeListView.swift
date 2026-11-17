// 公告時間軸、單則公告、公告內頁，以及打開校網原文的 Safari。全部照 Reeder 排版：
//   - 左上角玻璃膠囊：側邊欄按鈕 ｜ 標題、副標 ｜ 回到最上面；右上角膠囊：重新整理、搜尋
//   - 每則公告：圓形來源頭像 + 來源名稱 + 分類，右上角是「3h」，下面是粗體標題、灰色摘要、圖片
//   - 上一次點開的那則用灰色圓角卡片標出來，回來時知道看到哪裡
//   - 內頁：來源、大標題、日期、圖片、內文，最後是「原文」連結
// 玻璃效果都是系統的導覽列和工具列自己產生的，沒有自己畫。

import SafariServices
import SwiftUI

/// 公告時間軸，可以下拉更新。沒資料、載入中、載入失敗時顯示對應的提示。
struct NoticeTimeline: View {
    @Environment(NoticeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    let title: String
    let subtitle: String
    let notices: [Notice]
    var emptyTitle = "目前沒有公告"
    var emptyMessage = "下拉可以重新整理"

    @State private var lastOpened: Notice.ID?
    @State private var searching = false
    @State private var query = ""

    /// 搜尋標題和內文
    private var shown: [Notice] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return notices }
        return notices.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.content.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(shown) { notice in
                    Button {
                        lastOpened = notice.id
                        router.path.append(notice)
                    } label: {
                        NoticeRow(notice: notice)
                    }
                    .buttonStyle(CardPressStyle(highlighted: notice.id == lastOpened))
                    // 每一則外面都留 14pt，卡片裡面再留 16pt，所以文字離螢幕邊 30pt（跟 Reeder 一樣）。
                    // 不管有沒有卡片，大小都一樣，點下去排版不會跳。
                    .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                    .listRowBackground(Color.paper)
                    .listRowSeparatorTint(Color.paperChip)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 16 }
                    .alignmentGuide(.listRowSeparatorTrailing) { $0.width - 16 }
                    .id(notice.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .refreshable { await store.refresh() }
            .overlay { placeholder }
            .modifier(SearchIfNeeded(active: $searching, query: $query))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)  // 標題改放在左上角的膠囊裡
            .navigationBarBackButtonHidden()  // 用左上角的側邊欄按鈕代替返回鍵
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        // 回到側邊欄（Reeder 在這裡放的是側邊欄圖示，不是返回箭頭）
                        Button { dismiss() } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel("側邊欄")
                        Divider().frame(height: 26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title).font(.headline).foregroundStyle(Color.ink)
                            Text(subtitle).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        // 先限制最寬 190，再用 fixedSize 讓工具列照文字寬度排，不然會被擠到看不見
                        .frame(maxWidth: 190, alignment: .leading)
                        .fixedSize()
                        Button {
                            if let first = shown.first {
                                withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                            }
                        } label: {
                            Image(systemName: "arrow.up.circle")
                        }
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("回到最上面")
                    }
                    .padding(.horizontal, 6)
                }
                // 兩個按鈕放在同一個 ToolbarItemGroup，系統會把它們包在同一顆玻璃膠囊裡
                ToolbarItemGroup(placement: .topBarTrailing) {
                    RefreshButton()
                    Button {
                        withAnimation { searching.toggle() }
                        if !searching { query = "" }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜尋")
                }
            }
            .tint(Color.ink)  // 工具列圖示用深灰色，跟 Reeder 一樣
        }
    }

    @ViewBuilder private var placeholder: some View {
        if store.data == nil && store.isLoading {
            ProgressView("載入公告中…")
        } else if store.data == nil, let error = store.errorMessage {
            ContentUnavailableView {
                Label("無法載入公告", systemImage: "wifi.slash")
            } description: {
                Text(error)
            } actions: {
                Button("重試") { Task { await store.refresh() } }
                    .buttonStyle(.glassProminent)
            }
        } else if store.data != nil && shown.isEmpty {
            if query.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "tray", description: Text(emptyMessage))
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}

/// 公告的點擊效果：按下去或是上次點開的那則，背後出現灰色圓角卡片（Reeder 的樣子）
private struct CardPressStyle: ButtonStyle {
    let highlighted: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color.paperChip.opacity(configuration.isPressed ? 1 : highlighted ? 0.75 : 0))
            }
            .contentShape(.rect(cornerRadius: 26))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// 按了搜尋按鈕才出現搜尋框（系統的 searchable）
private struct SearchIfNeeded: ViewModifier {
    @Binding var active: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if active {
            content.searchable(text: $query, isPresented: $active,
                               placement: .navigationBarDrawer(displayMode: .always),
                               prompt: "搜尋標題和內文")
        } else {
            content
        }
    }
}

/// 右上角的重新整理按鈕，載入中會變成轉圈圈
struct RefreshButton: View {
    @Environment(NoticeStore.self) private var store

    var body: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            if store.isLoading {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(store.isLoading)
        .tint(Color.ink)
        .accessibilityLabel("重新整理")
    }
}

/// 單則公告
struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SourceAvatar(source: notice.source, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SourceStyle.name(notice.source))
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
                Spacer(minLength: 8)
                Text(notice.relativeTime)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.headline)
                    .foregroundStyle(notice.isUrgent ? Color.red : Color.ink)
                    .lineLimit(4)
                if !notice.summary.isEmpty {
                    Text(notice.summary)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .multilineTextAlignment(.leading)

            if let url = notice.imageURL {
                NoticeImage(url: url, cropTall: true)
            }
        }
        // 跟學生無關的公告整則淡一點
        .opacity(notice.forStudents ? 1 : 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// 頭像旁邊第二行：分類，例如「教務 · #考試」；沒有分類就寫學校名稱
    private var subtitle: String {
        var parts = notice.tags
        if notice.isUrgent { parts.insert("緊急", at: 0) }
        if !notice.forStudents { parts.append("跟學生無關") }
        return parts.isEmpty ? "師大附中" : parts.joined(separator: " · ")
    }
}

/// 公告內頁：照 Reeder 的文章頁
struct NoticeDetailView: View {
    let notice: Notice
    @State private var showOriginal = false

    private var url: URL? { URL(string: notice.url) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    SourceAvatar(source: notice.source, size: 34)
                    Text("hs.ntnu.edu.tw")
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                }
                .padding(.bottom, 14)

                Text(notice.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(notice.isUrgent ? Color.red : Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.longDate)
                    Text("師大附中 · \(SourceStyle.name(notice.source))")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

                if !notice.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notice.tags, id: \.self) { tag in
                            Label(tag, systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                        }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.brand)
                    .padding(.top, 24)
                }

                if let imageURL = notice.imageURL {
                    NoticeImage(url: imageURL)
                        .padding(.top, 24)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(notice.content.split(separator: "\n").enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                    }
                    // 「原文」連結，跟 Reeder 一樣用主色
                    Button { showOriginal = true } label: {
                        Text("[原文]").fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.brand)
                    Text("附件和完整格式要看原文。")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .font(.body)
                .foregroundStyle(Color.ink.opacity(0.85))
                .lineSpacing(5)
                .textSelection(.enabled)
                .padding(.top, 24)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.paper)
        .toolbar(removing: .title)
        .toolbar {
            if let url {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showOriginal = true } label: { Image(systemName: "safari") }
                        .accessibilityLabel("閱讀原文")
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .tint(Color.ink)
        .sheet(isPresented: $showOriginal) {
            if let url { SafariView(url: url).ignoresSafeArea() }
        }
    }
}

/// 前面是小圓點的清單樣式
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.icon.font(.system(size: 6)).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
            configuration.title
        }
    }
}

/// 在 App 裡用 Safari 打開校網原文，看完往下滑就回到 App
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

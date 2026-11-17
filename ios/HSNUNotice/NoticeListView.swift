// 公告時間軸、單則公告、公告內頁，以及打開校網原文的 Safari。
// 排版參考 RSS 閱讀器 Reeder：
//   - 左上角一顆玻璃膠囊放標題、副標和「回到最上面」，右上角放重新整理
//   - 每則公告：圓形來源頭像 + 來源名稱 + 分類，右上角是多久以前，下面是粗體標題
//   - 點公告先進到內頁（大標題、日期、分類），再按「閱讀原文」打開校網
// 玻璃效果都是系統的導覽列和工具列自己產生的，沒有自己畫。

import SafariServices
import SwiftUI

/// 公告時間軸，可以下拉更新。沒資料、載入中、載入失敗時顯示對應的提示。
struct NoticeTimeline: View {
    @Environment(NoticeStore.self) private var store
    let title: String
    let subtitle: String
    let notices: [Notice]
    var emptyTitle = "目前沒有公告"
    var emptyMessage = "下拉可以重新整理"

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(notices) { notice in
                    // 用隱藏的 NavigationLink 蓋在下面，列表右邊才不會多出「>」
                    NoticeRow(notice: notice)
                        .background { NavigationLink(value: notice) { EmptyView() }.opacity(0) }
                        .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                        .listRowBackground(Color.paper)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .id(notice.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .refreshable { await store.refresh() }
            .overlay { placeholder }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)  // 標題改放在左上角的膠囊裡
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title).font(.headline)
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .fixedSize()  // 不然工具列會把文字擠到看不見
                        Button {
                            if let first = notices.first {
                                withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                            }
                        } label: {
                            Image(systemName: "arrow.up.circle")
                        }
                        .accessibilityLabel("回到最上面")
                        .tint(Color.ink)
                    }
                    .padding(.horizontal, 6)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    RefreshButton()
                }
            }
            .navigationDestination(for: Notice.self) { NoticeDetailView(notice: $0) }
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
        } else if store.data != nil && notices.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "tray", description: Text(emptyMessage))
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
        .tint(Color.ink)  // 工具列圖示用深灰色，跟 Reeder 一樣
        .accessibilityLabel("重新整理")
    }
}

/// 單則公告
struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                SourceAvatar(source: notice.source)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SourceStyle.name(notice.source))
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(notice.relativeTime)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(notice.title)
                .font(.headline)
                .foregroundStyle(notice.isUrgent ? Color.red : Color.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(4)
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

/// 公告內頁：校網的 RSS 只有標題，所以這裡顯示標題、日期、分類，按「閱讀原文」看全文
struct NoticeDetailView: View {
    let notice: Notice
    @State private var showOriginal = false

    private var url: URL? { URL(string: notice.url) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    SourceAvatar(source: notice.source, size: 30)
                    Text("hs.ntnu.edu.tw")
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                }

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

                if !notice.tags.isEmpty || !notice.forStudents {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notice.tags, id: \.self) { tag in
                            Label(tag, systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                                .foregroundStyle(Color.brand)
                        }
                        if !notice.forStudents {
                            Label("爬蟲判斷這則跟學生無關", systemImage: "circle.fill")
                                .labelStyle(BulletLabelStyle())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.body.weight(.semibold))
                    .padding(.top, 8)
                }

                Button {
                    showOriginal = true
                } label: {
                    Label("閱讀原文", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Color.brand)
                .padding(.top, 16)

                Text("校網的通知只提供標題，完整內容和附件要看原文。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.paper)
        .toolbar(removing: .title)
        .toolbar {
            if let url {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showOriginal = true } label: { Image(systemName: "safari") }
                        .accessibilityLabel("閱讀原文")
                        .tint(Color.ink)
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .tint(Color.ink)
                }
            }
        }
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

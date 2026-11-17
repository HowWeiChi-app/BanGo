// 公告列表、單則公告，以及點公告時打開的校網頁面。

import SafariServices
import SwiftUI

/// 可以下拉更新的公告列表。沒資料、載入中、載入失敗時顯示對應的提示。
struct NoticeListView: View {
    @Environment(NoticeStore.self) private var store
    let notices: [Notice]
    let emptyTitle: String
    let emptyMessage: String

    @State private var opened: Notice?

    var body: some View {
        List(notices) { notice in
            Button { opened = notice } label: {
                NoticeRow(notice: notice)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .refreshable { await store.refresh() }
        .overlay { placeholder }
        .sheet(item: $opened) { notice in
            if let url = URL(string: notice.url) {
                SafariView(url: url).ignoresSafeArea()
            }
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

/// 單則公告
struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if notice.isUrgent {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("緊急")
                }
                Text(notice.title)
                    .font(.body.weight(.medium))
                    // 跟學生無關的公告用淡一點的顏色
                    .foregroundStyle(notice.forStudents ? .primary : .secondary)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 6) {
                Text("\(notice.date) · \(notice.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ForEach(notice.tags, id: \.self) { TagLabel(text: $0) }
                if !notice.forStudents {
                    TagLabel(text: "跟學生無關", muted: true)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

/// 公告上的小標籤，例如「教務」「#考試」
struct TagLabel: View {
    let text: String
    var muted = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .background(muted ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint.opacity(0.15)), in: .capsule)
            .lineLimit(1)
            .fixedSize()
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

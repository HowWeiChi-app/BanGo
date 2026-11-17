// 公告列表、單則公告，以及點公告時打開的校網頁面。

import SafariServices
import SwiftUI

/// 可以下拉更新的公告列表，參考 Reeder 的時間軸排版：
/// 依日期分段（今天、昨天、11月13日 星期四），每則公告上面一行是來源和時間，下面是粗體標題。
/// 沒資料、載入中、載入失敗時顯示對應的提示。
struct NoticeListView: View {
    @Environment(NoticeStore.self) private var store
    let notices: [Notice]
    let emptyTitle: String
    let emptyMessage: String

    @State private var opened: Notice?

    var body: some View {
        List {
            ForEach(DaySection.group(notices)) { section in
                Section {
                    ForEach(section.notices) { notice in
                        Button { opened = notice } label: {
                            NoticeRow(notice: notice)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                    }
                } header: {
                    Text(section.title)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
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

/// 同一天的公告
struct DaySection: Identifiable {
    let id: String           // "2026-11-16"
    let title: String        // "今天"、"昨天"、"11月13日 星期四"
    let notices: [Notice]

    /// 公告本來就是由新到舊，照日期（字串前 10 個字）切段
    static func group(_ notices: [Notice], now: Date = .now) -> [DaySection] {
        var sections: [DaySection] = []
        for notice in notices {
            let day = String(notice.date.prefix(10))
            if let last = sections.last, last.id == day {
                sections[sections.count - 1] = DaySection(id: day, title: last.title, notices: last.notices + [notice])
            } else {
                sections.append(DaySection(id: day, title: title(for: notice.postedAt, fallback: day, now: now), notices: [notice]))
            }
        }
        return sections
    }

    private static func title(for date: Date?, fallback: String, now: Date) -> String {
        guard let date else { return fallback }
        let calendar = Calendar.taipei
        if calendar.isDate(date, inSameDayAs: now) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "昨天" }
        return date.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_TW")))
    }
}

extension Calendar {
    /// 用台灣時間判斷「今天」「昨天」，出國或改了手機時區也不會錯
    static let taipei: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }()
}

/// 單則公告：上面一行是來源圖示、來源名稱、時間，下面是標題和分類
struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SourceIcon(source: notice.source)
                Text(notice.source.isEmpty ? "校網" : notice.source)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if notice.isUrgent {
                    Text("緊急")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 8)
                Text(timeText)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Text(notice.title)
                .font(.headline)
                .foregroundStyle(notice.isUrgent ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .multilineTextAlignment(.leading)
                .lineLimit(4)

            if !notice.tags.isEmpty || !notice.forStudents {
                Text(tagText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        // 跟學生無關的公告整則淡一點
        .opacity(notice.forStudents ? 1 : 0.55)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// 今天的公告顯示「3 小時前」，更早的只顯示時間（日期已經在分段標題上）
    private var timeText: String {
        guard let date = notice.postedAt else { return "" }
        let minutes = Int(Date.now.timeIntervalSince(date) / 60)
        if Calendar.taipei.isDateInToday(date) && minutes >= 0 {
            if minutes < 1 { return "剛剛" }
            if minutes < 60 { return "\(minutes) 分鐘前" }
            return "\(minutes / 60) 小時前"
        }
        return String(notice.date.suffix(5))  // "15:16"
    }

    private var tagText: String {
        var parts = notice.tags
        if !notice.forStudents { parts.append("跟學生無關") }
        return parts.joined(separator: " · ")
    }
}

/// 來源的小圖示，像 RSS 閱讀器裡每個網站的小 icon
struct SourceIcon: View {
    let source: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(color.gradient, in: .rect(cornerRadius: 5))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch source {
        case "重要公告": "megaphone.fill"
        case "學生": "person.2.fill"
        case "來文公告": "envelope.fill"
        case "行事曆": "calendar"
        default: "doc.text.fill"
        }
    }

    private var color: Color {
        switch source {
        case "重要公告": .orange
        case "學生": .blue
        case "來文公告": .teal
        case "行事曆": .purple
        default: .gray
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

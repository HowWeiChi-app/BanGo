// 負責拿到公告資料、記住訂閱設定。所有畫面都從這裡讀資料。
//
// 資料來源：GitHub 上爬蟲 commit 的 notices.json（跟 Android 版同一份）。
// 下載成功會存一份在手機上，下次打開或沒網路時先顯示上次的資料。

import Foundation
import Observation

@Observable
final class NoticeStore {
    static let dataURL = URL(string: "https://raw.githubusercontent.com/cyy-615/hsnu-notice/main/scraper/data/notices.json")!

    /// 第一次打開 App 時預設訂閱的項目：只開最重要的，避免一開始就太吵。
    /// 「停課」是緊急公告，一定要預設打開。
    static let defaultSubscriptions: Set<String> = ["教務", "學務", "考試", "停課"]

    // 還沒載入到資料時，設定頁用這兩個清單（跟爬蟲 filters.py 一致）
    static let fallbackCategories = ["教務", "學務", "輔導", "獎學金", "比賽"]
    static let fallbackTopics = ["考試", "停課"]

    private static let subscriptionsKey = "subscribed"

    var data: NoticeData?
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private var shownBytes: Data?            // 現在顯示的資料的原始檔，用來判斷下載到的有沒有變
    @ObservationIgnored private var lastAttempt: Date?           // 上一次開始更新的時間
    @ObservationIgnored private var running: Task<Void, Never>?  // 正在進行的更新

    var subscribed: Set<String> {
        didSet { UserDefaults.standard.set(Array(subscribed), forKey: Self.subscriptionsKey) }
    }

    /// 全部公告裡要不要顯示跟學生無關的（教師研習、標案…），預設不顯示
    var showUnrelated: Bool {
        didSet { UserDefaults.standard.set(showUnrelated, forKey: Self.showUnrelatedKey) }
    }
    private static let showUnrelatedKey = "showUnrelated"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.subscriptionsKey)
        subscribed = saved.map(Set.init) ?? Self.defaultSubscriptions
        showUnrelated = UserDefaults.standard.bool(forKey: Self.showUnrelatedKey)
        // 打開 App 時先顯示上次的資料。這裡故意不放到背景：第一個畫面就要有公告，不要先閃一下空白
        if let bytes = try? Data(contentsOf: Self.cacheURL),
           let cached = try? JSONDecoder().decode(NoticeData.self, from: bytes) {
            data = cached
            shownBytes = bytes
        }
    }

    // MARK: - 給畫面用的資料

    var categories: [String] { data?.categories ?? Self.fallbackCategories }
    var topics: [String] { data?.topics ?? Self.fallbackTopics }

    /// 「我的公告」：符合訂閱的
    var myNotices: [Notice] { (data?.notices ?? []).filter { $0.matches(subscribed) } }

    /// 側邊欄每一項對應的公告
    func notices(_ filter: NoticeFilter) -> [Notice] {
        let visible = (data?.notices ?? []).filter { showUnrelated || $0.forStudents }
        return switch filter {
        case .mine: myNotices
        case .all: visible
        case .tag(let name): visible.filter { $0.has(name) }
        case .source(let source): visible.filter { $0.source == source }
        }
    }

    /// 資料裡出現過的來源，照第一次出現的順序
    var sources: [String] {
        var seen: [String] = []
        for notice in data?.notices ?? [] where !seen.contains(notice.source) {
            seen.append(notice.source)
        }
        return seen
    }

    func title(_ filter: NoticeFilter) -> String {
        switch filter {
        case .mine: "我的公告"
        case .all: "全部公告"
        case .tag(let name): topics.contains(name) ? "#\(name)" : name
        case .source(let source): SourceStyle.name(source)
        }
    }

    func subtitle(_ filter: NoticeFilter) -> String {
        switch filter {
        case .mine: "訂閱 \(subscribed.count) 個類別"
        case .all: showUnrelated ? "所有公告" : "跟學生有關的公告"
        default: "\(notices(filter).count) 則公告"
        }
    }

    func isSubscribed(_ name: String) -> Bool { subscribed.contains(name) }

    func setSubscribed(_ name: String, _ on: Bool) {
        if on { subscribed.insert(name) } else { subscribed.remove(name) }
    }

    // MARK: - 下載

    /// 打開 App、從背景回到 App 時用：距離上次更新不到 10 分鐘就不重新下載
    func refreshIfStale() async {
        if let lastAttempt, Date.now.timeIntervalSince(lastAttempt) < 10 * 60 { return }
        await refresh()
    }

    /// 重新下載。已經在下載了就等那一次，不會同時下載兩份
    func refresh() async {
        if let running {
            await running.value
            return
        }
        lastAttempt = .now
        let task = Task { await load() }
        running = task
        await task.value
        running = nil
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // 不用手機上的網路快取，確保拿到最新的
            let request = URLRequest(url: Self.dataURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            errorMessage = nil
            // 跟現在顯示的一模一樣（大部分時候都是）：不用重新解析，畫面也不用重畫
            guard bytes != shownBytes else { return }
            data = try await Self.decodeAndSave(bytes)
            shownBytes = bytes
        } catch {
            errorMessage = "更新失敗，請檢查網路"
        }
    }

    /// 在背景執行緒解析 JSON、存備份。公告內文很多，放在主執行緒解析會讓畫面頓一下
    @concurrent
    nonisolated private static func decodeAndSave(_ bytes: Data) async throws -> NoticeData {
        let decoded = try JSONDecoder().decode(NoticeData.self, from: bytes)
        try? bytes.write(to: cacheURL, options: .atomic)  // 解析成功才存，壞掉的資料不會蓋掉備份
        return decoded
    }

    // MARK: - 存在手機上的備份

    nonisolated private static var cacheURL: URL {
        URL.cachesDirectory.appending(path: "notices.json")
    }
}

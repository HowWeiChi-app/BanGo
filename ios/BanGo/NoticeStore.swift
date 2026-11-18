// 負責拿到公告資料、記住訂閱設定。所有畫面都從這裡讀資料。
//
// 資料來源：GitHub 上爬蟲 commit 的 notices.json（跟 Android 版同一份），每間學校一份（School.dataURL）。
// 下載成功會存一份在手機上，下次打開或沒網路時先顯示上次的資料。

import Foundation
import Observation

@Observable
final class NoticeStore {
    /// 第一次打開 App 時預設訂閱的項目：只開最重要的，避免一開始就太吵。
    /// 「停課」是緊急公告，一定要預設打開。
    static let defaultSubscriptions: Set<String> = ["教務", "學務", "考試", "停課"]

    // 還沒載入到資料時，設定頁用這兩個清單（跟爬蟲 filters.py 一致）
    static let fallbackCategories = ["教務", "學務", "輔導", "獎學金", "比賽"]
    static let fallbackTopics = ["考試", "停課"]

    private static let subscriptionsKey = "subscribed"

    var data: NoticeData? { didSet { clearCache() } }
    var isLoading = false
    var errorMessage: String?
    var lastChecked: String?      // 這間學校最後一次成功檢查更新的時間，公告沒變動也算

    @ObservationIgnored private var shownBytes: Data?            // 現在顯示的資料的原始檔，用來判斷下載到的有沒有變
    @ObservationIgnored private var lastAttempt: Date?           // 上一次開始更新的時間
    @ObservationIgnored private var running: Task<Void, Never>?  // 正在進行的更新
    @ObservationIgnored private var lastSchool = ""               // 上一次下載的是哪間學校

    var subscribed: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(subscribed), forKey: Self.subscriptionsKey)
            clearCache()
        }
    }

    /// 全部公告裡要不要顯示跟學生無關的（教師研習、標案…），預設不顯示
    var showUnrelated: Bool {
        didSet {
            UserDefaults.standard.set(showUnrelated, forKey: Self.showUnrelatedKey)
            clearCache()
        }
    }
    private static let showUnrelatedKey = "showUnrelated"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.subscriptionsKey)
        subscribed = saved.map(Set.init) ?? Self.defaultSubscriptions
        showUnrelated = UserDefaults.standard.bool(forKey: Self.showUnrelatedKey)
        // 打開 App 時先顯示上次的資料。這裡故意不放到背景：第一個畫面就要有公告，不要先閃一下空白
        loadCache()
    }

    /// 先顯示手機上這間學校的備份（沒有就是空的）
    private func loadCache() {
        lastChecked = UserDefaults.standard.string(forKey: Self.lastCheckedKey(AppSettings.shared.schoolID))
        if let bytes = try? Data(contentsOf: AppSettings.shared.school.cacheURL),
           let cached = try? JSONDecoder().decode(NoticeData.self, from: bytes) {
            data = cached
            shownBytes = bytes
        } else {
            data = nil
            shownBytes = nil
        }
    }

    /// 設定裡換了學校：換成那間學校的備份，再馬上下載最新的
    func schoolChanged() {
        loadCache()
        errorMessage = nil
        lastAttempt = nil
        Task { await refresh() }
    }

    // MARK: - 給畫面用的資料

    var categories: [String] { data?.categories ?? Self.fallbackCategories }
    var topics: [String] { data?.topics ?? Self.fallbackTopics }

    /// 「我的公告」：符合訂閱的
    /// 只看這學期的公告：上學期從 8/1 開始（到隔年 1 月底），下學期從 2/1 開始（到 7 月底）
    static func semesterStart(_ now: Date = .now) -> Date {
        let calendar = taipei
        let year = calendar.component(.year, from: now), month = calendar.component(.month, from: now)
        let start = switch month {
        case 8...12: DateComponents(year: year, month: 8, day: 1)
        case 1: DateComponents(year: year - 1, month: 8, day: 1)
        default: DateComponents(year: year, month: 2, day: 1)
        }
        return calendar.date(from: start) ?? .distantPast
    }

    private static let taipei: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }()

    // MARK: 算好的清單（快取）
    // 側邊欄每一行的數字、時間軸、副標題都要「這一類有哪些公告」。每次畫面重畫（換頁、按下去、載入中轉圈）
    // 都重新篩選整份公告的話，側邊欄一次要篩二十幾遍，換頁會頓。資料、訂閱、顯示設定沒變就直接用上次的結果。
    // 這些快取不參與畫面更新的追蹤（@ObservationIgnored）；讀的時候還是會讀 data、subscribed、showUnrelated，
    // 所以它們一變，用到的畫面照樣會重畫，那時候快取已經清掉、會重新算
    @ObservationIgnored private var semesterCache: (start: Date, notices: [Notice])?
    @ObservationIgnored private var filterCache: [NoticeFilter: [Notice]] = [:]
    @ObservationIgnored private var sourcesCache: [String]?

    private func clearCache() {
        semesterCache = nil
        filterCache = [:]
        sourcesCache = nil
    }

    /// 這學期的公告（時間看不懂的留著，寧可多顯示也不要漏掉）
    var semesterNotices: [Notice] {
        let all = data?.notices ?? []  // 先讀 data：資料換了，用到的畫面才會重畫
        let start = Self.semesterStart()
        if let cached = semesterCache, cached.start == start { return cached.notices }
        let result = all.filter { ($0.postedAt ?? .distantFuture) >= start }
        // 跨學期（例如 App 開著過了 8/1）：其他清單也要重算
        filterCache = [:]
        sourcesCache = nil
        semesterCache = (start, result)
        return result
    }

    var myNotices: [Notice] { notices(.mine) }

    /// 側邊欄每一項對應的公告
    func notices(_ filter: NoticeFilter) -> [Notice] {
        let unrelated = showUnrelated, subscribed = subscribed  // 先讀：設定改了，用到的畫面才會重畫
        let semester = semesterNotices
        if let cached = filterCache[filter] { return cached }
        let visible = { semester.filter { unrelated || $0.forStudents } }
        let result = switch filter {
        case .mine: semester.filter { $0.matches(subscribed) }
        case .all: visible()
        case .tag(let name): visible().filter { $0.has(name) }
        case .source(let source): visible().filter { $0.source == source }
        }
        filterCache[filter] = result
        return result
    }

    /// 資料裡出現過的來源，照第一次出現的順序
    var sources: [String] {
        let semester = semesterNotices
        if let cached = sourcesCache { return cached }
        var seen: [String] = []
        var set = Set<String>()
        for notice in semester where set.insert(notice.source).inserted {
            seen.append(notice.source)
        }
        sourcesCache = seen
        return seen
    }

    func title(_ filter: NoticeFilter) -> String {
        switch filter {
        case .mine: L("我的公告", "My Notices")
        case .all: L("全部公告", "All Notices")
        case .tag(let name): topics.contains(name) ? "#\(TagName.display(name))" : TagName.display(name)
        case .source(let source): TagName.display(SourceStyle.name(source))
        }
    }

    func subtitle(_ filter: NoticeFilter) -> String {
        switch filter {
        case .mine: L("訂閱 \(subscribed.count) 個類別", "\(subscribed.count) subscriptions")
        case .all: showUnrelated ? L("所有公告", "Every notice") : L("跟學生有關的公告", "Notices for students")
        default: L("\(notices(filter).count) 則公告", "\(notices(filter).count) notices")
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
        if Demo.isOn { return }  // 展示模式固定用截圖腳本放進來的公告
        if let running {
            await running.value
            // 等的那一次是換學校之前開始的：再抓一次現在這間
            if lastSchool == AppSettings.shared.schoolID { return }
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
        let school = AppSettings.shared.school
        lastSchool = school.id
        do {
            // 不用手機上的網路快取，確保拿到最新的
            let request = URLRequest(url: school.dataURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (bytes, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            // 下載途中換了學校：這份是舊學校的，不要顯示
            guard school.id == AppSettings.shared.schoolID else { return }
            errorMessage = nil
            // 跟現在顯示的一模一樣（大部分時候都是）：不用重新解析，畫面也不用重畫
            if bytes != shownBytes {
                let decoded = try await Self.decodeAndSave(bytes, to: school.cacheURL)
                guard school.id == AppSettings.shared.schoolID else { return }
                data = decoded
                shownBytes = bytes
            }
            markChecked(school.id)
        } catch {
            errorMessage = L("更新失敗，請檢查網路", "Update failed. Check your connection.")
        }
    }

    private static func lastCheckedKey(_ schoolID: String) -> String { "lastChecked_\(schoolID)" }

    /// 記下這次檢查成功的時間，下次打開 App 也看得到
    private func markChecked(_ schoolID: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let text = formatter.string(from: .now)
        lastChecked = text
        UserDefaults.standard.set(text, forKey: Self.lastCheckedKey(schoolID))
    }

    /// 在背景執行緒解析 JSON、存備份。公告內文很多，放在主執行緒解析會讓畫面頓一下
    @concurrent
    nonisolated private static func decodeAndSave(_ bytes: Data, to cacheURL: URL) async throws -> NoticeData {
        let decoded = try JSONDecoder().decode(NoticeData.self, from: bytes)
        try? bytes.write(to: cacheURL, options: .atomic)  // 解析成功才存，壞掉的資料不會蓋掉備份
        return decoded
    }
}

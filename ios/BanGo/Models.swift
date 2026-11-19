// 公告的資料格式，跟爬蟲輸出的 scraper/data/notices.json 一一對應。
// Android 版（app/lib/models.dart）讀的是同一份資料，爬蟲那邊的欄位改了，兩邊都要跟著改。

import Foundation

// nonisolated：這兩個資料格式不屬於主執行緒，才能在背景執行緒解析 JSON（見 NoticeStore）

nonisolated struct Notice: Codable, Identifiable, Hashable {
    let title: String
    let date: String          // "2026-11-16 15:16"
    let url: String           // 校網原文網址，也是公告的唯一 ID
    var dept: String = ""     // 處室，師大附中抓不到，通常是空字串
    var source: String = ""   // "重要公告"、"學生"、"來文公告"、"行事曆"
    var categories: [String] = []
    var topics: [String] = []
    var forStudents: Bool = true  // false = 爬蟲判定跟學生無關（教師研習、標案…）
    var content: String = ""  // 公告內文（純文字，段落用換行分開），舊資料可能是空的
    var image: String = ""    // 內文裡第一張圖片的網址

    // 下面三個在解碼時就先算好存起來。列表捲動時每一則都會重畫很多次，
    // 每次都重新處理整篇內文、重新解析日期會讓捲動變卡。

    /// 列表上的摘要：內文前 150 個字（段落接在一起）。畫面上最多只顯示 4 行，
    /// 只留 150 字讓文字排版快很多；完整內文在內頁看。
    private(set) var summary = ""
    private(set) var imageURL: URL?
    /// 把 "2026-11-16 15:16"（台灣時間）轉成 Date，格式不對時是 nil
    private(set) var postedAt: Date?

    var id: String { url }

    /// 顯示用的標籤，主題前面加 #，例如 ["教務", "#考試"]
    var tags: [String] { categories + topics.map { "#\($0)" } }

    /// 是否屬於某個類別或主題
    func has(_ name: String) -> Bool { categories.contains(name) || topics.contains(name) }

    /// 跟爬蟲的 should_push 規則一樣：跟學生有關，而且屬於任何一個訂閱的類別或主題
    func matches(_ subscribed: Set<String>) -> Bool {
        forStudents && (categories + topics).contains(where: subscribed.contains)
    }

    /// 是不是緊急公告（停課、颱風）
    var isUrgent: Bool { topics.contains("停課") }

    /// 列表右上角的時間，很短。中文：「剛剛」「5 分鐘」「3 小時」「2 天」；
    /// 英文用短寫：「now」「5m」「3h」「2d」。超過一週顯示「11/3」
    @MainActor var relativeTime: String {
        guard let posted = postedAt else { return "" }
        let minutes = max(0, Int(Date.now.timeIntervalSince(posted) / 60))
        switch minutes {
        case ..<1: return L("剛剛", "now")
        case ..<60: return L("\(minutes) 分鐘", "\(minutes)m")
        case ..<(60 * 24): return L("\(minutes / 60) 小時", "\(minutes / 60)h")
        case ..<(60 * 24 * 7): return L("\(minutes / 60 / 24) 天", "\(minutes / 60 / 24)d")
        default:
            let parts = date.prefix(10).split(separator: "-").compactMap { Int($0) }
            return parts.count == 3 ? "\(parts[1])/\(parts[2])" : ""
        }
    }

    /// 內頁的完整日期，例如「2026年11月17日 星期二 14:30」
    @MainActor var longDate: String {
        guard let posted = postedAt else { return date }
        let locale = Locale(identifier: AppSettings.shared.isEnglish ? "en_US" : "zh_TW")
        var style = Date.FormatStyle(date: .complete, time: .shortened, locale: locale)
        style.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return posted.formatted(style)
    }

    private static let taipei: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }()

    /// "2026-11-16 15:16"（台灣時間）→ Date。直接拆數字，比 DateFormatter 快，也可以在背景執行緒用
    private static func parseDate(_ text: String) -> Date? {
        let n = text.split { !$0.isASCII || !$0.isNumber }.compactMap { Int($0) }
        guard n.count >= 5 else { return nil }
        return taipei.date(from: DateComponents(year: n[0], month: n[1], day: n[2], hour: n[3], minute: n[4]))
    }

    enum CodingKeys: String, CodingKey {
        case title, date, url, dept, source, categories, topics, content, image
        case forStudents = "for_students"
    }

    // 自己寫解碼：JSON 少了某個欄位時用預設值，不要整份資料讀不出來
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        dept = try c.decodeIfPresent(String.self, forKey: .dept) ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? []
        forStudents = try c.decodeIfPresent(Bool.self, forKey: .forStudents) ?? true
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        image = try c.decodeIfPresent(String.self, forKey: .image) ?? ""
        prepare()
    }

    init(title: String, date: String, url: String, source: String = "",
         categories: [String] = [], topics: [String] = [], forStudents: Bool = true) {
        self.title = title
        self.date = date
        self.url = url
        self.source = source
        self.categories = categories
        self.topics = topics
        self.forStudents = forStudents
        prepare()
    }

    /// 先算好列表要用的資料
    private mutating func prepare() {
        postedAt = Notice.parseDate(date)
        imageURL = image.isEmpty ? nil : URL(string: image)
        let joined = content.split(separator: "\n").joined(separator: " ")
        summary = joined.count > 150 ? String(joined.prefix(150)) + "…" : joined
    }
}

nonisolated struct NoticeData: Codable {
    var updated: String = ""          // 最後一次有新公告的時間
    var categories: [String] = []     // 所有類別，設定頁用來產生開關
    var topics: [String] = []         // 所有主題
    var notices: [Notice] = []        // 由新到舊
}

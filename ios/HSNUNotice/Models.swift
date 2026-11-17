// 公告的資料格式，跟爬蟲輸出的 scraper/data/notices.json 一一對應。
// Android 版（app/lib/models.dart）讀的是同一份資料，爬蟲那邊的欄位改了，兩邊都要跟著改。

import Foundation

struct Notice: Codable, Identifiable, Hashable {
    let title: String
    let date: String          // "2026-11-16 15:16"
    let url: String           // 校網原文網址，也是公告的唯一 ID
    var dept: String = ""     // 處室，師大附中抓不到，通常是空字串
    var source: String = ""   // "重要公告"、"學生"、"來文公告"、"行事曆"
    var categories: [String] = []
    var topics: [String] = []
    var forStudents: Bool = true  // false = 爬蟲判定跟學生無關（教師研習、標案…）

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

    /// 把 "2026-11-16 15:16"（台灣時間）轉成 Date，格式不對時是 nil
    var postedAt: Date? { Notice.dateParser.date(from: date) }

    private static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    enum CodingKeys: String, CodingKey {
        case title, date, url, dept, source, categories, topics
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
    }
}

struct NoticeData: Codable {
    var updated: String = ""          // 最後一次有新公告的時間
    var categories: [String] = []     // 所有類別，設定頁用來產生開關
    var topics: [String] = []         // 所有主題
    var notices: [Notice] = []        // 由新到舊
}

// 公告的資料格式，跟爬蟲輸出的 scraper/data/notices.json 一一對應。
// 爬蟲那邊的欄位改了，這裡也要跟著改。

class Notice {
  const Notice({
    required this.title,
    required this.date,
    required this.url,
    this.dept = '',
    this.source = '',
    this.categories = const [],
    this.topics = const [],
    this.forStudents = true,
  });

  final String title;
  final String date; // "2026-11-16 15:16"
  final String url; // 校網原文網址，也是公告的唯一 ID
  final String dept; // 處室，師大附中抓不到，通常是空字串
  final String source; // "重要公告" 或 "來文公告"
  final List<String> categories; // 例如 ["教務"]
  final List<String> topics; // 例如 ["考試"]
  final bool forStudents; // false = 爬蟲判定跟學生無關（教師研習、標案…）

  factory Notice.fromJson(Map<String, dynamic> json) {
    return Notice(
      title: json['title'] as String? ?? '',
      date: json['date'] as String? ?? '',
      url: json['url'] as String? ?? '',
      dept: json['dept'] as String? ?? '',
      source: json['source'] as String? ?? '',
      categories: List<String>.from(json['categories'] as List? ?? const []),
      topics: List<String>.from(json['topics'] as List? ?? const []),
      forStudents: json['for_students'] as bool? ?? true,
    );
  }

  /// 顯示用的標籤，主題前面加 #，例如 ["教務", "#考試"]
  List<String> get tags => [...categories, ...topics.map((t) => '#$t')];

  /// 是否屬於某個類別或主題
  bool hasTag(String name) => categories.contains(name) || topics.contains(name);

  /// 跟爬蟲的 should_push 規則一樣：跟學生有關，而且屬於任何一個訂閱的類別或主題
  bool matches(Set<String> subscribed) =>
      forStudents && [...categories, ...topics].any(subscribed.contains);
}

class NoticeData {
  const NoticeData({
    required this.updated,
    required this.categories,
    required this.topics,
    required this.notices,
  });

  final String updated; // 爬蟲最後一次更新資料的時間
  final List<String> categories; // 所有類別，設定頁用來產生開關
  final List<String> topics; // 所有主題
  final List<Notice> notices; // 由新到舊

  factory NoticeData.fromJson(Map<String, dynamic> json) {
    return NoticeData(
      updated: json['updated'] as String? ?? '',
      categories: List<String>.from(json['categories'] as List? ?? const []),
      topics: List<String>.from(json['topics'] as List? ?? const []),
      notices: (json['notices'] as List? ?? const [])
          .map((e) => Notice.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

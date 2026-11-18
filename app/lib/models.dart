// 公告的資料格式，跟爬蟲輸出的 scraper/data/notices.json 一一對應。
// 爬蟲那邊的欄位改了，這裡也要跟著改。

import 'settings.dart';

class Notice {
  Notice({
    required this.title,
    required this.date,
    required this.url,
    this.dept = '',
    this.source = '',
    this.categories = const [],
    this.topics = const [],
    this.forStudents = true,
    this.content = '',
    this.image = '',
  })  : summary = _summary(content),
        postedAt = _parseDate(date);

  final String title;
  final String date; // "2026-11-16 15:16"（台灣時間）
  final String url; // 校網原文網址，也是公告的唯一 ID
  final String dept; // 處室：北一女、成功、中山有，附中、建中是空字串
  final String source; // 分類，例如 "重要公告"
  final List<String> categories; // 例如 ["教務"]
  final List<String> topics; // 例如 ["考試"]
  final bool forStudents; // false = 爬蟲判定跟學生無關（教師研習、標案…）
  final String content; // 內文（純文字，段落用換行分開）
  final String image; // 內文裡第一張圖片的網址

  /// 列表上的摘要：內文前 150 個字（段落接在一起）。完整內文在內頁看
  final String summary;

  /// 發布時間（換算成 UTC），格式不對時是 null
  final DateTime? postedAt;

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
      content: json['content'] as String? ?? '',
      image: json['image'] as String? ?? '',
    );
  }

  String get id => url;

  /// 顯示用的標籤，主題前面加 #，例如 ["教務", "#考試"]
  List<String> get tags => [...categories, ...topics.map((t) => '#$t')];

  /// 是否屬於某個類別或主題
  bool hasTag(String name) => categories.contains(name) || topics.contains(name);

  /// 跟爬蟲的 should_push 規則一樣：跟學生有關，而且屬於任何一個訂閱的類別或主題
  bool matches(Set<String> subscribed) => forStudents && [...categories, ...topics].any(subscribed.contains);

  /// 是不是緊急公告（停課、颱風）
  bool get isUrgent => topics.contains('停課');

  Uri? get imageUri => image.isEmpty ? null : Uri.tryParse(image);

  /// 列表右上角的時間，很短。中文：「剛剛」「5 分鐘」「3 小時」「2 天」；英文：「now」「5m」「3h」「2d」。超過一週顯示「11/3」
  String relativeTime([DateTime? now]) {
    final posted = postedAt;
    if (posted == null) return '';
    final minutes = (now ?? DateTime.now()).difference(posted).inMinutes;
    if (minutes < 1) return L('剛剛', 'now');
    if (minutes < 60) return L('$minutes 分鐘', '${minutes}m');
    if (minutes < 60 * 24) return L('${minutes ~/ 60} 小時', '${minutes ~/ 60}h');
    if (minutes < 60 * 24 * 7) return L('${minutes ~/ 1440} 天', '${minutes ~/ 1440}d');
    final parts = date.length >= 10 ? date.substring(0, 10).split('-') : <String>[];
    return parts.length == 3 ? '${int.parse(parts[1])}/${int.parse(parts[2])}' : '';
  }

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  static const _weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'];

  /// 內頁的完整日期：「2026年11月17日 星期二 下午2:33」／「Tuesday, November 17, 2026 at 2:33 PM」
  String get longDate {
    final posted = postedAt;
    if (posted == null) return date;
    final t = posted.add(const Duration(hours: 8)); // 台灣時間（UTC+8），用 UTC 的欄位讀
    final hour12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    if (AppSettings.shared.isEnglish) {
      return '${_weekdaysEn[t.weekday - 1]}, ${_months[t.month - 1]} ${t.day}, ${t.year} at $hour12:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
    }
    return '${t.year}年${t.month}月${t.day}日 星期${_weekdays[t.weekday - 1]} ${t.hour < 12 ? '上午' : '下午'}$hour12:$minute';
  }

  static String _summary(String content) {
    final joined = content.split('\n').join(' ');
    return joined.length > 150 ? joined.substring(0, 150) : joined;
  }

  /// "2026-11-16 15:16"（台灣時間）→ UTC 的 DateTime
  static DateTime? _parseDate(String text) {
    final n = RegExp(r'\d+').allMatches(text).map((m) => int.parse(m.group(0)!)).toList();
    if (n.length < 5) return null;
    return DateTime.utc(n[0], n[1], n[2], n[3], n[4]).subtract(const Duration(hours: 8));
  }
}

class NoticeData {
  const NoticeData({
    required this.updated,
    required this.categories,
    required this.topics,
    required this.notices,
  });

  final String updated; // 爬蟲最後一次有新公告的時間
  final List<String> categories; // 所有類別，設定頁用來產生開關
  final List<String> topics; // 所有主題
  final List<Notice> notices; // 由新到舊

  factory NoticeData.fromJson(Map<String, dynamic> json) {
    return NoticeData(
      updated: json['updated'] as String? ?? '',
      categories: List<String>.from(json['categories'] as List? ?? const []),
      topics: List<String>.from(json['topics'] as List? ?? const []),
      notices: (json['notices'] as List? ?? const []).map((e) => Notice.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

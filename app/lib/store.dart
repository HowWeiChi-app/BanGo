// 負責拿到公告資料、記住訂閱設定。所有畫面都從這裡讀資料。
//
// 資料來源：GitHub 上爬蟲 commit 的 notices.json，每間學校一份（School.dataUrl）。
// 下載成功會存一份在手機上，下次打開或沒網路時先顯示上次的資料。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'settings.dart';

/// 時間軸顯示哪一種公告
class NoticeFilter {
  const NoticeFilter._(this.kind, [this.name = '']);
  static const mine = NoticeFilter._('mine'); // 我的公告（符合訂閱的）
  static const all = NoticeFilter._('all'); // 全部公告
  const NoticeFilter.tag(String name) : this._('tag', name); // 類別或主題
  const NoticeFilter.source(String name) : this._('source', name); // 來源，例如「重要公告」

  final String kind;
  final String name;

  @override
  bool operator ==(Object other) => other is NoticeFilter && other.kind == kind && other.name == name;
  @override
  int get hashCode => Object.hash(kind, name);
}

/// 下載資料的方式；測試時換成假的
typedef Fetcher = Future<String> Function(Uri url);

Future<String> _httpFetch(Uri url) async {
  final res = await http.get(url).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) throw Exception('伺服器回應 ${res.statusCode}');
  return utf8.decode(res.bodyBytes); // 用 bodyBytes 自己解碼，確保中文是用 UTF-8 解讀
}

class NoticeStore extends ChangeNotifier {
  NoticeStore({Fetcher? fetcher}) : _fetch = fetcher ?? _httpFetch;

  final Fetcher _fetch;

  /// 第一次打開 App 時預設訂閱的項目：只開最重要的，避免一開始就太吵。「停課」是緊急公告，一定要預設打開
  static const defaultSubscriptions = {'教務', '學務', '考試', '停課'};
  static const fallbackCategories = ['教務', '學務', '輔導', '獎學金', '比賽'];
  static const fallbackTopics = ['考試', '停課'];

  NoticeData? data;
  bool isLoading = false;
  String? errorMessage;
  String? lastChecked; // 這間學校最後一次成功檢查更新的時間，公告沒變動也算
  Set<String> subscribed = {...defaultSubscriptions};
  bool showUnrelated = false; // 全部公告裡要不要顯示跟學生無關的（教師研習、標案…）

  SharedPreferences? _prefs;
  String? _shownText; // 現在顯示的資料的原始檔，用來判斷下載到的有沒有變
  DateTime? _lastAttempt;
  Future<void>? _running;
  String _lastSchool = '';

  /// 打開 App 時先讀設定和上次的資料，第一個畫面就要有公告
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs!.getStringList('subscribed');
    if (saved != null) subscribed = saved.toSet();
    showUnrelated = _prefs!.getBool('showUnrelated') ?? false;
    _loadCache();
  }

  static String _lastCheckedKey(String schoolID) => 'lastChecked_$schoolID';

  /// 記下這次檢查成功的時間，下次打開 App 也看得到
  Future<void> _markChecked(String schoolID) async {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    lastChecked = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    await _prefs?.setString(_lastCheckedKey(schoolID), lastChecked!);
  }

  void _loadCache() {
    lastChecked = _prefs?.getString(_lastCheckedKey(AppSettings.shared.schoolID));
    final text = _prefs?.getString(AppSettings.shared.school.cacheKey);
    data = null;
    _shownText = null;
    if (text == null) return;
    try {
      data = NoticeData.fromJson(jsonDecode(text) as Map<String, dynamic>);
      _shownText = text;
    } catch (_) {} // 存的資料壞掉就當作沒有
  }

  // MARK: 給畫面用的資料

  List<String> get categories => data?.categories ?? fallbackCategories;
  List<String> get topics => data?.topics ?? fallbackTopics;

  /// 只看這學期的公告：上學期從 8/1 開始（到隔年 1 月底），下學期從 2/1 開始（到 7 月底）
  static DateTime semesterStart([DateTime? now]) {
    final t = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8)); // 台灣的年月
    final start = switch (t.month) {
      >= 8 => DateTime.utc(t.year, 8, 1),
      1 => DateTime.utc(t.year - 1, 8, 1),
      _ => DateTime.utc(t.year, 2, 1),
    };
    return start.subtract(const Duration(hours: 8)); // 台灣時間的 0 點
  }

  /// 這學期的公告（時間看不懂的留著，寧可多顯示也不要漏掉）
  List<Notice> get semesterNotices {
    final start = semesterStart();
    return (data?.notices ?? const <Notice>[]).where((n) => n.postedAt == null || !n.postedAt!.isBefore(start)).toList();
  }

  List<Notice> get myNotices => semesterNotices.where((n) => n.matches(subscribed)).toList();

  /// 側邊欄每一項對應的公告
  List<Notice> notices(NoticeFilter filter) {
    final visible = semesterNotices.where((n) => showUnrelated || n.forStudents);
    return switch (filter.kind) {
      'mine' => myNotices,
      'all' => visible.toList(),
      'tag' => visible.where((n) => n.hasTag(filter.name)).toList(),
      _ => visible.where((n) => n.source == filter.name).toList(),
    };
  }

  /// 資料裡出現過的來源，照第一次出現的順序
  List<String> get sources {
    final seen = <String>[];
    for (final n in semesterNotices) {
      if (!seen.contains(n.source)) seen.add(n.source);
    }
    return seen;
  }

  String title(NoticeFilter filter) => switch (filter.kind) {
        'mine' => L('我的公告', 'My Notices'),
        'all' => L('全部公告', 'All Notices'),
        'tag' => topics.contains(filter.name) ? '#${TagName.display(filter.name)}' : TagName.display(filter.name),
        _ => TagName.display(SourceStyle.name(filter.name)),
      };

  String subtitle(NoticeFilter filter) {
    switch (filter.kind) {
      case 'mine':
        return L('訂閱 ${subscribed.length} 個類別', '${subscribed.length} subscriptions');
      case 'all':
        return showUnrelated ? L('所有公告', 'Every notice') : L('跟學生有關的公告', 'Notices for students');
      default:
        final count = notices(filter).length;
        return L('$count 則公告', '$count notices');
    }
  }

  bool isSubscribed(String name) => subscribed.contains(name);

  void setSubscribed(String name, bool on) {
    subscribed = {...subscribed};
    on ? subscribed.add(name) : subscribed.remove(name);
    notifyListeners();
    _prefs?.setStringList('subscribed', subscribed.toList());
  }

  void setShowUnrelated(bool on) {
    showUnrelated = on;
    notifyListeners();
    _prefs?.setBool('showUnrelated', on);
  }

  /// 設定裡換了學校：換成那間學校的備份，再馬上下載最新的
  void schoolChanged() {
    _loadCache();
    errorMessage = null;
    _lastAttempt = null;
    notifyListeners();
    refresh();
  }

  // MARK: 下載

  /// 打開 App、從背景回到 App 時用：距離上次更新不到 10 分鐘就不重新下載
  Future<void> refreshIfStale() async {
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) return;
    await refresh();
  }

  /// 重新下載。已經在下載了就等那一次，不會同時下載兩份
  Future<void> refresh() async {
    final running = _running;
    if (running != null) {
      await running;
      if (_lastSchool == AppSettings.shared.schoolID) return; // 等的那一次是換學校之前開始的：再抓一次
    }
    _lastAttempt = DateTime.now();
    final task = _load();
    _running = task;
    await task;
    _running = null;
  }

  Future<void> _load() async {
    isLoading = true;
    notifyListeners();
    final school = AppSettings.shared.school;
    _lastSchool = school.id;
    try {
      final text = await _fetch(school.dataUrl);
      if (school.id != AppSettings.shared.schoolID) return; // 下載途中換了學校：這份是舊學校的，不要顯示
      errorMessage = null;
      if (text != _shownText) {
        data = NoticeData.fromJson(jsonDecode(text) as Map<String, dynamic>);
        _shownText = text;
        await _prefs?.setString(school.cacheKey, text); // 解析成功才存，壞掉的資料不會蓋掉備份
      }
      await _markChecked(school.id);
    } catch (_) {
      errorMessage = L('更新失敗，請檢查網路', 'Update failed. Check your connection.');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}

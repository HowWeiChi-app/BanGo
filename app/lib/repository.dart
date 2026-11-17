// 負責「拿到公告資料」：從網路下載，並存一份在手機上，沒網路時也能看上次的資料。
//
// 目前資料來源是 GitHub 上爬蟲 commit 的 notices.json。
// 之後接上 Firebase 時，只要改這個檔案，畫面的程式碼都不用動。

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const dataUrl =
    'https://raw.githubusercontent.com/cyy-615/hsnu-notice/main/scraper/data/notices.json';

class NoticeRepository {
  static const _cacheKey = 'notices_cache';

  /// 讀取上次存在手機上的資料；沒有的話回傳 null。
  Future<NoticeData?> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_cacheKey);
    if (text == null) return null;
    try {
      return NoticeData.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return null; // 存的資料壞掉就當作沒有
    }
  }

  /// 從網路下載最新資料，成功的話順便存到手機上。失敗會丟出例外。
  Future<NoticeData> fetch() async {
    final res = await http.get(Uri.parse(dataUrl)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('伺服器回應 ${res.statusCode}');
    }
    // 用 bodyBytes 自己解碼，確保中文是用 UTF-8 解讀
    final text = utf8.decode(res.bodyBytes);
    final data = NoticeData.fromJson(jsonDecode(text) as Map<String, dynamic>);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, text);
    return data;
  }
}

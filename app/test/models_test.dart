// 測試資料解析和篩選規則。執行：flutter test

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hsnu_notice/models.dart';

// 跟爬蟲輸出的 notices.json 同樣格式的範例
const sampleJson = '''
{
 "updated": "2026-11-17 13:06",
 "categories": ["教務", "學務", "輔導", "獎學金", "比賽"],
 "topics": ["考試"],
 "notices": [
  {"title": "115學年第1學期_第二次期中考_考試範圍", "date": "2026-11-16 15:16", "dept": "",
   "url": "https://www.hs.ntnu.edu.tw/content?a=1", "source": "重要公告",
   "categories": ["教務"], "topics": ["考試"], "for_students": true},
  {"title": "AI導入數位教學教師增能系列研習", "date": "2026-11-16 09:55", "dept": "",
   "url": "https://www.hs.ntnu.edu.tw/content?a=2", "source": "來文公告",
   "categories": [], "topics": [], "for_students": false},
  {"title": "清寒獎學金申請", "date": "2026-11-15 10:00", "dept": "",
   "url": "https://www.hs.ntnu.edu.tw/content?a=3", "source": "重要公告",
   "categories": ["獎學金"], "topics": [], "for_students": true}
 ]
}
''';

void main() {
  final data = NoticeData.fromJson(jsonDecode(sampleJson) as Map<String, dynamic>);

  test('解析 notices.json', () {
    expect(data.updated, '2026-11-17 13:06');
    expect(data.topics, ['考試']);
    expect(data.notices.length, 3);
    final exam = data.notices.first;
    expect(exam.title, '115學年第1學期_第二次期中考_考試範圍');
    expect(exam.tags, ['教務', '#考試']);
    expect(data.notices[1].forStudents, isFalse);
  });

  test('只訂閱「考試」主題', () {
    final mine = data.notices.where((n) => n.matches({'考試'})).map((n) => n.title);
    expect(mine, ['115學年第1學期_第二次期中考_考試範圍']);
  });

  test('跟學生無關的公告不管訂閱什麼都不會出現', () {
    final all = {...data.categories, ...data.topics};
    expect(data.notices[1].matches(all), isFalse);
  });

  test('缺欄位時不會壞掉', () {
    final n = Notice.fromJson({'title': '只有標題'});
    expect(n.url, '');
    expect(n.tags, isEmpty);
    expect(n.forStudents, isTrue);
  });
}

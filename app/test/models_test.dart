// 測試資料解析和篩選規則。執行：flutter test

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bango/article_page.dart';
import 'package:bango/extras.dart';
import 'package:bango/models.dart';
import 'package:bango/store.dart';

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

  test('學期從 8/1、2/1 開始（台灣時間）', () {
    expect(NoticeStore.semesterStart(DateTime.utc(2026, 11, 18)), DateTime.utc(2026, 7, 31, 16));
    expect(NoticeStore.semesterStart(DateTime.utc(2027, 1, 10)), DateTime.utc(2026, 7, 31, 16));
    expect(NoticeStore.semesterStart(DateTime.utc(2027, 3, 1)), DateTime.utc(2027, 1, 31, 16));
  });

  test('相對時間', () {
    final exam = data.notices.first; // 2026-11-16 15:16 台灣時間
    expect(exam.relativeTime(DateTime.utc(2026, 11, 16, 7, 20)), '4 分鐘');
    expect(exam.relativeTime(DateTime.utc(2026, 11, 17, 7, 16)), '1 天');
    expect(exam.relativeTime(DateTime.utc(2026, 12, 30)), '11/16');
  });

  test('附中內頁的附件和參考網站', () {
    const html = '<div class="file_odd"><h3>參考資料</h3><ul><li>'
        '<a class="download_btn x" href="/static/webroot/a.pdf" download="考試範圍.pdf">下載</a></li></ul></div>'
        '<div class="link_odd"><h3>參考網站</h3><ul><li><a href="https://example.org/?a=1&amp;b=2" title="報名">報名網站</a></li></ul></div>';
    final e = ExtrasParser.parse(html, Uri.parse('https://www.hs.ntnu.edu.tw/content?a=1'));
    expect(e.files.single.name, '考試範圍.pdf');
    expect(e.files.single.url.toString(), 'https://www.hs.ntnu.edu.tw/static/webroot/a.pdf');
    expect(e.files.single.isPdf, isTrue);
    expect(e.links.single.title, '報名網站');
    expect(e.links.single.url.toString(), 'https://example.org/?a=1&b=2');
  });

  test('建中（NSS）的附件', () {
    const html = r"<h4>{{ $t('FEZ012') }}</h4><button><a href=" '"/uploads/x.pdf"' r"><span><svg><path/></svg> 實施計畫.pdf</span></a></button>"
        r"<h4>{{ $t('FEZ013') }}</h4><a href=" '"https://ck.example/form"' r">報名表單</a><hr><a href=" '"/other"' r">其他</a>";
    final e = ExtrasParser.parse(html, Uri.parse('https://www.ck.tp.edu.tw/nss/main/freeze/x'));
    expect(e.files.map((f) => f.name), ['實施計畫.pdf']);
    expect(e.files.single.url.toString(), 'https://www.ck.tp.edu.tw/uploads/x.pdf');
    expect(e.links.map((l) => l.title), ['報名表單']);
  });

  test('WordPress 學校的附件，重複的只留一個', () {
    const item = '<ul class="nojs_modal_list"><li><a href="https://www.fg.tp.edu.tw/wp-content/uploads/a.pdf">簡章&#8211;最新.pdf</a></li></ul>';
    final e = ExtrasParser.parse(item + item, Uri.parse('https://www.fg.tp.edu.tw/?p=1'));
    expect(e.files.map((f) => f.name), ['簡章–最新.pdf']);
  });

  test('內文的網址變成連結，後面的中文和標點不算', () {
    final links = Linkify.find('報名網址：https://forms.gle/abc123。或 www.example.com/x）詳見');
    expect(links.map((l) => l.url), ['https://forms.gle/abc123', 'https://www.example.com/x']);
  });
}

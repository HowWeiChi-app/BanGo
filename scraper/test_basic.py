"""執行方式：在 scraper 資料夾裡跑  python3 -m unittest -v"""

import tempfile
import unittest
from datetime import datetime
from unittest import mock
from pathlib import Path

from export import load_notices, merge, save_notices
from filters import KEYWORD_CATEGORIES, TOPICS, classify, should_push
from notify_fcm import FCM_TOPICS, build_message
from notice import Notice
from parser import FetchError, ParseError, parse_rss
from notify_discord import MAX_LEN, build_messages, format_notice
from store import TAIPEI, find_new, is_recent, load_seen, save_seen


def make(title, dept="", url=None):
    return Notice(title=title, date="2026-11-17 08:00", dept=dept, url=url or f"https://example.edu.tw/{title}")


class FilterTest(unittest.TestCase):
    def test_dept_category(self):
        n = classify(make("115學年度第一學期第二次段考日程", dept="教務處"))
        self.assertEqual(n.categories, ["教務"])
        self.assertTrue(n.for_students)

    def test_keyword_category(self):
        n = classify(make("清寒獎學金申請公告", dept="學務處"))
        self.assertEqual(n.categories, ["學務", "獎學金"])

    def test_exclude(self):
        n = classify(make("本校115年度電腦設備採購案", dept="總務處"))
        self.assertFalse(n.for_students)
        self.assertFalse(should_push(n, {"教務", "學務"}))

    def test_push_only_subscribed(self):
        n = classify(make("全國科展競賽報名", dept="教務處"))
        self.assertTrue(should_push(n, {"比賽"}))
        self.assertFalse(should_push(n, {"輔導"}))


# 師大附中的真實公告標題（2026-11-17）→ (應該分到的類別, 是否跟學生有關)
# 調整 filters.py 之後跑一次測試，就知道有沒有把原本對的弄壞。
REAL_TITLES = [
    ("115學年第1學期_第二次期中考_考試範圍", ["教務"], True),
    ("公告本校116繁星推薦校內推薦作業實施辦法【115.11.05通過】", ["教務"], True),
    ("115年11月15日-愛校服務(週輔)暨改過銷過名單", ["學務"], True),
    ("116年青年生涯領航計畫實體說明會及企劃撰寫工作坊（高三學生）", ["輔導"], True),
    ("115學年度第1學期課業輔導檢核表", ["教務"], True),  # 不是輔導室的事
    ("公告115學年度校內動態國語文競賽優勝名單", ["比賽"], True),
    ("115年度新購Hyread電子書及台灣全文資料庫歡迎使用", [], True),
    ("朝陽科技大學資訊學院資訊管理系、資訊工程系、資訊與通訊系共同辦理「2026年畢業專題成果展」之活動訊息", [], True),
    ("臺北市數位實驗高級中等學校辦理「AI導入數位教學教師增能系列研習」線上教師研習", [], False),
    ("公告本校116學年上下學期教育實習甄選錄取名單", [], False),
    ("轉知國立臺北大學116學年度碩士在職專班招生簡章，請查照。", [], False),
    ("臺北市立第一女子高級中學辦理「『肌』不可失：肌電訊號與智慧醫療科技應用」師生增能研習", [], True),
]


class TopicTest(unittest.TestCase):
    def test_exam_topic(self):
        self.assertEqual(classify(make("115學年第1學期_第二次期中考_考試範圍")).topics, ["考試"])
        self.assertEqual(classify(make("115學年度第1學期期末考試日程表")).topics, ["考試"])
        self.assertEqual(classify(make("115學年度補考名單及時間")).topics, ["考試"])
        # 學期行事曆有考試日期；暑假、圖書館的行事曆沒有
        self.assertEqual(classify(make("115學年度第1學期行事曆")).topics, ["考試"])
        self.assertEqual(classify(make("115學年度暑假行事曆")).topics, [])
        self.assertEqual(classify(make("113學年度第2學期圖書館行事曆")).topics, [])
        # 學測報名不是校內考試日程，不收進來
        self.assertEqual(classify(make("【重要】檢核學測、英語第二次及術科考試報名結果")).topics, [])

    def test_subscribe_topic_only(self):
        exam = classify(make("115學年第1學期_第二次期中考_考試範圍"))
        other = classify(make("115學年度學生學習歷程檔案系統上傳時程重要通知"))  # 教務，但不是考試
        self.assertTrue(should_push(exam, {"考試"}))
        self.assertFalse(should_push(other, {"考試"}))


class RealTitleTest(unittest.TestCase):
    def test_real_titles(self):
        for title, categories, for_students in REAL_TITLES:
            with self.subTest(title=title):
                n = classify(make(title))
                self.assertEqual(n.categories, categories)
                self.assertEqual(n.for_students, for_students)


# 從師大附中「重要公告」RSS 實際擷取的兩則（2026-11-17）
SAMPLE_RSS = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"><channel><title>重要公告</title>
<item><title>公告115學年度第一學期代辦費收入情形一覽表</title><link>https://www.hs.ntnu.edu.tw/content?a=T0RESVRYcGpNMDE2UlROT1ZGVTl3TUdSUEJ6YTY1RWUwc0dWaW50ZWx5</link><description>&lt;p&gt;詳如附件&lt;/p&gt;</description><pubDate>2026-11-17 08:14:40</pubDate></item>
<item><title>115學年第1學期_第二次期中考_考試範圍</title><link>https://www.hs.ntnu.edu.tw/content?a=T0RESVRXcE5NRTlFWXpKT2Vtczk2VkVSUEJ6YTY1RWUwc0dWaW50ZWx5</link><description>&lt;p&gt;詳如附件&lt;/p&gt;</description><pubDate>2026-11-16 15:16:47</pubDate></item>
</channel></rss>""".encode("utf-8")


class ParserTest(unittest.TestCase):
    def test_parse_sample(self):
        notices = parse_rss(SAMPLE_RSS, "重要公告")
        self.assertEqual(len(notices), 2)
        self.assertEqual(notices[1].title, "115學年第1學期_第二次期中考_考試範圍")
        self.assertEqual(notices[1].date, "2026-11-16 15:16")
        self.assertEqual(notices[1].source, "重要公告")
        self.assertTrue(notices[1].url.startswith("https://www.hs.ntnu.edu.tw/content?a="))

    def test_fetch_retries_then_gives_up(self):
        import parser as p
        calls = []

        def always_fail(req, timeout):
            calls.append(1)
            raise OSError("連線逾時")

        with mock.patch.object(p.urllib.request, "urlopen", always_fail), \
                mock.patch.object(p.time, "sleep", lambda s: None):  # 測試時不要真的等
            with self.assertRaises(FetchError):
                p.fetch("https://example.edu.tw/rss")
        self.assertEqual(len(calls), 3)

    def test_broken_rss_raises(self):
        with self.assertRaises(ParseError):
            parse_rss("<html>網站維護中</html>".encode("utf-8"), "重要公告")


class StoreTest(unittest.TestCase):
    def test_seen_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "data" / "seen.json"
            self.assertIsNone(load_seen(path))  # 第一次執行
            save_seen(path, {make("A").url, make("B").url})

            seen = load_seen(path)
            current = [make("C"), make("A"), make("B")]
            self.assertEqual([n.title for n in find_new(current, seen)], ["C"])
            # 存檔後再比對一次，就不會重複
            save_seen(path, seen | {n.url for n in current})
            self.assertEqual(find_new(current, load_seen(path)), [])


class RecentTest(unittest.TestCase):
    def test_only_recent_notices_are_pushed(self):
        now = datetime(2026, 11, 17, 13, 0, tzinfo=TAIPEI)
        self.assertTrue(is_recent(Notice("今天", "2026-11-17 08:00", "", "u1"), now))
        self.assertTrue(is_recent(Notice("前天下午", "2026-11-15 14:00", "", "u2"), now))
        self.assertFalse(is_recent(Notice("上學期行事曆", "2026-09-21 09:16", "", "u3"), now))
        self.assertTrue(is_recent(Notice("日期壞掉", "不知道", "", "u4"), now))  # 寧可推也不要漏


class ExportTest(unittest.TestCase):
    def test_merge_and_save(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "notices.json"
            old = [Notice("舊的期中考公告", "2026-11-01 08:00", "", "https://x/1")]
            current = [Notice("新的獎學金公告", "2026-11-17 08:00", "", "https://x/2")]
            self.assertTrue(save_notices(path, merge(old, current)))

            loaded = load_notices(path)
            self.assertEqual([n.title for n in loaded], ["新的獎學金公告", "舊的期中考公告"])  # 新的在前
            self.assertEqual(loaded[1].topics, ["考試"])  # 舊公告也有重新分類
            # 內容沒變就不寫檔
            self.assertFalse(save_notices(path, merge(loaded, current)))


class FcmTest(unittest.TestCase):
    def test_every_category_and_topic_has_fcm_topic(self):
        # 新增類別或主題卻忘了加 FCM 主題名稱，訂閱的同學會收不到推播
        for name in list(KEYWORD_CATEGORIES) + list(TOPICS):
            self.assertIn(name, FCM_TOPICS)
        for topic_id in FCM_TOPICS.values():
            self.assertRegex(topic_id, r"^[a-zA-Z0-9\-_.~%]+$")

    def test_one_message_for_multiple_tags(self):
        n = classify(make("115學年第1學期_第二次期中考_考試範圍"))
        msg = build_message(n)["message"]
        self.assertEqual(msg["condition"], "'academic' in topics || 'exam' in topics")
        self.assertEqual(msg["notification"]["body"], n.title)
        self.assertEqual(msg["data"]["url"], n.url)

    def test_no_tags_no_message(self):
        self.assertIsNone(build_message(classify(make("115年度新購Hyread電子書"))))


class DiscordMessageTest(unittest.TestCase):
    def test_format(self):
        n = classify(make("115學年第1學期_第二次期中考_考試範圍"))
        text = format_notice(n)
        self.assertIn("**115學年第1學期_第二次期中考_考試範圍**", text)
        self.assertIn("教務 · #考試", text)
        self.assertIn(f"<{n.url}>", text)

    def test_urgent_notice_stands_out(self):
        n = classify(make("颱風來襲，明日（11/18）停課一天"))
        self.assertIn("停課", n.topics)
        self.assertTrue(format_notice(n).startswith("🚨"))
        self.assertTrue(format_notice(classify(make("期中考考試範圍"))).startswith("📢"))

    def test_split_under_limit(self):
        notices = [classify(make(f"第{i}則期中考公告" + "很長" * 30)) for i in range(40)]
        messages = build_messages(notices)
        self.assertGreater(len(messages), 1)  # 太長要拆成好幾則
        self.assertTrue(all(len(m) <= MAX_LEN for m in messages))
        self.assertEqual(sum(m.count("**第") for m in messages), 40)  # 一則都沒漏


if __name__ == "__main__":
    unittest.main()

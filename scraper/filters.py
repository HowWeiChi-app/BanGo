"""公告分類與過濾規則。

規則全部集中在這個檔案最上面的幾個表，要調整只改表就好，不用動下面的函式。
注意：被排除的公告只是「不推播」，仍然會出現在 App 的「全部公告」列表。

師大附中的 RSS 沒有處室欄位，所以分類主要靠標題關鍵字（KEYWORD_CATEGORIES）。
這些關鍵字是根據 2026-11-17 抓到的 50 則真實公告挑的，之後看到漏掉或分錯的再補。
"""

from notice import Notice

# 處室名稱 → 類別。給有處室欄位的學校用；師大附中用不到。
DEPT_CATEGORIES = {
    "教務": "教務",
    "學務": "學務",
    "輔導": "輔導",
}

# 類別 → 標題關鍵字。標題包含任何一個字，就算這個類別。一則公告可以同時屬於好幾個類別。
KEYWORD_CATEGORIES = {
    "教務": ["考試", "期中考", "期末考", "段考", "學測", "分科測驗", "統測", "繁星", "推薦",
             "成績", "學分", "補考", "重修", "選課", "課程", "學習歷程", "課業輔導",
             "畢業條件", "畢業典禮"],  # 不用「畢業」，不然大學的「畢業專題成果展」也會算進來
    "學務": ["停課", "颱風", "請假", "銷過", "獎懲", "愛校服務", "社團", "校慶", "運動會",
             "健康檢查", "制服"],
    # 不用「輔導」兩個字，因為「課業輔導」是教務處的事
    "輔導": ["輔導室", "生涯", "升學", "招生訊息", "單獨招生", "心理"],
    "獎學金": ["獎學金", "助學金"],
    "比賽": ["比賽", "競賽", "錦標賽"],
}

# 主題 → 標題關鍵字。主題比類別細，用來把「同一件事」的公告收在一起，
# 例如 App 裡可以有一個「考試」分頁，只放考試日程、範圍、補考。
# 類別回答「這是哪個處室的事」，主題回答「這是在講什麼」。一則公告兩種都可以有。
# 要新增主題，在這裡加一行就好，例如 "停課": ["停課", "颱風假"]。
TOPICS = {
    "考試": ["期中考", "期末考", "段考", "模擬考", "複習考", "補考",
             "考試範圍", "考試日程", "考程", "考試時程",
             # 學期行事曆裡有期中考、期末考的日期。用「學期行事曆」而不是「行事曆」，
             # 才不會收到「暑假行事曆」「第2學期圖書館行事曆」
             "學期行事曆"],
    # 緊急公告：Discord 會用 🚨 標示，App 預設訂閱
    "停課": ["停課", "停班", "颱風", "防颱"],
}

# 這些主題是緊急公告，通知要比較明顯
URGENT_TOPICS = {"停課"}

# 標題出現這些字，就判定跟學生無關、不推播……
EXCLUDE_KEYWORDS = [
    "標案", "採購", "招標",
    "教師",            # 教師甄選、教師增能、教師法律諮詢…
    "實習甄選",        # 師大的教育實習生甄選
    "研習",
    "碩士", "在職專班",  # 研究所招生
]

# ……除非標題同時明確提到學生。例如「學生科學研習營」「師生增能研習」不會被排除。
KEEP_KEYWORDS = ["學生", "師生", "同學", "高一", "高二", "高三"]


def classify(notice: Notice) -> Notice:
    """幫公告填上 categories 和 for_students，回傳同一個物件。"""
    categories = []

    for key, category in DEPT_CATEGORIES.items():
        if key in notice.dept and category not in categories:
            categories.append(category)

    for category, words in KEYWORD_CATEGORIES.items():
        if any(w in notice.title for w in words) and category not in categories:
            categories.append(category)

    notice.categories = categories
    notice.topics = [t for t, words in TOPICS.items() if any(w in notice.title for w in words)]

    excluded = any(w in notice.title for w in EXCLUDE_KEYWORDS)
    mentions_students = any(w in notice.title for w in KEEP_KEYWORDS)
    notice.for_students = not excluded or mentions_students
    return notice


def should_push(notice: Notice, subscribed: set[str]) -> bool:
    """這則公告要不要推給「訂閱了 subscribed 這些類別或主題」的同學。

    subscribed 裡類別和主題混著放，例如 {"獎學金", "考試"}：
    只訂「考試」主題的同學，會收到考試公告，但不會收到教務處的其他公告。
    沒有任何類別或主題的公告（例如電子書資料庫、外校成果展）不推，避免太吵。
    """
    if not notice.for_students:
        return False
    return any(c in subscribed for c in notice.categories + notice.topics)

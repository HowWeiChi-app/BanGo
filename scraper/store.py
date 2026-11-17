"""新公告偵測：跟上次抓到的結果比對。

目前先把「看過的公告網址」存在 data/seen.json，GitHub Actions 每次跑完會把它 commit 回 repo；
第 3 週接上 Firebase 後再改成存 Firestore。
"""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

from notice import Notice


def load_seen(path: Path) -> set[str] | None:
    """讀取看過的公告網址。檔案不存在時回傳 None，代表這是第一次執行。"""
    if not path.exists():
        return None
    return set(json.loads(path.read_text(encoding="utf-8")))


def save_seen(path: Path, seen: set[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # sorted 讓檔案內容固定順序，commit 進 git 時 diff 比較好看
    path.write_text(json.dumps(sorted(seen), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


TAIPEI = timezone(timedelta(hours=8))
MAX_PUSH_AGE = timedelta(days=2)


def is_recent(notice: Notice, now: datetime | None = None) -> bool:
    """公告是不是 2 天內發布的。只有最近的公告才推播。

    沒看過、但很舊的公告（例如新加了一個 RSS 分類，或校網把舊公告重新上架），
    只記成看過，不推播，免得一次洗出一堆舊消息。
    """
    now = now or datetime.now(TAIPEI)
    try:
        published = datetime.strptime(notice.date, "%Y-%m-%d %H:%M").replace(tzinfo=TAIPEI)
    except ValueError:
        return True  # 日期格式看不懂時寧可推播，也不要漏掉
    return now - published <= MAX_PUSH_AGE


def find_new(notices: list[Notice], seen: set[str]) -> list[Notice]:
    """回傳 seen 裡沒有的公告。

    這個函式只比對、不存檔。要等通知真的發出去之後才存，
    不然 Discord 剛好連不上的那次，新公告會被記成「看過」，永遠不會再發。
    """
    return [n for n in notices if n.url not in seen]

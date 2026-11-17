"""把公告存成 App 讀得懂的 data/notices.json。

RSS 每個分類只有最新 25 則，所以每次執行都把新抓到的跟之前存的合併，慢慢累積成歷史紀錄，
App 的「全部公告」和「考試」主題才看得到比較早的公告。

每次都會用最新的 filters.py 重新分類全部公告，所以調整關鍵字之後，舊公告的分類也會跟著更新。

目前 App 是直接讀 GitHub 上的這個檔案；第 3 週接上 Firebase 後，可以改成寫進 Firestore。
"""

import json
from dataclasses import fields
from datetime import datetime, timedelta, timezone
from pathlib import Path

from filters import KEYWORD_CATEGORIES, TOPICS, classify
from notice import Notice

MAX_NOTICES = 300  # 最多保留幾則，避免檔案越來越大，App 下載變慢
TAIPEI = timezone(timedelta(hours=8))
_FIELDS = {f.name for f in fields(Notice)}


def load_notices(path: Path) -> list[Notice]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    return [Notice(**{k: v for k, v in d.items() if k in _FIELDS}) for d in data["notices"]]


def merge(old: list[Notice], current: list[Notice]) -> list[Notice]:
    """合併新舊公告：同一個網址以這次抓到的為準，依時間由新到舊，最多 MAX_NOTICES 則。"""
    by_url = {n.url: n for n in old}
    by_url.update({n.url: n for n in current})
    merged = sorted(by_url.values(), key=lambda n: n.date, reverse=True)[:MAX_NOTICES]
    for n in merged:
        classify(n)
    return merged


def save_notices(path: Path, notices: list[Notice]) -> bool:
    """寫入 notices.json，回傳有沒有變動。

    公告內容沒變就不寫檔，免得 GitHub Actions 每 30 分鐘都產生一個只改了時間的 commit。
    """
    payload = {
        "categories": list(KEYWORD_CATEGORIES),  # App 的設定頁用這兩個清單產生開關
        "topics": list(TOPICS),
        "notices": [n.to_dict() for n in notices],
    }
    if path.exists():
        old = json.loads(path.read_text(encoding="utf-8"))
        old.pop("updated", None)
        if old == payload:
            return False

    payload = {"updated": datetime.now(TAIPEI).strftime("%Y-%m-%d %H:%M"), **payload}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    return True

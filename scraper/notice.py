"""公告的資料格式。爬蟲、過濾、推播、App 都用這個格式溝通。"""

from dataclasses import dataclass, field, asdict


@dataclass
class Notice:
    title: str   # 公告標題
    date: str    # 公告時間，統一用 "YYYY-MM-DD HH:MM"（字串直接比大小就能排序）
    dept: str    # 發布處室，例如 "教務處"；抓不到就給空字串（師大附中的 RSS 沒有這欄）
    url: str     # 原始校網頁面的完整網址，也拿來當公告的唯一 ID
    source: str = ""  # 來自哪個公告分類，例如 "重要公告"、"來文公告"
    categories: list[str] = field(default_factory=list)  # 過濾後填入，例如 ["教務", "獎學金"]
    topics: list[str] = field(default_factory=list)      # 比類別更細的主題，例如 ["考試"]
    for_students: bool = True  # False 表示跟學生無關（標案、教師甄選…），不推播
    content: str = ""  # 公告內文（純文字，段落用換行分開），App 顯示摘要和內頁用
    image: str = ""    # 內文裡第一張圖片的完整網址，沒有就是空字串

    def to_dict(self) -> dict:
        return asdict(self)

"""各校公告抓取與解析。校網改版時，通常只需要改這個檔案（學校清單在 schools.py）。

各校的公告列表頁是用 JavaScript 載入的，直接抓 HTML 拿不到公告，
所以改用校網提供的 RSS。RSS 是固定格式的 XML，比 HTML 穩定，也不用另外裝套件。
"""

import html
import re
import time
from datetime import timedelta, timezone
from email.utils import parsedate_to_datetime
import urllib.parse
import urllib.request
from html.parser import HTMLParser
import xml.etree.ElementTree as ET

from notice import Notice

from schools import HSNU_BASE, SCHOOLS

BASE = HSNU_BASE  # 舊程式和測試用；各校的網址在 schools.py

# 師大附中的分類 RSS（其他學校的在 schools.py）
FEEDS = SCHOOLS["hsnu"]["feeds"]

# RSS 裡用到的命名空間
_CONTENT = "{http://purl.org/rss/1.0/modules/content/}encoded"
_CREATOR = "{http://purl.org/dc/elements/1.1/}creator"
TAIPEI = timezone(timedelta(hours=8))

# 標明自己是誰，讓學校看得出這不是攻擊
USER_AGENT = "SchoolNoticeBot/0.1 (student project; polls every 10+ min)"


MAX_CONTENT = 3000  # 內文最多存幾個字，避免 notices.json 太大、App 下載變慢


class _TextExtractor(HTMLParser):
    """把公告內文的 HTML 轉成純文字，同時記下第一張圖片。"""

    BLOCKS = {"p", "br", "div", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6"}

    def __init__(self):
        super().__init__(convert_charrefs=True)  # 自動把 &amp; 這類符號轉回正常文字
        self.parts: list[str] = []
        self.image = ""

    def handle_starttag(self, tag, attrs):
        if tag in self.BLOCKS:
            self.parts.append("\n")
        if tag == "img" and not self.image:
            self.image = dict(attrs).get("src") or ""

    def handle_endtag(self, tag):
        if tag in self.BLOCKS:
            self.parts.append("\n")

    def handle_data(self, data):
        self.parts.append(data)


def html_to_text(description: str, base: str = BASE) -> tuple[str, str]:
    """RSS 的 <description> 是一段 HTML，回傳 (純文字內文, 第一張圖片的完整網址)。
    base 是學校網址，用來把圖片的相對網址補完整。"""
    extractor = _TextExtractor()
    extractor.feed(description)
    # 每行去掉多餘空白（包括全形空白和 &nbsp;），空行拿掉
    lines = (" ".join(line.split()) for line in "".join(extractor.parts).split("\n"))
    text = "\n".join(line for line in lines if line)
    if len(text) > MAX_CONTENT:
        text = text[:MAX_CONTENT].rstrip() + "…"
    image = urllib.parse.urljoin(base + "/", extractor.image) if extractor.image else ""
    return text, image


class ParseError(Exception):
    """RSS 格式跟預期不同，通常代表校網改版了。"""


class FetchError(Exception):
    """校網連不上（重試幾次都失敗）。通常是校網暫時當機，過一陣子會自己好。"""


RETRY_WAIT = [5, 15]  # 失敗後分別等幾秒再試；總共試 3 次


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(len(RETRY_WAIT) + 1):
        try:
            with urllib.request.urlopen(req, timeout=20) as resp:
                return resp.read()
        except OSError as e:  # 連線失敗、逾時、HTTP 錯誤（例如 500）都算
            if attempt == len(RETRY_WAIT):
                raise FetchError(f"試了 {attempt + 1} 次都連不上校網（{e}）") from e
            time.sleep(RETRY_WAIT[attempt])


def normalize_date(pub: str) -> str:
    """各校的 pubDate 統一成台灣時間 "YYYY-MM-DD HH:MM"（字串直接比大小就能排序）。

    師大附中："2026-11-16 15:16:47"（已經是台灣時間）
    其他學校：標準 RSS 格式 "Tue, 17 Nov 2026 11:02:42 +0000"、"Fri, 13 Nov 2026 01:30:00 GMT"
    看不懂的格式回傳空字串（呼叫的人會當成格式錯誤）。
    """
    pub = pub.strip()
    if re.match(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}", pub):
        return pub[:16]
    try:
        return parsedate_to_datetime(pub).astimezone(TAIPEI).strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        return ""


def parse_rss(xml_bytes: bytes, source: str, school: str = "hsnu") -> list[Notice]:
    """把 RSS 的 XML 轉成 Notice 陣列。各校的差異見 schools.py 開頭的說明。

    師大附中的每則公告長這樣：
      <item>
        <title>115學年第1學期_第二次期中考_考試範圍</title>
        <link>https://www.hs.ntnu.edu.tw/content?a=...</link>
        <description>&lt;p&gt;內文（HTML）…&lt;/p&gt;</description>
        <pubDate>2026-11-16 15:16:47</pubDate>
      </item>
    """
    info = SCHOOLS[school]
    name = f"{info['name']} {source}"
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError as e:
        raise ParseError(f"{name}：不是合法的 XML（{e}）") from e

    items = root.findall("./channel/item")
    if not items:
        raise ParseError(f"{name}：RSS 裡找不到任何 <item>")

    notices = []
    for item in items:
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        if not title or not link:
            raise ParseError(f"{name}：有公告缺少標題或連結")
        date = normalize_date(item.findtext("pubDate") or "")
        if not date:
            raise ParseError(f"{name}：看不懂公告時間「{item.findtext('pubDate')}」")
        # WordPress 的 description 只有摘要，全文在 content:encoded
        body = item.findtext(_CONTENT) or item.findtext("description") or ""
        content, image = html_to_text(body, info["base"])
        # WordPress 的 dc:creator 是處室（「試務組」）；建中的是帳號 ID，附中沒有
        dept = (item.findtext(_CREATOR) or "").strip() if info["kind"] == "wordpress" else ""
        notices.append(Notice(
            title=html.unescape(title),  # 把 &amp; 這類符號轉回正常文字
            date=date,
            dept=dept,
            url=link,
            source=source,
            content=content,
            image=image,
        ))
    return notices


def fetch_all(school: str = "hsnu") -> list[Notice]:
    """抓一間學校的所有分類，合併、去除重複，依時間由新到舊排序
    （建中的 RSS 沒照時間排，置頂的在最前面，這裡一起排好）。"""
    by_url: dict[str, Notice] = {}
    for source, url in SCHOOLS[school]["feeds"].items():
        for n in parse_rss(fetch(url), source, school):
            by_url.setdefault(n.url, n)  # 同一則出現在兩個分類時，保留先抓到的
    return sorted(by_url.values(), key=lambda n: n.date, reverse=True)

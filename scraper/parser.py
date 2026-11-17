"""師大附中公告抓取與解析。校網改版時，通常只需要改這個檔案。

師大附中的公告列表頁是用 JavaScript 載入的，直接抓 HTML 拿不到公告，
所以改用校網提供的 RSS。RSS 是固定格式的 XML，比 HTML 穩定，也不用另外裝套件。
"""

import html
import time
import urllib.parse
import urllib.request
from html.parser import HTMLParser
import xml.etree.ElementTree as ET

from notice import Notice

BASE = "https://www.hs.ntnu.edu.tw"

# 公告分類名稱 → RSS 網址（從校網首頁各分類旁的「RSS 訂閱」按鈕取得）
# 同一則公告可能同時出現在好幾個分類（網址相同），會以排在前面的分類為準。
# 校網還有這些分類，目前刻意不抓：
#   榮譽榜（「賀！本校參與…競賽榮獲佳績」，會被當成比賽公告推播，太吵）
#   研習資訊（教師研習）、新冠肺炎專區（已停用）、新生專區（只有暑假有用，到時候再加）
FEEDS = {
    "重要公告": BASE + "/rssfeeds?a=T0RESTEyNTIxODAyNTk2MjI2MVRDaW50ZWx5&b=T0RESTYyaW50ZWx5&c=T0RESU1EVTNOakl5TXpjPXdBek55SWpOeElrVGludGVseQ==",
    "學生": BASE + "/rssfeeds?a=T0RESTk5OTY1NDU3Njk2MjI2MVRDaW50ZWx5&b=T0RESTYyaW50ZWx5&c=T0RESU1EVTNOakl5TXpjPXdBek55SWpOeElrVGludGVseQ==",
    "來文公告": BASE + "/rssfeeds?a=T0RESTk5ODEzMzE2Mzk2MjI2MVRDaW50ZWx5&b=T0RESTYyaW50ZWx5&c=T0RESU1EVTNOakl5TXpjPXdBek55SWpOeElrVGludGVseQ==",
    "行事曆": BASE + "/rssfeeds?a=T0RESTQ2OTMxMDQ5MzQ4ODM2MVRDaW50ZWx5&b=T0RESTYyaW50ZWx5&c=T0RESU1EVTNOakl5TXpjPXdBek55SWpOeElrVGludGVseQ==",
}

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


def html_to_text(description: str) -> tuple[str, str]:
    """RSS 的 <description> 是一段 HTML，回傳 (純文字內文, 第一張圖片的完整網址)。"""
    extractor = _TextExtractor()
    extractor.feed(description)
    # 每行去掉多餘空白（包括全形空白和 &nbsp;），空行拿掉
    lines = (" ".join(line.split()) for line in "".join(extractor.parts).split("\n"))
    text = "\n".join(line for line in lines if line)
    if len(text) > MAX_CONTENT:
        text = text[:MAX_CONTENT].rstrip() + "…"
    image = urllib.parse.urljoin(BASE + "/", extractor.image) if extractor.image else ""
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


def parse_rss(xml_bytes: bytes, source: str) -> list[Notice]:
    """把 RSS 的 XML 轉成 Notice 陣列。

    每則公告長這樣：
      <item>
        <title>115學年第1學期_第二次期中考_考試範圍</title>
        <link>https://www.hs.ntnu.edu.tw/content?a=...</link>
        <description>&lt;p&gt;內文（HTML）…&lt;/p&gt;</description>
        <pubDate>2026-11-16 15:16:47</pubDate>
      </item>
    """
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError as e:
        raise ParseError(f"{source}：不是合法的 XML（{e}）") from e

    items = root.findall("./channel/item")
    if not items:
        raise ParseError(f"{source}：RSS 裡找不到任何 <item>")

    notices = []
    for item in items:
        title = (item.findtext("title") or "").strip()
        link = (item.findtext("link") or "").strip()
        pub = (item.findtext("pubDate") or "").strip()
        if not title or not link:
            raise ParseError(f"{source}：有公告缺少標題或連結")
        content, image = html_to_text(item.findtext("description") or "")
        notices.append(Notice(
            title=html.unescape(title),  # 把 &amp; 這類符號轉回正常文字
            # 師大附中的 pubDate 是 "2026-11-16 15:16:47"（不是標準 RSS 格式），取到分鐘就好
            date=pub[:16],
            dept="",
            url=link,
            source=source,
            content=content,
            image=image,
        ))
    return notices


def fetch_all() -> list[Notice]:
    """抓所有分類，合併、去除重複，依時間由新到舊排序。"""
    by_url: dict[str, Notice] = {}
    for source, url in FEEDS.items():
        for n in parse_rss(fetch(url), source):
            by_url.setdefault(n.url, n)  # 同一則出現在兩個分類時，保留先抓到的
    return sorted(by_url.values(), key=lambda n: n.date, reverse=True)

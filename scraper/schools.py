"""支援的學校。新增學校：在這裡加一筆，App 的學校清單（ios/BanGo/AppSettings.swift 的 School）也加一筆。

kind 是校網用的系統，決定 RSS 怎麼解析（見 parser.parse_rss）：
  hsnu       師大附中自己的系統：pubDate 是 "2026-11-16 15:16:47"，description 是全文
  nss        建中的 NSS：pubDate 是標準 RSS 格式（GMT），description 是全文，dc:creator 是帳號 ID 不能用
  wordpress  北一女、成功、中山：description 只有摘要，全文在 content:encoded，dc:creator 是處室

feeds 是「分類名稱 → RSS 網址」。同一則公告出現在好幾個分類時，以排在前面的分類為準。
只抓跟學生有關的分類（榮譽榜、教師研習這類不抓）。各校網址的來源見 docs/multi-school.md。

data 是輸出的公告檔（相對於 scraper/data/）。附中沿用舊路徑，還沒更新的 App 才不會壞。
"""

HSNU_BASE = "https://www.hs.ntnu.edu.tw"
_HSNU_RSS = HSNU_BASE + "/rssfeeds?a={}&b=T0RESTYyaW50ZWx5&c=T0RESU1EVTNOakl5TXpjPXdBek55SWpOeElrVGludGVseQ=="
_CK_RSS = "https://www.ck.tp.edu.tw/nss/main/feeder/5abf2d62aa93092cee58ceb4/{}&vector=private&static=false"

SCHOOLS = {
    "hsnu": {
        "name": "師大附中",
        "base": HSNU_BASE,
        "kind": "hsnu",
        "data": "notices.json",
        "feeds": {
            # 附中還有這些分類，目前刻意不抓：
            #   榮譽榜（「賀！本校參與…競賽榮獲佳績」，會被當成比賽公告推播，太吵）
            #   研習資訊（教師研習）、新冠肺炎專區（已停用）、新生專區（只有暑假有用，到時候再加）
            "重要公告": _HSNU_RSS.format("T0RESTEyNTIxODAyNTk2MjI2MVRDaW50ZWx5"),
            "學生": _HSNU_RSS.format("T0RESTk5OTY1NDU3Njk2MjI2MVRDaW50ZWx5"),
            "來文公告": _HSNU_RSS.format("T0RESTk5ODEzMzE2Mzk2MjI2MVRDaW50ZWx5"),
            "行事曆": _HSNU_RSS.format("T0RESTQ2OTMxMDQ5MzQ4ODM2MVRDaW50ZWx5"),
        },
    },
    "ck": {
        "name": "建國中學",
        "base": "https://www.ck.tp.edu.tw",
        "kind": "nss",
        "data": "ck/notices.json",
        "feeds": {
            "重要公告": _CK_RSS.format("KG5mY0d9355?f=normal&%240=hhyrNQJ0110"),
            "最新消息": _CK_RSS.format("IXZld9j7619?f=normal&%240=kpenVCJ9015"),
        },
    },
    "fg": {
        "name": "北一女中",
        "base": "https://www.fg.tp.edu.tw",
        "kind": "wordpress",
        "data": "fg/notices.json",
        "feeds": {
            "最新消息": "https://www.fg.tp.edu.tw/category/news/news1/feed/",
            "學生園地": "https://www.fg.tp.edu.tw/category/news/news5/feed/",
            "來文宣導": "https://www.fg.tp.edu.tw/category/news/news7/feed/",
        },
    },
    "cksh": {
        "name": "成功高中",
        "base": "https://www.cksh.tp.edu.tw",
        "kind": "wordpress",
        "data": "cksh/notices.json",
        "feeds": {
            "行政公告": "https://www.cksh.tp.edu.tw/category/news/news_1/feed/",
            "活動競賽": "https://www.cksh.tp.edu.tw/category/news/news_2/feed/",
            "升學訊息": "https://www.cksh.tp.edu.tw/category/news/news_4/feed/",
            "獎助學金": "https://www.cksh.tp.edu.tw/category/news/news_6/feed/",
        },
    },
    "csghs": {
        "name": "中山女高",
        "base": "https://www.csghs.tp.edu.tw",
        "kind": "wordpress",
        "data": "csghs/notices.json",
        "feeds": {
            "最新消息": "https://www.csghs.tp.edu.tw/category/news/news1/feed/",
            "學生專區": "https://www.csghs.tp.edu.tw/category/news/news2/feed/",
        },
    },
}

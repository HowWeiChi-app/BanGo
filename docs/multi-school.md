# 多校支援調查與規劃

> 調查日期：2026-11-17。只讀公開頁面和 RSS，沒有改爬蟲或 App 的程式碼。

## 結論先講

**這四所學校的校網跟附中不是同一套系統。** 一共有三種：

| 學校 | 系統 | 公告網址長相 | RSS |
|---|---|---|---|
| 師大附中 | 附中自己的系統（`/content?a=…`、`/rssfeeds?a=…&b=…&c=…`） | `/content?a=<編碼>` | 有，每分類 25 則 |
| 建國中學 | NSS（`/nss/p/…`，整頁用 JavaScript 畫出來） | `/nss/main/freeze/<站台>/<模組>/<id>` | 有，每個 100 則 |
| 北一女、成功、中山女高 | **WordPress**（同一家廠商做的佈景，`category/news/…`） | `/news/<標題轉成的網址>/` | 有，每分類 10 則，可用 `?paged=2` 翻頁 |

北一女、成功、中山三所彼此才是同一套（WordPress），寫一個解析器就能共用。建中要另外處理。
好消息是**五所學校都有 RSS 2.0**，所以不用改抓 HTML，`parse_rss()` 的骨架都能留著，只要處理欄位差異。

## 各校 RSS 網址

只列跟學生有關的分類。WordPress 學校的任何分類都可以在分類網址後面加 `feed/` 得到 RSS。

**建國中學**（首頁「RSS訂閱」按鈕）

| 分類 | RSS |
|---|---|
| 重要公告 | `https://www.ck.tp.edu.tw/nss/main/feeder/5abf2d62aa93092cee58ceb4/KG5mY0d9355?f=normal&%240=hhyrNQJ0110&vector=private&static=false` |
| 最新消息 | `https://www.ck.tp.edu.tw/nss/main/feeder/5abf2d62aa93092cee58ceb4/IXZld9j7619?f=normal&%240=kpenVCJ9015&vector=private&static=false` |

**北一女中**（`https://www.fg.tp.edu.tw/category/news/<代號>/feed/`）

最新消息 `news1`、榮譽榜 `news2`、國際交流 `news3`、綠園新聞 `news4`、學生園地 `news5`、教師研習 `news6`、來文宣導 `news7`；全部公告 `https://www.fg.tp.edu.tw/category/news/feed/`

**成功高中**（`https://www.cksh.tp.edu.tw/category/news/<代號>/feed/`）

行政公告 `news_1`、活動競賽 `news_2`、得獎榮譽 `news_3`、生涯與升學訊息 `news_4`、研習講座 `news_5`、獎助學金 `news_6`、國際交流 `news_7`、新生入學 `news_8`、學生學習歷程檔案 `news_9`、防疫專區 `news_10`；全部公告 `https://www.cksh.tp.edu.tw/category/news/feed/`

**中山女高**（`https://www.csghs.tp.edu.tw/category/news/<代號>/feed/`）

最新消息 `news1`、學生專區 `news2`、教師專區 `news3`、榮譽榜 `news4`、學生自治組織 `stu-council_desc`；全部公告 `https://www.csghs.tp.edu.tw/category/news/feed/`

四校 `robots.txt` 都允許抓這些路徑（WordPress 只擋 `/wp-admin/`，建中明確 `Allow: /nss/`）。

## 實測結果：直接用現在的 `parse_rss()`

每個 RSS 抓一次，丟進 `parser.parse_rss()`（只在記憶體跑，沒寫 `scraper/data/`、沒發通知）。
**每一個都沒有報錯**，但結果有好幾個欄位不能用：

| 項目 | 附中 | 建中 | WordPress 三校 |
|---|---|---|---|
| 解析成功 | ✅ 25 則 | ✅ 100 則 | ✅ 10 則 |
| `title`、`link` | ✅ | ✅ | ✅ |
| `pubDate` 格式 | `2026-11-17 14:45:46`（台灣時間） | `Mon, 16 Nov 2026 07:17:00 GMT` | `Tue, 17 Nov 2026 11:02:42 +0000` |
| 現在得到的 `date` | ✅ `2026-11-17 14:45` | ❌ `Mon, 16 Nov 2026` | ❌ `Tue, 17 Nov 2026` |
| 內文 | `<description>` 全文 | `<description>` 全文 | ❌ `<description>` 只有摘要（結尾 `[…]`），全文在 `<content:encoded>` |
| 發布處室 | 沒有 | `<dc:creator>` 是帳號 ID（如 `632ac8bb…`），不能用 | ✅ `<dc:creator>` 就是處室（如「試務組」「輔導室」） |
| 分類 | 靠抓哪個 RSS | 靠抓哪個 RSS | `<category>` 一則可以有好幾個 |
| 附件 | 無 | `<name>` 是附件檔名（如 `…函文.pdf`） | 在內文 HTML 裡 |
| 排序 | 由新到舊 | ❌ 沒照時間（置頂的在最前面，最舊一則是 1 月） | 由新到舊 |
| 檔案大小 | 28 KB | ❌ 每個 RSS 約 0.5–0.8 MB | 25–50 KB |

日期錯是最嚴重的：`date` 變成 `Tue, 17 Nov 2026` 之後，排序、`is_recent()`（2 天內才推播）、App 顯示時間全部會錯。

另外兩個小問題：
- `html_to_text()` 用固定的 `BASE`（附中網址）補完整圖片網址，換學校要改成用該校網址。
- WordPress 的 `link` 是用標題產生的，學校改標題時網址可能跟著變，會被當成新公告。比較穩的 ID 是 `<guid>`，但這裡的 guid 也是網址形式（`/uncategorized/…`），所以先維持用 `link`，遇到重複再說。
- 本機 Mac 的 Python 抓 https 會出現 `CERTIFICATE_VERIFY_FAILED`（本機沒裝憑證，執行 `Install Certificates.command` 即可），GitHub Actions 上沒這個問題，跟學校無關。

## 爬蟲要改的地方

1. **學校清單設定**：新增 `scraper/schools.py`（或 `schools.json`），一校一筆：
   ```python
   SCHOOLS = {
       "hsnu":  {"name": "師大附中", "base": "https://www.hs.ntnu.edu.tw", "kind": "hsnu",
                 "feeds": {"重要公告": "...", "學生": "...", "來文公告": "...", "行事曆": "..."}},
       "ck":    {"name": "建國中學", "base": "https://www.ck.tp.edu.tw", "kind": "nss",
                 "feeds": {"重要公告": "...", "最新消息": "..."}},
       "fg":    {"name": "北一女中", "base": "https://www.fg.tp.edu.tw", "kind": "wordpress",
                 "feeds": {"最新消息": ".../category/news/news1/feed/", "學生園地": ".../news5/feed/"}},
       "cksh":  {"name": "成功高中", ...},
       "csghs": {"name": "中山女高", ...},
   }
   ```
   `id` 用網域的第一段，之後也是 App 和推播主題用的代號。

2. **`parse_rss()` 依 `kind` 處理差異**（同一個函式加幾個判斷就好，不用拆三份）：
   - 日期：附中照舊；其他用 `email.utils.parsedate_to_datetime()` 解析，再轉成台灣時間（+8）輸出 `YYYY-MM-DD HH:MM`。這樣 `Notice.date` 格式不變，後面的程式都不用改。
   - 內文：有 `<content:encoded>` 就用它，沒有才用 `<description>`。
   - 處室：WordPress 用 `<dc:creator>` 填 `dept`；建中跟附中一樣留空。
   - 圖片網址：`html_to_text()` 改收該校的 `base`。
3. **`fetch_all(school)`**：抓完一律照時間排序（現在已經有 `sorted`，建中的亂序會被修正）。
4. **每校一個輸出檔**：`scraper/data/<id>/notices.json`、`scraper/data/<id>/seen.json`。附中可以先維持 `data/notices.json` 舊路徑一段時間（或兩個都寫），讓還沒更新的舊版 App 不會壞。
5. **`run.py` 跑迴圈**：每校各自抓、各自存。一校失敗（`FetchError`/`ParseError`）只跳過那一校，不要讓整次執行失敗，免得一間學校當機就害其他學校也沒更新。
6. **分類關鍵字（`filters.py`）**：大致可共用（都是「獎學金」「考試」「轉知」這類字），但各校分類名稱不同，`source` 欄會是各校自己的分類名。WordPress 三校還可以直接用 `<category>` 輔助判斷。可以先共用，跑一陣子再看哪些要調。
7. **建中的大檔**：每次抓 0.8 MB × 2，每 30 分鐘一次還算可以；不想抓這麼多的話，可以試試看 feeder 網址有沒有能限制筆數的參數（這次沒測）。
8. **推播**：Discord 維持只發附中（現在的頻道是附中同學在用）。FCM 主題名前面加學校代號，例如 `ck_考試`，App 只訂閱自己學校的主題。
9. **測試**：每種 `kind` 存一份真實 RSS 範例到 `scraper/tests/` 當固定資料，`test_basic.py` 加日期轉換、`content:encoded`、`dc:creator` 的測試。

## App 端要改的地方

現在 `ios/BanGo/NoticeStore.swift` 的 `dataURL` 寫死成
`https://raw.githubusercontent.com/HowWeiChi-app/BanGo/main/scraper/data/notices.json`，Android 的 `app/lib/repository.dart` 也一樣。

1. **學校清單**：App 內建一份清單（代號 + 名稱），或讓爬蟲多輸出一個 `scraper/data/schools.json`，App 啟動時讀它，以後新增學校就不用更新 App。建議用後者。
2. **選學校**：第一次開 App 先出一個「選擇學校」畫面；設定頁也能換。選的代號存在 `AppSettings`（UserDefaults / `@AppStorage`）。
3. **資料網址**：`dataURL` 改成依選的學校組出來：`.../scraper/data/\(schoolID)/notices.json`。
4. **快取**：`cacheURL` 也要分學校（`notices-<id>.json`），不然換學校時會先閃一下舊學校的公告。
5. **換學校時**：清掉已讀紀錄或改成分校存、重新訂閱 FCM 主題（取消舊學校、訂新學校）。
6. **名稱**：App 名稱和畫面上寫死的「附中」要改成顯示選的學校名稱（另一個 session 正在改 iOS UI，等那邊合併後再動）。

## 建議順序

1. 爬蟲：先做學校清單 + 日期/內文/處室修正，附中照舊輸出，確認測試全過。
2. 加 WordPress 三校（一套程式三校共用，最划算），輸出到各自資料夾，跑幾天看分類準不準。
3. 加建中。
4. App 加選學校（iOS 等目前的 UI 改動合併後再做）。

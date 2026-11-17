# 附中公告

自動抓取師大附中校網公告，過濾出跟學生有關的內容，發到 Discord 頻道和 Android App。
高中生自主學習專案，企劃見 [PLAN.md](PLAN.md)。

## 怎麼運作

```
師大附中校網 RSS（重要公告、學生、來文公告、行事曆）
  ↓ GitHub Actions 每 30 分鐘抓一次（.github/workflows/scrape.yml）
scraper/：分類、排除跟學生無關的、找出新公告
  ├→ Discord 頻道：發新公告
  └→ scraper/data/notices.json：存最近 300 則公告
        ↓
app/：Android App 下載 notices.json 顯示
```

## 資料夾

| 路徑 | 內容 |
|---|---|
| `scraper/parser.py` | 抓 RSS、轉成公告格式。**校網改版時通常只要改這裡** |
| `scraper/filters.py` | 分類和排除規則。**要調整關鍵字改這裡最上面的表** |
| `scraper/run.py` | 排程每次執行的完整流程 |
| `scraper/data/` | 爬蟲的資料（GitHub Actions 自動更新，不要手動改） |
| `app/lib/` | Android App（Flutter）的程式碼 |
| `ios/HSNUNotice/` | iPhone App（原生 SwiftUI、Liquid Glass）的程式碼 |
| `.github/workflows/` | 三個自動化流程：抓公告、編譯 Android App、編譯 iPhone App |

## 爬蟲

需要 Python 3.10 以上，不用裝任何套件。

```bash
cd scraper
python3 main.py          # 印出最新 20 則公告
python3 main.py 考試     # 只印出「考試」主題
python3 run.py           # 跑一次完整流程（沒設定 DISCORD_WEBHOOK_URL 時只印出、不發送）
python3 -m unittest -v   # 跑測試
```

> **Mac 上出現 `CERTIFICATE_VERIFY_FAILED`**：python.org 版的 Python 沒附根憑證，
> 在指令前面加上 `SSL_CERT_FILE=/etc/ssl/cert.pem` 就好，例如 `SSL_CERT_FILE=/etc/ssl/cert.pem python3 main.py`。

### Discord 測試訊息

到 GitHub 的 Actions 分頁 → 「抓校網公告」→「Run workflow」，勾選「發一則測試訊息」再執行，
頻道收到訊息就代表 webhook 設定正確。

## App

### 下載 APK（不用裝任何開發工具）

每次 `app/` 有變動，GitHub Actions 就會自動編譯：
Actions 分頁 →「編譯 App」→ 點最新一次成功的執行 → 最下面「Artifacts」下載 `hsnu-notice-apk`
→ 解壓縮得到 `app-release.apk`，傳到 Android 手機上安裝（要允許「安裝不明來源的應用程式」）。

### 發給同學（GitHub Release）

Artifacts 要登入 GitHub 才能下載，而且 30 天後會刪除。要發給同學時，推一個版本標籤：

```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions 會自動編譯，並在 Releases 頁面建立「附中公告 v0.1.0」附上 APK，
同學不用登入就能從 <https://github.com/cyy-615/hsnu-notice/releases/latest> 下載。
下一版記得改 `app/pubspec.yaml` 的 `version`（例如 `0.2.0+2`，`+` 後面的數字每版都要變大，手機才能直接更新）。

### 在自己電腦上開發

1. 安裝 [Flutter](https://docs.flutter.dev/get-started/install) 和 Android Studio。
2. 產生 Android 專案檔（第一次要做；`android/` 不在 repo 裡）：
   ```bash
   cd app
   bash tool/prepare_android.sh
   ```
3. 接上手機或開模擬器，執行 `flutter run`。
4. 跑測試：`flutter test`

### iPhone 版（`ios/`，原生 SwiftUI）

iPhone 版**另外用 SwiftUI 寫**，不是 Flutter。排版完全照 RSS 閱讀器 Reeder：沒有下方分頁列，
一層一層點進去「側邊欄 → 公告時間軸 → 公告內頁」，打開時直接停在「我的公告」；設定從側邊欄左上角彈出。
玻璃效果用 iOS 26 起蘋果官方的 Liquid Glass：導覽列、工具列、選單由系統自動變成玻璃，沒有自己畫。
資料跟 Android 一樣讀同一份 `notices.json`。
**還沒有推播**，要打開 App 下拉更新。需要 iOS 26 以上。

GitHub Actions 只確認能編譯，要裝到手機上得在自己的 Mac 用 Xcode 簽名：

1. 用 Xcode（26 以上）打開 `ios/HSNUNotice.xcodeproj`。
2. 左邊點「HSNUNotice」→「Signing & Capabilities」→ Team 選你自己的 Apple ID（Personal Team）。
   Bundle Identifier 如果顯示已被使用，在後面加幾個字改成獨一無二的。
3. iPhone 接上 Mac，上方選你的 iPhone，按 ▶︎。
4. 第一次打開會顯示「未受信任的開發者」：iPhone「設定」→「一般」→「VPN 與裝置管理」→ 信任你的 Apple ID。

⚠️ 免費 Apple ID 簽的 App **7 天後會打不開**，要重新按一次 ▶︎。
要發給其他同學（TestFlight）需要 US$99/年的 Apple 開發者帳號，見 PLAN.md 第 6 節。

### 畫面

- **我的公告**：只顯示你在設定裡訂閱的類別或主題（預設：教務、學務、#考試、#停課）
- **全部公告**：所有公告，可以依類別或主題篩選（iPhone 版在側邊欄選類別、主題或來源）；跟學生無關的公告預設隱藏
- **設定**：開關要訂閱的類別和主題

點任何一則公告會打開校網原文。iPhone 版先進到公告內頁，按「原文」才在 App 裡打開，從右邊推進來，從螢幕左邊緣往右滑就回來。
兩個版本功能一樣，iPhone 版的排版照 Reeder。

## 給同學試用

使用說明在 [docs/for-classmates.md](docs/for-classmates.md)（發出去前要先填 Discord 邀請連結和回饋方式）。

## 還沒做的

- 手機推播（需要建立 Firebase 專案，見 PLAN.md）
- iPhone 版的推播（需要 Apple 付費開發者帳號）

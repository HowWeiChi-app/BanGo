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
| `app/lib/` | Flutter App 的程式碼 |
| `.github/workflows/` | 兩個自動化流程：抓公告、編譯 App |

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

### 畫面

- **我的公告**：只顯示你在設定裡訂閱的類別或主題（預設：教務、學務、#考試）
- **全部公告**：所有公告，上面可以點類別或主題篩選；跟學生無關的公告預設隱藏
- **設定**：開關要訂閱的類別和主題

點任何一則公告會用瀏覽器打開校網原文。

## 還沒做的

- 手機推播（需要建立 Firebase 專案，見 PLAN.md）
- iOS 版

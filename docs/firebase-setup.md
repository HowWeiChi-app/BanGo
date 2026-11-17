# 設定 Firebase（手機推播需要）

手機推播要透過 Firebase Cloud Messaging（FCM），免費。
這些步驟要用你們自己的 Google 帳號操作，大約 10 分鐘。

## 推播的設計：用「主題訂閱」，不用存任何同學的資料

FCM 有一個功能叫 topic（主題）：App 在手機上訂閱幾個主題，伺服器發訊息給某個主題，
有訂閱的手機就會收到。所以：

- App 設定頁打開「教務」→ 手機訂閱 FCM 主題 `academic`
- 爬蟲發現新的教務公告 → 發給主題 `academic`

這樣伺服器**不需要知道有哪些手機、也不用存任何同學的資料**，也不用 Firestore。

| 類別／主題 | FCM 主題名稱 |
|---|---|
| 教務 | `academic` |
| 學務 | `student-affairs` |
| 輔導 | `counseling` |
| 獎學金 | `scholarship` |
| 比賽 | `competition` |
| #考試 | `exam` |

（FCM 主題名稱只能用英文、數字和 `-_.~%`，所以要對照。）

## 步驟

### 1. 建立 Firebase 專案

1. 打開 <https://console.firebase.google.com/>，用 Google 帳號登入。
   未滿 18 歲的話，Google 帳號的使用規定請先確認（可能需要家長同意）。
2. 點「建立專案」，名稱填 `hsnu-notice`。
3. 問要不要啟用 Google Analytics：選**不要**（用不到，也少收集資料）。
4. 等它建好，按「繼續」。

### 2. 加入 Android App

1. 在專案首頁點 Android 圖示（「將 Firebase 新增至你的 Android 應用程式」）。
2. **Android 套件名稱**一定要填：`io.github.cyy615.hsnu_notice`
   （跟 `app/tool/prepare_android.sh` 裡 `--org` 加 `--project-name` 一致，填錯推播會收不到）
3. 暱稱隨意，例如「附中公告」。SHA-1 不用填。
4. 下載 `google-services.json`。
5. 後面「新增 Firebase SDK」的步驟**全部跳過**，按「繼續前往控制台」。程式碼的部分我來改。

### 3. 產生伺服器用的金鑰（給爬蟲發推播用）

1. 專案首頁左上角齒輪 →「專案設定」→「服務帳戶」分頁。
2. 點「產生新的私密金鑰」→「產生金鑰」，會下載一個 `.json` 檔。

⚠️ **這個檔案是真正的密碼**，拿到它的人可以用你們的名義發推播給所有同學：
- 不要放進 repo、不要傳到聊天室，也不要貼給 Claude。
- 存進 GitHub Secrets 之後就可以把電腦上的檔案刪掉。
- 萬一外流，到同一頁把那把金鑰刪掉，再產生一把新的。

### 4. 把兩個檔案存進 GitHub Secrets

在終端機執行（把路徑換成你下載的檔案位置，檔案可以直接從 Finder 拖進終端機產生路徑）：

```bash
gh secret set FIREBASE_SERVICE_ACCOUNT --repo cyy-615/hsnu-notice < ~/Downloads/hsnu-notice-xxxxx.json
```

```bash
gh secret set GOOGLE_SERVICES_JSON --repo cyy-615/hsnu-notice < ~/Downloads/google-services.json
```

（`google-services.json` 其實不算機密，Firebase 官方說可以公開；但 repo 是 public，放 secret 比較保險。）

確認有存好（只會列出名稱）：

```bash
gh secret list --repo cyy-615/hsnu-notice
```

做完跟 Claude 說「Firebase 設定好了」，接下來的程式碼由 Claude 處理：
App 加上推播接收和主題訂閱、爬蟲加上發送推播。

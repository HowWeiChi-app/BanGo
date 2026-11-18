#!/usr/bin/env bash
# 產生 Android 專案檔（android/ 資料夾），並補上這個 App 需要的設定。
#
# 為什麼不直接把 android/ commit 進 repo：那是 flutter create 自動產生的幾十個檔案，
# 不同 Flutter 版本產生的內容不一樣，用這個腳本每次重新產生比較不會出錯。
# 已經存在的檔案（lib/、test/、pubspec.yaml）flutter create 不會覆蓋。
#
# 用法：在 app 資料夾裡跑  bash tool/prepare_android.sh

set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --platforms=android --org io.github.howweichi --project-name bango .
# flutter create 會補一份預設說明，這個專案用不到
grep -qs "A new Flutter project" README.md && rm README.md

python3 - android/app/src/main/AndroidManifest.xml <<'EOF'
import re
import sys
path = sys.argv[1]
m = open(path, encoding="utf-8").read()

# 1. 正式版 App 需要網路權限才能下載公告（flutter create 只在測試版加了這個權限）
if "android.permission.INTERNET" not in m:
    i = m.index(">", m.index("<manifest")) + 1
    m = m[:i] + '\n    <uses-permission android:name="android.permission.INTERNET"/>' + m[i:]

# 2. Android 11 以上要先宣告「會打開網頁」，url_launcher 才能用瀏覽器開校網
view_https = """
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>"""
if 'android:scheme="https"' not in m:
    if "<queries>" in m:
        m = m.replace("<queries>", "<queries>" + view_https, 1)
    else:
        m = m.replace("</manifest>", "    <queries>" + view_https + "\n    </queries>\n</manifest>")

# 3. 手機桌面上顯示的 App 名稱：跟著系統語言，實際文字在下面的 strings.xml
m = re.sub(r'android:label="[^"]*"', 'android:label="@string/app_name"', m, count=1)

open(path, "w", encoding="utf-8").write(m)
print("AndroidManifest.xml 已更新")
EOF

# App 名稱：中文系統顯示「校板」，其他語言顯示「BanGo」
mkdir -p android/app/src/main/res/values
printf '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="app_name">BanGo</string>\n</resources>\n' \
  > android/app/src/main/res/values/strings.xml
# Android 把 values-zh 當成簡體，台灣和香港的手機要另外列出來才會顯示中文名稱
for dir in values-zh values-zh-rTW values-zh-rHK values-b+zh+Hant; do
  mkdir -p "android/app/src/main/res/$dir"
  printf '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <string name="app_name">校板</string>\n</resources>\n' \
    > "android/app/src/main/res/$dir/strings.xml"
done
echo "App 名稱已更新"

# 4. App 圖示：全畫幅的 adaptive icon（Android 8 以上）和舊版用的方形圖示，都在 tool/icon/，
#    蓋掉 flutter create 的預設圖示。圖是 tool/make_android_icon.swift 從 iPhone 版的圖示產生的
for dir in tool/icon/mipmap-*; do
  mkdir -p "android/app/src/main/res/$(basename "$dir")"
  cp "$dir"/* "android/app/src/main/res/$(basename "$dir")/"
done
echo "App 圖示已更新"

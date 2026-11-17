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

flutter create --platforms=android --org io.github.cyy615 --project-name hsnu_notice .

python3 - android/app/src/main/AndroidManifest.xml <<'EOF'
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

# 3. 手機桌面上顯示的 App 名稱
m = m.replace('android:label="hsnu_notice"', 'android:label="附中公告"')

open(path, "w", encoding="utf-8").write(m)
print("AndroidManifest.xml 已更新")
EOF

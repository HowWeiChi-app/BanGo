#!/usr/bin/env bash
# 產生 iOS 專案檔（ios/ 資料夾），並補上這個 App 需要的設定。只能在 Mac 上跑。
#
# 跟 prepare_android.sh 一樣：ios/ 是 flutter create 自動產生的，不放進 repo，
# 已經存在的檔案（lib/、test/、pubspec.yaml）flutter create 不會覆蓋。
#
# 用法：在 app 資料夾裡跑  bash tool/prepare_ios.sh

set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --platforms=ios --org io.github.cyy615 --project-name hsnu_notice .

PLIST=ios/Runner/Info.plist

# 手機桌面上顯示的 App 名稱（plutil 是 Mac 內建的 plist 編輯工具）
plutil -replace CFBundleDisplayName -string "附中公告" "$PLIST"

# 介面只用繁體中文，系統按鈕（例如複製、貼上）也顯示中文
plutil -replace CFBundleDevelopmentRegion -string "zh_TW" "$PLIST"

echo "Info.plist 已更新：$(plutil -extract CFBundleDisplayName raw "$PLIST")"

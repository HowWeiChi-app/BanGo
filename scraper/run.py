"""排程每次執行的完整流程：抓公告 → 分類 → 找出新公告 → 發到 Discord → 存檔。

Discord 和手機推播只發師大附中（頻道是附中同學在用）。
其他學校（schools.py）只抓下來、分類、存成 data/<學校>/notices.json 給 App 讀。

GitHub Actions 每 30 分鐘跑一次  python run.py
在自己電腦上跑時，沒設定 DISCORD_WEBHOOK_URL 就只會印出「本來要發的內容」，不會真的發。
"""

import os
import sys
from pathlib import Path

from export import load_notices, merge, save_notices
from filters import KEYWORD_CATEGORIES, TOPICS, classify, should_push
import notify_fcm
from notify_discord import build_messages, post, send
from parser import FetchError, ParseError, fetch_all
from schools import SCHOOLS
from store import find_new, is_recent, load_seen, save_seen

SEEN_PATH = Path(__file__).parent / "data" / "seen.json"
DATA_DIR = Path(__file__).parent / "data"
NOTICES_PATH = DATA_DIR / SCHOOLS["hsnu"]["data"]

# Discord 是全班共用一個頻道，沒辦法每個人設定不同，所以所有類別和主題都發
CHANNEL_SUBSCRIBED = set(KEYWORD_CATEGORIES) | set(TOPICS)


def update_other_schools() -> None:
    """附中以外的學校：抓、分類、存檔。不推播、不記已讀。
    一校失敗只跳過那一校（印出原因），不影響附中和其他學校。"""
    for school, info in SCHOOLS.items():
        if school == "hsnu":
            continue
        try:
            notices = fetch_all(school)
        except (ParseError, FetchError) as e:
            print(f"{info['name']}這次跳過：{e}", file=sys.stderr)
            continue
        path = DATA_DIR / info["data"]
        if save_notices(path, merge(load_notices(path), notices)):
            print(f"{info['name']}的 notices.json 已更新（這次抓到 {len(notices)} 則）")


def main() -> int:
    # 其他學校先做：附中後面有好幾個地方會提早結束
    update_other_schools()

    webhook = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    in_ci = os.environ.get("GITHUB_ACTIONS") == "true"
    if in_ci and not webhook:
        # 不擋下來的話，會把新公告記成看過，卻沒發出去
        print("GitHub Secrets 裡沒有設定 DISCORD_WEBHOOK_URL", file=sys.stderr)
        return 1

    # 手動執行時勾選「發一則測試訊息」才會有這個變數，用來確認 webhook 設定正確
    if webhook and os.environ.get("SEND_TEST") == "true":
        try:
            post(webhook, "✅ 校網公告機器人連線測試：看到這則訊息，代表 Discord 設定成功了")
        except Exception as e:
            # 不印出網址本身，避免 webhook 網址出現在公開的執行紀錄裡
            print(f"測試訊息發送失敗，請檢查 DISCORD_WEBHOOK_URL 是否完整：{type(e).__name__} {getattr(e, 'code', '')}",
                  file=sys.stderr)
            return 1
        print("測試訊息已發送")

    try:
        notices = fetch_all()
    except ParseError as e:
        print(f"解析失敗，可能是校網改版：{e}", file=sys.stderr)
        return 1
    except FetchError as e:
        print(f"{e}。這次先跳過，下次排程會再試。", file=sys.stderr)
        return 1
    for n in notices:
        classify(n)

    # 給 App 讀的公告清單（跟 Discord 通知無關，先存起來也不會造成重複通知）
    if save_notices(NOTICES_PATH, merge(load_notices(NOTICES_PATH), notices)):
        print("notices.json 已更新")

    current = {n.url for n in notices}
    seen = load_seen(SEEN_PATH)
    if seen is None:
        # 第一次執行：全部記成看過、不發，免得一次洗出 50 則舊公告
        save_seen(SEEN_PATH, current)
        print(f"第一次執行，記下目前的 {len(current)} 則公告，不發通知")
        return 0

    new = find_new(notices, seen)
    to_send = [n for n in new if should_push(n, CHANNEL_SUBSCRIBED) and is_recent(n)]
    to_send.reverse()  # 舊的先發，Discord 裡最新的就會在最下面
    old = sum(1 for n in new if not is_recent(n))
    print(f"新公告 {len(new)} 則（其中 {old} 則超過 2 天不推播），要發的 {len(to_send)} 則")

    if to_send:
        if webhook:
            try:
                send(webhook, to_send)
            except Exception as e:
                # 不存檔就結束：這幾則還是「沒看過」，下次排程會再發一次
                # （GitHub 會自動把 webhook 網址遮掉，這裡也只印錯誤種類，不印網址）
                print(f"Discord 發送失敗，下次排程會再試：{type(e).__name__} {getattr(e, 'code', '')}",
                      file=sys.stderr)
                return 1
        else:
            print("（沒設定 DISCORD_WEBHOOK_URL，只印出內容）")
            for msg in build_messages(to_send):
                print("-" * 40 + "\n" + msg)

    # 手機推播：有設定 Firebase 金鑰才發。
    # 失敗時不中斷：Discord 已經發出去了，如果因此不存檔，下次 Discord 會重複發。
    # 改成照樣存檔、最後回傳失敗，讓 GitHub 寄信通知開發者。
    fcm_failed = False
    fcm_key = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "").strip()
    if to_send and fcm_key:
        try:
            print(f"手機推播已發送 {notify_fcm.send(fcm_key, to_send)} 則")
        except Exception as e:
            # 只印例外種類和狀態碼，不印內容，避免金鑰相關資訊出現在公開的執行紀錄
            print(f"手機推播發送失敗：{type(e).__name__} {getattr(e, 'code', '')}", file=sys.stderr)
            fcm_failed = True

    # Discord 發送成功才存；沒發成功的話，下次執行會再試一次
    save_seen(SEEN_PATH, seen | current)
    return 1 if fcm_failed else 0


if __name__ == "__main__":
    sys.exit(main())

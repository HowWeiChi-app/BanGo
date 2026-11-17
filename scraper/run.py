"""排程每次執行的完整流程：抓公告 → 分類 → 找出新公告 → 發到 Discord → 存檔。

GitHub Actions 每 30 分鐘跑一次  python run.py
在自己電腦上跑時，沒設定 DISCORD_WEBHOOK_URL 就只會印出「本來要發的內容」，不會真的發。
"""

import os
import sys
from pathlib import Path

from filters import KEYWORD_CATEGORIES, TOPICS, classify, should_push
from notify_discord import build_messages, send
from parser import ParseError, fetch_all
from store import find_new, load_seen, save_seen

SEEN_PATH = Path(__file__).parent / "data" / "seen.json"

# Discord 是全班共用一個頻道，沒辦法每個人設定不同，所以所有類別和主題都發
CHANNEL_SUBSCRIBED = set(KEYWORD_CATEGORIES) | set(TOPICS)


def main() -> int:
    webhook = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    in_ci = os.environ.get("GITHUB_ACTIONS") == "true"
    if in_ci and not webhook:
        # 不擋下來的話，會把新公告記成看過，卻沒發出去
        print("GitHub Secrets 裡沒有設定 DISCORD_WEBHOOK_URL", file=sys.stderr)
        return 1

    try:
        notices = fetch_all()
    except ParseError as e:
        print(f"解析失敗，可能是校網改版：{e}", file=sys.stderr)
        return 1
    for n in notices:
        classify(n)

    current = {n.url for n in notices}
    seen = load_seen(SEEN_PATH)
    if seen is None:
        # 第一次執行：全部記成看過、不發，免得一次洗出 50 則舊公告
        save_seen(SEEN_PATH, current)
        print(f"第一次執行，記下目前的 {len(current)} 則公告，不發通知")
        return 0

    new = find_new(notices, seen)
    to_send = [n for n in new if should_push(n, CHANNEL_SUBSCRIBED)]
    to_send.reverse()  # 舊的先發，Discord 裡最新的就會在最下面
    print(f"新公告 {len(new)} 則，要發的 {len(to_send)} 則")

    if to_send:
        if webhook:
            send(webhook, to_send)
        else:
            print("（沒設定 DISCORD_WEBHOOK_URL，只印出內容）")
            for msg in build_messages(to_send):
                print("-" * 40 + "\n" + msg)

    # 發送成功才存；沒發成功的話，下次執行會再試一次
    save_seen(SEEN_PATH, seen | current)
    return 0


if __name__ == "__main__":
    sys.exit(main())

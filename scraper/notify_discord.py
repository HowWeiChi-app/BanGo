"""把新公告發到 Discord 頻道（用 webhook，不用寫機器人）。

webhook 網址的取得方式：Discord 頻道設定 → 整合 → Webhook → 新 Webhook → 複製網址。
這個網址等於頻道的發文權限，不要寫進程式碼或 commit，要放在 GitHub Secrets。
（這個檔案不叫 discord.py，是為了避免跟同名的 Python 套件撞名。）
"""

import json
import time
import urllib.request

from notice import Notice

MAX_LEN = 2000  # Discord 單則訊息的字數上限


def format_notice(n: Notice) -> str:
    tags = " · ".join(n.categories + ["#" + t for t in n.topics])
    # 網址包在 <> 裡，Discord 就不會展開一大塊預覽圖
    return f"📢 **{n.title}**\n{tags} · {n.date}\n<{n.url}>"


def build_messages(notices: list[Notice]) -> list[str]:
    """把公告排成好幾則訊息，每則不超過 2000 字。"""
    messages, current = [], ""
    for n in notices:
        block = format_notice(n)[:MAX_LEN]
        if current and len(current) + 2 + len(block) > MAX_LEN:
            messages.append(current)
            current = ""
        current = f"{current}\n\n{block}" if current else block
    if current:
        messages.append(current)
    return messages


def send(webhook_url: str, notices: list[Notice]) -> None:
    for i, text in enumerate(build_messages(notices)):
        if i:
            time.sleep(1)  # Discord 有發送頻率限制，慢慢發
        body = json.dumps({
            "content": text,
            # 不讓訊息觸發任何 @提及，就算公告標題裡剛好有 @everyone 也不會吵到全頻道
            "allowed_mentions": {"parse": []},
        }).encode("utf-8")
        req = urllib.request.Request(webhook_url, data=body, method="POST", headers={
            "Content-Type": "application/json",
            "User-Agent": "SchoolNoticeBot/0.1",  # Discord 會擋沒有 User-Agent 的請求
        })
        urllib.request.urlopen(req, timeout=20).close()  # 失敗會丟出例外，run.py 就不會存檔

"""在電腦上印出最新公告。

執行方式（在 scraper 資料夾裡）：
  python3 main.py        印出最新 20 則
  python3 main.py 考試   只印出「考試」主題的公告
"""

import sys

from filters import TOPICS, classify
from parser import FetchError, ParseError, fetch_all


def main() -> int:
    topic = sys.argv[1] if len(sys.argv) > 1 else None
    if topic and topic not in TOPICS:
        print(f"沒有「{topic}」這個主題，可以用的有：{'、'.join(TOPICS)}", file=sys.stderr)
        return 2

    try:
        notices = fetch_all()
    except ParseError as e:
        print(f"解析失敗，可能是校網改版：{e}", file=sys.stderr)
        return 1  # 非 0 代表失敗，之後 GitHub Actions 會因此寄信通知開發者
    except FetchError as e:
        # Mac 上看到 CERTIFICATE_VERIFY_FAILED：指令前面加 SSL_CERT_FILE=/etc/ssl/cert.pem（見 README）
        print(e, file=sys.stderr)
        return 1

    for n in notices:
        classify(n)
    if topic:
        notices = [n for n in notices if topic in n.topics]
        if not notices:
            print(f"目前抓得到的公告裡沒有「{topic}」主題的公告")

    for n in notices[:20]:
        mark = "  " if n.for_students else "✗ "  # ✗ = 判定跟學生無關，不推播
        tags = ",".join(n.categories + ["#" + t for t in n.topics]) or "-"
        print(f"{mark}{n.date}  [{n.source}] [{tags}]  {n.title}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

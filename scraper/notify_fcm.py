"""透過 Firebase Cloud Messaging（FCM）發手機推播。

設計：用 FCM 的「主題訂閱」。App 在手機上訂閱主題（例如打開「教務」就訂閱 academic），
這裡發送時指定主題，伺服器不需要知道有哪些手機，也不用存任何同學的資料。

一則公告可能同時是「教務」和「#考試」。如果分別發給兩個主題，兩個都訂閱的同學會收到兩次，
所以改用 FCM 的 condition：「有訂閱 academic 或 exam 的手機」，每支手機只會收到一次。

需要的 GitHub Secret：FIREBASE_SERVICE_ACCOUNT（服務帳戶金鑰 JSON，設定方式見 docs/firebase-setup.md）
需要的套件：google-auth、requests（只有 GitHub Actions 上會裝，本機跑測試不需要）
"""

import json
import urllib.request

from notice import Notice

# 類別／主題 → FCM 主題名稱。FCM 主題名稱只能用英文、數字和 -_.~%
# App 那邊（app/lib/push.dart）要用同一張表。新增類別或主題時兩邊都要加，測試會檢查有沒有漏。
FCM_TOPICS = {
    "教務": "academic",
    "學務": "student-affairs",
    "輔導": "counseling",
    "獎學金": "scholarship",
    "比賽": "competition",
    "考試": "exam",
    "停課": "class-suspension",
}

MAX_CONDITION_TOPICS = 5  # FCM 的 condition 最多只能寫 5 個主題


def condition_for(notice: Notice) -> str | None:
    """產生 FCM condition，例如 "'academic' in topics || 'exam' in topics"。沒有任何主題就回傳 None。"""
    ids = [FCM_TOPICS[t] for t in notice.categories + notice.topics if t in FCM_TOPICS]
    ids = list(dict.fromkeys(ids))[:MAX_CONDITION_TOPICS]  # 去掉重複，保留順序
    if not ids:
        return None
    return " || ".join(f"'{i}' in topics" for i in ids)


def build_message(notice: Notice) -> dict | None:
    condition = condition_for(notice)
    if condition is None:
        return None
    tags = " · ".join(notice.categories + ["#" + t for t in notice.topics])
    return {
        "message": {
            "condition": condition,
            "notification": {
                "title": f"附中公告 · {tags}",
                "body": notice.title,
            },
            # App 點通知時用這個網址打開校網原文
            "data": {"url": notice.url},
            "android": {"notification": {"channel_id": "notices"}},
        }
    }


def _access_token(service_account: dict) -> str:
    """用服務帳戶金鑰換一個短期的存取權杖。"""
    # 放在函式裡才 import：本機沒裝這兩個套件時，其他功能和測試照樣能跑
    from google.auth.transport.requests import Request
    from google.oauth2 import service_account as sa

    creds = sa.Credentials.from_service_account_info(
        service_account, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
    )
    creds.refresh(Request())
    return creds.token


def send(service_account_json: str, notices: list[Notice]) -> int:
    """發推播，回傳發了幾則。失敗會丟出例外。"""
    info = json.loads(service_account_json)
    token = _access_token(info)
    url = f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send"

    sent = 0
    for n in notices:
        message = build_message(n)
        if message is None:
            continue
        req = urllib.request.Request(
            url,
            data=json.dumps(message).encode("utf-8"),
            method="POST",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        )
        urllib.request.urlopen(req, timeout=20).close()
        sent += 1
    return sent

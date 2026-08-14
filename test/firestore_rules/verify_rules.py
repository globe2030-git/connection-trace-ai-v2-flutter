#!/usr/bin/env python3
"""Firestore 보안 규칙 검증 (P0-8, backlog 추가 82).

왜 필요한가: `users/{uid}` 문서에 클라이언트 쓰기가 전면 허용돼 있어서 로그인한
사용자가 AI 호출 한도(`aiUsage`)를 직접 리셋할 수 있었다. 그 비용은 회사 명의
유료 Gemini 키로 나간다. 규칙을 필드 단위로 좁혔는데, 이런 실수는 화면을 아무리
눌러봐도 드러나지 않으므로 규칙 자체를 테스트로 고정한다.

**로컬 에뮬레이터를 쓰지 않는 이유**: 이 환경에 설치된 JDK(IBM Semeru 26)에서
Firestore 에뮬레이터의 규칙 엔진이 뜨지 않는다(전부 허용하는 최소 규칙조차
`ExceptionInInitializerError`로 실패). 대신 Firebase의 규칙 테스트 API로 서버에서
평가한다 — 실제 배포에 쓰이는 것과 같은 엔진이라 오히려 신뢰도가 높고, 아직
배포하지 않은 규칙 파일을 그대로 보내 평가하므로 운영 데이터에 아무 영향이 없다.

실행: python3 test/firestore_rules/verify_rules.py
      (firebase CLI가 로그인돼 있어야 한다 — 저장된 토큰을 재사용한다)
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

PROJECT = "connection-sense"
RULES_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "firestore.rules")
CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi"

OWNER = "user_owner"
OTHER = "user_other"
DOC = f"/databases/(default)/documents/users/{OWNER}"
NOW = "2026-08-06T00:00:00Z"


def access_token() -> str:
    path = os.path.expanduser("~/.config/configstore/firebase-tools.json")
    refresh = json.load(open(path))["tokens"]["refresh_token"]
    body = urllib.parse.urlencode({
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "refresh_token": refresh,
        "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body)
    return json.load(urllib.request.urlopen(req, timeout=30))["access_token"]


def case(name, expect, *, uid, method, path=DOC, before=None, after=None, token=None):
    """규칙 테스트 케이스 하나.

    before = 이미 저장돼 있는 문서(rules의 `resource`)
    after  = 쓰기가 끝난 뒤의 문서 상태(rules의 `request.resource`)
    token  = request.auth.token에 넣을 커스텀 클레임(예: 이메일 인증 상태로
             관리자 판별을 태우는 케이스). isAdmin()은 request.auth.token.email과
             email_verified를 보므로, 관리자 여부를 검증하려면 이 값이 필요하다.
    """
    request = {"method": method, "path": path, "time": NOW}
    if uid:
        auth = {"uid": uid}
        if token is not None:
            auth["token"] = token
        request["auth"] = auth
    if after is not None:
        request["resource"] = {"data": after}
    tc = {"expectation": expect, "request": request}
    if before is not None:
        tc["resource"] = {"data": before}
    return name, tc


# 관리자 판별용 토큰 — firestore.rules의 isAdmin() 허용목록과 같은 값이어야
# 한다(functions/src/adminEmails.ts와도 동기화됨, tool/check_admin_sync.py).
ADMIN_TOKEN = {
    "email": "connectionsense@creamhouse.net",
    "email_verified": True,
}
NON_ADMIN_TOKEN = {
    "email": "someone@example.com",
    "email_verified": True,
}
APP_UPDATE_PATH = "/databases/(default)/documents/config/appUpdate"


def app_update_doc(**overrides):
    base = {
        "minSupportedBuildIos": 5,
        "minSupportedBuildAndroid": 5,
        "latestBuildIos": 10,
        "latestBuildAndroid": 10,
        "iosUrl": "https://apps.apple.com/app/id123",
        "androidUrl": "https://play.google.com/store/apps/details?id=x",
        "minSupportedBuild": 5,
        "latestBuild": 10,
    }
    base.update(overrides)
    return base


KEY = "ORIGINAL_KEY"
PROFILE = {"encrypted": "CIPHER", "schemaVersion": 2}

CASES = [
    # ── 소유권 ────────────────────────────────────────────────────────
    case("본인 문서를 읽을 수 있다", "ALLOW",
         uid=OWNER, method="get", before={"encryptionKeyB64": KEY}),
    case("다른 사용자의 문서는 읽을 수 없다", "DENY",
         uid=OTHER, method="get", before={"encryptionKeyB64": KEY}),
    case("로그인하지 않으면 읽을 수 없다", "DENY",
         uid=None, method="get", before={"encryptionKeyB64": KEY}),

    # ── AI 호출 한도 (P0-8의 핵심) ────────────────────────────────────
    case("⭐ AI 호출 한도를 클라이언트가 리셋할 수 없다", "DENY",
         uid=OWNER, method="update",
         before={"encryptionKeyB64": KEY, "aiUsage": {"dailyCount": 10}},
         after={"encryptionKeyB64": KEY, "aiUsage": {"dailyCount": 0}}),
    case("⭐ 문서를 덮어써 한도를 지우는 것도 막는다", "DENY",
         uid=OWNER, method="update",
         before={"encryptionKeyB64": KEY, "aiUsage": {"dailyCount": 10}},
         after={"encryptionKeyB64": KEY}),
    case("한도가 있어도 프로필 백업은 계속 된다", "ALLOW",
         uid=OWNER, method="update",
         before={"encryptionKeyB64": KEY, "aiUsage": {"dailyCount": 10}},
         after={"encryptionKeyB64": KEY, "aiUsage": {"dailyCount": 10},
                "profile": PROFILE}),

    # ── 암호화 키 ─────────────────────────────────────────────────────
    case("암호화 키가 없으면 최초 1회 넣을 수 있다", "ALLOW",
         uid=OWNER, method="update",
         before={"profile": PROFILE},
         after={"profile": PROFILE, "encryptionKeyB64": "NEW_KEY"}),
    case("⭐ 이미 발급된 암호화 키는 바꿀 수 없다", "DENY",
         uid=OWNER, method="update",
         before={"encryptionKeyB64": KEY},
         after={"encryptionKeyB64": "HACKED"}),
    case("키가 있어도 프로필만 바꾸는 것은 허용된다", "ALLOW",
         uid=OWNER, method="update",
         before={"encryptionKeyB64": KEY},
         after={"encryptionKeyB64": KEY, "profile": PROFILE}),

    # ── 허용되지 않은 필드 ────────────────────────────────────────────
    case("알 수 없는 필드는 쓸 수 없다", "DENY",
         uid=OWNER, method="update",
         before={"encryptionKeyB64": KEY},
         after={"encryptionKeyB64": KEY, "isAdmin": True}),
    case("최초 생성은 허용된 필드만 가능하다", "ALLOW",
         uid=OWNER, method="create",
         after={"encryptionKeyB64": KEY, "updatedAt": NOW}),
    case("최초 생성에 한도 필드를 끼워 넣을 수 없다", "DENY",
         uid=OWNER, method="create",
         after={"encryptionKeyB64": KEY, "aiUsage": {"dailyCount": 0}}),

    # ── 명함(하위 컬렉션)과 계정 삭제 ─────────────────────────────────
    case("본인 명함은 쓸 수 있다", "ALLOW",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/users/{OWNER}/contacts/c1",
         after={"encrypted": "CIPHER", "schemaVersion": 2}),
    case("다른 사용자의 명함은 쓸 수 없다", "DENY",
         uid=OTHER, method="create",
         path=f"/databases/(default)/documents/users/{OWNER}/contacts/c1",
         after={"encrypted": "CIPHER", "schemaVersion": 2}),
    case("계정 삭제를 위해 본인 문서를 지울 수 있다", "ALLOW",
         uid=OWNER, method="delete",
         before={"encryptionKeyB64": KEY, "aiUsage": {"dailyCount": 3}}),

    # ── 강제 업데이트 URL 허용목록 (ADMIN-VULN-003) ──────────────────────
    case("관리자가 정상 스토어 URL과 min<=latest로 쓰면 허용된다", "ALLOW",
         uid="admin1", method="update", path=APP_UPDATE_PATH, token=ADMIN_TOKEN,
         before={}, after=app_update_doc()),
    case("관리자가 http(비-https)로 apps.apple.com을 쓰면 거부된다", "DENY",
         uid="admin1", method="update", path=APP_UPDATE_PATH, token=ADMIN_TOKEN,
         before={}, after=app_update_doc(iosUrl="http://apps.apple.com/app/id123")),
    case("관리자가 커스텀 스킴 URL을 쓰면 거부된다", "DENY",
         uid="admin1", method="update", path=APP_UPDATE_PATH, token=ADMIN_TOKEN,
         before={}, after=app_update_doc(androidUrl="myapp://update")),
    case("관리자가 비공식 host를 쓰면 거부된다", "DENY",
         uid="admin1", method="update", path=APP_UPDATE_PATH, token=ADMIN_TOKEN,
         before={}, after=app_update_doc(androidUrl="https://evil.example.com/app")),
    case("관리자가 minSupportedBuildIos > latestBuildIos로 쓰면 거부된다", "DENY",
         uid="admin1", method="update", path=APP_UPDATE_PATH, token=ADMIN_TOKEN,
         before={}, after=app_update_doc(minSupportedBuildIos=20, latestBuildIos=10)),
    case("관리자가 빈 URL + min<=latest(초기값 0/0)로 쓰면 허용된다", "ALLOW",
         uid="admin1", method="update", path=APP_UPDATE_PATH, token=ADMIN_TOKEN,
         before={}, after=app_update_doc(
             iosUrl="", androidUrl="",
             minSupportedBuildIos=0, minSupportedBuildAndroid=0,
             latestBuildIos=0, latestBuildAndroid=0,
             minSupportedBuild=0, latestBuild=0)),
    case("관리자가 아닌 로그인 사용자는 정상 값이어도 거부된다", "DENY",
         uid="user1", method="update", path=APP_UPDATE_PATH, token=NON_ADMIN_TOKEN,
         before={}, after=app_update_doc()),
]


def main() -> int:
    rules = open(RULES_PATH).read()
    body = {
        "source": {"files": [{"name": "firestore.rules", "content": rules}]},
        "testSuite": {"testCases": [tc for _, tc in CASES]},
    }
    req = urllib.request.Request(
        f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}:test",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {access_token()}",
                 "Content-Type": "application/json"},
    )
    try:
        res = json.load(urllib.request.urlopen(req, timeout=90))
    except urllib.error.HTTPError as e:
        print("규칙 평가 요청 실패:", e.code, e.read().decode()[:500])
        return 2

    if "issues" in res:
        print("⚠️ 규칙 문법 문제:")
        for issue in res["issues"]:
            print("   ", issue.get("description"), issue.get("sourcePosition"))
        return 2

    results = res.get("testResults", [])
    failed = 0
    for (name, tc), r in zip(CASES, results):
        ok = r.get("state") == "SUCCESS"
        if not ok:
            failed += 1
        suffix = "" if ok else f"  (기대: {tc['expectation']})"
        print(f"  {'✅' if ok else '❌'} {name}{suffix}")

    print(f"\n  {len(results) - failed}/{len(results)} 통과")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

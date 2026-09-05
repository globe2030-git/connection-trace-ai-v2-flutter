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


def get_mock(path, data):
    """rules 안의 get(...) 호출을 가로채 고정된 문서를 돌려주게 하는 목(mock).

    `inquiries/{id}/replies/{id}` 규칙처럼 부모 문서를 get()으로 조회해야
    하는 규칙은, 실제 운영 Firestore에 그 문서가 없으면 get()이 그냥 실패해
    항상 DENY로 떨어진다(회귀 방지 테스트로 쓸모없어짐) — 그렇다고 테스트를
    위해 운영 Firestore에 실제 문서를 심는 것도 원치 않는다. firebaserules
    테스트 API가 지원하는 `functionMocks`로 get() 호출 자체를 가짜 데이터로
    대체한다(2026-08-14, ADMIN-VULN-005 검증용으로 조사해 확인한 API 동작 —
    exactValue에 `/databases/(default)/documents/...` 형태의 경로 문자열을
    넣고 result.value에 `{"data": {...}}`를 주면 get(...).data가 그 값으로
    평가된다).
    """
    return {
        "function": "get",
        "args": [{"exactValue": path}],
        "result": {"value": {"data": data}},
    }


def case(name, expect, *, uid, method, path=DOC, before=None, after=None,
         token=None, mocks=None):
    """규칙 테스트 케이스 하나.

    before = 이미 저장돼 있는 문서(rules의 `resource`)
    after  = 쓰기가 끝난 뒤의 문서 상태(rules의 `request.resource`)
    token  = request.auth.token에 넣을 커스텀 클레임(예: 이메일 인증 상태로
             관리자 판별을 태우는 케이스). isAdmin()은 request.auth.token.email과
             email_verified를 보므로, 관리자 여부를 검증하려면 이 값이 필요하다.
    mocks  = get_mock(...)으로 만든 functionMocks 리스트. get()으로 다른
             문서를 조회하는 규칙(예: inquiries/{id}/replies)을 테스트할 때 쓴다.
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
    if mocks:
        tc["functionMocks"] = mocks
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

# `request.time`(NOW)을 epoch 밀리초로 옮긴 값. 관리자 2차 인증 세션의
# `expiresAt` 이 Timestamp 가 아니라 **숫자**로 저장되기 때문에 필요하다
# (functions/src/index.ts 의 writeAdminSession → adminAuth.ts 의
# adminSessionExpiresAt 가 number 를 돌려준다). firestore.rules 는
# `request.time.toMillis()` 로 맞춰 비교한다.
NOW_MS = 1785974400000  # 2026-08-06T00:00:00Z
ADMIN_UID = "admin1"
ADMIN_SESSION_PATH = f"/databases/(default)/documents/adminSessions/{ADMIN_UID}"


def admin_session_mocks(expires_at_ms):
    """관리자 2차 인증 세션 문서를 가짜로 세워 준다.

    `expires_at_ms=None` 이면 **문서가 없는 상태**다 — exists() 가 False 를
    돌려주고 rules 의 `&&` 가 거기서 끊긴다.
    """
    if expires_at_ms is None:
        return [{
            "function": "exists",
            "args": [{"exactValue": ADMIN_SESSION_PATH}],
            "result": {"value": False},
        }]
    return [
        {
            "function": "exists",
            "args": [{"exactValue": ADMIN_SESSION_PATH}],
            "result": {"value": True},
        },
        get_mock(ADMIN_SESSION_PATH, {"expiresAt": expires_at_ms}),
    ]
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


# ── 충전 상품 설정 스키마 검증용 (ADMIN-VULN-004) ───────────────────────
BILLING_PATH = "/databases/(default)/documents/config/billing"
TIER_PRICES = [1000, 3000, 5000, 10000, 30000, 50000, 100000]


def billing_doc(*, free_credits=10, tiers=None):
    """docs/admin/admin.js billingSaveBtn 핸들러가 실제로 보내는 것과 같은
    모양(7개 티어 전부, priceKrw는 TIER_PRICES와 정확히 일치)."""
    if tiers is None:
        tiers = [
            {"priceKrw": p, "credits": 10, "active": True} for p in TIER_PRICES
        ]
    return {"freeCredits": free_credits, "tiers": tiers, "updatedAt": NOW}


# ── 관리자 감사 로그 스키마 검증용 (ADMIN-VULN-010) ─────────────────────
ADMIN_AUDIT_PATH = "/databases/(default)/documents/adminAuditLogs/LOG1"


def admin_audit_doc(**overrides):
    base = {
        "actorUid": "admin1",
        "actorEmail": ADMIN_TOKEN["email"],
        "action": "billing.save",
        "target": "config/billing",
        "summary": "무료 10회, 활성 티어 3개",
        "at": NOW,
    }
    base.update(overrides)
    return base


KEY = "ORIGINAL_KEY"
PROFILE = {"encrypted": "CIPHER", "schemaVersion": 2}

# ── OCR 통계 스키마 검증용 (ADMIN-VULN-009) ─────────────────────────────
OCR_PATH = f"/databases/(default)/documents/ocrStats/{OWNER}"
NORMAL_OCR = {
    "scans": 42,
    "correctedCards": 5,
    "filled": {"name": 40, "company": 35, "mobile": 38},
    "nameSource": {"keywordSplit": 20, "koreanStripped": 15, "none": 2},
    "companySource": {"keyword": 30, "none": 5},
    "corrections": {
        "name": {"unchanged": 30, "edited": 5, "cleared": 1},
        "mobile": {"unchanged": 38},
    },
    "platform": "android",
    "updatedAt": NOW,
}

# ── 1:1 문의 스키마 검증용 (ADMIN-VULN-005) ─────────────────────────────
INQ_ID = "INQ1"
INQ_PATH = f"/databases/(default)/documents/inquiries/{INQ_ID}"
REPLY_PATH = f"/databases/(default)/documents/inquiries/{INQ_ID}/replies/REPLY1"
INQUIRER = "user_inquirer"
INQUIRER_EMAIL = "inquirer@example.com"
INQUIRER_TOKEN = {"email": INQUIRER_EMAIL, "email_verified": True}


def inquiry_create_doc(**overrides):
    base = {
        "userId": INQUIRER,
        "userName": "홍길동",
        "userEmail": INQUIRER_EMAIL,
        "subject": "로그인이 안 돼요",
        "message": "재설치했는데도 로그인이 안 됩니다.",
        "status": "pending",
        "createdAt": NOW,
    }
    base.update(overrides)
    return base


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

    # ── OCR 통계 스키마 검증 (ADMIN-VULN-009) ──────────────────────────
    case("OCR 통계 정상 페이로드는 허용된다", "ALLOW",
         uid=OWNER, method="update", path=OCR_PATH,
         before={}, after=NORMAL_OCR),
    case("⭐ 감소하는 값도 정상으로 허용된다(초기화 버튼 플로우)", "ALLOW",
         uid=OWNER, method="update", path=OCR_PATH,
         before={**NORMAL_OCR, "scans": 999},
         after={**NORMAL_OCR, "scans": 3}),
    case("정의되지 않은 최상위 키를 끼워 넣으면 거부된다", "DENY",
         uid=OWNER, method="update", path=OCR_PATH,
         before={}, after={**NORMAL_OCR, "hacked": True}),
    case("scans가 문자열이면 거부된다", "DENY",
         uid=OWNER, method="update", path=OCR_PATH,
         before={}, after={**NORMAL_OCR, "scans": "42"}),
    case("scans가 음수면 거부된다", "DENY",
         uid=OWNER, method="update", path=OCR_PATH,
         before={}, after={**NORMAL_OCR, "scans": -1}),
    case("scans가 100만을 초과하면 거부된다", "DENY",
         uid=OWNER, method="update", path=OCR_PATH,
         before={}, after={**NORMAL_OCR, "scans": 999999999}),
    case("filled에 정의되지 않은 키가 있으면 거부된다", "DENY",
         uid=OWNER, method="update", path=OCR_PATH,
         before={}, after={**NORMAL_OCR, "filled": {"ssn": 1}}),
    case("⭐ 다른 사용자의 ocrStats 문서에는 쓸 수 없다", "DENY",
         uid=OTHER, method="update", path=OCR_PATH,
         before={}, after=NORMAL_OCR),

    # ── 1:1 문의 스키마 검증 (ADMIN-VULN-005) ──────────────────────────
    case("toCreatePayload() 그대로의 정상 문의 생성은 허용된다", "ALLOW",
         uid=INQUIRER, method="create", path=INQ_PATH, token=INQUIRER_TOKEN,
         after=inquiry_create_doc()),
    case("⭐ addUserReply() 그대로의 정상 사용자 답장은 허용된다", "ALLOW",
         uid=INQUIRER, method="create", path=REPLY_PATH,
         after={"from": "user", "message": "답장입니다", "createdAt": NOW},
         mocks=[get_mock(INQ_PATH, {"userId": INQUIRER})]),
    case("관리자의 정상 답변은 허용된다", "ALLOW",
         uid="admin1", method="create", path=REPLY_PATH, token=ADMIN_TOKEN,
         after={"from": "admin", "message": "확인했습니다", "createdAt": NOW},
         mocks=[get_mock(INQ_PATH, {"userId": INQUIRER})]),
    case("⭐ 일반 사용자가 from:'admin'으로 답변을 위조할 수 없다", "DENY",
         uid=INQUIRER, method="create", path=REPLY_PATH,
         after={"from": "admin", "message": "가짜 관리자 답변", "createdAt": NOW},
         mocks=[get_mock(INQ_PATH, {"userId": INQUIRER})]),
    case("⭐ 문의 생성 시 status를 'answered'로 위조할 수 없다", "DENY",
         uid=INQUIRER, method="create", path=INQ_PATH, token=INQUIRER_TOKEN,
         after=inquiry_create_doc(status="answered")),
    case("⭐ 문의 생성 시 타인 이메일을 userEmail로 위조할 수 없다", "DENY",
         uid=INQUIRER, method="create", path=INQ_PATH, token=INQUIRER_TOKEN,
         after=inquiry_create_doc(userEmail="other@example.com")),
    case("문의 생성 시 정의되지 않은 추가 필드는 거부된다", "DENY",
         uid=INQUIRER, method="create", path=INQ_PATH, token=INQUIRER_TOKEN,
         after=inquiry_create_doc(internalNote="VIP 고객")),
    case("⭐ 다른 사용자가 남의 문의에 from:'user'로 답장할 수 없다", "DENY",
         uid=OTHER, method="create", path=REPLY_PATH,
         after={"from": "user", "message": "몰래 답장", "createdAt": NOW},
         mocks=[get_mock(INQ_PATH, {"userId": INQUIRER})]),

    # ── 충전 상품 설정 스키마 검증 (ADMIN-VULN-004) ─────────────────────
    case("관리자가 정상 billing 설정(7개 티어)을 쓰면 허용된다", "ALLOW",
         uid="admin1", method="update", path=BILLING_PATH, token=ADMIN_TOKEN,
         before={}, after=billing_doc()),
    case("⭐ tier credits에 속성탈출 문자열을 넣으면 거부된다", "DENY",
         uid="admin1", method="update", path=BILLING_PATH, token=ADMIN_TOKEN,
         before={}, after=billing_doc(tiers=[
             {"priceKrw": p,
              "credits": ('"><script>alert(1)</script>' if p == 1000 else 10),
              "active": True}
             for p in TIER_PRICES
         ])),
    case("tier에 정의되지 않은 여분 키가 있으면 거부된다", "DENY",
         uid="admin1", method="update", path=BILLING_PATH, token=ADMIN_TOKEN,
         before={}, after=billing_doc(tiers=[
             {"priceKrw": p, "credits": 10, "active": True, "note": "x"}
             if p == 1000 else {"priceKrw": p, "credits": 10, "active": True}
             for p in TIER_PRICES
         ])),
    case("tiers 배열이 6개면 거부된다", "DENY",
         uid="admin1", method="update", path=BILLING_PATH, token=ADMIN_TOKEN,
         before={}, after=billing_doc(tiers=[
             {"priceKrw": p, "credits": 10, "active": True}
             for p in TIER_PRICES[:6]
         ])),
    case("tiers 배열이 8개면 거부된다", "DENY",
         uid="admin1", method="update", path=BILLING_PATH, token=ADMIN_TOKEN,
         before={}, after=billing_doc(tiers=[
             {"priceKrw": p, "credits": 10, "active": True}
             for p in TIER_PRICES
         ] + [{"priceKrw": 1000, "credits": 10, "active": True}])),
    case("freeCredits가 음수면 거부된다", "DENY",
         uid="admin1", method="update", path=BILLING_PATH, token=ADMIN_TOKEN,
         before={}, after=billing_doc(free_credits=-1)),
    case("freeCredits가 100000을 초과하면 거부된다", "DENY",
         uid="admin1", method="update", path=BILLING_PATH, token=ADMIN_TOKEN,
         before={}, after=billing_doc(free_credits=100001)),
    case("관리자가 아닌 로그인 사용자는 정상값이어도 billing을 쓸 수 없다", "DENY",
         uid="user1", method="update", path=BILLING_PATH, token=NON_ADMIN_TOKEN,
         before={}, after=billing_doc()),

    # ── 관리자 감사 로그 스키마 검증 (ADMIN-VULN-010) ───────────────────
    case("관리자가 정상 스키마로 감사 로그를 생성하면 허용된다", "ALLOW",
         uid="admin1", method="create", path=ADMIN_AUDIT_PATH, token=ADMIN_TOKEN,
         after=admin_audit_doc()),
    case("⭐ actorEmail을 자신의 토큰 이메일과 다르게 쓰면(관리자 행세) 거부된다", "DENY",
         uid="admin1", method="create", path=ADMIN_AUDIT_PATH, token=ADMIN_TOKEN,
         after=admin_audit_doc(actorEmail="other-admin@example.com")),
    case("action이 허용 목록에 없는 값이면 거부된다", "DENY",
         uid="admin1", method="create", path=ADMIN_AUDIT_PATH, token=ADMIN_TOKEN,
         after=admin_audit_doc(action="admin.deleteEverything")),
    case("여분 필드(message)가 있으면 거부된다", "DENY",
         uid="admin1", method="create", path=ADMIN_AUDIT_PATH, token=ADMIN_TOKEN,
         after=admin_audit_doc(message="여분 필드")),
    case("관리자가 아닌 사용자는 감사 로그를 생성할 수 없다", "DENY",
         uid="user1", method="create", path=ADMIN_AUDIT_PATH, token=NON_ADMIN_TOKEN,
         after=admin_audit_doc(actorUid="user1", actorEmail=NON_ADMIN_TOKEN["email"])),
    case("⭐ 이미 있는 감사 로그는 관리자도 update할 수 없다(append-only)", "DENY",
         uid="admin1", method="update", path=ADMIN_AUDIT_PATH, token=ADMIN_TOKEN,
         before=admin_audit_doc(), after=admin_audit_doc(summary="수정 시도")),
    # ── 리퍼럴 코드(referralCodes, U2 — bootstrapAccount) ────────────
    # 코드 발급·검증은 항상 서버(Admin SDK)를 거친다는 원칙을 규칙
    # 레벨에서 강제 — 클라이언트는 읽기/쓰기 모두 불가(로그인 여부와
    # 무관하게 거부).
    case("⭐ 리퍼럴 코드는 본인 것도 클라이언트가 읽을 수 없다", "DENY",
         uid=OWNER, method="get",
         path="/databases/(default)/documents/referralCodes/ABC123",
         before={"uid": OWNER}),
    case("⭐ 리퍼럴 코드는 클라이언트가 만들 수 없다", "DENY",
         uid=OWNER, method="create",
         path="/databases/(default)/documents/referralCodes/ABC123",
         after={"uid": OWNER}),
    case("리퍼럴 코드는 로그인 안 해도 당연히 거부", "DENY",
         uid=None, method="get",
         path="/databases/(default)/documents/referralCodes/ABC123",
         before={"uid": OWNER}),

    # ── 기기 단위 무료체험 이력(deviceLedger, U5 — 재가입 무한루프 방어) ──
    # appleAuth와 같은 패턴: 서버(Admin SDK)만 접근, 클라이언트는 로그인
    # 여부와 무관하게 읽기/쓰기 모두 거부.
    case("⭐ deviceLedger는 로그인해도 클라이언트가 읽을 수 없다", "DENY",
         uid=OWNER, method="get",
         path="/databases/(default)/documents/deviceLedger/HASH123",
         before={"trialGrantsIssued": 1}),
    case("⭐ deviceLedger는 클라이언트가 새로 만들 수 없다", "DENY",
         uid=OWNER, method="create",
         path="/databases/(default)/documents/deviceLedger/HASH123",
         after={"trialGrantsIssued": 0}),
    case("⭐ deviceLedger는 클라이언트가 갱신할 수도 없다(캡 우회 시도 방지)", "DENY",
         uid=OWNER, method="update",
         path="/databases/(default)/documents/deviceLedger/HASH123",
         before={"trialGrantsIssued": 1},
         after={"trialGrantsIssued": 0}),
    case("deviceLedger는 로그인 안 해도 당연히 거부", "DENY",
         uid=None, method="get",
         path="/databases/(default)/documents/deviceLedger/HASH123",
         before={"trialGrantsIssued": 1}),

    # ── 파일럿(베타) 계측 이벤트(pilotEvents, 2026-08-15) ────────────────
    case("본인 복사/전송 이벤트는 만들 수 있다", "ALLOW",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e1",
         after={"type": "copy_send", "uid": OWNER, "at": NOW, "channel": "call"}),
    case("본인 피드백 이벤트(척도)는 만들 수 있다", "ALLOW",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e2",
         after={"type": "feedback", "uid": OWNER, "at": NOW, "rating": 4}),
    case("본인 피드백 이벤트(👍/👎)는 만들 수 있다", "ALLOW",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e3",
         after={"type": "feedback", "uid": OWNER, "at": NOW, "thumbsUp": True}),
    case("⭐ 다른 사람 uid 하위에 이벤트를 만들 수 없다", "DENY",
         uid=OTHER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e4",
         after={"type": "copy_send", "uid": OWNER, "at": NOW, "channel": "sms"}),
    case("⭐ 문서 경로 uid와 내부 uid 필드가 다르면 거부(위조 방지)", "DENY",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e5",
         after={"type": "copy_send", "uid": OTHER, "at": NOW, "channel": "sms"}),
    case("⭐ 서버 전용 타입(activation)은 클라이언트가 절대 못 만든다", "DENY",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e6",
         after={"type": "activation", "uid": OWNER, "at": NOW}),
    case("정의되지 않은 채널이면 거부", "DENY",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e7",
         after={"type": "copy_send", "uid": OWNER, "at": NOW, "channel": "fax"}),
    case("rating이 범위(1~5)를 벗어나면 거부", "DENY",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e8",
         after={"type": "feedback", "uid": OWNER, "at": NOW, "rating": 6}),
    case("thumbsUp도 rating도 없는 feedback은 거부(빈 반응)", "DENY",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e9",
         after={"type": "feedback", "uid": OWNER, "at": NOW}),
    case("허용되지 않은 여분 필드(개인정보 원문 등)를 끼워 넣으면 거부", "DENY",
         uid=OWNER, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e10",
         after={"type": "copy_send", "uid": OWNER, "at": NOW, "channel": "call",
                "point": "이 문장은 대화 포인트 원문이라 절대 들어가면 안 됨"}),
    case("⭐ 로그는 불변 — 본인 것이어도 수정할 수 없다", "DENY",
         uid=OWNER, method="update",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e1",
         before={"type": "copy_send", "uid": OWNER, "at": NOW, "channel": "call"},
         after={"type": "copy_send", "uid": OWNER, "at": NOW, "channel": "sms"}),
    case("로그인 안 하면 pilotEvents도 당연히 거부", "DENY",
         uid=None, method="create",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e11",
         after={"type": "copy_send", "uid": OWNER, "at": NOW, "channel": "call"}),
    case("관리자는 본인 것이 아니어도 읽을 수 있다", "ALLOW",
         uid="admin1", method="get", token=ADMIN_TOKEN,
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e1",
         before={"type": "copy_send", "uid": OWNER, "at": NOW, "channel": "call"}),
    case("관리자가 아니면 본인 것도 아닌 이벤트를 읽을 수 없다", "DENY",
         uid=OTHER, method="get",
         path=f"/databases/(default)/documents/pilotEvents/{OWNER}/events/e1",
         before={"type": "copy_send", "uid": OWNER, "at": NOW, "channel": "call"}),

    # ── users/{uid}.cohortWeek·pilotActivatedAt(U6) — 서버 전용 필드 ─────
    # clientWritableUserFields()에 없는 필드라 기존 필드 화이트리스트 규칙이
    # 그대로 막아준다는 것을 명시적으로 고정한다(회귀 방지).
    case("⭐ 클라이언트가 cohortWeek을 직접 써넣을 수 없다", "DENY",
         uid=OWNER, method="update",
         before={"encryptionKeyB64": KEY},
         after={"encryptionKeyB64": KEY, "cohortWeek": "2026-W33"}),
    case("⭐ 클라이언트가 pilotActivatedAt을 직접 써넣을 수 없다", "DENY",
         uid=OWNER, method="update",
         before={"encryptionKeyB64": KEY},
         after={"encryptionKeyB64": KEY, "pilotActivatedAt": NOW}),

    # ── 관리자 2차 인증 잠금 (2026-09-05, 설계 2단계) ─────────────────────
    # adminSessions·config/admins 는 Admin SDK 전용이다. 🚨 쓰기를 열면 2차
    # 인증이 통째로 무의미해진다 — 클라이언트가 세션 문서를 스스로 만들면
    # 인증번호를 한 번도 안 받고 관리자 조작을 할 수 있다.
    case("🚨 관리자여도 adminSessions 를 읽을 수 없다", "DENY",
         uid=ADMIN_UID, method="get", token=ADMIN_TOKEN, path=ADMIN_SESSION_PATH,
         before={"otpVerifiedAt": NOW_MS, "lastActiveAt": NOW_MS,
                 "expiresAt": NOW_MS + 1200000}),
    case("🚨 본인 uid 여도 adminSessions 를 만들 수 없다 — 이게 열리면 2차 "
         "인증이 통째로 무의미해진다", "DENY",
         uid=ADMIN_UID, method="create", token=ADMIN_TOKEN, path=ADMIN_SESSION_PATH,
         after={"otpVerifiedAt": NOW_MS, "lastActiveAt": NOW_MS,
                "expiresAt": NOW_MS + 999999999}),
    case("🚨 관리자여도 config/admins 를 **읽을** 수 없다 — 번호 해시 자체가 "
         "관리자의 전화번호다", "DENY",
         uid=ADMIN_UID, method="get", token=ADMIN_TOKEN,
         path="/databases/(default)/documents/config/admins",
         before={"connectionsense@creamhouse.net": "hash"}),
    case("🚨 관리자여도 config/admins 를 고칠 수 없다 — 고칠 수 있으면 다른 "
         "관리자의 인증 번호를 자기 것으로 바꿀 수 있다", "DENY",
         uid=ADMIN_UID, method="update", token=ADMIN_TOKEN,
         path="/databases/(default)/documents/config/admins",
         before={"connectionsense@creamhouse.net": "hash"},
         after={"connectionsense@creamhouse.net": "attacker-hash"}),
    # ⚠️ 대조군 — config 아래 **다른** 문서는 관리자에게 열려 있다. 위 넷만
    # 닫은 것이 의도된 차이라는 것을 여기서 고정한다. 「일관성」을 이유로
    # 나중에 config/admins 를 열지 말 것.
    case("대조군: config/testers 는 관리자에게 열려 있다(의도된 차이)", "ALLOW",
         uid=ADMIN_UID, method="get", token=ADMIN_TOKEN,
         path="/databases/(default)/documents/config/testers",
         before={"emails": ["a@example.com"]}),

    # ── ③ 스위치가 **꺼져 있는** 동안의 동작 ──────────────────────────────
    # 🚨 이 케이스가 「지금 배포해도 안전하다」를 고정한다. 콘솔 인증 화면
    # (설계 4단계)이 아직 없으므로, 세션 없이도 기존 관리자 조작이 되어야 한다.
    # 이것이 DENY 로 바뀌면 **관리자가 아무것도 못 하게 된 것**이다.
    case("⭐ adminSessionRequired() 가 꺼져 있는 동안은 세션 없이도 관리자 "
         "조작이 된다", "ALLOW",
         uid=ADMIN_UID, method="update", token=ADMIN_TOKEN,
         path="/databases/(default)/documents/legalDocs/privacy",
         before={"body": "before"}, after={"body": "after"},
         mocks=admin_session_mocks(None)),
]

# ══════════════════════════════════════════════════════════════════════════
# 스위치를 **켠** 상태 (설계 4단계 배포 시점의 모습)
#
# 🚨 켜기 전까지 이 경로는 한 번도 안 돈다 — 그래서 여기서 미리 재 둔다.
# 실제로 여기서 하나 잡혔다: 인수인계 문서는 `request.time < expiresAt` 이었는데
# `expiresAt` 은 숫자라 그대로 적으면 타입이 달라 **오류**가 되고, rules 의
# 오류는 곧 거부라 **관리자가 조용히 잠긴다.**
# ══════════════════════════════════════════════════════════════════════════
SESSION_ON_CASES = [
    case("🔒 켜면: 세션 문서가 없으면 관리자 조작이 막힌다", "DENY",
         uid=ADMIN_UID, method="update", token=ADMIN_TOKEN,
         path="/databases/(default)/documents/legalDocs/privacy",
         before={"body": "before"}, after={"body": "after"},
         mocks=admin_session_mocks(None)),
    case("🔒 켜면: 살아 있는 세션이면 통과한다", "ALLOW",
         uid=ADMIN_UID, method="update", token=ADMIN_TOKEN,
         path="/databases/(default)/documents/legalDocs/privacy",
         before={"body": "before"}, after={"body": "after"},
         mocks=admin_session_mocks(NOW_MS + 1)),
    case("🔒 켜면: 만료된 세션은 막힌다", "DENY",
         uid=ADMIN_UID, method="update", token=ADMIN_TOKEN,
         path="/databases/(default)/documents/legalDocs/privacy",
         before={"body": "before"}, after={"body": "after"},
         mocks=admin_session_mocks(NOW_MS - 1)),
    case("🔒 켜면: 딱 그 순간(expiresAt == now)은 막힌다 — 경계", "DENY",
         uid=ADMIN_UID, method="update", token=ADMIN_TOKEN,
         path="/databases/(default)/documents/legalDocs/privacy",
         before={"body": "before"}, after={"body": "after"},
         mocks=admin_session_mocks(NOW_MS)),
    case("🔒 켜면: 세션이 살아 있어도 허용목록에 없는 이메일은 여전히 막힌다",
         "DENY",
         uid=ADMIN_UID, method="update", token=NON_ADMIN_TOKEN,
         path="/databases/(default)/documents/legalDocs/privacy",
         before={"body": "before"}, after={"body": "after"},
         mocks=admin_session_mocks(NOW_MS + 1)),
]


SWITCH_OFF = """    function adminSessionRequired() {
      return false;
    }"""
SWITCH_ON = SWITCH_OFF.replace("return false;", "return true;")


def flip_switch_on(rules: str) -> str:
    """`adminSessionRequired()` 를 켠 사본을 만든다.

    🚨 **파일을 고치지 않는다.** 평가 API 에 보내는 문자열만 바꾼다 —
    저장소의 `firestore.rules` 는 꺼진 채로 남아야 한다(설계 4단계 화면이
    없는 상태로 켜지면 관리자가 아무것도 못 하게 된다).

    ⚠️ 스위치의 모양이 바뀌면 여기서 바로 터진다. 조용히 「안 켜진 채」
    통과하면 **켠 상태를 한 번도 안 잰 것**이 되므로 일부러 예외를 던진다.
    """
    if rules.count(SWITCH_OFF) != 1:
        raise ValueError(
            "firestore.rules 에서 adminSessionRequired() 의 `return false;` 를 "
            "찾지 못했습니다 — 스위치 모양이 바뀌었으면 이 함수도 함께 고쳐야 "
            "합니다. 안 고치면 「켠 상태」를 한 번도 안 재게 됩니다."
        )
    return rules.replace(SWITCH_OFF, SWITCH_ON)


def run_suite(token: str, rules: str, cases: list) -> tuple[int, int]:
    """케이스 묶음 하나를 평가해 (실패 수, 전체 수) 를 돌려준다."""
    body = {
        "source": {"files": [{"name": "firestore.rules", "content": rules}]},
        "testSuite": {"testCases": [tc for _, tc in cases]},
    }
    req = urllib.request.Request(
        f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}:test",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {token}",
                 "Content-Type": "application/json"},
    )
    try:
        res = json.load(urllib.request.urlopen(req, timeout=90))
    except urllib.error.HTTPError as e:
        print("규칙 평가 요청 실패:", e.code, e.read().decode()[:500])
        return -1, 0

    if "issues" in res:
        print("⚠️ 규칙 문법 문제:")
        for issue in res["issues"]:
            print("   ", issue.get("description"), issue.get("sourcePosition"))
        return -1, 0

    results = res.get("testResults", [])
    failed = 0
    for (name, tc), r in zip(cases, results):
        ok = r.get("state") == "SUCCESS"
        if not ok:
            failed += 1
        suffix = "" if ok else f"  (기대: {tc['expectation']})"
        print(f"  {'✅' if ok else '❌'} {name}{suffix}")
    return failed, len(results)


def main() -> int:
    rules = open(RULES_PATH).read()
    token = access_token()

    failed, total = run_suite(token, rules, CASES)
    if failed < 0:
        return 2

    # 🚨 같은 파일을 스위치만 켠 사본으로 한 번 더 잰다. 켜기 전까지는 그 경로가
    # 한 번도 안 돌기 때문에, 여기서 안 재면 설계 4단계에서야 드러난다.
    print("\n  ── adminSessionRequired() 를 켠 사본 (파일은 안 고친다) ──")
    on_failed, on_total = run_suite(token, flip_switch_on(rules), SESSION_ON_CASES)
    if on_failed < 0:
        return 2

    failed += on_failed
    total += on_total
    print(f"\n  {total - failed}/{total} 통과")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

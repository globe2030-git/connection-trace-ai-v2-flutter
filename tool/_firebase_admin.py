"""실물 점검 스크립트들이 함께 쓰는 Firebase 접근·복호화 헬퍼.

**이 도구들이 왜 필요한가**(backlog 추가 77·79·83): 이 프로젝트에서 실제로
아팠던 결함들은 *코드는 맞는데 실물이 틀린* 유형이었다.

- 서버에 명함 개인정보가 평문으로 남아 있었다(5건 중 3건). 암호화 함수도
  단위 테스트도 정상이었고, "한 번도 다시 저장되지 않은 기존 문서"라는
  데이터 이력이 문제였다.
- 좌표 재계산이 복원 경로에서만 호출돼 사실상 죽어 있었다. 서비스 단위
  테스트 10건은 전부 통과하고 있었다.

이런 건 화면을 아무리 눌러봐도, 테스트를 아무리 돌려도 안 나온다. **저장소의
실제 내용을 직접 열어봐야** 보인다. 그 절차를 매번 즉석에서 다시 만들지
않도록 스크립트로 고정한 것이다.

**개인정보 취급 원칙**: 이 도구들은 운영 데이터를 읽는다. 이름·전화번호·
이메일·주소 같은 값은 **절대 출력하지 않는다.** 항상 "그 키가 있는지 없는지"와
건수만 본다. 이 원칙을 깨는 수정을 하지 말 것.

**인증**: Firebase CLI가 로그인돼 있어야 한다(`firebase login`). CLI가 저장해
둔 refresh token을 액세스 토큰으로 교환해 관리자 권한으로 읽는다. 관리자
권한이므로 보안 규칙을 우회한다 — 규칙 자체를 검증하려면
`test/firestore_rules/verify_rules.py`를 쓸 것.
"""
from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.parse
import urllib.request

PROJECT = "connection-sense"
BASE = (
    f"https://firestore.googleapis.com/v1/projects/{PROJECT}"
    "/databases/(default)/documents"
)

# firebase-tools가 쓰는 공식 클라이언트 자격증명. CLI가 저장해 둔 refresh
# token을 액세스 토큰으로 바꾸는 데만 쓴다(비밀이 아니라 CLI에 공개된 값).
_CLIENT_ID = (
    "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
)
_CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi"
_CONFIG = "~/.config/configstore/firebase-tools.json"


class FirebaseAuthError(RuntimeError):
    pass


def access_token() -> str:
    """Firebase CLI 자격증명으로 Firestore 관리자 액세스 토큰을 받는다."""
    path = os.path.expanduser(_CONFIG)
    try:
        tokens = json.load(open(path))["tokens"]
        refresh = tokens["refresh_token"]
    except (OSError, KeyError) as exc:
        raise FirebaseAuthError(
            f"Firebase CLI 자격증명을 찾지 못했습니다({path}). "
            "`firebase login`을 먼저 실행하세요."
        ) from exc

    body = urllib.parse.urlencode({
        "client_id": _CLIENT_ID,
        "client_secret": _CLIENT_SECRET,
        "refresh_token": refresh,
        "grant_type": "refresh_token",
    }).encode()
    try:
        req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body)
        return json.load(urllib.request.urlopen(req, timeout=30))["access_token"]
    except urllib.error.HTTPError as exc:
        raise FirebaseAuthError(
            f"액세스 토큰 발급 실패({exc.code}). `firebase login --reauth`가 필요할 수 있습니다."
        ) from exc


def get_json(url: str, token: str):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    return json.load(urllib.request.urlopen(req, timeout=30))


def get_json_or_none(url: str, token: str):
    """문서가 없으면(404) None을 돌려준다.

    기기에는 로그인 기록이 남아 있는데 서버에서는 그 계정이 이미 삭제된
    경우가 실제로 있다(계정 삭제 후 앱을 지우지 않은 기기). 그때 예외가
    그대로 터지면 도구가 무슨 상황인지 알려주지 못한다.
    """
    try:
        return get_json(url, token)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise


def list_users(token: str) -> list[dict]:
    return get_json(f"{BASE}/users?pageSize=100", token).get("documents", [])


def list_contacts(uid: str, token: str) -> list[dict]:
    return get_json(
        f"{BASE}/users/{uid}/contacts?pageSize=200", token
    ).get("documents", [])


def uid_of(doc: dict) -> str:
    return doc["name"].split("/")[-1]


def encryption_key(user_doc: dict) -> bytes | None:
    """`users/{uid}.encryptionKeyB64`를 바이트로 돌려준다(없으면 None)."""
    b64 = user_doc.get("fields", {}).get("encryptionKeyB64", {}).get("stringValue")
    return base64.b64decode(b64) if b64 else None


def decrypt_payload(encrypted_b64: str, key: bytes) -> dict:
    """앱이 저장한 AES-256-GCM 암호문을 푼다.

    포맷은 `DataCryptoService`와 같다 — base64(nonce 12B + 암호문 + MAC 16B).
    """
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    raw = base64.b64decode(encrypted_b64)
    plain = AESGCM(key).decrypt(raw[:12], raw[12:], None)
    return json.loads(plain.decode())

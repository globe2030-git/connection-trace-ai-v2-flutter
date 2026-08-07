#!/usr/bin/env python3
"""서버(Firestore)에 남아 있으면 안 되는 것이 없는지 확인한다.

확인하는 것 두 가지:

1. **평문 문서가 없는가** — 명함/프로필은 AES-256-GCM으로 암호화해 저장한다
   (backlog 추가 72). 그런데 그 암호화는 "다음에 저장될 때 재암호화"되는
   구조라, 한 번도 다시 저장되지 않은 옛 문서는 계속 평문으로 남는다.
   실제로 명함 5건 중 3건이 이름·전화번호·이메일·주소까지 평문으로 읽히는
   상태였다(추가 77).

2. **좌표가 남아 있지 않은가** — 명함 주소를 변환한 좌표는 서버에 저장하지
   않기로 했다(추가 76, C안). 좌표는 주소에서 파생되는 값이라 보관할 이유가
   없고, 보관하면 "회사가 위치정보를 보유한다"는 해석 여지가 생긴다.
   복원 후에는 기기에서 주소로 다시 계산한다.

**언제 돌리나**
- 저장·암호화·마이그레이션 관련 코드를 고친 뒤
- 개인정보처리방침을 게시하기 전(방침이 사실과 맞는지 확인)
- 릴리스 체크리스트의 한 항목으로

**개인정보는 출력하지 않는다.** 키가 있는지 없는지와 건수만 본다.

사용법:
    python3 tool/verify_server_privacy.py
    python3 tool/verify_server_privacy.py --uid <특정 계정만>

종료 코드: 0 = 통과, 1 = 남아 있음, 2 = 실행 실패
"""
from __future__ import annotations

import argparse
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])

from _firebase_admin import (  # noqa: E402
    FirebaseAuthError,
    PROJECT,
    access_token,
    decrypt_payload,
    encryption_key,
    list_contacts,
    list_users,
    uid_of,
)

COORD_KEYS = ("lat", "lng")


def main() -> int:
    parser = argparse.ArgumentParser(description="서버에 평문·좌표가 남아 있는지 확인")
    parser.add_argument("--uid", help="이 계정만 확인(기본값: 전체)")
    args = parser.parse_args()

    try:
        token = access_token()
    except FirebaseAuthError as exc:
        print(f"❌ {exc}")
        return 2

    print(f"서버 점검 — project={PROJECT}\n")
    total = plaintext = with_coords = undecryptable = 0

    users = list_users(token)
    if args.uid:
        users = [u for u in users if uid_of(u) == args.uid]
        if not users:
            print(f"❌ 계정을 찾지 못했습니다: {args.uid}")
            return 2

    for user in users:
        uid = uid_of(user)
        key = encryption_key(user)
        fields = sorted(user.get("fields", {}).keys())
        print(f"=== uid {uid[:10]}…  (users 문서 필드: {fields or '없음'}) ===")

        contacts = list_contacts(uid, token)
        if not contacts:
            print("  명함 없음")
        for doc in contacts:
            total += 1
            cid = uid_of(doc)
            doc_fields = doc.get("fields", {})
            encrypted = doc_fields.get("encrypted", {}).get("stringValue")

            if not encrypted:
                # 암호화 도입 이전에 저장된 평문 문서.
                plaintext += 1
                has_coords = any(k in doc_fields for k in COORD_KEYS)
                if has_coords:
                    with_coords += 1
                print(f"  {cid:16} ❌ 평문        좌표={'있음' if has_coords else '없음'}")
                continue

            if key is None:
                undecryptable += 1
                print(f"  {cid:16} ?  암호화(키 없음 — 확인 불가)")
                continue

            try:
                plain = decrypt_payload(encrypted, key)
            except Exception as exc:  # noqa: BLE001
                undecryptable += 1
                print(f"  {cid:16} ?  복호화 실패: {type(exc).__name__}")
                continue

            has_coords = any(k in plain for k in COORD_KEYS)
            if has_coords:
                with_coords += 1
            print(f"  {cid:16} {'❌' if has_coords else '✅'} 암호화       좌표키={'있음' if has_coords else '없음'}")
        print()

    print("─" * 56)
    print(f"명함 총 {total}건 / 평문 {plaintext}건 / 좌표 포함 {with_coords}건"
          + (f" / 확인 불가 {undecryptable}건" if undecryptable else ""))

    ok = plaintext == 0 and with_coords == 0
    if ok and undecryptable:
        print("판정: ⚠️ 평문 0건·좌표 0건이지만 확인하지 못한 문서가 있습니다")
    else:
        print("판정:", "✅ 통과 — 평문 0건, 좌표 0건" if ok else "❌ 남아 있음")

    if not ok:
        print("\n조치: 해당 계정으로 앱에 로그인하면 마이그레이션이 돌아 해소됩니다"
              "(rebackupAllContacts). 로그인하지 않는 계정은 서버에서 직접"
              " 정리해야 합니다 — backlog 추가 83 참고.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

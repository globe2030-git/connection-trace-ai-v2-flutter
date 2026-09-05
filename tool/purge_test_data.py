#!/usr/bin/env python3
"""서버(Firestore·Storage)의 **테스트 자료**를 세고, 승인이 있으면 지운다.

globe2030님 결정(2026-09-05): *"그동안 등록된 자료는 모두 테스트 자료야.
모두 지워도 되는거야."*

## 🚨 기본이 dry-run 이다

되돌릴 수 없는 조작이다. 규약 4-2 가 *"되돌릴 수 없는 조작(삭제·탈퇴·결제)은
자동 조작으로 하지 않는다"* 고 적어 두었다. **먼저 세어 보여 주고, 사람이 그
숫자를 본 뒤에 지운다.**

    python3 tool/purge_test_data.py                 # 세기만 한다 (기본)
    python3 tool/purge_test_data.py --delete        # 🔴 만 지운다
    python3 tool/purge_test_data.py --delete --with-audit   # 🟡 까지 지운다

## 안전을 「주의」가 아니라 「구조」로 둔다

- `KEEP` 에 있는 것은 **어떤 인자로도 안 지운다.** 코드가 먼저 막는다.
- 지울 대상은 `DELETE_ALWAYS`·`DELETE_IF_AUDIT` 에 **적힌 것만**이다.
  서버에 새 컬렉션이 생겨도 **저절로 지워지지 않는다** — 모르는 것은 안 건드린다.
- 지운 뒤 **다시 세어 0인지 확인**하고, 아니면 실패로 끝낸다.

무엇을 왜 이렇게 갈랐는지는
`docs/planning/server-test-data-purge-2026-09-05.md` 에 실측과 함께 있다.
"""
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from _firebase_admin import (  # noqa: E402
    BASE,
    PROJECT,
    access_token,
    get_json_or_none,
    post_json,
)

BUCKET = f"{PROJECT}.firebasestorage.app"

# 🚨 어떤 인자로도 안 지운다. 지우면 무슨 일이 나는지 함께 적는다.
KEEP = {
    "config": "config/testers 를 지우면 **테스터가 AI 기능을 못 쓴다**. billing 은 과금 스위치다",
    "legalDocs": "앱이 읽는 법적 문서(방침·약관·권한 안내·탈퇴 안내)",
    "notices": "운영 공지",
}

# 🔴 계정에 딸린 자료 — 계정을 지우면 함께 사라져야 하는 것들.
DELETE_ALWAYS = [
    "users",              # 하위(contacts·cardSources·deletedContacts…) 포함
    "ocrStats",
    "appleAuth",
    "socialTesterEmails",
    "referralCodes",
    "pilotEvents",
]

# 🟡 성격이 달라 따로 승인받는 것 — 기록·감사·사람이 쓴 것.
DELETE_IF_AUDIT = [
    "aiAuditLogs",
    "adminAuditLogs",
    "inquiries",
    "socialUnlinkRequests",
]


def doc_ids(path: str, token: str) -> list[str]:
    out, page = [], None
    while True:
        url = f"{BASE}/{path}?pageSize=300" + (f"&pageToken={page}" if page else "")
        data = get_json_or_none(url, token) or {}
        out += [d["name"].split("/")[-1] for d in data.get("documents", [])]
        page = data.get("nextPageToken")
        if not page:
            return out


def subcollections(doc_path: str, token: str) -> list[str]:
    r = post_json(f"{BASE}/{doc_path}:listCollectionIds", token, {"pageSize": 100})
    return r.get("collectionIds", [])


def delete_doc(path: str, token: str) -> None:
    req = urllib.request.Request(
        f"{BASE}/{path}", method="DELETE",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        urllib.request.urlopen(req, timeout=30).read()
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise


def delete_doc_tree(path: str, token: str) -> int:
    """문서와 그 아래 하위 컬렉션 전부. 🚨 Firestore 는 문서를 지워도
    하위 컬렉션을 안 지운다 — 이 저장소가 같은 함정에 세 번 걸렸다."""
    n = 0
    for sub in subcollections(path, token):
        for child in doc_ids(f"{path}/{sub}", token):
            n += delete_doc_tree(f"{path}/{sub}/{child}", token)
    delete_doc(path, token)
    return n + 1


def storage_objects(token: str, prefix: str = "users/") -> list[str]:
    url = (f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o"
           f"?prefix={prefix}&maxResults=1000")
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    return [o["name"] for o in json.load(urllib.request.urlopen(req, timeout=30)).get("items", [])]


def delete_storage_object(name: str, token: str) -> None:
    safe = urllib.parse.quote(name, safe="")
    req = urllib.request.Request(
        f"https://storage.googleapis.com/storage/v1/b/{BUCKET}/o/{safe}",
        method="DELETE", headers={"Authorization": f"Bearer {token}"},
    )
    try:
        urllib.request.urlopen(req, timeout=30).read()
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            raise


def survey(token: str, targets: list[str]) -> dict[str, int]:
    return {c: len(doc_ids(c, token)) for c in targets}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--delete", action="store_true", help="실제로 지운다(기본은 세기만)")
    ap.add_argument("--with-audit", action="store_true",
                    help="🟡 감사·문의까지 지운다")
    args = ap.parse_args()

    token = access_token()
    targets = list(DELETE_ALWAYS) + (DELETE_IF_AUDIT if args.with_audit else [])

    # 🚨 구조로 막는다 — 실수로 KEEP 이 목록에 들어가도 여기서 멈춘다.
    bad = [c for c in targets if c in KEEP]
    if bad:
        print(f"🚨 KEEP 에 있는 것이 대상에 들어 있다: {bad}")
        return 2

    present = post_json(f"{BASE}:listCollectionIds", token, {"pageSize": 300})
    present = set(present.get("collectionIds", []))

    before = survey(token, targets)
    photos = storage_objects(token)

    print(f"프로젝트 {PROJECT} · 서버 최상위 컬렉션 {len(present)}개\n")
    print("지울 것")
    for c, n in before.items():
        mark = "" if c in present else "   (서버에 없음)"
        print(f"  🔴 {c:<22} {n}{mark}")
    print(f"  🔴 {'Storage users/':<22} {len(photos)}  (객체)")
    print("\n남길 것 — 어떤 인자로도 안 지운다")
    for c, why in KEEP.items():
        print(f"  🟢 {c:<22} {why}")
    if not args.with_audit:
        print("\n🟡 따로 승인이 필요해 이번엔 안 지운다 (--with-audit)")
        for c in DELETE_IF_AUDIT:
            print(f"     {c:<22} {len(doc_ids(c, token))}")

    if not args.delete:
        print("\n📌 세기만 했다. 지우려면 --delete 를 붙인다.")
        return 0

    print("\n지우는 중…")
    for c in targets:
        for did in doc_ids(c, token):
            delete_doc_tree(f"{c}/{did}", token)
        print(f"  🔴 {c} 완료")
    for name in photos:
        delete_storage_object(name, token)
    print(f"  🔴 Storage {len(photos)}개 완료")

    after = survey(token, targets)
    left = {c: n for c, n in after.items() if n}
    photos_left = storage_objects(token)
    print("\n지운 뒤 다시 셈:")
    for c, n in after.items():
        print(f"  {'✅' if n == 0 else '🚨'} {c:<22} {n}")
    print(f"  {'✅' if not photos_left else '🚨'} {'Storage users/':<22} {len(photos_left)}")
    if left or photos_left:
        print("\n🚨 안 지워진 것이 있다. 위 숫자를 그대로 보고할 것.")
        return 1
    print("\n✅ 전부 0.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

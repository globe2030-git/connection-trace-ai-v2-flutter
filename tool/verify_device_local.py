#!/usr/bin/env python3
"""Android 기기에 저장된 내용이 의도대로인지 확인한다.

서버 점검(`verify_server_privacy.py`)과 짝이다. 설계 의도는 **좌표는 기기에만
있고 서버에는 없다**는 것인데, 한쪽만 봐서는 절반만 확인한 것이다. 이 도구가
기기 쪽을 맡는다.

확인하는 것:

1. **기기 저장분이 암호문인가** — `adb run-as`로 앱 내부 저장소를 열면 예전에는
   명함이 평문 JSON으로 그대로 읽혔다(backlog 추가 72에서 수정).
2. **좌표가 기기에 채워져 있는가** — 서버에서 복원한 뒤 주소로 재계산해
   채운다(추가 76). 재계산이 실패하면 그 명함은 주변 인맥 목록에서 조용히
   빠지는데, 화면만 봐서는 "근처에 없어서 안 보이는 것"과 구분되지 않는다.
   실제로 재시도가 복원 경로에서만 호출돼 죽어 있던 결함을 이 방법으로
   잡았다(추가 79).
3. **재계산 실패 기록** — 3회 실패하면 포기하므로, 남아 있으면 그 명함은
   영영 거리가 안 뜬다(P1-25).

**전제**: 기기가 `adb`로 연결돼 있고, **디버그 빌드가 설치돼 있어야 한다**
(`run-as`는 릴리스 빌드에서 동작하지 않는다). 릴리스 빌드로 테스트 중이라면
이 점검을 위해 디버그 빌드를 잠시 설치해야 한다.

**개인정보는 출력하지 않는다.** 주소·이름 같은 값 대신 "있는지 없는지"와
길이만 본다.

사용법:
    python3 tool/verify_device_local.py

종료 코드: 0 = 통과, 1 = 문제 있음, 2 = 실행 실패(기기 미연결 등)
"""
from __future__ import annotations

import html
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])

from _firebase_admin import (  # noqa: E402
    BASE,
    FirebaseAuthError,
    access_token,
    decrypt_payload,
    encryption_key,
    get_json_or_none,
)

PKG = "com.connectiontrace.connection_trace_ai_flutter"
PREFS = "shared_prefs/FlutterSharedPreferences.xml"
ADB = os.path.expanduser("~/Library/Android/sdk/platform-tools/adb")


def adb(*args: str) -> str:
    exe = ADB if os.path.exists(ADB) else "adb"
    return subprocess.run(
        [exe, *args], capture_output=True, text=True, timeout=60
    ).stdout


def pref(xml: str, name: str) -> str | None:
    """`shared_preferences` 값을 꺼낸다(모든 키에 `flutter.` 접두사가 붙는다)."""
    m = re.search(
        rf'<string\s+name="flutter\.{re.escape(name)}"\s*>(.*?)</string>', xml, re.S
    )
    return html.unescape(m.group(1)).strip() if m else None


def connected_devices() -> list[str]:
    """`adb devices` 출력에서 실제 기기 목록만 뽑는다.

    첫 줄이 "List of devices attached"라 단순히 'device' 문자열을 찾으면
    기기가 없어도 있다고 판단한다(실제로 그렇게 잘못 짰다가 잡았다).
    """
    lines = adb("devices").splitlines()[1:]
    return [
        line.split("\t")[0]
        for line in lines
        if line.strip() and line.split("\t")[-1].strip() == "device"
    ]


def main() -> int:
    devices = connected_devices()
    if not devices:
        print("❌ adb에 연결된 기기가 없습니다. USB로 연결하고 디버깅을 허용하세요.")
        return 2
    if len(devices) > 1:
        print(f"❌ 기기가 여러 대 연결돼 있습니다: {', '.join(devices)}")
        print("   한 대만 남기고 다시 실행하세요.")
        return 2

    xml = adb("shell", "run-as", PKG, "cat", PREFS)
    if not xml.lstrip().startswith("<?xml"):
        print("❌ 앱 내부 저장소를 읽지 못했습니다.")
        print("   `run-as`는 디버그 빌드에서만 동작합니다 — 릴리스 빌드가 설치돼 있으면")
        print("   `flutter build apk --debug`로 잠시 바꿔 설치한 뒤 다시 실행하세요.")
        return 2

    uid = pref(xml, "last_signed_in_uid_v1")
    raw = pref(xml, "saved_contacts_v2")
    attempts = pref(xml, "geo_backfill_attempts_v1")

    print(f"기기 점검 — package={PKG}\n")
    print(f"  로그인 계정 : {uid[:10] + '…' if uid else '없음(로그아웃 상태)'}")

    if not raw:
        print("  명함 저장분 : 없음")
        print("\n판정: ⚠️ 확인할 데이터가 없습니다. 로그인 후 명함을 등록하고 다시 실행하세요.")
        return 2

    if raw.lstrip().startswith("["):
        print("  명함 저장분 : ❌ **평문 JSON** — 암호화되지 않은 상태입니다")
        print("\n판정: ❌ 기기에 평문으로 저장돼 있습니다(backlog 추가 72 회귀).")
        return 1
    print(f"  명함 저장분 : ✅ 암호문 ({len(raw)}자)")

    if not uid:
        print("\n판정: ⚠️ 로그인 계정을 알 수 없어 복호화할 수 없습니다.")
        return 2

    try:
        token = access_token()
    except FirebaseAuthError as exc:
        print(f"\n❌ {exc}")
        return 2

    user_doc = get_json_or_none(f"{BASE}/users/{uid}", token)
    if user_doc is None:
        print(f"\n⚠️ 서버에 이 계정({uid[:10]}…)의 문서가 없습니다.")
        print("   계정이 삭제됐는데 기기에는 로그인 기록과 명함이 남아 있는 상태입니다.")
        print("   암호화 키가 없어 기기 저장분을 열 수 없습니다 — 앱에서 다시 로그인하거나")
        print("   앱 데이터를 지운 뒤 다시 실행하세요.")
        return 2

    key = encryption_key(user_doc)
    if key is None:
        print("\n❌ 서버에 이 계정의 암호화 키가 없어 복호화할 수 없습니다.")
        return 2

    try:
        contacts = decrypt_payload(raw, key)["contacts"]
    except Exception as exc:  # noqa: BLE001
        print(f"\n❌ 복호화 실패: {type(exc).__name__}")
        return 2

    print(f"\n=== 기기에 저장된 명함 {len(contacts)}건 ===")
    missing = []
    for c in contacts:
        addr = (c.get("address") or "").strip()
        has_geo = c.get("lat") is not None and c.get("lng") is not None
        if addr and not has_geo:
            missing.append(c["id"])
        print(f"  {c['id']:16} 주소={'있음' if addr else '없음':4} "
              f"좌표={'✅ 있음' if has_geo else '❌ 없음'}")

    print("\n=== 좌표 재계산 실패 기록 ===")
    if attempts:
        for cid, rec in json.loads(attempts).items():
            print(f"  {cid:16} 실패 {rec.get('n')}회"
                  + ("  ← 3회면 포기 상태(P1-25)" if rec.get("n", 0) >= 3 else ""))
    else:
        print("  (없음 — 전부 성공)")

    print("\n" + "─" * 56)
    if missing:
        print(f"판정: ⚠️ 주소는 있는데 좌표가 없는 명함 {len(missing)}건 — "
              "주변 인맥 목록에서 빠집니다.")
        print("      앱을 다시 켜면 재시도합니다. 계속 남으면 지오코딩 영구 실패이거나")
        print("      backfill 호출 경로가 끊긴 것입니다(backlog 추가 79 유형).")
        return 1
    print("판정: ✅ 통과 — 기기 저장분은 암호문이고, 주소가 있는 명함에 좌표가 모두 있습니다")
    print("      서버 쪽은 tool/verify_server_privacy.py로 함께 확인하세요.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

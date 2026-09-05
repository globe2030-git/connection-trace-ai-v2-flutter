#!/usr/bin/env python3
"""pubspec.lock 의 SDK 핀이 지금 쓰는 Flutter 와 맞는지 본다.

🚨 왜 있나 — 2026-09-05 에 실제로 난 일이다.

PR #820 이 **3.44.8 이 아닌 Flutter** 로 `pub get` 한 결과를 커밋해 넣었다.
그 뒤로 맥에서 작업하는 세션마다 `pubspec.lock` 에 8줄이 떴고, **세 세션이
각자 다른 원인을 짚었다** — 「빌드 부산물이다」 · 「맥이라 구조적으로 그렇다」 ·
「채널이 달라서다」. 셋 다 틀렸고 답은 `git log -1 -- pubspec.lock` 한 줄이었다.

⚠️ **CI 는 그동안 계속 통과했다.** `flutter pub get` 이 SDK 핀 패키지를 자기
것으로 덮으므로 CI 는 lock 이 뭐라고 적혀 있든 자기 값으로 돈다. 그래서
**어긋난 채로 두 주를 갈 수도 있었다.**

📌 그런데 그 「덮는다」에 기대는 검사는 안 된다. 실제로 재 봤더니
**`flutter pub get` 도 `flutter test` 도 로컬에서는 lock 을 안 고쳤다**(md5 로
확인). lock 이 제약을 만족하면 pub 이 굳이 안 바꾸기 때문이다. 그래서
`pub get` 뒤에 `git diff --exit-code pubspec.lock` 을 두는 방식은
**잡을 때도 있고 못 잡을 때도 있다.**

⭐ 그래서 이 스크립트는 **pub 을 거치지 않는다.** SDK 가 소스에 적어 둔 핀을
직접 읽어 lock 과 견준다. 환경·캐시·순서에 안 흔들린다.

쓰는 법:
    python3 tool/check_lock_sdk_pins.py            # 지금 flutter 로 검사
    python3 tool/check_lock_sdk_pins.py --list     # 핀 값만 보여준다

Flutter SDK 는 `which flutter` 로 찾는다. `FLUTTER_ROOT` 가 있으면 그것을 쓴다.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# SDK 가 핀으로 박는 패키지들. 여기 적힌 것만 검사한다.
#
# ⚠️ 목록을 늘릴 때는 **SDK 소스에 고정 버전으로 적혀 있는 것**만 넣는다.
# 캐럿(`^1.2.3`)이나 `any` 로 적힌 것은 lock 값이 SDK 와 달라도 정상이다.
PINNED = ("matcher", "meta", "test_api", "vector_math")

# SDK 안에서 핀이 적혀 있는 파일들. 여러 곳에 흩어져 있다.
PIN_FILES = (
    "packages/flutter/pubspec.yaml",
    "packages/flutter_test/pubspec.yaml",
)


def flutter_root() -> Path:
    """Flutter SDK 루트를 찾는다."""
    env = os.environ.get("FLUTTER_ROOT")
    if env:
        return Path(env)
    exe = shutil.which("flutter")
    if not exe:
        sys.exit("flutter 를 PATH 에서 못 찾았다. FLUTTER_ROOT 를 지정하라.")
    # <root>/bin/flutter → <root>
    return Path(os.path.realpath(exe)).parent.parent


def sdk_pins(root: Path) -> dict[str, str]:
    """SDK 소스에서 고정 버전으로 적힌 핀을 읽는다."""
    pins: dict[str, str] = {}
    for rel in PIN_FILES:
        path = root / rel
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\s+([a-z_0-9]+):\s*([0-9]+\.[0-9]+\.[0-9]+[^\s#]*)\s*$", line)
            if m and m.group(1) in PINNED:
                pins[m.group(1)] = m.group(2)
    return pins


def lock_versions(lock: Path) -> dict[str, str]:
    """pubspec.lock 에서 패키지별 version 을 읽는다."""
    out: dict[str, str] = {}
    name: str | None = None
    for line in lock.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^  ([a-z_0-9]+):\s*$", line)
        if m:
            name = m.group(1)
            continue
        if name:
            v = re.match(r'^    version:\s*"?([^"]+)"?\s*$', line)
            if v:
                out[name] = v.group(1)
                name = None
    return out


def git_last_touch(lock: Path) -> str:
    """lock 을 마지막으로 만진 커밋 — 어긋났을 때 어디서 왔는지 바로 보이게."""
    try:
        r = subprocess.run(
            ["git", "log", "-1", "--format=%h %ad %s", "--date=short", "--", str(lock)],
            capture_output=True, text=True, timeout=10, cwd=lock.parent,
        )
        return r.stdout.strip() or "(모름)"
    except Exception:
        return "(모름)"


def main() -> int:
    repo = Path(__file__).resolve().parent.parent
    lock = repo / "pubspec.lock"
    if not lock.exists():
        sys.exit(f"pubspec.lock 이 없다: {lock}")

    root = flutter_root()
    pins = sdk_pins(root)
    if not pins:
        sys.exit(f"SDK 에서 핀을 못 읽었다: {root}\n{PIN_FILES} 를 확인하라.")

    locked = lock_versions(lock)

    if "--list" in sys.argv:
        print(f"Flutter SDK: {root}")
        for k in sorted(pins):
            print(f"  {k:<12} SDK {pins[k]:<10} lock {locked.get(k, '(없음)')}")
        return 0

    bad = [(k, pins[k], locked.get(k)) for k in sorted(pins) if locked.get(k) != pins[k]]

    if not bad:
        print(f"✅ pubspec.lock 의 SDK 핀 {len(pins)}개가 지금 Flutter 와 맞다.")
        return 0

    print("🚨 pubspec.lock 이 지금 쓰는 Flutter 와 맞지 않는다.\n")
    print(f"   Flutter SDK  {root}")
    print(f"   lock 최종 변경  {git_last_touch(lock)}\n")
    for name, want, have in bad:
        print(f"   {name:<12} SDK 는 {want:<10} lock 은 {have}")
    print()
    print("   ⚠️ 다른 버전의 Flutter 로 `pub get` 한 결과가 커밋된 것으로 보인다.")
    print("   고치는 법: 위 SDK 로 `flutter pub get` 을 돌리고 그 lock 을 커밋한다.")
    print("   또는 어긋나기 직전 커밋에서 되돌린다:")
    print("       git log --format='%h %ad %s' --date=short -- pubspec.lock")
    print("       git checkout <그 커밋>^ -- pubspec.lock")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

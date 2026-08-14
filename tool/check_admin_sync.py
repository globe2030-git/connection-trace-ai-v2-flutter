#!/usr/bin/env python3
"""관리자 이메일 목록 동기화 검사 (2026-08-14, ADMIN-VULN-001 인터림 조치).

왜 필요한가: `firestore.rules`의 `isAdmin()`과 `functions/src/index.ts`(현재는
`functions/src/adminEmails.ts`)가 관리자 이메일을 각자 따로 갖고 있었다.
Rules에서만 관리자를 지워도 `getUserUsage`·`grantBonusCredits` Cloud
Functions는 Admin SDK로 직접 접근하므로 그 계정이 계속 관리자 권한을 쓸 수
있었다(ADMIN-VULN-001). 진짜 단일 원본(`config/admins` Firestore 문서 +
Rules `get()`)은 운영 Firestore에 그 문서가 실제로 있어야 검증 가능해 이번
세션에서 재현할 수 없었다 — 그래서 "공유 상수 + 자동 동기화 검사"로 드리프트
(두 목록이 벌어지는 것)만 잡는 인터림 조치를 대신 넣는다.

**순수 로컬 파일 비교다.** 운영 Firestore나 `firebase login`에 의존하지
않는다 — 소스 파일들(현재는 `firestore.rules`, `functions/src/adminEmails.ts`)을
읽어 정규식으로 이메일 배열을 뽑아 집합으로 비교할 뿐이다.

실행: python3 tool/check_admin_sync.py
자체 테스트(가짜 불일치 케이스로 이 스크립트 자체를 검증): python3 tool/check_admin_sync.py --selftest

⚠️ CI 반영 여부: 이 스크립트는 운영 인프라·인증에 의존하지 않으므로
`.github/workflows/ci.yml`에 추가하는 것을 권장한다. 실제로 추가했는지는
그 워크플로 파일의 주석을 확인할 것.
"""
import argparse
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
RULES_PATH = os.path.join(ROOT, "firestore.rules")
ADMIN_EMAILS_TS_PATH = os.path.join(ROOT, "functions", "src", "adminEmails.ts")


def extract_rules_admin_emails(rules_text: str) -> set[str]:
    """firestore.rules의 isAdmin() 안 `token.email in [...]` 배열에서
    작은따옴표 문자열만 뽑는다. 주석에는 따옴표가 없다는 전제(현재 파일
    실제 상태)라 별도 주석 제거 없이도 안전하다."""
    m = re.search(r"token\.email\s+in\s*\[(.*?)\]", rules_text, re.DOTALL)
    if not m:
        raise ValueError(
            "firestore.rules에서 isAdmin()의 이메일 배열(token.email in [...])을 "
            "찾지 못했습니다 — 정규식이 실제 문법과 어긋났을 수 있습니다."
        )
    return set(re.findall(r"'([^']+)'", m.group(1)))


def extract_ts_admin_emails(ts_text: str) -> set[str]:
    """adminEmails.ts의 `ADMIN_EMAILS = [...]` 배열에서 큰따옴표 문자열만
    뽑는다."""
    m = re.search(r"ADMIN_EMAILS\s*=\s*\[(.*?)\]", ts_text, re.DOTALL)
    if not m:
        raise ValueError(
            "functions/src/adminEmails.ts에서 ADMIN_EMAILS 배열을 찾지 "
            "못했습니다 — export 이름이나 문법이 바뀌었을 수 있습니다."
        )
    return set(re.findall(r'"([^"]+)"', m.group(1)))


# 관리자 이메일 소스 목록. 여기 등록된 소스가 몇 개든 compare_all()이 동일한
# 방식으로 전부 비교한다. 3번째 소스(예: 앱의
# `lib/data/repositories/auth_repository.dart` 관리자 목록, PR #144 반영 후)가
# 생기면 이 리스트에 `{"name", "path", "extract"}` 항목 하나만 추가하면 된다.
SOURCES = [
    {
        "name": "firestore.rules",
        "path": RULES_PATH,
        "extract": extract_rules_admin_emails,
    },
    {
        "name": "functions/src/adminEmails.ts",
        "path": ADMIN_EMAILS_TS_PATH,
        "extract": extract_ts_admin_emails,
    },
]


def compare_all(source_emails: dict[str, set[str]]) -> tuple[bool, str]:
    """소스 개수에 상관없이 동작하는 비교. 모든 소스 이메일의 합집합을
    기준으로, 각 소스가 그 합집합과 정확히 같은지 확인한다. 다르면 어느
    소스에 무엇이 빠져 있는지 소스 이름과 함께 알려준다."""
    if not source_emails:
        return True, "비교할 소스가 없습니다."

    union: set[str] = set()
    for emails in source_emails.values():
        union |= emails

    missing_by_source = {
        name: sorted(union - emails)
        for name, emails in source_emails.items()
        if emails != union
    }

    if not missing_by_source:
        return True, f"일치합니다 ({len(union)}개): {sorted(union)}"

    lines = ["불일치합니다."]
    for name, missing in missing_by_source.items():
        lines.append(f"  {name}에 없음(다른 소스엔 있음): {missing}")
    return False, "\n".join(lines)


def run_selftest() -> int:
    """이 스크립트 자체를 검증한다 — 가짜 일치/불일치 케이스를 스크립트
    안에 내장해 실제 파일을 건드리지 않고 회귀를 잡는다. compare_all()이
    제네릭 구조라는 것을 증명하는 게 목적이라, 여기서도 여전히 소스 2개로
    검증한다(3개 이상에서도 동일한 로직이 동작한다)."""
    ok = True

    # 1) 일치 케이스 — 통과해야 한다.
    rules_ok = """
    function isAdmin() {
      return request.auth != null &&
        request.auth.token.email_verified == true &&
        request.auth.token.email in [
          'a@example.com',
          'b@example.com'
        ];
    }
    """
    ts_ok = """
    export const ADMIN_EMAILS = [
      "a@example.com",
      "b@example.com",
    ];
    """
    passed, msg = compare_all(
        {
            "firestore.rules(가짜)": extract_rules_admin_emails(rules_ok),
            "adminEmails.ts(가짜)": extract_ts_admin_emails(ts_ok),
        }
    )
    print(f"[selftest] 일치 케이스 → {'✅ PASS' if passed else '❌ FAIL'} ({msg})")
    if not passed:
        ok = False

    # 2) 불일치 케이스 — 실패로 잡아내야 한다(스크립트가 실패를 감지 못하면
    #    이 selftest 자체가 실패로 보고된다).
    rules_mismatch = """
    function isAdmin() {
      return request.auth.token.email in [
        'a@example.com',
        'c@example.com'
      ];
    }
    """
    ts_mismatch = """
    export const ADMIN_EMAILS = [
      "a@example.com",
      "b@example.com",
    ];
    """
    passed, msg = compare_all(
        {
            "firestore.rules(가짜)": extract_rules_admin_emails(rules_mismatch),
            "adminEmails.ts(가짜)": extract_ts_admin_emails(ts_mismatch),
        }
    )
    detected = not passed  # 불일치를 "감지"했어야 selftest가 성공
    print(f"[selftest] 불일치 케이스 → {'✅ PASS(감지함)' if detected else '❌ FAIL(못 잡음)'}")
    if not detected:
        ok = False
    else:
        print(f"           {msg}")

    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="실제 파일 대신 내장된 가짜 불일치 케이스로 스크립트 자체를 검증",
    )
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    source_emails: dict[str, set[str]] = {}
    for source in SOURCES:
        name, path, extract = source["name"], source["path"], source["extract"]
        try:
            text = open(path, encoding="utf-8").read()
        except OSError as e:
            print(f"[{name}] 파일을 읽지 못했습니다: {e}")
            return 2
        try:
            source_emails[name] = extract(text)
        except ValueError as e:
            print(f"[{name}] 파싱 실패: {e}")
            return 2

    passed, msg = compare_all(source_emails)
    print(msg)
    if not passed:
        source_names = ", ".join(s["name"] for s in SOURCES)
        print(f"\n관리자를 추가/제거했다면 다음 소스를 모두 고치세요: {source_names}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())

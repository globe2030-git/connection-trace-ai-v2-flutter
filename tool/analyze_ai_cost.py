#!/usr/bin/env python3
"""AI 호출 1회당 실제 원가를 `aiAuditLogs`에서 집계한다.

**왜 필요한가**(`docs/planning/beta-observability-plan.md` 2절): 지금 충전
티어 회차(1,000원=10회 … 100,000원=1,000회)는 **1,000원당 10회 비례
잠정치**다. 실제 Gemini 원가를 몰라 정한 숫자라, 베타 테스터 실사용
데이터로 원가를 실측해야 손익이 맞는지 확인할 수 있다. 이 스크립트는 그
실측을 위한 도구다 — 표본이 차는 순간 바로 돌릴 수 있도록 미리 만든다.

**원가 공식**(계획 문서 2-2절, `functions/src/index.ts` 주석 — Gemini
`gemini-3.6-flash`, `THINKING_LEVEL="MINIMAL"` 고정):

    원가(USD) = (promptTokenCount * 1.50
                 + (candidatesTokenCount + thoughtsTokenCount) * 7.50)
                / 1,000,000
    원가(KRW) = 원가(USD) * 환율

입력 $1.50/1M 토큰, 출력+사고 토큰 $7.50/1M 토큰(사고 토큰이 출력과 동일
단가로 과금되는 것이 확인된 사실). `totalTokenCount`는 세 필드의 합이라
이중 계산 방지용 검증에만 쓰고, 원가 계산에는 세부 필드를 직접 쓴다(입력/
출력 단가가 다르기 때문). 단가·환율이 바뀌면 아래 상수만 고치면 된다.

**표본 요건**(계획 문서 2-3절) — 아래 세 조건을 **모두** 만족해야
"계산 가능"으로 판단한다(먼저 도달하는 게 아니라 전부 충족):

1. 성공 호출(`ok=true`) 150건 이상
2. 참여 uid(distinct) 5명 이상
3. 관측 기간(첫 성공 호출 ~ 마지막 성공 호출) 영업일 기준 7일 이상

**개인정보 원칙**(CLAUDE.md, 계획 문서 2-4절): 출력에 **email은 절대
넣지 않는다** — uid만 쓴다(집계에 이메일이 필요 없다). distinct uid는
**개수만** 세고, uid 목록 자체는 출력하지 않는다(재시도 신호 절에서만
앞 8자로 부분 마스킹해 "어떤 사례인지" 식별 가능한 최소 정보만 남긴다).
`aiAuditLogs`에는 원래 명함·프롬프트 원문이 없지만, 혹시 예상 못 한
필드가 있어도 이 스크립트는 정해진 필드만 읽고 출력한다.

기존 패턴 재사용: `tool/verify_server_privacy.py`와 같은 방식으로
Firebase CLI 리프레시 토큰 → 액세스 토큰 교환 → Firestore REST 관리자
조회(`_firebase_admin.py`)를 쓴다.

사용법:
    python3 tool/analyze_ai_cost.py                              # 최근 14일(KST)
    python3 tool/analyze_ai_cost.py --from 2026-08-01 --to 2026-08-10
    python3 tool/analyze_ai_cost.py --exchange-rate 1400          # 환율 변경

종료 코드: 0 = 표본 요건 충족(계산 가능), 1 = 미충족(정보성 — 문제가
아니라 "아직 더 모아야 함"이라는 뜻), 2 = 실행 실패(인증 실패 등)
"""
from __future__ import annotations

import argparse
import math
import statistics
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone

sys.path.insert(0, __file__.rsplit("/", 1)[0])

from _firebase_admin import (  # noqa: E402
    BASE,
    FirebaseAuthError,
    PROJECT,
    access_token,
    post_json,
)

# --- 원가 상수 (출처: docs/planning/beta-observability-plan.md 2-2절,
# functions/src/index.ts 주석 — gemini-3.6-flash, THINKING_LEVEL=MINIMAL) ---
USD_PER_1M_PROMPT_TOKENS = 1.50
USD_PER_1M_OUTPUT_TOKENS = 7.50  # candidates + thoughts, 동일 단가
DEFAULT_EXCHANGE_RATE = 1430.0  # pnl 문서 기준 ₩1,430/$

# --- 표본 요건 (2-3절) ---
MIN_SUCCESS_CALLS = 150
MIN_DISTINCT_UIDS = 5
MIN_BUSINESS_DAYS = 7

# 재시도 의심 신호(1절 표 근사 정의): 같은 uid가 실패 직후 이 시간 안에
# 다시 호출하면 "재시도"로 본다. 서버가 어떤 명함/요청인지 남기지 않으므로
# 정확한 인과관계는 알 수 없는 근사치다.
RETRY_WINDOW_MINUTES = 5

KST = timezone(timedelta(hours=9))  # 한국은 DST가 없어 고정 오프셋으로 충분
COLLECTION = "aiAuditLogs"
# 한 번에 조회하는 최대 건수. 베타 규모(테스터 10명대)에서는 충분히 크지만,
# 기존 도구들(list_users pageSize=100 등)과 같은 "필요 이상으로 복잡한
# 페이지네이션을 만들지 않는다" 관례를 따른다 — 이 값에 닿으면 잘렸을 수
# 있다고 경고만 한다.
QUERY_LIMIT = 20000


def parse_date(s: str) -> date:
    return date.fromisoformat(s)


def kst_midnight_to_utc(d: date) -> datetime:
    return datetime(d.year, d.month, d.day, tzinfo=KST).astimezone(timezone.utc)


def parse_firestore_timestamp(s: str) -> datetime:
    """"2026-08-12T03:04:05.123456789Z" 형태를 UTC datetime으로 바꾼다."""
    s = s.rstrip("Z")
    if "." in s:
        main, frac = s.split(".")
        frac = (frac + "000000")[:6]
        s = f"{main}.{frac}"
    return datetime.fromisoformat(s).replace(tzinfo=timezone.utc)


def field_value(fields: dict, name: str):
    v = fields.get(name)
    if v is None or "nullValue" in v:
        return None
    if "integerValue" in v:
        return int(v["integerValue"])
    if "doubleValue" in v:
        return float(v["doubleValue"])
    if "stringValue" in v:
        return v["stringValue"]
    if "booleanValue" in v:
        return v["booleanValue"]
    if "timestampValue" in v:
        return v["timestampValue"]
    return None


def fetch_logs(token: str, from_utc: datetime, to_utc_exclusive: datetime) -> tuple[list[dict], bool]:
    """기간 내 aiAuditLogs를 전량 조회해 파싱된 레코드 목록을 돌려준다.

    두 번째 반환값은 "잘렸을 가능성"(QUERY_LIMIT에 정확히 닿았는지).
    """
    body = {
        "structuredQuery": {
            "from": [{"collectionId": COLLECTION}],
            "where": {
                "compositeFilter": {
                    "op": "AND",
                    "filters": [
                        {
                            "fieldFilter": {
                                "field": {"fieldPath": "at"},
                                "op": "GREATER_THAN_OR_EQUAL",
                                "value": {"timestampValue": from_utc.isoformat().replace("+00:00", "Z")},
                            }
                        },
                        {
                            "fieldFilter": {
                                "field": {"fieldPath": "at"},
                                "op": "LESS_THAN",
                                "value": {"timestampValue": to_utc_exclusive.isoformat().replace("+00:00", "Z")},
                            }
                        },
                    ],
                }
            },
            "orderBy": [{"field": {"fieldPath": "at"}, "direction": "ASCENDING"}],
            "limit": QUERY_LIMIT,
        }
    }
    result = post_json(f"{BASE}:runQuery", token, body)

    records = []
    for entry in result:
        doc = entry.get("document")
        if not doc:
            continue  # 결과 없음을 나타내는 빈 항목(readTime만 있음)
        fields = doc.get("fields", {})
        at_raw = field_value(fields, "at")
        if at_raw is None:
            continue
        records.append(
            {
                "uid": field_value(fields, "uid"),
                "ok": bool(field_value(fields, "ok")),
                "errorCode": field_value(fields, "errorCode"),
                "prompt": field_value(fields, "promptTokenCount"),
                "candidates": field_value(fields, "candidatesTokenCount"),
                "thoughts": field_value(fields, "thoughtsTokenCount"),
                "total": field_value(fields, "totalTokenCount"),
                "at": parse_firestore_timestamp(at_raw),
            }
        )
    truncated = len(records) >= QUERY_LIMIT
    return records, truncated


def cost_krw(prompt: int, candidates: int, thoughts: int, exchange_rate: float) -> float:
    usd = (
        prompt * USD_PER_1M_PROMPT_TOKENS
        + (candidates + thoughts) * USD_PER_1M_OUTPUT_TOKENS
    ) / 1_000_000
    return usd * exchange_rate


def percentile(sorted_vals: list[float], pct: float) -> float:
    """선형 보간 방식 백분위수(numpy 기본 방식과 동일). numpy 없이 계산."""
    if not sorted_vals:
        return 0.0
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    k = (len(sorted_vals) - 1) * (pct / 100)
    f, c = math.floor(k), math.ceil(k)
    if f == c:
        return sorted_vals[int(k)]
    return sorted_vals[f] * (c - k) + sorted_vals[c] * (k - f)


def count_business_days(start: date, end: date) -> int:
    if end < start:
        return 0
    days = (end - start).days + 1
    return sum(
        1 for i in range(days) if (start + timedelta(days=i)).weekday() < 5
    )


def krw(v: float) -> str:
    return f"₩{v:,.2f}"


def main() -> int:
    parser = argparse.ArgumentParser(description="aiAuditLogs로 AI 호출 1회당 실제 원가를 집계한다")
    parser.add_argument("--from", dest="from_date", type=parse_date, help="조회 시작일(KST, YYYY-MM-DD). 기본값: 오늘-13일")
    parser.add_argument("--to", dest="to_date", type=parse_date, help="조회 종료일(KST, YYYY-MM-DD, 포함). 기본값: 오늘")
    parser.add_argument("--exchange-rate", type=float, default=DEFAULT_EXCHANGE_RATE, help=f"USD→KRW 환율(기본값 {DEFAULT_EXCHANGE_RATE:g}, pnl 문서 기준)")
    args = parser.parse_args()

    today_kst = datetime.now(KST).date()
    to_date = args.to_date or today_kst
    from_date = args.from_date or (to_date - timedelta(days=13))
    if from_date > to_date:
        print("❌ --from이 --to보다 뒤입니다.")
        return 2

    try:
        token = access_token()
    except FirebaseAuthError as exc:
        print(f"❌ {exc}")
        return 2

    from_utc = kst_midnight_to_utc(from_date)
    to_utc_exclusive = kst_midnight_to_utc(to_date + timedelta(days=1))

    print(f"=== AI 호출 원가 분석 — project={PROJECT} ===")
    print(f"조회 기간: {from_date.isoformat()} ~ {to_date.isoformat()} (KST, {(to_date - from_date).days + 1}일)")
    print(f"환율: 1 USD = {args.exchange_rate:,.0f} KRW"
          + ("" if args.exchange_rate == DEFAULT_EXCHANGE_RATE else " (기본값 아님, 인자로 지정됨)"))
    print()

    try:
        records, truncated = fetch_logs(token, from_utc, to_utc_exclusive)
    except Exception as exc:  # noqa: BLE001
        print(f"❌ Firestore 조회 실패: {type(exc).__name__}: {exc}")
        return 2

    if truncated:
        print(f"⚠️ 이번 조회가 상한({QUERY_LIMIT}건)에 닿았습니다 — 기간을 좁혀서 다시 확인하세요.\n")

    if not records:
        print("아직 데이터 없음 — 이 기간에 aiAuditLogs 로그가 없습니다.")
        print("표본 요건(성공 150건↑ / uid 5명↑ / 영업일 7일↑)을 채울 때까지 기다리거나,")
        print("--from/--to로 더 넓은 기간을 지정해 보세요.")
        return 1

    total = len(records)
    successes = [r for r in records if r["ok"]]
    failures = [r for r in records if not r["ok"]]
    all_uids = {r["uid"] for r in records if r["uid"]}
    success_uids = {r["uid"] for r in successes if r["uid"]}

    print("[전체 집계]")
    print(f"  총 로그 건수:                 {total}건")
    print(f"  성공(ok=true):                {len(successes)}건 ({len(successes) / total * 100:.1f}%)")
    print(f"  실패:                         {len(failures)}건")
    print(f"  참여 uid(성공 기준, distinct): {len(success_uids)}명")
    print(f"  참여 uid(전체, distinct):      {len(all_uids)}명")
    print()

    # --- 원가 계산: 성공 호출 중 토큰 정보가 있는 건만 ---
    costed = []
    integrity_mismatch = 0
    for r in successes:
        p, c, t, tot = r["prompt"], r["candidates"], r["thoughts"], r["total"]
        if p is None and c is None and t is None:
            continue
        p, c, t = p or 0, c or 0, t or 0
        if tot is not None and tot != p + c + t:
            integrity_mismatch += 1
        costed.append(cost_krw(p, c, t, args.exchange_rate))

    print("[원가(KRW) — 성공 호출 기준, 토큰 정보 있는 건만]")
    skipped = len(successes) - len(costed)
    print(f"  집계 대상: {len(costed)}건"
          + (f" (성공 {len(successes)}건 중 토큰 정보 없음 {skipped}건 제외)" if skipped else ""))
    if costed:
        costed_sorted = sorted(costed)
        print(f"  평균:     {krw(statistics.mean(costed))}")
        print(f"  중앙값:   {krw(statistics.median(costed))}")
        print(f"  P90:      {krw(percentile(costed_sorted, 90))}  ← 평균만 보면 가려지는 값(사고 토큰이 튄 소수 사용자)")
        print(f"  최댓값:   {krw(max(costed))}")
    else:
        print("  (원가를 계산할 성공 호출이 없습니다)")
    if integrity_mismatch:
        print(f"  ⚠️ totalTokenCount 불일치 {integrity_mismatch}건 — 세부 토큰 필드 합과 다릅니다(원가 계산에는 영향 없음, 데이터 이상 신호)")
    print()

    # --- 일별 추이 (KST 날짜 기준) ---
    by_day = defaultdict(lambda: {"total": 0, "success": 0, "costs": []})
    for r in records:
        d = r["at"].astimezone(KST).date()
        by_day[d]["total"] += 1
        if r["ok"]:
            by_day[d]["success"] += 1
    # costed 리스트는 skip(토큰 정보 없음)이 있어 순서만으로 날짜와 매칭할
    # 수 없으므로, 날짜별 원가는 성공 호출을 다시 순회해 따로 계산한다.
    for r in successes:
        p, c, t = r["prompt"], r["candidates"], r["thoughts"]
        if p is None and c is None and t is None:
            continue
        d = r["at"].astimezone(KST).date()
        by_day[d]["costs"].append(cost_krw(p or 0, c or 0, t or 0, args.exchange_rate))

    print("[일별 추이 (KST 기준)]")
    print(f"  {'날짜':<12}{'호출':>6}{'성공':>6}{'평균원가(KRW)':>16}{'합계원가(KRW)':>16}")
    for d in sorted(by_day):
        info = by_day[d]
        avg = statistics.mean(info["costs"]) if info["costs"] else 0.0
        tot = sum(info["costs"])
        print(f"  {d.isoformat():<12}{info['total']:>6}{info['success']:>6}{avg:>16,.2f}{tot:>16,.2f}")
    print()

    # --- 재시도 의심 신호 ---
    by_uid = defaultdict(list)
    for r in records:
        if r["uid"]:
            by_uid[r["uid"]].append(r)
    retry_cases = []
    for uid, recs in by_uid.items():
        recs.sort(key=lambda r: r["at"])
        for prev, curr in zip(recs, recs[1:]):
            if not prev["ok"] and (curr["at"] - prev["at"]) <= timedelta(minutes=RETRY_WINDOW_MINUTES):
                retry_cases.append((uid, prev["errorCode"]))

    print("[사고 토큰 재시도 의심 신호]")
    print(f"  같은 uid가 실패 직후 {RETRY_WINDOW_MINUTES}분 이내 재호출한 사례: {len(retry_cases)}건")
    if retry_cases:
        masked = ", ".join(sorted({f"{uid[:8]}…({err or '?'})" for uid, err in retry_cases}))
        print(f"  관련 uid(앞 8자만) / 직전 실패 사유: {masked}")
    print("  (서버 로그에 어떤 명함·요청인지는 없어 정확한 인과관계는 알 수 없는 근사치)")
    print()

    # --- 표본 요건 판정 ---
    success_count = len(successes)
    uid_count = len(success_uids)
    if successes:
        span_start = min(r["at"] for r in successes).astimezone(KST).date()
        span_end = max(r["at"] for r in successes).astimezone(KST).date()
        business_days = count_business_days(span_start, span_end)
    else:
        span_start = span_end = None
        business_days = 0

    ok_success = success_count >= MIN_SUCCESS_CALLS
    ok_uid = uid_count >= MIN_DISTINCT_UIDS
    ok_days = business_days >= MIN_BUSINESS_DAYS

    print("[표본 요건 판정 — beta-observability-plan.md 2-3절]")
    print(f"  {'✅' if ok_success else '❌'} 성공 호출 {MIN_SUCCESS_CALLS}건 이상       → {success_count}건"
          + ("" if ok_success else f" (부족 {MIN_SUCCESS_CALLS - success_count}건)"))
    print(f"  {'✅' if ok_uid else '❌'} 참여 uid {MIN_DISTINCT_UIDS}명 이상          → {uid_count}명"
          + ("" if ok_uid else f" (부족 {MIN_DISTINCT_UIDS - uid_count}명)"))
    span_desc = f"{span_start.isoformat()} ~ {span_end.isoformat()}" if span_start else "-"
    print(f"  {'✅' if ok_days else '❌'} 관측 기간 영업일 {MIN_BUSINESS_DAYS}일 이상  → {business_days}일 ({span_desc})"
          + ("" if ok_days else f" (부족 {MIN_BUSINESS_DAYS - business_days}일)"))
    print()

    all_ok = ok_success and ok_uid and ok_days
    if all_ok:
        print("판정: ✅ 계산 가능 — 세 조건을 모두 충족했습니다. 위 원가 통계를 실측치로 검토하세요.")
    else:
        missing = []
        if not ok_success:
            missing.append(f"성공 호출 {MIN_SUCCESS_CALLS - success_count}건")
        if not ok_uid:
            missing.append(f"참여 uid {MIN_DISTINCT_UIDS - uid_count}명")
        if not ok_days:
            missing.append(f"영업일 {MIN_BUSINESS_DAYS - business_days}일")
        print("판정: ❌ 아직 계산 불가 — " + ", ".join(missing) + " 부족")
        print("(세 조건을 모두 충족해야 '계산 가능'입니다. 급하게 필요하면 '미달 상태에서의")
        print(" 잠정 재확인'이라고 명시하고 지금 표본으로 계산하는 것도 절차상 허용됩니다 — 2-3절)")

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())

/**
 * 파일럿(베타) 계측 — 활성화 판정 + 가입 주차 코호트 계산의 순수 로직만
 * 떼어낸 파일. index.ts는 이 함수들만 호출하고 Firestore 트랜잭션·읽기/쓰기는
 * index.ts에 남아 있다(freeGrant.ts/walletCredits.ts와 같은 이유 — 순수
 * 함수여야 유닛테스트할 수 있다).
 *
 * 배경: docs/planning/beta-observability-plan.md, 세션 작업 지시서
 * (2026-08-15, 파일럿 계측 단위 작업). 개인정보 원칙(CLAUDE.md 4절)에 따라
 * 여기서 다루는 값은 전부 숫자·플래그·주차 라벨뿐이고 이름·전화번호·이메일·
 * 대화 포인트 원문은 절대 다루지 않는다.
 */

import {toKstFields} from "./usageReset";

/**
 * 활성화 판정 최소 명함 수(명함 3장 + AI 1회 사용).
 *
 * ⚠️ U2의 리퍼럴 활성화 조건("명함 1장 + AI 1회", 아직 미구현)과는 **다른,
 * 완전히 독립된 지표**다 — 값도 다르고(1 vs 3) 판정 지점·저장 위치도 다르다.
 * 혼동해서 하나로 합치지 말 것(작업 지시서 명시).
 */
export const ACTIVATION_MIN_CONTACTS = 3;

export interface ActivationPlanInput {
  /** users/{uid}.pilotActivatedAt이 이미 있으면 true — 멱등 가드. */
  alreadyActivated: boolean;
  /** users/{uid}/contacts 문서 수(Admin SDK count() 집계 결과). */
  contactCount: number;
}

export interface ActivationPlan {
  /** true면 이번 호출에서 활성화 이벤트를 1회 기록해야 한다. */
  shouldRecord: boolean;
}

/**
 * "명함 3장 이상 + AI 브리핑 1회 이상 사용" 두 조건이 모두 충족된 시점(둘
 * 중 나중에 벌어진 사건 시점)에 1회만 기록하기 위한 순수 판정.
 *
 * 이 함수 자체는 "AI를 몇 번 썼는지"를 모른다 — 호출부(generateBriefing
 * 성공 직후)가 이미 "지금 이 순간 AI 사용이 1회 이상 일어났다"는 사실을
 * 알고 있는 유일한 지점이므로, 남은 조건(명함 수)만 여기서 판정한다.
 * 이미 활성화됐으면(멱등 가드) 무조건 스킵한다.
 */
export function planActivation(input: ActivationPlanInput): ActivationPlan {
  if (input.alreadyActivated) {
    return {shouldRecord: false};
  }
  return {shouldRecord: input.contactCount >= ACTIVATION_MIN_CONTACTS};
}

/**
 * `signupInstant`(가입 시점, 최초 `bootstrapAccount` 호출 시각)를 KST 기준
 * ISO-8601 주차 문자열("GGGG-Www", 예: "2026-W33")로 변환한다.
 *
 * ISO 8601 주차 규칙:
 * - 월요일이 한 주의 시작.
 * - 그 주의 목요일이 속한 연도에 그 주 전체가 귀속된다(연말/연초 경계에서
 *   "12월 31일인데 다음 해 1주차"이거나 "1월 1일인데 전년도 마지막 주"인
 *   경우를 표준 방식대로 처리하기 위함).
 *
 * KST 필드 추출에는 `usageReset.ts`의 `toKstFields`를 그대로 재사용한다
 * (오프셋 산술을 이 파일에서 다시 구현하지 않는다).
 */
export function kstIsoWeekCohort(signupInstant: Date): string {
  const kst = toKstFields(signupInstant);

  // KST 기준 "그 날짜"만 UTC 필드에 담은 자정 시각을 만든다 — 이후 계산은
  // 전부 이 값의 UTC 필드로만 진행하므로(이미 KST 벽시계 값이 들어 있음)
  // 타임존 변환을 다시 신경 쓸 필요가 없다.
  const target = new Date(
    Date.UTC(kst.getUTCFullYear(), kst.getUTCMonth(), kst.getUTCDate())
  );

  // ISO 요일: 월=1 ... 일=7 (JS Date#getUTCDay는 일=0 ... 토=6).
  const isoWeekday = target.getUTCDay() || 7;
  // 그 주의 목요일로 이동 — ISO 8601이 "목요일이 속한 연도·주차"를 기준으로
  // 삼기 때문.
  target.setUTCDate(target.getUTCDate() + 4 - isoWeekday);

  const isoYear = target.getUTCFullYear();
  const yearStart = new Date(Date.UTC(isoYear, 0, 1));
  const weekNumber = Math.ceil(
    ((target.getTime() - yearStart.getTime()) / 86400000 + 1) / 7
  );

  return `${isoYear}-W${String(weekNumber).padStart(2, "0")}`;
}

/**
 * AI 사용량 일/월 리셋 시각 계산 — 반드시 한국시간(KST) 기준이어야 한다.
 *
 * 배경(버그): `incrementAndCheckUsage`가 원래 `Date#setHours`/`Date#getMonth`로
 * 다음 자정·다음 달 1일을 계산했는데, 이 메서드들은 **Node 프로세스의 로컬
 * 시간대** 기준이다. Cloud Functions Node 런타임은 TZ 환경변수를 지정하지
 * 않으면 기본값이 UTC라 — 함수 리전이 asia-northeast3(서울)여도 런타임
 * 시간대와는 무관하다 — 실제로는 "한국시간 자정"이 아니라 "UTC 자정"(=한국시간
 * 오전 9시)에 리셋됐다.
 *
 * 이 파일의 함수들은 KST(UTC+9, 한국은 서머타임이 없어 연중 고정 오프셋이라
 * 오프셋 산술이 안전하다)를 명시적으로 계산해 그 문제를 없앤다.
 * `process.env.TZ = "Asia/Seoul"` 같은 전역 상태에 기대지 않는다 — 나중에
 * 다른 곳에서 `new Date()`를 쓰는 코드가 이 전역 설정에 암묵적으로 의존하는지
 * 아닌지 알기 어려워지기 때문이다.
 */

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

/**
 * UTC 시각을 "그 순간의 KST 벽시계 값이 UTC 필드에 그대로 들어간" Date로
 * 바꾼다. 반환값은 여전히 내부적으로 UTC 타임스탬프를 갖는 `Date` 객체이지만,
 * `getUTC*()`로 읽으면 KST 기준 연/월/일/시가 나온다 — Node에 KST용
 * `Intl`/타임존 DB를 쓰지 않고 오프셋 산술만으로 날짜 필드를 얻기 위한 트릭이다.
 * 반드시 [fromKstFields]와 짝으로 쓴다.
 *
 * 파일 밖으로 export하는 이유: `pilotEvents.ts`(파일럿 계측, 주차 코호트
 * 계산)가 "KST 기준 연/월/일 필드"만 필요하고 실제 UTC 타임스탬프로 되돌릴
 * 필요는 없어 이 함수만 재사용한다. KST 오프셋 산술을 두 곳에서 각자
 * 다시 구현하지 않기 위함 — 새로 만들지 말 것(작업 지시서 명시).
 */
export function toKstFields(utcInstant: Date): Date {
  return new Date(utcInstant.getTime() + KST_OFFSET_MS);
}

/** [toKstFields]로 만든 "KST 필드" Date를 실제 UTC 시각(진짜 타임스탬프)으로 되돌린다. */
function fromKstFields(kstFields: Date): Date {
  return new Date(kstFields.getTime() - KST_OFFSET_MS);
}

/**
 * `now` 기준 "다음 한국시간 자정"(오늘이 이미 지난 자정 이후라면 내일 00:00
 * KST)의 실제 UTC 시각을 반환한다.
 *
 * 원래 로직 `nextMidnight.setHours(24, 0, 0, 0)`과 같은 의미(항상 "내일의
 * 시작")를 KST 기준으로 재현한다 — `now`가 정확히 자정이어도 24시간 뒤인
 * 다음 날 자정을 가리킨다.
 */
export function nextKstMidnight(now: Date): Date {
  const kst = toKstFields(now);
  const nextMidnightKstFields = new Date(
    Date.UTC(kst.getUTCFullYear(), kst.getUTCMonth(), kst.getUTCDate() + 1, 0, 0, 0, 0)
  );
  return fromKstFields(nextMidnightKstFields);
}

/**
 * `now` 기준 "다음 달 1일 00:00 한국시간"의 실제 UTC 시각을 반환한다.
 * `Date.UTC`가 월 오버플로(12월 → 다음 해 1월)를 알아서 정규화하므로 연말
 * 경계도 별도 분기 없이 처리된다.
 */
export function nextKstMonthStart(now: Date): Date {
  const kst = toKstFields(now);
  const nextMonthStartKstFields = new Date(
    Date.UTC(kst.getUTCFullYear(), kst.getUTCMonth() + 1, 1, 0, 0, 0, 0)
  );
  return fromKstFields(nextMonthStartKstFields);
}

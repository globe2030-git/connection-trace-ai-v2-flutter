# 관리자 매뉴얼 — 서버/AI 연동 설정

운영자가 직접 콘솔에서 진행해야 하는 절차만 모아둔 문서. 코드 작업은
다루지 않는다(코드 변경은 `backlog.md`/커밋 이력 참고). 절차를 실제로
진행한 순서 그대로 기록했다.

---

## 1. AI 서버(Gemini) 연동 설정

**목적**: 앱의 AI 대화 브리핑 기능(`generateBriefing`)을 실제로 동작시키기
위한 서버 측 설정. 이 절차가 끝나야 앱에서 AI 기능이 "준비 중" 대신 실제로
작동한다.

**관리 계정**: creamhouseapp@gmail.com (Firebase/Google Cloud/Google AI
Studio 전부 이 계정으로 로그인)

### 1-1. Firebase Blaze(종량제) 요금제 전환

Cloud Functions는 무료(Spark) 요금제에서 실행되지 않는다 — Blaze로
전환해야 서버 코드(AI 프록시 등)를 배포할 수 있다.

1. [Firebase 콘솔](https://console.firebase.google.com) 접속 (creamhouseapp@gmail.com)
2. **connection-sense** 프로젝트 선택
3. 왼쪽 하단 "Spark 요금제" 뱃지 클릭 → **⚙️ 설정 → 사용량 및 결제 → 세부정보 및 설정**으로도 진입 가능
4. "**Blaze - 종량제**" 선택 → "플랜 선택"
5. Cloud Billing 계정이 없으면 "**Cloud Billing 계정 만들기**" → 국가(대한민국) → 계정 유형(개인/사업자) → 카드 정보 입력 → 약관 동의
6. 결제 계정 선택 후 "**Blaze로 업그레이드**"

전환 시 **Google Cloud 무료 체험판 크레딧($300 상당, 원화 환산 약
₩430,000대)**이 자동 적용되는 경우가 있다(2026-08-07 확인, 유효기간
90일) — 이 크레딧이 소진되기 전까지는 추가 비용이 거의 발생하지 않는다.

### 1-2. 예산 알림 확인/설정 (안전장치)

Blaze로 전환하면 Firebase가 프로젝트 기준 기본 예산(₩5,000/월, 알림
50%/90%/100%)을 자동으로 만들어 두는 경우가 있다 — 아래에서 이미 있는지
먼저 확인하고, 없으면 새로 만든다.

1. [Google Cloud 콘솔 → 결제 → 예산 및 알림](https://console.cloud.google.com/billing/budgets) 접속
2. 목록에 "Firebase Project connection-sense" 같은 예산이 이미 있으면 그대로 사용
3. 없으면 "예산 만들기" → 이름 지정 → 프로젝트를 connection-sense로 한정 → 금액 ₩5,000~10,000 정도로 설정 → 기본 알림 임계값(50/90/100%)으로 저장

> 상단에 "cost data delays" 관련 경고 배너가 뜰 수 있는데, 구글 쪽 시스템
> 이슈(비용 집계 지연)로 조치할 것 없음.

### 1-3. Gemini API 키 발급

1. [Google AI Studio → API 키](https://aistudio.google.com/api-keys) 접속 (creamhouseapp@gmail.com)
2. "**API 키 만들기**" 클릭
3. "가져온 프로젝트 선택" 드롭다운에서 **connection-sense**가 안 보이면 → "**프로젝트 가져오기**" 클릭 → connection-sense 선택
4. connection-sense가 선택된 상태로 "만들기"
5. 생성된 키의 "프로젝트" 칸이 **connection-sense**로, "결제 등급"이 무료 등급이 아닌 것으로 표시되는지 확인

> ⚠️ **"Default Gemini Project"로 만들어진 키를 쓰면 안 된다** — 무료
> 등급으로 잡혀서 Blaze 크레딧과 무관하게 동작하고 한도도 낮다. 반드시
> connection-sense 프로젝트로 만든 키를 써야 한다.

> ⚠️ **발급된 키 값은 어디에도(채팅, 캡처, 커밋) 남기지 않는다.** 키가
> 한 번이라도 외부에 노출되면 즉시 삭제하고 새로 발급받는다.

### 1-4. 키를 Firebase Secret Manager에 등록

터미널에서 프로젝트 루트로 이동한 뒤 실행한다.

```bash
cd "/Volumes/X31(VM)/Claude/connection-trace-ai-v2-flutter"
```

인터랙티브 프롬프트(`firebase functions:secrets:set GEMINI_API_KEY`만
실행 후 값 입력)는 값이 빈 채로 등록되는 오류(`Secret Payload cannot be
empty`)가 반복 발생했다 — **파이프 방식을 쓴다:**

```bash
echo -n "실제_API_키_값" | firebase functions:secrets:set GEMINI_API_KEY
```

> ⚠️ **`GEMINI_API_KEY`는 고정된 이름(리터럴 문자열)이다.** 서버 코드
> (`functions/src/index.ts`의 `defineSecret("GEMINI_API_KEY")`)가 이
> 이름을 그대로 찾기 때문에, 절대 이 자리에 실제 키 값을 넣으면 안 된다.
> 큰따옴표 안(`echo -n "..."`)에만 실제 키 값이 들어간다.

성공하면 `+ Created a new secret version for GEMINI_API_KEY` 같은
메시지가 뜬다. 실행 후 `history -c`로 터미널 기록을 지우는 것을 권장.

### 1-5. Cloud Functions 배포

```bash
firebase deploy --only functions
```

`generateBriefing(asia-northeast3)` 관련 성공 메시지가 뜨면 완료.

### 1-6. 앱 코드 반영 (개발자 작업, 참고용)

배포가 끝나면 `lib/core/services/ai_briefing_service.dart`의
`kAiServiceDeployed`를 `false → true`로 바꾸고 앱을 재빌드해야
클라이언트에서 실제로 AI 기능이 켜진다 — 이건 코드 변경이라 이 문서가
아니라 개발 담당(에이전트/개발자)이 처리.

---

## 2. 참고 — 이 프로젝트에서 쓰는 Google 관련 주소 전부

**주의**: Firebase Blaze 결제, Google Cloud 결제, Google AI Studio(Gemini)
결제는 **서로 다른 시스템**이다(2026-08-07 확인 — backlog 추가 96 참고).
카드를 한 번 등록했다고 셋 다 자동으로 연결되는 게 아니라서, 문제가 생기면
아래 표에서 "정확히 어느 콘솔"인지 구분해서 확인해야 한다.

| 용도 | 주소 | 비고 |
|---|---|---|
| Firebase 콘솔(프로젝트 개요) | https://console.firebase.google.com/project/connection-sense/overview | |
| Firestore 데이터 직접 조회/수정 | https://console.firebase.google.com/project/connection-sense/firestore/data | 사용량 카운터(`users/{uid}.aiUsage`) 등을 관리자 권한으로 직접 볼 때. **운영 데이터라 신중히.** |
| Google Cloud 콘솔 — 결제 예산 및 알림 | https://console.cloud.google.com/billing/budgets | Firebase Blaze 전체 사용량 예산. **Gemini API 자체 결제는 여기 안 잡힘**(아래 항목 참고). |
| Google Cloud 콘솔 — API 라이브러리(Gmail API) | https://console.cloud.google.com/apis/library/gmail.googleapis.com?project=connection-sense | 앱의 Gmail 가져오기 기능이 403으로 실패하면 여기서 "사용 설정"이 꺼져 있는지 가장 먼저 확인(2026-08-07 실제로 이게 원인이었음 — 추가 98). |
| Google AI Studio — API 키 발급 | https://aistudio.google.com/api-keys | 반드시 "connection-sense" 프로젝트로 만든 키를 쓸 것(위 1-3 참고). |
| Google AI Studio — 프로젝트/선불 크레딧 | https://aistudio.google.com/projects | Gemini API는 Firebase Blaze와 별개로 **자체 선불 크레딧**을 쓴다. "prepayment credits are depleted" 에러가 나면 여기서 충전(최소 단위 16,000원 확인됨, 2026-08-07). |
| Google AI Studio — 월 지출 한도(spend cap) | https://aistudio.google.com/spend | 크레딧을 충전해도 이 한도가 낮게 잡혀 있으면 또 429로 막힌다 — "project has exceeded its monthly spending cap" 에러가 나면 여기서 상향(2026-08-07 실제로 겪음 — 추가 96). |
| GitHub 저장소 | https://github.com/globe2030-git/connection-trace-ai-v2-flutter | |
| 관리자 웹 콘솔(공지/문의/법적문서/경영리포트) | Firebase Hosting `admin` 타겟으로 배포 (`firebase deploy --only hosting:admin`) | |

### 2026-08-07에 실제로 겪은 문제 → 어느 콘솔에서 풀었는지

AI 브리핑을 처음 실기기로 써보면서 겪은 순서 그대로. 다음에 비슷한 에러가
나면 이 표에서 증상으로 먼저 찾아볼 것.

| 에러 메시지(요지) | 원인 | 어디서 해결 |
|---|---|---|
| "Your prepayment credits are depleted" | Gemini API 자체 선불 크레딧이 0원 | AI Studio — 프로젝트/선불 크레딧 페이지에서 충전 |
| "Your project has exceeded its monthly spending cap" | 위 크레딧을 채워도 월 지출 한도 자체가 낮게 걸려 있음 | AI Studio — 월 지출 한도 페이지에서 상향 |
| "AI 브리핑 서비스 준비 중이에요" (반복) | 서버(`generateBriefing`)의 사용자별 하루 호출 한도(10회)를 오늘 테스트로 다 씀 | Firestore 데이터 직접 조회/수정 페이지에서 `users/{uid}.aiUsage.dailyCount`를 0으로 |
| Gmail 가져오기 "Bad state: Gmail 조회에 실패했습니다 (403)" | connection-sense 프로젝트에서 Gmail API 자체가 비활성화 상태 | Google Cloud 콘솔 — API 라이브러리(Gmail API) 페이지에서 "사용 설정" |

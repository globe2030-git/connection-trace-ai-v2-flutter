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

## 2. 참고 — 이 프로젝트의 다른 콘솔 주소

| 용도 | 주소 |
|---|---|
| Firebase 콘솔 | https://console.firebase.google.com |
| Google Cloud 콘솔(결제/예산) | https://console.cloud.google.com/billing |
| Google AI Studio(Gemini API 키) | https://aistudio.google.com/api-keys |
| GitHub 저장소 | https://github.com/globe2030-git/connection-trace-ai-v2-flutter |
| 관리자 웹 콘솔(공지/문의/법적문서/경영리포트) | Firebase Hosting `admin` 타겟으로 배포 (`firebase deploy --only hosting:admin`) |

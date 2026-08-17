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
cd ~/Claude/connection-trace-ai-v2-flutter
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

## 2. App Check — AI 호출을 우리 앱만 할 수 있게 막기

**목적**: `generateBriefing`은 로그인 여부(`request.auth`)만 확인한다. 즉
Google 로그인만 통과하면 **우리 앱이 아닌 스크립트도 호출할 수 있고**, 그
호출은 회사 명의 유료 Gemini 키로 나가 그대로 요금이 된다. uid당 하루 10회
한도가 있지만 계정을 여러 개 만들면 우회된다. App Check는 "이 호출이 진짜
우리 앱, 진짜 기기에서 왔는가"를 증명하는 토큰을 붙여 이 구멍을 막는다.

**⚠️ 강제(`enforceAppCheck: true`)를 켠 뒤로는 토큰을 못 만드는 빌드에서
AI 브리핑이 막힌다.** 그리고 **정식 무결성 검증기는 스토어 배포를 전제로
한다** — 2026-08-08 실기기에서 확인한 사실이다.

| 검증기 | 언제 통과하나 | 지금 |
|---|---|---|
| Play Integrity (Android) | Google Play가 아는 앱(내부 테스트 트랙 포함) | ❌ Play 미배포 + debug 키 서명(P1-19) |
| App Attest (iOS) | TestFlight / App Store 빌드 | ❌ 개발 서명 빌드는 Firebase가 `403 App attestation failed`로 거부 |

그래서 **스토어를 거치지 않는 빌드는 debug 제공자 + 기기별 디버그 토큰**으로
쓴다. 빌드할 때 세 번째 인자를 붙이면 된다.

```bash
tool/build_app.sh ios release appcheck-debug   # devicectl로 직접 설치할 때
tool/build_app.sh apk release appcheck-debug   # 테스터 배포용 APK
```

⚠️ **스토어에 올리는 빌드에는 이 인자를 붙이지 말 것.** 붙이면 디버그 토큰만
있으면 누구나 우리 앱인 척할 수 있어 App Check가 무의미해진다.

| 단계 | 누가 | 상태(2026-08-08) |
|---|---|---|
| 앱에 App Check 붙이기(코드) | 개발 | ✅ 완료 |
| 인스턴스 상한 명시(코드) | 개발 | ✅ 배포 완료(`maxInstances=3` 확인) |
| App Check API 활성화(2-0) | 개발 | ✅ 완료 |
| iOS 앱에 Apple 팀 ID 등록 | 개발 | ✅ 완료(`77L7BH2M2W`) |
| 갤럭시 디버그 토큰 등록 + 서버 도달 확인 | 개발 | ✅ `app: VALID` 확인 |
| 아이폰 디버그 토큰 등록 + 서버 도달 확인 | 개발 | ⬜ |
| `enforceAppCheck: true`로 전환·재배포 | 개발 | ⬜ |
| 스토어 배포 후 정식 검증기로 재확인 | 개발 | ⬜ P0-1 / P1-19 이후 |

### 2-0. Firebase App Check API 켜기 (가장 먼저)

**2026-08-08 확인: 이 프로젝트는 App Check API가 꺼져 있었다**(`state:
DISABLED`). 이 상태에서는 콘솔에 앱과 디버그 토큰을 아무리 정확히 등록해도
기기에서 토큰 교환이 403으로 실패한다. 그런데 앱 로그에는 "등록 안 했으면
콘솔에서 등록하라"는 **엉뚱한 안내**만 떠서, 원인을 등록 실수로 오해하기 쉽다.

- 확인·활성화: https://console.cloud.google.com/apis/api/firebaseappcheck.googleapis.com/overview?project=connection-sense
- 2026-08-08에 이미 켰으므로 지금은 추가 조치 없음. 위 증상이 재발하면 여기부터 볼 것.

### 2-1. Firebase 콘솔에 앱 등록

1. [Firebase 콘솔 → App Check](https://console.firebase.google.com/project/connection-sense/appcheck) 접속
2. "앱" 탭에 Android/iOS 앱이 목록에 보인다. 각각 클릭해서 인증 제공자를 등록한다.
   - **Android** → **Play Integrity** 선택 후 저장
   - **iOS** → **App Attest** 선택 후 저장 (팀 ID를 물으면 `77L7BH2M2W`)
3. 각 앱 행의 "⋮ → 디버그 토큰 관리"에서 개발용 토큰을 등록한다(아래 2-2).

> ⚠️ **iOS 앱이 목록에 두 개 보인다.** 반드시 번들 ID가
> `com.creamhouse.connectionsense`인 쪽(appId `…ios:534c871d9bfd7d78182254`)을
> 고를 것. 다른 하나(`com.connectiontrace.…`, appId `…ios:711add…`)는
> 2026-08-04에 버린 옛 앱이다. 앱 ID를 헷갈리면 등록은 성공한 것처럼 보이는데
> 기기에서는 계속 실패한다 — 2026-08-08에 실제로 이 함정을 밟았다.
>
> 또 하나: App Check REST API는 **등록 여부와 무관하게 기본 config를
> 돌려준다.** 조회 결과가 그럴듯하다고 "등록돼 있다"고 판단하면 안 된다.

### 2-2. 디버그 토큰 등록 (개발·테스트 기기용)

debug 빌드로 앱을 실행하면 로그에 아래 같은 줄이 한 번 찍힌다.

```
Enter this debug secret into the allow list in the Firebase Console for your project:
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

- Android: `adb logcat | grep -i "debug secret"`
- iOS: Xcode 콘솔 출력에서 검색

이 값을 위 2-1의 "디버그 토큰 관리"에 등록하면 그 기기만 통과한다.

> ⚠️ **디버그 토큰은 사실상 우회 열쇠다.** 유출되면 누구나 우리 앱인 척할 수
> 있으니 채팅·캡처·커밋에 남기지 말고, 안 쓰는 토큰은 콘솔에서 지운다.

### 2-3. 비용 한도 — 예산 알림은 차단 장치가 아니다

1-2의 예산(₩5,000/월)은 **알림만** 보낸다. 한도에 닿아도 자동으로 멈추지
않으므로, 실제로 요금을 막는 건 아래 세 가지다.

| 장치 | 어디 | 지금 값 |
|---|---|---|
| App Check 강제 | 코드 `enforceAppCheck` | ✅ 켜짐(2026-08-08) |
| 동시 인스턴스 상한 | 코드 `functions/src/index.ts`의 `maxInstances` | 3 |
| 사용자별 호출 한도 | 코드 `DAILY_LIMIT`/`MONTHLY_LIMIT` | 10/일, 100/월 |
| Gemini 월 지출 한도 | [AI Studio — spend cap](https://aistudio.google.com/spend) | **확인 필요** |

> `maxInstances`가 3인 이유: 값을 지정하지 않았는데도 이미 3이 잡혀 있었다.
> 어디서 온 건지 모르는 기본값에 기대면 다음 배포에서 조용히 바뀌어도 아무도
> 모르므로, 그 값을 그대로 코드에 못 박았다. 인스턴스당 동시 요청이 80이라
> 3개면 최대 240건을 동시에 처리한다.

Gemini 월 지출 한도가 마지막 방어선이다. 위 두 가지를 다 뚫어도 이 한도를
넘으면 Google이 호출을 거절한다 — **감당 가능한 금액으로 잡혀 있는지
확인해 둘 것.**

---

## 3. 출시 준비 — Apple / Google Play 콘솔 작업

앱을 스토어에 올리기까지 **운영자가 콘솔에서 직접 해야 하는 일**만 순서대로
정리했다. 각 항목이 어느 주소인지 붙여 뒀으므로 이 문서 하나만 열어두고
진행하면 된다.

> ⚠️ **Apple 주소의 하위 경로는 로그인 없이 검증할 수 없다.** Apple은 없는
> 경로도 로그인 페이지로 넘겨버려서(302) 404로 구분이 안 된다. 아래 최상위
> 주소는 확인했고 하위 경로는 Apple 표준 구조 기준이다 — 링크가 엉뚱한 데로
> 가면 최상위에서 메뉴를 따라 들어갈 것.

### 3-0. 순서를 이렇게 잡는 이유

**① Apple 권한 문제(P-1)를 가장 먼저 던져둔다.** 계정 이메일 왕복에 시간이
걸릴 수 있고, 이게 안 풀리면 iOS는 TestFlight도 App Attest 검증도 전부 막힌다.
답을 기다리는 동안 나머지를 진행하면 된다.

**② 테스터를 늘리려면 Play 내부 테스트(A-3)를 먼저 한다.** 지금처럼 APK를
직접 전달하면 **기기마다 App Check 디버그 토큰을 등록해야 AI 브리핑이
동작한다**(2절 참고). 사람이 늘수록 관리가 안 되고, 디버그 토큰은 사실상
우회 열쇠라 유출 위험도 함께 커진다. Play 내부 테스트 트랙에 올리면 Play
Integrity가 정상 동작해 **토큰 등록이 아예 필요 없어진다.**

### 3-1. 🍎 Apple

| # | 할 일 | 주소 | 비고 |
|---|---|---|---|
| **P-1** | **빌드 업로드 403 해결** — `apps@creamhouse.net`의 역할 확인, 목록에 없으면 신규 초대 | [App Store Connect → 사용자 및 접근](https://appstoreconnect.apple.com/access/users) | **최대 병목.** Developer Portal 권한과 App Store Connect 권한은 **별개 시스템**이라, 포털에서 Admin이어도 여기 목록에 없으면 업로드가 막힌다 |
| P-2 | Sign in with Apple 키(.p8) 발급 | [Developer → Keys](https://developer.apple.com/account/resources/authkeys/list) | **.p8 파일은 발급 시 한 번만 내려받을 수 있다.** 잃어버리면 재발급뿐 |
| P-2b | App ID에 Sign in with Apple 활성화 + Services ID 생성 | [Developer → Identifiers](https://developer.apple.com/account/resources/identifiers/list) | App ID는 `com.creamhouse.connectionsense` |
| P-3 | Firebase에 Apple 제공사 등록 | [Firebase → Authentication → 로그인 방법](https://console.firebase.google.com/project/connection-sense/authentication/providers) | Services ID · Team ID(`77L7BH2M2W`) · Key ID · .p8 키 |
| P-4 | 앱 레코드 생성 + TestFlight 테스터 등록 | [App Store Connect → 앱](https://appstoreconnect.apple.com/apps) | P-1 해결 후에만 가능 |
| P-5 | **App Privacy 양식** 작성 | 위 앱 레코드 → 앱 개인정보 보호 | 개인정보처리방침과 **불일치하면 즉시 반려**. 방침 URL은 3-3 참고 |
| P-6 | 인증서·프로비저닝 만료 확인 | [Developer → Certificates](https://developer.apple.com/account/resources/certificates/list) | 만료일 정책은 [여기](https://developer.apple.com/support/expiration/) |

### 3-2. 🤖 Google Play

| # | 할 일 | 주소 | 비고 |
|---|---|---|---|
| A-1 | 개발자 계정 등록(**$25 1회**) | [Play Console 가입](https://play.google.com/console/signup) | 개인/사업자 선택 주의 — 사업자로 하면 사업자등록증 확인이 필요하다 |
| **A-2** | **업로드 키스토어 생성** | 로컬 작업 | `.gitignore` 안전망은 2026-08-08에 넣어 뒀다(루트 `.gitignore`, 12개 위치 검증 완료). 다만 **키는 저장소 밖(예: `~/keys/`)에 두는 것이 원칙**이다 — `.gitignore`는 실수 방지용이지 보관 위치가 아니다. ⚠️ **키를 잃으면 앱 업데이트를 영원히 못 올린다** — 반드시 별도 백업 |
| A-3 | 앱 등록 + **내부 테스트 트랙** 생성, 테스터 이메일 등록 | [Play Console](https://play.google.com/console) | 이걸 해야 App Check 디버그 토큰에서 벗어난다(3-0 참고) |
| A-4 | **앱 콘텐츠** — 개인정보처리방침 URL, **계정 삭제 URL** 입력 | Play Console → 앱 → 정책 → 앱 콘텐츠 | URL은 3-3에 준비돼 있다. 계정 삭제 URL이 없으면 **제출 자체가 진행되지 않는다** |
| A-5 | **데이터 보안(Data safety) 양식** | 같은 "앱 콘텐츠" 화면 | 방침과 불일치하면 즉시 반려 |
| A-6 | App Check에서 Play Integrity 동작 확인 | [Firebase → App Check](https://console.firebase.google.com/project/connection-sense/appcheck) | A-3 후 자동 동작 |

### 3-3. 스토어 양식에 넣을 URL (이미 게시돼 있음)

Firebase Hosting에 배포돼 서비스 중이다(2026-08-08 확인).

| 용도 | URL |
|---|---|
| 개인정보처리방침 | https://connection-sense.web.app/privacy-policy |
| 이용약관 | https://connection-sense.web.app/terms-of-service |
| 접근권한 안내 | https://connection-sense.web.app/app-permissions |
| **계정 삭제 안내** | https://connection-sense.web.app/account-deletion |

> ⚠️ 이 공개 페이지(`docs/legal/*.html`)와 앱 안에서 보이는 문서
> (`legalDocs` Firestore)는 **서로 동기화되지 않는다.** 관리자 콘솔에서만
> 고치면 여기 URL은 옛 문안 그대로 남는다 — 스토어에 등록한 문서는 특히
> 양쪽을 함께 고칠 것(`docs/admin/README.md` 참고).

### 3-4. 💰 스토어 수수료 15% 만들기 — 유료 상품 출시 전 신청 2건

인앱결제(AI 횟수 충전 등 디지털 상품)는 스토어 결제가 의무이고, 수수료는
기본 30%지만 **둘 다 연 매출 100만 달러 이하 구간은 15%로 낮출 수 있다.**
애플은 **신청해야** 적용되고, 구글도 등급 등록 절차가 있다. 배경 계산은
backlog 추가 151 참고 (1,000원 판매 → 부가세·수수료 제하고 약 773원 정산).

**🍎 Apple — App Store Small Business Program (반드시 신청)**

| 단계 | 내용 |
|---|---|
| 1 | https://developer.apple.com/kr/app-store/small-business-program/ 접속 |
| 2 | **계정 소유자**(Account Holder) Apple ID로 로그인해야 신청 가능 — 이 프로젝트는 `apps@creamhouse.net` |
| 3 | 유료 응용 프로그램 계약(Paid Apps Agreement)이 활성 상태여야 함 — 2026-08-08 확인 시 이미 활성 |
| 4 | 연결된 개발자 계정이 더 있으면 모두 신고(합산 매출로 자격 판정) |
| 5 | 신청 후 승인되면 15% 적용. **적용 시점이 신청·승인 월 기준으로 정해지므로 유료 상품을 파는 첫 달 전에 미리 신청할 것** |

- 자격: 직전 연도 정산 수익(proceeds) 100만 달러 이하 — 신규 개발사는 해당.
- 연 매출이 100만 달러를 넘기면 그 시점부터 30%로 전환되고 프로그램에서 나가게 된다.

**🤖 Google Play — 15% 서비스 수수료 등급 (등록 확인)**

| 단계 | 내용 |
|---|---|
| 1 | [Play Console](https://play.google.com/console) → 설정 → **서비스 수수료** (또는 "수수료 등급") 메뉴 확인 |
| 2 | 연 수익 100만 달러까지 15%가 적용되는 등급에 **계정 그룹 정보를 제출/동의**해야 하는 절차가 있음 (관련 개발자 계정이 있으면 함께 신고) |
| 3 | 등록 상태가 "적용 중"인지 확인 — 미등록 상태면 첫 달러부터 30%가 나간다 |

- ⚠️ 메뉴 이름·위치는 콘솔 개편으로 바뀔 수 있다. "서비스 수수료"로 콘솔 내 검색하면 나온다.

**공통 참고**

- 한국은 제3자 결제(외부 PG)도 법적으로 허용되지만 그 경우에도 스토어에 26% + PG 수수료 2~3%가 들어 **15% 인앱결제보다 손해**다. 쓰지 말 것.
- 부가세 10%는 스토어가 소비자가에서 대신 걷어 납부한다. 정산액 감각: **판매가의 약 77%** (15% 구간 기준).

---

## 4. 참고 — 이 프로젝트에서 쓰는 주소 전부

**주의**: Firebase Blaze 결제, Google Cloud 결제, Google AI Studio(Gemini)
결제는 **서로 다른 시스템**이다(2026-08-07 확인 — backlog 추가 96 참고).
카드를 한 번 등록했다고 셋 다 자동으로 연결되는 게 아니라서, 문제가 생기면
아래 표에서 "정확히 어느 콘솔"인지 구분해서 확인해야 한다. 같은 이유로
**Apple Developer Portal 권한과 App Store Connect 권한도 별개 시스템**이다
(3-1의 P-1 참고).

| 용도 | 주소 | 비고 |
|---|---|---|
| Firebase 콘솔(프로젝트 개요) | https://console.firebase.google.com/project/connection-sense/overview | |
| Firestore 데이터 직접 조회/수정 | https://console.firebase.google.com/project/connection-sense/firestore/data | 사용량 카운터(`users/{uid}.aiUsage`) 등을 관리자 권한으로 직접 볼 때. **운영 데이터라 신중히.** |
| Google Cloud 콘솔 — 결제 예산 및 알림 | https://console.cloud.google.com/billing/budgets | Firebase Blaze 전체 사용량 예산. **알림만 보내고 자동 차단은 안 한다**(2-3 참고). **Gemini API 자체 결제는 여기 안 잡힘**(아래 항목 참고). |
| Firebase 콘솔 — App Check | https://console.firebase.google.com/project/connection-sense/appcheck | 앱별 인증 제공자(Play Integrity/App Attest) 등록, 디버그 토큰 관리, 토큰 도착 현황 확인. 위 2절 참고. |
| Google Cloud 콘솔 — API 라이브러리(Gmail API) | https://console.cloud.google.com/apis/library/gmail.googleapis.com?project=connection-sense | 앱의 Gmail 가져오기 기능이 403으로 실패하면 여기서 "사용 설정"이 꺼져 있는지 가장 먼저 확인(2026-08-07 실제로 이게 원인이었음 — 추가 98). |
| Google AI Studio — API 키 발급 | https://aistudio.google.com/api-keys | 반드시 "connection-sense" 프로젝트로 만든 키를 쓸 것(위 1-3 참고). |
| Google AI Studio — 프로젝트/선불 크레딧 | https://aistudio.google.com/projects | Gemini API는 Firebase Blaze와 별개로 **자체 선불 크레딧**을 쓴다. "prepayment credits are depleted" 에러가 나면 여기서 충전(최소 단위 16,000원 확인됨, 2026-08-07). |
| Google AI Studio — 월 지출 한도(spend cap) | https://aistudio.google.com/spend | 크레딧을 충전해도 이 한도가 낮게 잡혀 있으면 또 429로 막힌다 — "project has exceeded its monthly spending cap" 에러가 나면 여기서 상향(2026-08-07 실제로 겪음 — 추가 96). |
| GitHub 저장소 | https://github.com/globe2030-git/connection-trace-ai-v2-flutter | |
| **App Store Connect** | https://appstoreconnect.apple.com | 빌드 업로드·앱 레코드·TestFlight·App Privacy. ⚠️ `appstoreconnect.com`이 아니라 **`.apple.com`**이다 |
| App Store Connect — 사용자 및 접근 | https://appstoreconnect.apple.com/access/users | 업로드 403(P-1)이 나면 **여기부터** 볼 것 |
| Apple Developer — 계정 | https://developer.apple.com/account | 팀 ID `77L7BH2M2W` |
| Apple Developer — Keys(.p8) | https://developer.apple.com/account/resources/authkeys/list | Sign in with Apple 키. **발급 시 한 번만 내려받을 수 있다** |
| Apple Developer — Identifiers | https://developer.apple.com/account/resources/identifiers/list | App ID `com.creamhouse.connectionsense`, Services ID |
| Apple Developer — Certificates | https://developer.apple.com/account/resources/certificates/list | 만료 정책: https://developer.apple.com/support/expiration/ |
| **Google Play Console** | https://play.google.com/console | 앱 등록·내부 테스트·앱 콘텐츠·데이터 보안 |
| Play Console — 개발자 계정 가입 | https://play.google.com/console/signup | $25 1회 |
| Firebase — Authentication(로그인 방법) | https://console.firebase.google.com/project/connection-sense/authentication/providers | Apple 제공사 등록(P-3) |
| Firebase — Authentication(사용자) | https://console.firebase.google.com/project/connection-sense/authentication/users | 계정 정리·인증 상태 확인 |
| Firebase — App Distribution | https://console.firebase.google.com/project/connection-sense/appdistribution | Play 트랙 쓰기 전 임시 테스터 배포 |
| Firebase — Hosting | https://console.firebase.google.com/project/connection-sense/hosting/sites | `legal`·`admin` 두 사이트 |
| **관리자 콘솔(운영)** | https://connection-sense-admin.web.app | 공지·1:1문의·법적문서 편집. `connectionsense@creamhouse.net`으로 **Google 계정 로그인** |
| 법적 고지(공개) | https://connection-sense.web.app | 스토어 양식에 넣는 URL — 3-3 참고 |
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

---

## 5. 앱 업데이트 안내(버전 게이트) 운영 가이드

관리자 콘솔 **"앱 업데이트" 탭**에서 "지금 스토어에 올라간 앱보다 낡은
빌드를 쓰는 사람"에게 업데이트를 안내하는 기능. **코드 배포 없이, 여기서
값만 바꾸면 앱을 다시 켤 때 즉시 반영**된다(config/appUpdate, P1-45).

이 기능은 **읽을 줄 알아야 하는 두 가지 숫자**로 동작한다.

- **빌드 번호**: 스토어에 올라간 앱 버전이 아니라, `pubspec.yaml`의
  `1.0.0+7` 같은 표기에서 **`+` 뒤의 정수**다. 화면에 보이는 "1.0.0"이
  아니라 "7" 쪽. 앱은 자기 빌드 번호와 여기 설정한 숫자를 비교한다.
- **최소 지원 빌드 / 최신 빌드**: "최소"보다 낮으면 **강제**(닫을 수 없고
  스토어로만 이동), "최신"보다 낮으면 **권장**("나중에" 허용). 두 값 다
  0이면 아무 안내도 하지 않는다.

**iOS/Android는 따로 설정한다**(2026-08-12, PR #117). 두 스토어의 심사
통과 시점이 서로 다르기 때문 — 예를 들어 iOS 빌드 7이 먼저 심사를
통과했는데 Android는 아직 6이면, "최신 빌드"를 하나로만 두면 아직 스토어에
없는 Android 7을 있다고 잘못 안내하게 된다. 그래서 iOS/Android 칸이
각각 따로 있다 — **자기 플랫폼 칸만 채우면 된다.**

### 5-1. 언제 값을 바꾸나 (평소 운영 순서)

1. 새 빌드를 스토어(App Store/Play)에 올리고 **심사를 통과**시킨다.
2. 그 플랫폼의 **"최신 빌드 번호"** 칸에 새 빌드 번호를 넣고 저장 →
   구버전 사용자에게 "업데이트 있어요"(권장, 닫아도 됨) 안내가 뜨기
   시작한다.
3. 그 빌드가 **문제없이 며칠 안정적으로 돌아간다고 확인되면**, 그때
   "최소 지원 빌드 번호"를 그 아래 어떤 빌드까지 봐줄지로 올려 강제
   전환한다. **새 빌드를 올리자마자 바로 최소값을 올리지 말 것** — 아직
   검증 안 된 빌드로 전원을 강제 이동시키는 셈이라 위험하다.
4. 두 플랫폼 다 갱신했으면 저장 한 번, 앱은 별도 배포 없이 다음 실행부터
   바로 반영한다.

### 5-2. 스토어 URL 채우는 법 (쉽게)

"iOS 스토어 URL" / "Android 스토어 URL" 칸은 안내 화면의 "스토어로 이동"
버튼이 여는 주소다. 형식만 맞추면 되고, 매번 똑같은 규칙이라 한 번 채워
두면 다시 바꿀 일이 거의 없다.

**🍎 iOS — `https://apps.apple.com/app/id` 뒤에 숫자만 붙이면 된다.**

```
https://apps.apple.com/app/id6501234567
```

- 뒤에 붙는 숫자는 **Apple ID**(앱마다 하나씩 자동으로 부여되는 고유
  번호, 개발자 본인 Apple 계정 ID와는 다른 것).
- 찾는 곳: **App Store Connect → 해당 앱 선택 → "앱 정보"(App
  Information) → "Apple ID"** 항목에 적힌 숫자를 그대로 복사해 위 URL
  뒤에 붙인다.

**🤖 Android — `https://play.google.com/store/apps/details?id=` 뒤에
패키지명을 붙이면 된다.**

```
https://play.google.com/store/apps/details?id=com.connectiontrace.connection_trace_ai_flutter
```

- 패키지명은 이미 정해져 있고 앞으로도 안 바뀐다 —
  **`com.connectiontrace.connection_trace_ai_flutter`**를 그대로 복사해
  붙이면 끝(`android/app/build.gradle.kts`의 `applicationId`와 동일).

**⚠️ 베타 심사 중 주의 — 두 URL 모두 스토어에 정식 공개(또는 공개
트랙)되기 전에는 링크를 눌러도 빈 페이지거나 "찾을 수 없음"이 뜬다.**
지금은 **URL만 미리 채워 두고, "최소 지원 빌드" 칸은 반드시 0(강제
없음)**으로 둘 것. 최소값을 0보다 높게 걸어 두면, 아직 스토어에 앱이
없는 상태에서 강제 업데이트를 발동시켜 **사용자를 갈 곳 없는 빈
스토어 페이지로 보내고 앱만 막는 사고**가 난다(soft-brick). 정식
공개가 확정된 뒤에 최소값을 올릴 것.

### 5-3. 구버전 앱과의 호환 (알아만 둘 것)

플랫폼별 칸(iOS/Android)과 별도로, 화면에는 안 보이는 **레거시 값**이
저장 시 자동으로 함께 채워진다(두 플랫폼 값 중 더 낮은 쪽). 아주 옛날
버전 앱(플랫폼 구분을 모르는 빌드)을 위한 안전장치라, 관리자가 따로
신경 쓸 부분은 없다 — 그냥 iOS/Android 칸만 정확히 채우면 나머지는
자동으로 처리된다.

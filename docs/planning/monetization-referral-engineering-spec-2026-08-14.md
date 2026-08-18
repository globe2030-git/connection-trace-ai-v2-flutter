# 과금·리퍼럴 — 엔지니어링 구현 스펙 (2026-08-14, flutter-planner 작성)

**상태: 설계 문서만. 코드 구현·커밋 없음.** 이 문서는
[`monetization-referral-implementation-spec-2026-08-14.md`](./monetization-referral-implementation-spec-2026-08-14.md)
(사용자 확정 파라미터, 이하 "확정 스펙")을 실제 코드 인수 기준·파일 경로·
착수 단위로 전개한 것이다. 착수 지시는 사용자가 별도로 준다.

## 0. 이 문서가 기존 설계와 맺는 관계 (먼저 읽을 것)

이 작업을 시작하기 전 코드를 직접 grep한 결과, **과금 인프라의 상당 부분이
이미 설계·구현돼 있었다.** 확정 스펙 §2·§4가 제안한 `aiCredits`/
`creditLedger`라는 이름은 **이미 있는 더 상세한 설계와 이름이 다를 뿐 같은
것을 가리킨다** — 새로 만들지 않고 기존 설계를 그대로 쓴다.

| 확정 스펙(2026-08-14)이 제안한 이름 | 실제로 이미 설계·구현된 것 | 상태 |
|---|---|---|
| `users/{uid}.aiCredits` | `users/{uid}.aiUsage.freeBalance` + `.paidBalance` | **설계 완료**(`docs/planning/ai-credit-wallet-spec.md`, 2026-08-12), **미구현** |
| `users/{uid}/creditLedger/{txId}` | `creditGrants/{id}` 컬렉션 | 설계 완료, 미구현 |
| 결제 회계 원장 | `purchases/{transactionId}` | **규칙까지 배포됨**(`firestore.rules:63-68`), 서버 함수 미구현 |
| 충전 상품 카탈로그 | `config/billing`(`freeCredits`, `tiers[]`) | **관리자 콘솔까지 완료**(`docs/admin/admin.js:207-314`), 앱 읽기도 완료(`lib/data/repositories/billing_config_repository.dart`) |
| 충전 화면 UI | `lib/presentation/features/settings/views/ai_charge_view.dart` | **UI 완료, 구매 버튼만 비활성**(2026-08-12 병합 완료, `4088e01`) |
| 무료/유료 소비 순서, 환불 규칙, 관리자 히스토리 | `ai-credit-wallet-spec.md` §2~§5 | 설계 완료, 미구현 |
| 리퍼럴 로직 전체 | (전무) | **이 문서에서 신규 설계** |

**결론**: 이번 스펙의 실제 신규 작업 범위는 ① `ai-credit-wallet-spec.md`를
실제로 구현하는 것(원래도 해야 했던 일, P1-5) ② 그 위에 리퍼럴을 얹는 것
③ 리퍼럴이 wallet 설계의 재가입 관용(§3-1 "재가입 시 재지급은 이미 수용된
동작")과 충돌하는 지점을 막는 것 — 이 세 가지다. 아래 4절이 ③을 다룬다.

⚠️ **`ai-credit-wallet-spec.md` §3-1의 다음 문장은 이 문서로 갱신(supersede)
된다**: "재가입(계정 삭제→재가입) 시 재지급되는 것은 이미 수용된 동작이다 …
이 스펙에서 새로 막지 않는다." → 리퍼럴이 없던 시점엔 재가입 재지급이
"요율 리셋"에 불과해 손실이 제한적이었지만, 리퍼럴이 붙으면 재가입 1회당
받는 총액이 커지고(무료10+피초대자5=15 — **2026-08-18 무료 20회 개정 후로는 25, +67%**) 무한 반복 가능한 구조가 된다.
⚠️ **그래서 무료 20회는 기기 가드(U5)와 한 쌍이다.** 가드 없이 지갑만 켜면 손실이 원래 설계의 1.67배로 나간다.
**4절에서 이 지점만 정확히 막는다** — 무료체험·리퍼럴 두 가지 "돈과 동등한
지급"에만 기기 단위 가드를 추가하고, 그 밖의 개인정보·명함·소통기록은
지금처럼 탈퇴 시 완전 파기 그대로 둔다.

---

## 1. 확정 파라미터 → 코드 인수 기준(AC)

| # | 확정 파라미터(확정 스펙 §1) | 코드 인수 기준(AC) |
|---|---|---|
| AC-1 | 체험 **20회**, 1회성 (2026-08-18 개정, 원래 10회) | `config/billing.freeCredits = 20`(관리자 데이터, 코드 아님). ⚠️ **지금 Firestore 값은 아직 10이다** — 코드 폴백(`DEFAULT_FREE_CREDITS`)만 20으로 바꿔 뒀고, 콘솔 반영은 지갑 배포와 같은 타이밍이다. `bootstrapAccount` 호출 시 uid당 **정확히 1회만** `freeBalance`에 가산된다 — 멱등 가드는 `aiUsage.freeGrantedAt`(uid 스코프) **+** `deviceLedger/{deviceHash}.trialGrantsIssued < 1`(기기 스코프, 4절) 두 겹. 후자가 없으면 재가입으로 무한 재지급된다(4절 핵심). 안정기 5회 환원은 `freeCredits` 값만 바꾸면 되고 코드 변경 없음(이미 이렇게 설계돼 있음, `ai-credit-wallet-spec.md` §2-4). |
| AC-2 | 충전 티어 4개, 회당 단가 단조감소 | **2026-08-18 전면 개정(사용자 확정, 추가 303)**: 활성 4단계 `{1000,30}/{3000,100}/{5000,200}/{10000,450}`, 비활성 3단계 `{30000,1500}/{50000,2500}/{100000,5500}` — 회당 ₩33.3→30.0→25.0→22.2→20.0→20.0→18.2. **활성 4단계는 단조감소를 충족한다.** 비활성 구간의 ₩30,000·₩50,000만 ₩20.0으로 동률이지만, 아래 티어 조합 대비로는 이점이 있다(구현 스펙 §1 🚨). ⚠️ 상위 3단계 **활성화 여부는 미결** — 켜면 티어가 7개가 되어 이 기준의 "4개" 전제가 바뀐다. 아래는 개정 전 기준이다: `config/billing.tiers`에 정확히 4행: `{1000,10}/{3000,33}/{5000,60}/{10000,130}`, 나머지 기존 3티어(30000/50000/100000, 2026-08-11 결정분)는 `active:false`로 비활성(데이터 변경, 관리자 콘솔에서 즉시 가능 — **코드 배포 불필요**). `BillingConfigRepository.fetchConfig()`가 `active`만 필터하므로 앱은 자동으로 4개만 그린다(코드 변경 0줄). |
| AC-3 | 리퍼럴 각 +5 (비대칭 지급) | 피초대자: 가입 완료(코드 유효성 확인 성공) **즉시** `freeBalance += 5`. 초대자: 피초대자의 "명함 1장 등록 **AND** AI 1회 사용" 활성화 확인 **시점**에 `freeBalance += 5`. 상한: 초대자 uid당 KST 월 10명/50회 — 넘으면 `creditGrants`에 `type:'referral_referrer', capped:true` 로그만 남기고 지급 안 함(초대자에게 조용히 스킵, 에러 아님). |
| AC-4 | 최초 충전 +5 (1회성) | 최초 ₩1,000 이상 결제(=그 uid의 **첫 번째** `purchases` 문서가 성공 처리되는 순간) 시 `paidBalance`가 아니라 `freeBalance += 5`(무료 성격 보너스이므로 — 환불 시 보호 대상, 3-4절의 2버킷 분리 원칙과 일치). 가드: `aiUsage.firstChargeBonusGrantedAt`. |
| AC-5 | 회차 유효기간 무기한 | `dailyResetAt`/`monthlyResetAt`이 존재해도 wallet 모드 소비 게이팅에는 **관여하지 않는다**(표시 전용, `ai-credit-wallet-spec.md` §3-3). 리셋 로직이 잔액을 건드리는 코드 경로가 하나도 없어야 한다(리뷰 체크리스트 항목). |
| AC-6 | 사용량 표시 "오늘 사용+잔여, 5회미만 충전안내" | `AiUsage`(`lib/core/services/ai_usage_service.dart`)가 `freeBalance+paidBalance` 합산을 `totalRemaining`으로 노출(내부 2버킷은 화면에 분리 노출 금지 — wallet-spec §5). "일 N회/월 N회 남음" 문구 완전 제거. `remaining<5`면 `_LowBalanceBanner`(이미 존재, `ai_connection_modal_view.dart:207-235`)의 TODO(충전 화면 CTA 연결)를 실제로 `AiChargeView`로 라우팅. |

---

## 2. 손대는 곳 — 실제 파일 경로 (grep으로 확인 완료)

### 2-1. 서버 (Cloud Functions, `functions/src/index.ts`)

| 무엇 | 현재 상태(라인) | 필요한 변경 |
|---|---|---|
| `incrementAndCheckUsage`(313~389행) | reset 모드만(일/월 카운터) | `config/billing.model` 분기 추가(`ai-credit-wallet-spec.md` §3-2 그대로) — wallet이면 `freeBalance`→`paidBalance` 순서로 차감 |
| `grantBonusCredits`(845~895행) | 사유 입력 없이 양/음수 지급 | `grantSupportCredits`로 개명, `reason` 필수화, 음수(회수) 경로 제거(wallet-spec §3-5) |
| `generateBriefing`(485~597행) | AI 호출·소비만 | 소비 성공 직후 **초대자 활성화 체크**(4-3절) 추가 — 이 함수가 유일하게 "실제로 AI를 1회 썼다"를 서버가 아는 지점이므로 여기서 판정 |
| (신규) `bootstrapAccount` | 없음 | 로그인 시 1회 호출. 무료체험 지급(기기 가드 포함)+본인 리퍼럴코드 발급+피초대자 코드 redemption을 한 트랜잭션 계열로 처리(4-2절) |
| (신규) `verifyAndGrantPurchase` | 없음(P1-4) | Apple/Google 영수증 검증 → `purchases` 멱등 생성(`tx.create`, transactionId=문서ID) → `paidBalance` 가산 → 최초충전 보너스 판정(AC-4) |
| (신규) 환불 웹훅 처리 | 없음 | App Store Server Notifications(REFUND) / Play RTDN(voidedPurchases) 수신 → `paidBalance`만 회수(wallet-spec §3-4, `freeBalance` 절대 불가침) |
| `nextKstMidnight`/`nextKstMonthStart`(`functions/src/usageReset.ts`) | 이미 있음 | 초대자 월 캡(AC-3) 계산에 `nextKstMonthStart` **재사용** — 새 시간대 로직 안 만든다 |
| 시크릿(`defineSecret`) 패턴 | `geminiApiKey`/`appleSignInKey`(36·42행) | 신규 시크릿 3개 추가: `DEVICE_HASH_SALT`(4절), `APPLE_IAP_SHARED_SECRET` 또는 App Store Connect API 키, `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` |

### 2-2. 규칙 (`firestore.rules`)

| 경로 | 현재 | 필요한 변경 |
|---|---|---|
| `users/{uid}` `clientWritableUserFields()`(125~127행) | `['encryptionKeyB64','profile','updatedAt']` | **변경 없음.** `aiUsage.*`(freeBalance/paidBalance/freeGrantedAt), `referralCode`, `referredBy`, `firstChargeBonusGrantedAt`은 이 목록에 넣지 않는다 — 넣지 않는 것 자체가 "서버 전용"을 보장한다(추가 조치 불필요, wallet-spec §2-5와 동일 원리). |
| `purchases/{purchaseId}`(66~68행) | `allow read: if isAdmin();` | 변경 없음(쓰기는 이미 암묵적 거부, Admin SDK만 씀) |
| `creditGrants/{id}` | **없음** | 신규 추가: `allow read: if isAdmin(); allow write: if false;` |
| `deviceLedger/{deviceHash}` | **없음** | 신규 추가: `allow read, write: if false;`(`appleAuth`와 동일 패턴 — 클라이언트는 절대 접근 불가, 4절 핵심) |
| `referralCodes/{code}` | **없음** | 신규 추가: `allow read, write: if false;`(클라이언트가 코드 존재 여부를 직접 조회하지 못하게 — 코드 유효성 판정은 반드시 `bootstrapAccount` 콜러블을 통해서만) |
| `config/billing`(50~53행) | `read: 로그인 사용자 / write: 관리자` | 변경 없음, `model` 필드 추가는 스키마 자유 문서라 규칙 불변(wallet-spec §2-5) |

### 2-3. 모델 (Dart, 클라이언트)

이 프로젝트에는 별도 `user_model.dart`가 없다 — 사용자 문서는 각 서비스가
Map으로 직접 읽는다(`lib/core/services/ai_usage_service.dart` 128~142행
패턴). 리퍼럴도 같은 패턴을 따른다.

| 파일 | 현재 | 필요한 변경 |
|---|---|---|
| `lib/core/services/ai_usage_service.dart` | `AiUsage` 클래스가 `dailyUsed`/`monthlyUsed`/`bonusCredits`만 읽음(1~44행) | `freeBalance`/`paidBalance` 필드 추가, `config/billing.model` 읽어 wallet/reset 분기(AC-6), `totalRemaining` 계산 로직 교체 |
| (신규) `lib/core/services/referral_service.dart` | 없음 | `AiUsageService`와 동일 패턴 — `bootstrapAccount` 콜러블 호출, 결과(`referralCode`, 지급된 보너스)를 `ValueNotifier`로 노출 |
| (신규) `lib/data/models/referral_model.dart` | 없음 | 얇은 불변 데이터 클래스(`ReferralStatus{code, referredBy, invitedCount}`) — `billing_config_model.dart`와 동일한 스타일(`fromMap`, 안전 폴백) |

### 2-4. 결제 (IAP)

| 파일 | 현재 | 필요한 변경 |
|---|---|---|
| `pubspec.yaml` | `in_app_purchase` **의존성 없음**(전수 확인) | 추가 필요 |
| `pubspec.yaml` | `device_info_plus` **의존성 없음**(4절 기기 지문에 필요) | 추가 필요 |
| (신규) `lib/core/services/iap_service.dart` | 없음 | `in_app_purchase` 스토어 리스너, 구매 완료 시 서버(`verifyAndGrantPurchase`) 호출 후 `consumePurchase` |
| `lib/presentation/features/settings/views/ai_charge_view.dart` | 타일이 항상 비활성("준비중" 배지, `_TierTile` 243~297행) | `config/billing.model=='wallet'`일 때만 탭 가능하게, `IapService` 연결(wallet-spec §9 Phase 0-7과 동일 조건부 활성화) |

### 2-5. AI (`lib/core/services/ai_briefing_service.dart`)

**변경 없음(중요).** 이 파일은 `generateBriefing` 콜러블 호출·에러 매핑만
한다(52~189행) — 소비 로직은 전부 서버 안에 있으므로, 잔액이 부족하면
지금처럼 `resource-exhausted` → `AiQuotaExceededException`으로 그대로
잡힌다(141~144행). 서버 에러 문구만 wallet 모드용으로 바뀐다
(`functions/src/index.ts`의 `HttpsError` 메시지, 2-1절).

### 2-6. UI — 사용량 표시·충전·리퍼럴

| 파일 | 역할 | 변경 |
|---|---|---|
| `lib/presentation/features/settings/views/ai_connection_modal_view.dart` | AI 사용량 상시 표시(121~172행), `_LowBalanceBanner`(207~235행) | 잔여 문구를 AC-6대로 교체, `_LowBalanceBanner`의 기존 TODO 주석("충전 화면 완성되면 CTA 버튼 연결")을 실제로 `AiChargeView` 라우팅으로 해소 |
| `lib/presentation/features/settings/views/ai_charge_view.dart` | 충전 상품 목록(완료), 구매 비활성 | 구매 흐름 연결(2-4절) + 최초충전 보너스 강조 배너(AC-4) 추가 |
| `lib/presentation/features/settings/views/settings_view.dart` | "AI 충전" 진입점 이미 있음(약 525~528행) | 같은 자리에 "친구 초대" 행 추가 |
| `lib/presentation/features/briefing/views/briefing_overlay_view.dart` | AI 대화 포인트 표시 화면(`_points`, 71행) | 응답 성공 직후 리퍼럴 유도 배너 삽입(referral-program-spec.md §3 "가치 체감 직후") |
| (신규) `lib/presentation/features/settings/views/referral_view.dart` | 없음 | 내 초대코드 표시 + `share_plus`(이미 의존성 있음)로 공유 + 코드 직접 입력 필드(5절) |

### 2-7. 설정(config)

| 무엇 | 현재 | 변경 |
|---|---|---|
| `config/billing.freeCredits`/`tiers` | 이미 관리자 콘솔에서 편집 가능 | 값만 AC-1·AC-2대로 재설정(관리자 데이터 작업, 코드 아님) |
| `config/billing.model` | **없음**(wallet-spec에서 설계만 됨) | 신규 필드, 기본값 `'reset'`, 관리자 콘솔에 토글 UI 필요(`docs/admin/admin.js`, wallet-spec §8) |

---

## 3. 왜 이렇게 나눴는지 — reset/wallet과 무관하게 항상 참일 것

리퍼럴은 **wallet 모드 전제**로만 의미가 있다(reset 모드는 애초에 리셋되는
일/월 카운터라 "영구 지급"이라는 개념 자체가 없다). 따라서 **9절 착수
순서는 wallet 전환(P1-5, 이미 설계됨)이 리퍼럴보다 먼저**다 — 확정 스펙
§9의 순서(①원장 ②표시 ③IAP ④리퍼럴)와 일치한다.

---

## 4. 재가입×리퍼럴 무한 증정 루프 — 설계 (가장 중요한 부분)

### 4-1. 공격 시나리오를 구체적으로 적는다

기존에 수용된 위험(memory `ai-quota-reset-on-reregistration`, wallet-spec
§3-1)은 "계정 삭제 → 재가입 → 새 uid → 일/월 카운터 0으로 리셋"이었다.
이건 **그날의 요율 캡을 되찾는 것**뿐이라 손실이 제한적이었다.

리퍼럴이 얹히면 성격이 바뀐다. 공격자가 스크립트로 다음을 반복한다고
하자:

1. 계정 A를 만든다 → 무료체험 **+10**.
2. 계정 A가 자기 자신의(또는 서로 짜고 도는 다른 스크립트 계정의) 초대
   코드로 "가입"한다 → 피초대자 보너스 **+5**. (총 15)
3. 계정 A가 명함 1장 등록 + AI 1회 사용(활성화 조건 충족, 마침 이 AI
   1회는 방금 받은 15 중 1을 쓰면 됨) → **초대자 쪽 계정(B)에 +5** 적립.
4. 계정 A를 탈퇴 → `users/{uid}` 문서 통째로 삭제(개인정보 파기 원칙상
   정상 동작) → 1번으로 돌아가 새 uid로 반복.

**이 루프의 비용은 "새 Google/Apple 계정을 만드는 수고"뿐**이고, 서버
관점에서는 매번 uid가 달라 완전히 새 사용자처럼 보인다. 확정 스펙 §3-3이
"planner가 명시적으로 설계하라"고 지목한 지점이 정확히 이것이다.

### 4-2. 핵심 설계 원칙 — "탈퇴해도 사라지지 않는 것은 개인정보가 아니라 기기 지문 해시 하나뿐"

**무엇을 막고 무엇을 안 막는지 먼저 분리한다.**

- **막지 않는 것**: 명함·프로필·소통기록·이메일·이름 등 **개인정보는
  지금처럼 탈퇴 시 완전 파기**한다(방침·Apple/Play 완전삭제 요구와 계속
  일치). 탈퇴 후 재가입 자체를 막지도 않는다 — 새 사람이 쓰는 것과
  구분할 방법이 없다.
- **막는 것**: "돈과 동등한 지급"(무료체험 10, 피초대자 보너스 5) 두 가지
  **만**. 이 둘은 개인정보가 아니라 **"이 기기에 얼마를 이미 줬는가"라는
  운영 데이터**로 취급하고, 계정과 분리된 별도 컬렉션에 **계정 삭제와
  무관하게** 남긴다.

**신규 컬렉션 `deviceLedger/{deviceHash}`** (Admin SDK 전용, 규칙은 2-2절):

```
deviceHash: string          // = HMAC-SHA256(rawDeviceId, DEVICE_HASH_SALT), 문서 ID와 동일
trialGrantsIssued: number   // 이 기기에서 지급된 무료체험 지급 횟수(cap=1)
referralInviteeRewardsClaimed: number  // 이 기기에서 받은 피초대자 보너스 횟수(cap=1)
firstChargeBonusClaimed: number        // 이 기기에서 받은 최초충전 보너스 횟수(cap=1)
issuedToUids: string[]        // 이 기기로 bootstrapAccount를 호출한 모든 uid(자기초대 판별용, 4-4절)
firstSeenAt / lastGrantAt: Timestamp
```

`deviceHash`는 **서버가 계산**한다(클라이언트가 해시를 만들어 보내면
해시 충돌을 노려 다른 기기인 척 위장하기 쉬워진다) — 클라이언트는 raw
device id만 TLS로 전송하고, 서버가 `DEVICE_HASH_SALT`(신규 시크릿)로
HMAC-SHA256 해서 저장한다. raw id 자체은 로그에도 남기지 않는다(이
프로젝트의 "값이 있는지 없는지만 남긴다" 로깅 원칙, CLAUDE.md 4절).

**`onUserDeletedCleanup`(`functions/src/index.ts` 735~772행)은
`deviceLedger`를 건드리지 않는다** — 이게 이 설계의 핵심이다. `users/{uid}`
와 `aiAuditLogs`는 계정 삭제로 사라지지만, `deviceLedger` 문서는 계정과
무관하게 계속 산다.

### 4-3. 루프가 실제로 어떻게 끊기는지 (연쇄를 명시적으로 추적)

같은 물리적 기기에서 4-1절 루프를 두 번째 돌리면:

1. 새 계정 A'을 만든다. `bootstrapAccount` 호출 → 서버가
   `deviceLedger/{같은 deviceHash}.trialGrantsIssued`를 보니 이미 1 →
   **무료체험 0 지급**(A'의 `freeBalance`는 0으로 시작).
2. A'이 다른 계정 B'의 코드로 "가입"한다 → 서버가
   `deviceLedger.referralInviteeRewardsClaimed`를 보니 이미 1 →
   **피초대자 보너스도 0**.
3. A'의 잔액은 여전히 0. **활성화 조건("AI 1회 사용")을 채울 수 없다** —
   `generateBriefing`은 잔액 0이면 `resource-exhausted`로 거부한다(무료체험
   조차 없으므로 실제 결제 없이는 절대 통과 못 함).
4. 활성화가 없으므로 B'(초대자 역할)도 +5를 받지 못한다.

**즉 피초대자 쪽 지급 하나만 기기 단위로 막아도 초대자 쪽 보상까지
연쇄적으로 막힌다** — "활성화 = 실제 AI 사용"이 요구조건이고, 실제 AI
사용은 잔액이 있어야만 가능하며, 잔액은 기기당 1회로 캡된 지급들의
합이기 때문이다. 별도로 "초대자 계정도 기기별로 추적"할 필요가 없다 —
공격자가 초대자 역할의 새 uid를 계속 만들어도, 그 uid가 실제로 보상을
받으려면 **어떤 초대자든 진짜로 활성화된 피초대자가 필요**하고, 그
피초대자를 만드는 유일한 방법이 다시 기기 캡에 걸린다.

### 4-4. 추가 방어 — 자기초대(같은 기기) 명시적 차단

위 3항만으로 이미 경제적으로 막히지만, "잔액 0으로 시작해도 몇 번 시도해
보다 요행히 지급된다"는 경합 가능성을 없애기 위해 **한 가지를 명시적으로
더 막는다**: `bootstrapAccount`가 리퍼럴 코드를 받으면, 그 코드의 소유자
(초대자) uid가 **호출자와 같은 `deviceLedger.issuedToUids`에 들어 있으면**
(=같은 기기에서 나온 계정끼리의 초대) 즉시 거부(지급 없이 `referredBy`도
기록하지 않음, 조용히 무시 — 에러로 사용자를 막지 않는다).

### 4-5. 정직하게 밝히는 한계 (과장 금지 원칙)

- **완벽하지 않다.** iOS `identifierForVendor`는 "이 개발사(Vendor)의 앱을
  전부 지우면" 리셋되고, Android `androidId`류 값도 공장초기화나 일부
  기기에서 바뀔 수 있다. **목표는 "불가능하게 만드는 것"이 아니라 "물리
  기기 하나 더 구하거나 초기화하는 수고"로 비용을 올리는 것**이다 —
  기존에 이미 채택한 "데이터 전손이라는 자연 억제력" 논리의 연장선이다.
- **에뮬레이터/루팅 기기의 값 위조 가능성**은 남는다. IP 기반 보조 신호
  (확정 스펙 §3-3 "같은 IP 반복 카운트 제한")는 **자동 차단이 아니라
  관리자 콘솔에 이상 패턴(같은 IP에서 짧은 시간 내 다수 가입)을 노출하는
  용도로만** 쓴다 — IP는 공유 와이파이·통신사 NAT로 오탐이 흔해 자동
  차단하면 정상 사용자를 막는다.
- **정책 게이트(사용자 승인 필요)**: `deviceLedger`는 계정 삭제 후에도
  남는 데이터다. `docs/legal/privacy-policy.html`에 "부정 이용 방지를
  위해 기기 식별값의 해시와 지급 이력은 회원 탈퇴 후에도 보관하며, 이
  정보는 특정 개인을 식별하지 않고 명함·프로필 등 개인정보를 포함하지
  않는다"는 취지의 조항을 신설해야 한다(CLAUDE.md 4절 "새 데이터를
  서버로 보내면 방침도 함께 고친다"). **이 조항 초안 작성과 게시는
  다음 착수 단위에 포함하되, 게시는 사용자 승인 후에만 한다.**

### 4-6. 정당한 사용자를 막지 않는 안전판

가족이 기기를 공유해 두 번째 계정이 정말 무료체험을 못 받는 경우가
생길 수 있다. 이미 있는 CS 채널로 흡수한다 — 설정 → 1:1 문의로 요청하면
관리자가 `grantSupportCredits`(2-1절, 사유 필수)로 수동 지급한다. 새 UX를
만들 필요 없이 기존 문의 화면(`lib/presentation/features/settings/views/
inquiry_view.dart`)이 이미 이 경로를 제공한다.

---

## 5. 리퍼럴 귀속 UX — 범위를 좁게 잡는다

Firebase Dynamic Links는 쓰지 않는다(종료 예정, 확정 스펙 §3-1). 정식
Universal Link/App Link(iOS Associated Domains, Android App Links)는
서명·도메인 검증 등 인프라가 추가로 필요해 **1차 범위에서 제외**하고,
아래 두 가지만 구현한다(효과 대비 구현량이 작다는 판단 — 기술적 판단이라
사용자 확인 불필요):

1. **코드 직접 입력**: `referral_view.dart`에 6~8자 영숫자 코드 입력 필드.
   `bootstrapAccount({referralCodeInput})`로 서버 검증.
2. **공유 문구에 코드 포함 + 클립보드 보조**: 이미 의존성에 있는
   `share_plus`로 "[스토어 링크] 초대코드: XXXXXX" 형태 공유 → 앱 최초
   실행 시 클립보드에서 `CS-` 접두 패턴을 감지하면 입력 필드에 자동
   채움(사용자가 눌러서 확인, 자동 제출은 안 함).

정식 딥링크는 v1.1 이후 후속 과제로 남긴다.

---

## 6. 착수 순서 — flutter-developer 위임 단위

CLAUDE.md 4절 기준 검증 등급(전체=배포 직전 실기기 전 항목·부분=수정+영향
범위·자동=`flutter test`/`analyze`)을 각 단위에 표기한다.

| # | 단위 작업 | 선행조건 | 산출물(핵심 파일) | 검증 등급 |
|---|---|---|---|---|
| U1 | `config/billing`에 `model` 필드 추가 + 관리자 콘솔 토글 UI, 서버 `incrementAndCheckUsage`에 wallet 분기 작성(**아직 `model:'reset'`이라 무영향**) | 없음 | `functions/src/index.ts`, `docs/admin/admin.js` | 자동(회귀: reset 모드 동작 100% 동일함을 `flutter test`+함수 유닛테스트로 증명) |
| U2 | `bootstrapAccount` 콜러블 신설(무료체험 지급, 본인 리퍼럴코드 발급 — **리퍼럴 redemption은 U6까지 비워둠**) + 로그인 시 1회 호출 배선 | U1 | `functions/src/index.ts`, 앱의 `AuthGate`(로그인 배선 지점) | 자동 + 부분(로그인 화면) |
| U3 | `grantBonusCredits` → `grantSupportCredits` 개명, `reason` 필수화, 회수 경로 제거 | U1 | `functions/src/index.ts`, `docs/admin/admin.js` | 자동 |
| U4 | 앱 사용량 표시 wallet 분기 — `AiUsage`/`AiUsageService`(freeBalance+paidBalance 합산), `ai_connection_modal_view.dart` 문구 교체(AC-6), `_LowBalanceBanner` CTA를 `AiChargeView`로 연결 | U1 | `lib/core/services/ai_usage_service.dart`, `ai_connection_modal_view.dart` | 부분(AI 연동 모달, 설정 화면) |
| U5 | `device_info_plus`/`in_app_purchase` 의존성 추가, `deviceLedger` 규칙·해시 로직(`DEVICE_HASH_SALT` 시크릿), `bootstrapAccount`에 4-2·4-3·4-4절 기기 가드 적용 | U2 | `pubspec.yaml`, `functions/src/index.ts`, `firestore.rules` | **전체**(보안 규칙·신규 서버 로직 변경 — CLAUDE.md 4절 "저장·복원·마이그레이션·탈퇴·결제"에 해당) |
| U6 | 리퍼럴 코드 redemption(`bootstrapAccount` 확장) + `generateBriefing`에 초대자 활성화 체크(4-3절) 추가 + `referral_view.dart` UI 신설 + `settings_view.dart`/`briefing_overlay_view.dart` 진입점 | U5 | `functions/src/index.ts`, `lib/presentation/features/settings/views/referral_view.dart`(신규), `settings_view.dart`, `briefing_overlay_view.dart` | **전체**(리퍼럴 보상 지급 로직 — 금전 등가) |
| U7 | `verifyAndGrantPurchase`(Apple/Google 영수증 검증) + `iap_service.dart` + `AiChargeView` 구매 버튼 활성화 + 최초충전 보너스(AC-4) | U1, U5(기기가드 재사용) | `functions/src/index.ts`(신규 함수), `lib/core/services/iap_service.dart`(신규), `ai_charge_view.dart` | **전체**(결제) — ⚠️ 스토어 상품ID 등록(사용자 게이트) 선행 필요, 등록 전에는 샌드박스로만 검증 |
| U8 | 환불(refund) 웹훅 처리(App Store Server Notifications / Play RTDN) | U7 | `functions/src/index.ts` | **전체**(결제·환불) |
| U9 | 개인정보처리방침·이용약관 개정 초안 작성(4-5절 기기 지문 조항, 결제·환불 조항) | U5, U7 | `docs/legal/privacy-policy.html`, `docs/legal/terms-of-service.html` | 사용자 검토 후 `firebase deploy --only hosting`(게이트) |

**U1~U4는 reset 모드를 건드리지 않으므로 배포해도 위험이 낮다**
(`ai-credit-wallet-spec.md`의 "가"안 취지와 동일). **U5부터는 보안 규칙·
금전 등가 로직**이라 반드시 전체 테스트(실기기) 대상이다.

---

## 7. 사용자 승인 게이트 총정리

이번 스펙에서 실제 배포 전 사용자 결정/승인이 필요한 지점만 모은다(코드
작업 자체는 게이트 아님):

1. **스토어 소모성 상품 4종 등록**(App Store Connect/Play Console) — U7
   선행조건(기존 P1-1, 그대로).
2. **Apple/Google 결제 검증 자격증명 발급**(App Store Connect API 키 또는
   공유 비밀, Google Play 서비스 계정 JSON) — U7에 필요, Gemini 키
   발급과 같은 성격의 "계정 소유자만 할 수 있는" 작업.
3. **`config/billing.model`을 `'wallet'`로 전환하는 순간**(관리자 콘솔
   클릭 한 번) — 이후 전 사용자에게 실제로 적용되므로 배포 타이밍은
   사용자 확인 후(wallet-spec §9 Phase 1과 동일 원칙).
4. **개인정보처리방침·이용약관 개정 게시**(U9) — `firebase deploy
   --only hosting` 실행은 사용자 승인 후.
5. **`firestore.rules` 실서버 배포**(U5·U6 규칙 변경분) — 배포 자체는
   사용자 확인 후(과거에도 동일하게 게이트해 옴).

---

## 8. 남은 미결 (다음 세션에서 확인)

- `deviceLedger` 트리거링 규모 추정(직원 테스트 규모라 무시 가능하나,
  실사용자 규모에서 컬렉션 문서 수 급증 가능성 — Firestore 비용에 큰
  영향 없음, 문서당 필드 몇 개뿐).
- IAP 샌드박스 테스트는 실기기(Apple)/실기기 또는 라이선스 테스터
  (Google) 필요 — U7 착수 시 QA 계정 준비.
- Android `androidId`/iOS `identifierForVendor` 외에 더 안정적인 대안이
  device_info_plus 최신 버전에 있는지는 **구현 시점에 패키지 문서에서
  직접 확인**할 것(이 프로젝트가 이미 여러 번 "API 문서를 추측하지 말고
  디스커버리 문서에서 확인하라"고 기록해 둔 것과 같은 원칙,
  `functions/src/index.ts` 86~99행 참고).

---

*작성: flutter-planner, 2026-08-14. 참고: `docs/planning/
monetization-referral-implementation-spec-2026-08-14.md`,
`docs/planning/ai-credit-wallet-spec.md`, `docs/marketing/
referral-program-spec.md`, memory `ai-quota-reset-on-reregistration`,
`monetization-direction`.*

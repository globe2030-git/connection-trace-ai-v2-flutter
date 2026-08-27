# 과금(지갑형 wallet) 활성화 구현 계획 — 2026-08-27

> ⚠️ **이 문서는 계획이다. 지금 아무것도 켜지 않는다.**
> 사용자 확정(2026-08-27): *"과금 스위치(`config/billing.model` 필드 신설)는
> 기능 개발이 마무리되고 과금 부분 테스트를 할 때 켠다."* 최종 목표는
> **2026년 10월 말 실사용자 배포**(웹·앱 공통).
>
> 아래 내용은 전부 **실물 코드를 읽어 확인**했다(`functions/src/walletCredits.ts`,
> `functions/src/index.ts`, `firestore.rules`, `docs/admin/admin.js`,
> `lib/core/services/iap_service.dart`·`ai_usage_service.dart`). 코드를
> **실행**해서 확인한 것은 아니므로(콘솔에서 실제로 저장 버튼을 눌러보거나
> 실기기로 소진시켜 본 것이 아님) 문서 안에서 "코드 판독(계산)"과 "실측"을
> 구분해 표시한다.

---

## 0. 이미 되어 있는 것 — 생각보다 많다

코드를 읽어 보니 클라이언트 쪽 잔액 표시 로직은 이미 wallet 모드를 안다.

```
lib/core/services/ai_usage_service.dart:63
  isWalletMode ? freeBalance + paidBalance : remaining + bonusCredits
```

즉 `model`이 `'wallet'`로 바뀌는 순간 설정 화면의 "오늘 사용 가능 횟수"
표시는 **새 빌드 없이** 자동으로 "무료+충전 잔액 합계"로 바뀐다. 이 문서가
찾은 진짜 공백은 아래 1~5절에 있다.

---

## 1. 켜는 순간 무슨 일이 일어나나 (코드 판독)

### 1-0. 🚨 지금 상태로 스위치를 켜려 하면 **켜지지도 않는다**

`docs/admin/admin.js`에는 이미 "과금 모델" 저장 버튼이 있다
(`billingModelSaveBtn`, 427~433·523~527행) — `setDoc(doc(db,"config","billing"),
{model, updatedAt}, {merge:true})`를 부른다.

그런데 `firestore.rules`의 쓰기 검증 함수는 이렇다(69~97행):

```js
match /config/billing {
  allow write: if isAdmin() && isValidBillingConfig(request.resource.data);
}
function isValidBillingConfig(d) {
  return d.keys().hasOnly(['freeCredits', 'tiers', 'updatedAt']) && ...
}
```

`hasOnly`에 **`'model'`이 없다.** Firestore 보안 규칙에서 `merge:true` 쓰기의
`request.resource.data`는 "이 쓰기가 반영된 뒤의 문서 전체"를 가리키는 것으로
알려져 있다 — 즉 기존 문서(`freeCredits`·`tiers`·`updatedAt`)에 `model`을
merge하면 결과 문서에 `model` 키가 하나 더 생기고, `hasOnly`가 그 키를
모르는 키로 보고 **쓰기 자체를 거부한다.**

⚠️ **이건 코드 판독이다(계산) — 콘솔에서 실제로 눌러본 실측이 아니다.**
그래도 결론에 영향을 준다: **firestore.rules를 먼저 고치지 않으면, 관리자
콘솔에서 "과금 모델" 저장 버튼을 눌러도 아무 일도 안 일어난다(permission-denied).**
이것이 "켜기 전에 끝나 있어야 할 것" 0번이다(2절).

### 1-1. rules를 고쳤다고 가정하고 — `model: 'wallet'`이 실제로 저장된 순간

Cloud Function은 `config/billing` 문서를 **매 호출마다** 다시 읽는다(캐시
없음, `index.ts:390`, `:982`) — 그러므로 필드가 생기는 즉시, **재배포 없이도**
다음 호출부터 바로 적용된다.

**① 각 사용자의 다음 로그인(`bootstrapAccount` 호출)**

- 지금까지 `reset` 모드였던 시절에는 `bootstrapAccount`의 지급 블록 전체가
  건너뛰어졌다(`index.ts:1058` `if (billingModel !== "wallet") { ...return; }`)
  — 그 말은 **지금 살아 있는 테스터 전원이 `aiUsage.freeGrantedAt`이 한
  번도 안 찍힌 상태**라는 뜻이다(코드 판독).
- `model`이 `'wallet'`로 바뀌면, **다음 로그인 때 테스터 전원에게
  `config/billing.freeCredits`(현재 실물 값 20)만큼 `freeBalance`가
  지급된다.** 기기 지문(`deviceLedger`) 캡은 지금까지 한 번도 쌓인 적이
  없으므로(reset 모드에서는 이 블록 자체가 안 돎) **전원이 캡 없이 통과한다.**
- 이게 사용자가 미리 알고 있는 문장 그대로다: **"켜는 순간 전 테스터에게
  무료 회차가 지급되고 차감이 시작된다."** 코드로 순서까지 확인됐다.

**② AI 브리핑 호출마다 (`incrementAndCheckUsage`, `index.ts:424~461`)**

```
free 잔액부터 소진 → 0이 되면 paid 잔액 소진 → 둘 다 0이면
WalletExhaustedError → HttpsError("resource-exhausted",
  "AI 사용 가능 횟수를 모두 사용했어요. 충전 후 다시 시도해 주세요.")
```

**③ 🚨 여기서 이번 조사가 새로 찾은 것 — 20회를 다 쓰면 그 계정은 지금
코드로는 관리자도 못 풀어 준다**

`config/billing.model=wallet`이 되면 소진된 사용자가 다시 쓸 방법은 코드상
둘뿐이다.

```
① 결제(IAP)   verifyAndGrantPurchase 는 지금 무조건
              throw HttpsError("unimplemented", "결제 기능은 아직 준비 중이에요.")
              (index.ts:1906~2003, 실제 영수증 검증 블록은 전부 주석 처리된 TODO)
② 관리자 지급  grantSupportCredits 는 aiUsage.bonusCredits 필드에만 쓴다
              (index.ts:1784~1863)
              그런데 wallet 분기(incrementAndCheckUsage)는 bonusCredits를
              아예 읽지 않는다 — bonusCredits는 reset 분기(468행)에서만 쓰인다
```

즉 **"테스터 소진은 관리자 보너스 지급으로 해결된다"는 지금까지 유효했던
사실(메모리 기록)은 `model`이 `wallet`로 바뀌는 순간 깨진다.** 관리자 콘솔의
"보너스 회차 지급" 버튼을 눌러도 잔액에 반영되지 않는다 — 화면에는 성공한
것처럼 보이지만(트랜잭션 자체는 성공) 그 값을 아무도 안 읽는다.

⚠️ 이건 **코드를 끝까지 따라간 판독(계산)**이다. 실제로 버튼을 눌러
`aiAuditLogs`/`aiUsage` 문서를 대조해 본 실측은 아니다 — 그래도 두 함수의
읽기·쓰기 필드가 겹치지 않는 것은 코드 자체가 보여 주므로 신뢰도는 높다.

**남는 유일한 길**: Firebase 콘솔에서 `users/{uid}.aiUsage.freeBalance`(또는
`paidBalance`)를 **관리자가 직접 손으로 고친다.** 감사 기록(`creditGrants`)이
안 남고, 이메일로 찾는 것도 아니라 uid를 알아야 한다 — 지금 있는
"충전 내역 조회" UX와 완전히 다른, 훨씬 거친 경로다.

**④ 사용량 카운터(`dailyCount`/`monthlyCount`)는 wallet 모드에서도 계속 증가한다**

`index.ts:452~455` — 표시용("오늘 사용 N회")으로 남겨 뒀다는 주석이 있지만,
실제로는 **reset 모드가 게이팅에 쓰는 바로 그 필드**를 계속 갱신한다. 이건
당장은 무해하지만 4절(되돌리기)에서 문제가 된다.

### 1-2. 클라이언트

- `ai_usage_service.dart`는 이미 대응돼 있다(0절).
- `iap_service.dart:32` `kIapEnabled = false`(고정) — 구매 버튼은 계속
  "충전 준비 중"으로 남는다. **즉 스위치를 켜도 앱 화면에서 충전은 안 된다**
  — ③에서 확인한 "관리자도 못 풀어 준다"와 합쳐지면, **20회를 다 쓴 테스터는
  앱 안에서 스스로도, 관리자를 통해서도 회복할 방법이 없는 상태**가 된다.

---

## 2. 켜기 전에 끝나 있어야 할 것

| 무엇을 | 왜 필요한가(1절 근거) | 누가 결정 | 누가 실행 |
|---|---|---|---|
| **`firestore.rules`에 `model` 허용** | 지금 스키마로는 저장 자체가 막힌다(1-0) | 기술 판단(개발) | 개발자 — PR + `firebase deploy --only firestore:rules`(배포는 사용자 승인) |
| **관리자 지급 경로를 wallet 대응으로 개편** | `grantSupportCredits`가 지금 `bonusCredits`에 쓰는데 wallet은 그걸 안 읽는다(1-1③) — 이게 없으면 테스트 중 소진된 계정을 콘솔에서만 손으로 고쳐야 한다 | 기술 판단(개발), 단 "부분 테스트를 관리자 지급 없이 갈 것인가"는 사용자에게 확인 권장 | 개발자 |
| **클라이언트 IAP 연동(P1-2)** | `kIapEnabled=false` 고정, `buyConsumable` 부르는 곳 없음, 버튼 항상 비활성 | 착수 시점은 사용자(과금 게이트) | 개발자 |
| **스토어 소모성 상품(SKU) 등록(P1-1)** | `config/billing.tiers`의 `productId`가 전부 비어 있어 결제와 매칭이 안 됨 | **사용자만 가능**(콘솔 조작) — 수수료 15% 신청이 선행돼야 함(Apple Small Business Program) | 사용자 |
| **서버 영수증 검증 완성** | `verifyAndGrantPurchase`가 지금 항상 `unimplemented`(1-1③) | 기술 판단(개발), 단 시크릿 발급은 사용자만 | 개발자(로직) + 사용자(스토어 콘솔에서 `APPLE_IAP_SHARED_SECRET`/`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` 발급) |
| **일·월 한도(`DAILY_LIMIT`/`MONTHLY_LIMIT`) 제거** | P1-5 스펙에 이미 명시 — **지갑 배포와 같은 배포여야** 한다(먼저 지우면 그 사이 상한 공백) | 이미 사용자 확정(HANDOFF) | 개발자 |
| **Functions 배포(`firebase deploy --only functions`)** | 위 항목들이 서버에 실제로 올라가는 시점 | **사용자**(CLAUDE.md 6절 최상위 지침) | 사용자 승인 후 배포 |
| **`config/billing.model` 필드 신설** | 실제 스위치 — 여기서부터 전 테스터 차감 시작(1-1) | **사용자만, 직접 지시**(이미 확정된 원칙) | 사용자 지시 후 관리자 콘솔 |

📌 **순서 주의**: 위 8개 중 앞 6개(rules·관리자 지급·IAP·SKU·영수증 검증·한도 제거)가
전부 끝난 뒤에 Functions를 배포하고, 그 다음에 `model` 필드를 만드는 게
맞는 순서다. **rules만 먼저 배포해도 무해하다**(model 키가 허용되는 것과
실제로 그 값이 wallet인 것은 다른 문제 — rules는 "쓸 수 있게"만 할 뿐 아무도
안 쓰면 그대로 `reset` 폴백).

---

## 3. 과금 부분 테스트를 어떻게 안전하게 하나

**두 층으로 나뉜다 — 스토어가 필요 없는 층과 필요한 층.**

### 3-1. 스토어 없이 되는 것 (지금 코드로도 가능)

- `walletCredits.ts`의 소비 알고리즘(무료 먼저 소진→충전 소진→예외)은
  **이미 순수 함수라 자동 테스트로 덮여 있다**(파일 자체가 "유닛테스트하기
  쉽게 분리했다"고 명시). `flutter test`/`npm test`(functions) 범주.
- "잔액 소진 시 에러 메시지가 뜨는지", "설정 화면 표시가 wallet 합계로
  바뀌는지" 같은 **UI·에러 흐름**은 결제 없이도 검증 가능하다 — 테스트
  계정의 `freeBalance`/`paidBalance`를 Firebase 콘솔에서 직접 숫자를
  넣어 만들면 된다(0을 만들어 소진 상태 재현, 큰 수를 넣어 "충분한" 상태
  재현). **실제 결제가 전혀 필요 없다.**
- 이 층은 **부분 테스트**(CLAUDE.md 3절 정의)로 충분하다 — 스토어 SKU도,
  ID 통일 결정도 필요 없다.

### 3-2. 스토어가 필요한 것 — 실제 "결제→크레딧 지급" 흐름

공식 문서 기준(2026-08-27 확인, 콘솔 실측 아님):

| 플랫폼 | 샌드박스 경로 | 스토어 앱 레코드가 필요한가 |
|---|---|---|
| **iOS** | ① TestFlight의 Sandbox 테스터 계정으로 실제 구매 흐름 재현(청구 안 됨) | ✅ 필요 — App Store Connect에 앱 레코드가 있어야 TestFlight도 있다 |
| **iOS** | ② Xcode **StoreKit Configuration 파일**로 완전 로컬 테스트(2026-08-25 조사 결과, 이 문서에서 재확인) — 기기·시뮬레이터에서 구매 UI부터 서버 검증까지 흉내 가능. "Editor → Save Public Certificate"로 테스트 루트 인증서를 뽑아 서버 검증 로직에 임시로 넣는 방식 | **App Store Connect 앱 레코드 자체가 필요 없다**는 것이 조사 결과 — 단 이건 문서 조사이지 콘솔에서 직접 해 본 실측이 아니다 |
| **Android** | Play Console **라이선스 테스터(License Testing)** — 지정된 이메일 계정은 결제 UI를 그대로 타되 실제 청구가 안 된다(공식 문서, 2026-08-27 웹 검색 확인) | ✅ 필요 — 라이선스 테스터로 구매를 재현하려면 최소 **내부 테스트(internal testing) 트랙에 APK/AAB를 한 번은 올려야** 한다(공식 커뮤니티 문서: "This limitation applies whether you're uploading to internal testing or production tracks") |

📌 **핵심 결론**: iOS는 Xcode 로컬 테스트로 **앱 레코드 없이** 서버 검증까지
시험할 여지가 있다(단, 콘솔에서 실제로 해 봐야 확정). **Android는 그런
우회가 없다** — 실제 구매 흐름을 시험하려면 반드시 Play Console에 앱을
최소 한 번 업로드해야 하고, **그 순간 패키지명이 고정된다.** 이것이 5절의
충돌로 바로 이어진다.

---

## 4. 되돌리기 — 켠 뒤 문제가 생기면 끌 수 있나

### 4-1. 스위치 자체는 즉시, 무해하게 되돌아간다

`resolveBillingModel`(`walletCredits.ts:28`)은 `model`이 `'wallet'`이
아닌 모든 경우(필드 삭제·오타·`'reset'`으로 되돌림)에 **반드시 `'reset'`으로
폴백**한다. 서버가 매 호출마다 문서를 다시 읽으므로(1-1 상단) **재배포 없이
다음 호출부터 즉시** reset 판정으로 돌아간다.

### 4-2. 🚨 그런데 "원상복구"가 아니다 — 이번 조사에서 새로 찾은 위험

wallet 모드에서도 `dailyCount`/`monthlyCount`는 계속 증가한다(1-1④). reset
모드로 되돌리면 그 판정 로직(`index.ts:470` `dailyCount >= DAILY_LIMIT ||
monthlyCount >= MONTHLY_LIMIT`)이 **그 누적값을 그대로 이어받는다.**

```
예: wallet 모드에서 하루에 35번 AI를 쓴 테스터(무료+충전 잔액이 충분해서
    가능했던 것) → dailyCount는 35까지 쌓인 채로 남아 있다
    → model을 reset으로 되돌리는 순간, 그 사용자는 이미
      DAILY_LIMIT(20)·MONTHLY_LIMIT(100)을 넘긴 상태로 즉시 잠긴다
    → "되돌렸는데 오히려 더 막힌다"는 상황이 생길 수 있다
```

⚠️ 이것도 **코드 판독(계산)**이다 — 실제로 wallet을 켜서 35번을 불러 본
실측이 아니다. 그래도 게이팅 조건과 카운터 갱신 코드가 같은 파일 안에
나란히 있어 신뢰도는 높다. **되돌리기 전에 `dailyCount`/`monthlyCount`를
0으로 초기화하는 절차(또는 그 값을 게이팅에서 무시하는 임시 조치)가
필요하다** — 지금 코드에는 그 절차가 없다.

### 4-3. 이미 지급된 잔액은 어떻게 되나

- `freeBalance`/`paidBalance`는 reset으로 되돌려도 **삭제되지 않는다.**
  단지 reset 분기가 그 필드를 안 읽을 뿐, Firestore 문서에는 그대로 남는다.
  나중에 다시 wallet을 켜면 그 값 그대로 이어서 쓰인다(bootstrapAccount의
  `freeGrantedAt` 멱등 가드 덕에 무료체험이 중복 지급되지도 않는다).
- ⚠️ **실제 결제(IAP)로 채워진 `paidBalance`는 성격이 다르다.** 사용자가
  돈을 낸 잔액인데 reset으로 되돌리면 **그 순간 못 쓰게 된다**(reset 분기는
  paidBalance를 아예 안 봄). 테스트 단계(가짜 결제만 있는 동안)에는 문제가
  안 되지만, **실제 결제가 한 건이라도 발생한 뒤에 되돌리면 "돈 받고 못 쓰게
  한다"는 민원이 된다.** 즉 **되돌리기는 "테스트 중 발견"까지만 안전하고,
  실결제 이후에는 사실상 편도(one-way) 결정**이다.

---

## 5. 순서 충돌 — 과금 테스트 vs 개명·패키지 통일 시점

### 5-1. 지금 상태 (실물)

```
Android   com.connectiontrace.connection_trace_ai_flutter   (옛 프로젝트 이름)
iOS       com.creamhouse.connectionsense                    (정돈된 이름)
```

사용자 방침(오늘 확정): **앱 개명과 Android 패키지 ID 통일은 구글 스토어
배포 직전에 한다.**

### 5-2. 공식 문서로 확인한 것 (2026-08-27, 콘솔 실측 아님)

| | 언제 ID가 영구 고정되나 |
|---|---|
| **iOS (App Store Connect)** | **앱 레코드를 만드는 순간** — 번들 ID가 App ID·인증서·프로비저닝에 묶여 그 앱 레코드의 영구 식별자가 된다. 심사 제출·게시는 필요 없다(레코드 생성과 심사 제출은 별개 단계) |
| **Android (Play Console)** | **최초 업로드 순간** — 정식 출시뿐 아니라 **내부 테스트(internal testing) 트랙에 올리는 것만으로도** 패키지명이 그 앱 목록에 고정된다(공식 커뮤니티 문서에 "This limitation applies whether you're uploading to internal testing or production tracks"로 명시) |

### 5-3. 부딪히는가 — **부딪힌다, 최소한 Android는 확실히**

3-2에서 확인했듯 **Android는 실제 결제 샌드박스(라이선스 테스터)를 쓰려면
반드시 Play Console에 앱을 올려야 하고, 그 순간 패키지명이 고정된다.**

```
사용자 방침    "패키지 통일은 스토어 배포 직전에"
과금 테스트    "기능 개발이 마무리되면 켠다" — 스토어 배포보다 훨씬 이를 수 있다
Android 실제 결제 테스트  → Play Console 업로드가 필요 → 그 순간 ID 고정
```

**즉 "Android에서 실제 결제 흐름까지 테스트하려는 시점"이 오면, 그 시점에
이미 패키지명 결정을 강제로 앞당기게 된다** — "스토어 배포 직전"이라는
느긋한 시점이 아니라 "과금 부분 테스트를 시작하는 시점"으로 당겨진다.

iOS는 좀 더 여유가 있을 수 있다(3-2의 Xcode 로컬 경로가 실제로 앱 레코드
없이 되는지는 아직 콘솔로 확인 안 됨) — 하지만 iOS 번들 ID(`com.creamhouse.
connectionsense`)는 이미 "정돈된 이름"이라 통일 대상은 사실상 **Android
쪽**이므로, 결국 문제는 Android 하나로 좁혀진다.

### 5-4. 사용자가 고를 수 있는 선택지 (내일 물을 것)

| | 무엇을 하나 | 대가 |
|---|---|---|
| **ⓐ 지금 Android ID를 그대로 두고 Play Console에 올린다** | 과금 테스트를 계획대로 앞당길 수 있다 | Android ID(`com.connectiontrace.connection_trace_ai_flutter`, 옛 이름·언더스코어)가 **영구히 고정된다** — 나중에 개명해도 패키지명은 절대 못 바꾼다. 통일하려면 새 앱으로 재등록해야 하고 기존 테스터는 데이터를 잃는다 |
| **ⓑ Android ID 통일을 지금(과금 테스트 전으로) 앞당긴다** | ID가 깔끔해진 상태로 스토어에 올라간다 | "통일은 스토어 배포 직전"이라는 오늘 정한 방침을 스스로 앞당기는 것 — Firebase Android 앱을 새로 만들고 `google-services.json`을 교체해야 하고, **테스터는 기존 앱을 지우고 새로 깔아야 한다(데이터 소실)** |
| **ⓒ 과금 테스트를 3-1(스토어 불필요한 층)까지만 먼저 하고, 3-2(Android 실결제 샌드박스)는 ID 결정이 날 때까지 미룬다** | 지금 방침(통일은 배포 직전)을 안 건드린다 | "과금 부분 테스트"의 범위가 반쪽(소진·에러 흐름만)에 머무른다 — 실제 "결제→지급" 배선까지 검증하는 것은 ID 결정 이후로 순연 |

⚠️ **PM 의견은 담지 않는다 — 이건 순수하게 사용자가 고를 문제다.** 다만
ⓒ가 오늘 확정한 두 방침("과금 테스트는 개발 마무리 후" / "통일은 배포
직전") **둘 다 안 건드리는 유일한 선택지**라는 사실은 짚어 둔다.

---

## 6. 요약

- **켜는 순간**: 전 테스터 무료 20회 지급(다음 로그인 시) → AI 브리핑
  호출마다 소진 → 다 쓰면 "충전 후 다시 시도" 에러. **다만 지금 코드로는
  관리자도 클라이언트도 그 사용자를 못 풀어 준다**(1-1③, 이번 조사의 핵심
  발견).
- **켜기 전 남은 것 6건**(2절 표 앞 6줄) + Functions 배포 + `model` 신설,
  총 8단계 중 **개발이 끝내야 할 것은 6건**(rules·관리자 지급 개편·IAP
  연동·SKU 매칭 코드·영수증 검증·한도 제거), **사용자만 할 수 있는 것은
  SKU 등록·시크릿 발급·배포 승인·스위치 지시.**
- **부분 테스트는 두 층**: 스토어 없이도 되는 것(잔액 소진·에러 흐름,
  지금 코드로 가능)과 스토어가 필요한 것(실제 결제→지급, Android는
  Play Console 업로드가 반드시 선행돼야 함).
- **되돌리기는 즉시 되지만 원상복구는 아니다** — `dailyCount`/`monthlyCount`
  누적값이 reset 판정에 그대로 이어져 **되돌린 직후 오히려 잠기는 사용자가
  생길 수 있다**(4-2, 이번 조사의 두 번째 핵심 발견). 실결제 이후의 되돌리기는
  사실상 편도다.
- **순서 충돌은 실재한다**(5절) — Android 실결제 샌드박스 테스트가
  Play Console 업로드를 요구하고, 업로드는 패키지명을 영구 고정한다.
  "통일은 스토어 배포 직전"이라는 오늘 방침과 "과금 테스트는 개발 마무리
  후 곧"이라는 오늘 방침이 **Android에서는 같은 사건(Play Console 업로드)에
  묶여 있다.**

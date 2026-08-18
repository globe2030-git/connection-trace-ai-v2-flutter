# AI 사용 회차(크레딧) — 리셋형 → 지갑형(wallet) 전환 설계서

작성일: 2026-08-12 (원장·히스토리 요구사항 반영해 개정)
작성자: 서비스 기획/PM (flutter-planner)
상태: **문서만 작성, 코드 구현은 아직 시작 안 함.** 실제 구현은 이 문서의
"결정 필요" 항목에 사용자가 답한 뒤 `flutter-developer`에게 섹션 단위로
위임한다.

> 참고 문서: `connection-sense-assets/문서/커넥션센스_스펙_크레딧원장_충전_2026-08-11.md`
> (저장소 밖 — `/Volumes/X31/Claude/` 아래, 이하 "인계 스펙")가 이 문서의
> 출발점이다. 이 문서는 ① 사용자가 2026-08-12에 원문으로 확정한 목표 모델
> ② 같은 날 추가로 확정한 원장·히스토리 요구사항 ③ "가" 안(지금 라이브를 안
> 바꾼다) 하에서의 플래그 기반 스위치 설계 ④ 정확한 서버 트랜잭션 알고리즘
> ⑤ 전환 체크리스트를 구체화한다.

---

## 0. 목표 모델 (사용자 확정, 2026-08-12 원문 1차)

> "무료횟수는 앱 설치 시 처음 주는 거야. 그 무료 회수가 소진되면 충전을
> 안내하는 거고, 다시 날짜가 지났다고 무료가 생기지 않아. 다만, 관리자가
> 고객 응대를 하다가 불만을 처리하기 위해 관리자 화면에서 등록하는 경우만
> 무료에 추가해서 넣는 거야. 그것도 소진되면 무료는 없어지고 충전을 해야만
> 생기는 거야. 충전도 날짜가 바뀌었다고 충전잔량이 다시 더해지는 것이
> 아니라 그냥 사용할 때마다 차감되는 거고, 충전을 하면 그때 잔여 횟수에
> 충전횟수를 더하는 거야."

**정리**: 리셋 없는 선불 지갑(wallet). 잔액은 "가입 시 무료(1회성) + 관리자
CS 지급 + 충전"이 전부 한 통에 쌓이고, AI 호출마다 1씩 차감되며, 0이 되면
충전 안내만 뜬다. 날짜가 바뀌어도 아무것도 다시 채워지지 않는다.

## 0-1. 원장·히스토리 요구사항 (사용자 확정, 2026-08-12 원문 2차)

**앱(사용자 관점)**:
- 잔량은 **합산된 숫자 하나만** 보여준다(무료 지급분 + 고객응대 무료분 +
  충전 구매분을 전부 더한 값). 사용자에게 출처 구분을 노출하지 않는다.
- **충전 구입 내역 화면은 앱에 만들지 않는다** — 스토어(App Store/Play)에서
  이미 확인 가능하므로 중복 화면 불필요.

**관리자(콘솔 관점)**:
- 관리자가 무료 상품·충전 상품을 등록한다(기존 `config/billing`의
  `freeCredits`/`tiers` 개념을 그대로 연장).
- 사용자 조회 시 **지급 히스토리가 출처별로 구분**돼 보여야 한다: ①
  무료 지급(가입 시 1회성) ② 고객응대 무료 지급(관리자가 불만 처리 등으로
  지급) ③ 충전을 통한 지급(IAP 구매).
- 각 히스토리 항목에 **지급일시 + 계정**을 반드시 남긴다.
- **고객응대 무료 지급은 "사유"를 입력받아 함께 저장**한다 — 정산·감사·
  분쟁의 근거.
- 히스토리는 **관리자만** 본다.

**이 요구가 데이터 모델에 미치는 영향**: "사용자에게는 합산 하나"라는
요구와 "무료 먼저 소진, 그다음 충전"(0절)이라는 소비 순서 요구, 그리고
"환불 시 어느 분을 회수하는지"를 함께 만족하려면, **잔액을 사용자에게는
하나로 보이게 하되 서버 내부에서는 성격별로 나눠 관리하는 것이 정답**이라고
판단했다 — 2-1절에서 이 결론과 트레이드오프를 상세히 설명한다.

## 0-2. 진행 방향 — "가" 안 (지금 라이브를 안 바꾼다)

이유(사용자 확정): 충전 화면 구매 버튼이 아직 비활성이고 스토어 상품ID도
미등록이다. 지금 무료를 1회성으로 바꾸면 **돈 낼 방법이 없는데 무료만
끊긴 막다른 앱**이 되고, 직원 테스트(AI 사용성·비용 실측)가 중단된다.

**따라서 이 설계의 핵심 제약은 "전환이 스위치 켜기가 되게 만드는 것"이다.**
아래 1~8절이 그 설계이고, 9절이 실제로 스위치를 켜는 순서다.

---

## 1. 왜 플래그 방식을 채택하는가 (사용자 질문에 대한 답)

사용자가 "플래그 방식이 오히려 복잡도를 키운다고 판단되면 근거와 대안을
제시해도 된다"고 했으므로 먼저 이 판단부터 적는다.

**결론: 플래그(`config/billing.model: "reset" | "wallet"`) 방식을 채택한다.**
복잡도를 키우지 않는 이유는, reset 모드와 wallet 모드가 **서로 다른
Firestore 필드를 쓰도록 분리**하면 두 모드가 코드상 완전히 독립된 분기가
되기 때문이다.

- reset 모드는 지금 코드(`dailyCount`/`dailyResetAt`/`monthlyCount`/
  `monthlyResetAt`/`bonusCredits`)를 **한 글자도 안 건드리고 그대로 둔다.**
- wallet 모드는 **새 필드**(2-2절)만 쓴다.
- 플래그는 "어느 분기로 들어갈지"만 결정한다. 분기가 필드를 공유하지
  않으므로, 플래그를 만들다가 실수로 reset 모드 동작이 깨질 위험이
  구조적으로 없다 — 이게 "가" 안이 요구하는 "테스트 중단 없음"을
  코드로 보장하는 방법이다.
- 대안(플래그 없이 그냥 나중에 한 번에 전환)은 지금과 똑같이 위험하다 —
  전환 당일 여러 파일(서버·앱·규칙)을 동시에 배포해야 하고 되돌리기도
  어렵다. 플래그는 그 "동시 배포"를 "미리 배포해 둔 죽은 코드 켜기"로
  바꿔서 당일 리스크를 없앤다. 복잡도는 필드가 몇 개 더 생기는 정도이고,
  reset 모드 필드는 wallet 전환 후에도 삭제할 필요가 없어(비용 없음)
  정리 부채도 남기지 않는다.

---

## 2. 데이터 모델

### 2-1. 잔액 구조 — 출처 2버킷(무료/충전) 내부 분리 + 사용자에겐 합산 1개 표시

**단일 숫자(인계 스펙 결정①의 원안)만으로는 0-1절의 세 요구를 동시에
못 만족한다.** 왜인지 트레이드오프로 설명한다.

| 방식 | 소비 순서(무료 먼저) | 환불 시 무료분 보호 | 구현 복잡도 |
|---|---|---|---|
| (a) 단일 잔액(`creditBalance`) 하나 | 못 지킴 — 어느 게 무료였고 어느 게 유료였는지 잔액만으론 구분 불가 | 못 함 — 환불 시 얼마를 깎아야 무료를 안 건드리는지 알 수 없음 | 가장 단순 |
| (b) 지급 건마다 개별 잔액(FIFO, 구매 1건=행 1개) | 정확 | 정확 | 과함 — 소비 시마다 여러 행을 순회해야 함 |
| **(c) 성격별 2버킷**(`freeBalance` + `paidBalance`) | **정확**(버킷 우선순위로 강제) | **정확**(환불은 `paidBalance`만 건드림) | 필드 2개 추가, (b)보다 훨씬 단순 |

**채택: (c).** 0-1절에서 사용자가 명시적으로 "무료 먼저 소진"과 "환불
시 어느 분을 회수하는지"를 함께 요구했으므로, 이건 이제 "인계 스펙
결정①"의 답이 (a)에서 (c)로 바뀐 것이다 — 사용자에게 보여주는 화면은
여전히 `freeBalance + paidBalance`를 더한 숫자 하나뿐이라 0-1절의 "사용자는
합산 하나만 본다" 요구도 그대로 지킨다. 내부에 필드가 2개 있다는 사실은
서버·관리자 콘솔에만 존재하고 앱 화면·API 응답 어디에도 두 숫자를 따로
노출하지 않는다(5절).

### 2-2. `users/{uid}.aiUsage` 필드 전체 (reset + wallet 공존)

| 필드 | 소유 모드 | 설명 |
|---|---|---|
| `dailyCount`/`dailyResetAt` | reset | 기존 그대로. wallet 모드에서는 **게이팅에 안 쓰지만 "오늘 사용" 표시용으로 계속 갱신**(3-3절) |
| `monthlyCount`/`monthlyResetAt` | reset | 기존 그대로, wallet 모드에서도 표시용으로 계속 갱신 |
| `bonusCredits` | reset(레거시) | 기존 그대로 유지. wallet 전환 시 `freeBalance` 초기값 계산에 **1회만** 참조되고(3-6절) 이후로는 그 사용자에 한해 안 읽힘 — 필드 삭제는 안 함(비용 없음, 나중 데이터 정리 과제로 남김) |
| **`freeBalance`** | wallet(신규) | 무료 성격 잔액(가입 시 무료 + 고객응대 무료 지급의 합). 서버 전용 쓰기. 소비 시 **이쪽을 먼저** 깎는다 |
| **`paidBalance`** | wallet(신규) | 충전(구매) 성격 잔액. 서버 전용 쓰기. `freeBalance`가 0일 때만 깎인다. 환불은 **이 필드에서만** 회수 |
| **`freeGrantedAt`** | wallet(신규) | 가입 시 무료 1회성 지급이 끝났는지의 멱등 가드(Timestamp, 없으면 미지급) |

사용자·앱에 보이는 "잔여 횟수"는 항상 `freeBalance + paidBalance`다(5절).

### 2-3. 원장 컬렉션

**`purchases/{transactionId}`**(기존 스키마 유지, 문서 ID만 변경 권장 —
3-4절) — `priceKrw, credits, status, purchasedAt, platform, transactionId,
uid, email`. 결제(충전) 회계 원장. 서버만 쓴다(이미 규칙에 있음). 스토어
구매내역과 대응되는 원장이라 **사용자에게는 노출하지 않는다**(0-1절 —
스토어에서 이미 볼 수 있음).

**`creditGrants/{id}`**(신규) — 잔액이 변한 모든 사건의 감사 추적이자
0-1절이 요구한 "출처별 히스토리" 그 자체.
```
type: 'signup_free' | 'support_free' | 'purchase' | 'adjust'
amount: number        // +면 지급, -면 회수(환불·정정)
bucket: 'free' | 'paid'  // 이 사건이 어느 버킷에 반영됐는지
uid: string
email: string | null
grantedAt: Timestamp   // 지급일시(0-1절 필수 요구)
by: string | null      // support_free/adjust면 지급한 관리자 이메일, 그 외 null
reason: string | null  // ⚠️ type='support_free'면 필수(서버가 강제, 3-5절)
note: string | null    // purchase면 purchases 문서ID(=transactionId)를 여기 남겨 상호 참조
balanceAfter: {free: number, paid: number}  // 이 사건 직후 두 버킷 값 — CS 문의 시 즉시 재구성용
```
`type`은 0-1절이 요구한 세 가지(`signup_free`/`support_free`/`purchase`)를
그대로 쓰고, `adjust`는 그 세 가지에 안 들어가는 관리자 정정(환불로 인한
차감 등)에만 쓰는 보조 타입으로 추가했다 — 필수 요구 3종과 별개다.

`purchases`와 역할이 겹쳐 보이지만 목적이 다르다: `purchases`는 **결제
회계**(가격·상품·정산, 스토어 대응), `creditGrants`는 **잔액 변동
히스토리**(사용자별 조회 화면이 직접 읽는 테이블). 충전이 발생하면
**둘 다** 쓴다(3-4절 트랜잭션에서 원자적으로).

### 2-4. `config/billing` 확장

기존 필드(`freeCredits`, `tiers`)는 그대로 두고 최상위에 추가:
```
model: 'reset' | 'wallet'   // 신규, 기본값 'reset'
```
`freeCredits`는 **지금 서버가 안 읽는다는 사실이 이미 확인됨**(functions
전수 검색 결과 참조 0건) — wallet 모드에서 처음으로 실제 효과를 낸다.
관리자 콘솔에 이 사실을 문구로 못박는 안내가 필요하다(6절).

`freeCredits`/`tiers`는 이미 "관리자가 무료 상품·충전 상품을 등록한다"는
0-1절 요구를 구조적으로 충족하고 있다(2026-08-11에 이미 구축돼 배포됨) —
이번 설계에서 새로 만들 필요가 없다.

### 2-5. Firestore 규칙 변경

- `creditGrants/{id}` 신규 — `purchases`와 동일 패턴: `allow read: if
  isAdmin(); allow write: if false;`(서버 Admin SDK 전용 — 히스토리는
  "관리자만 본다"는 0-1절 요구를 규칙 레벨에서 강제).
- `users/{uid}`의 `clientWritableUserFields()`는 수정 불필요 —
  `freeBalance`/`paidBalance`/`freeGrantedAt`이 그 목록에 없으므로
  자동으로 서버 전용이 된다(추가 조치 없이 안전).
- `config/billing`은 기존 규칙(`read: 로그인 사용자 / write: 관리자`)
  그대로 재사용 가능 — 스키마 자유 문서라 `model` 필드 추가에 규칙
  변경이 필요 없다.

---

## 3. 서버 로직

### 3-1. 무료 초기 지급 (멱등) — "가입당 1회"를 어떻게 보장하나

**호출 시점**: 매 로그인 시 앱이 새 콜러블 `ensureFreeCreditsGranted()`를
1회 호출한다(기존 패턴과 동일 위치 — `AuthGate`가 uid를 리포지토리에
배선하는 지점, `rebackupAllContacts()`가 로그인마다 불리는 것과 같은
자리). **매 로그인마다 부르지만 실제 지급은 서버가 멱등 가드로 딱 한
번만 하게 만든다** — "매 로그인마다 주면 무한 무료가 된다"는 사용자의
우려는 여기서 막는다.

**왜 로그인 시점(반응형)이 아니라 가입 시점처럼 동작해야 하는가**: AI
브리핑을 처음 누르는 순간까지 잔액이 0으로 보이면 "무료 10회" 안내가
거짓말이 된다. `AiUsageService.fetch()`는 화면 진입 시 바로
`users/{uid}.aiUsage`를 읽으므로, 로그인 직후 지급을 끝내 둬야 사용자가
AI 화면에 처음 들어갔을 때부터 "잔여 10회"가 보인다.

**멱등 알고리즘** (트랜잭션):
```
tx.get(userRef)
if aiUsage.freeGrantedAt != null:
    return  // 이미 지급됨 — 아무 것도 안 함 (매 로그인 호출을 여기서 무해화)

carryOver = aiUsage.bonusCredits ?? 0   // 레거시 필드 1회성 이월(3-6절), 무료 성격이라 free 버킷으로
freeCredits = config/billing.freeCredits  // 같은 트랜잭션 밖에서 미리 읽어 옴
newFree = (aiUsage.freeBalance ?? 0) + freeCredits + carryOver
tx.set(userRef, {
  aiUsage: { freeBalance: newFree, freeGrantedAt: now }
}, merge: true)
tx.create(creditGrantRef, {
  type: 'signup_free', amount: freeCredits, bucket: 'free',
  grantedAt: now, uid, email, by: null, reason: null,
  balanceAfter: { free: newFree, paid: aiUsage.paidBalance ?? 0 },
})
if carryOver > 0:
    tx.create(creditGrantRef2, { type: 'adjust', amount: carryOver, bucket: 'free',
      note: 'bonusCredits 레거시 이월', grantedAt: now, uid, email, ... })
```

**재가입(계정 삭제→재가입) 시 재지급되는 것은 이미 수용된 동작이다** —
계정 삭제는 `users/{uid}` 문서 자체를 지우므로 재가입은 새 uid, 새
`freeGrantedAt`(없음)이 되어 다시 지급된다. 이건 A안(수용, memory
`ai-quota-reset-on-reregistration`)과 정확히 같은 성격의 우회이고, 이미
"데이터 전손이라는 자연 억제력에 의존한다"고 정리돼 있다. **이 스펙에서
새로 막지 않는다** — 사용자 지시대로 그대로 둔다.

### 3-2. 소비 (`incrementAndCheckUsage` 확장) — 무료 먼저, 그다음 충전

```
billingModel = (config/billing.model 읽기, 트랜잭션 밖, 실패 시 'reset' 폴백)

if billingModel == 'wallet':
    tx.get(userRef)
    free = aiUsage.freeBalance ?? 0
    paid = aiUsage.paidBalance ?? 0
    if free + paid <= 0:
        throw resource-exhausted, "AI 사용 가능 횟수를 모두 사용했어요. 충전 후 다시 시도해 주세요."

    if free > 0:
        newFree, newPaid = free - 1, paid       // 무료부터 소진
    else:
        newFree, newPaid = free, paid - 1        // 무료 없으면 충전분

    // 표시용 카운터는 계속 갱신(오늘 사용 N회 표시가 그대로 동작하게, 3-3절)
    dailyCount/monthlyCount 갱신 로직은 기존 그대로 실행(리셋 시각 계산 포함)
    tx.set(userRef, { aiUsage: {
        freeBalance: newFree, paidBalance: newPaid,
        dailyCount: ..., dailyResetAt: ...,
        monthlyCount: ..., monthlyResetAt: ...,
    }}, merge: true)
else:  // 'reset' — 지금 코드 그대로, 한 글자도 안 바뀜
    (기존 incrementAndCheckUsage 본문)
```
`config/billing.model` 조회 실패(문서 없음 등)는 **반드시 'reset'으로
폴백**한다 — 실패 시 wallet으로 폴백하면 장애 상황에서 조용히 무제한
과금 모델로 전환될 위험이 있고, reset 폴백은 지금과 동일한(이미 검증된)
동작이라 안전하다.

**소비는 `creditGrants`에 기록하지 않는다** — 매 AI 호출마다 히스토리
행이 쌓이면 0-1절이 요구한 "지급 히스토리"가 소비 로그로 뒤덮여 못
쓰게 된다. 소비 기록은 기존 `aiAuditLogs`가 이미 담당하고 있으므로
그대로 둔다(관리자의 "사용량·로그" 탭, 4절 참고).

### 3-3. "오늘 사용" 표시를 wallet 모드에서도 유지하는 이유

`dailyCount`/`dailyResetAt`을 wallet 모드에서도 계속 갱신하는 이유는
**게이팅에는 안 쓰되 정보 표시(설정 → AI 사용량 시트의 "오늘 사용 N회")를
공짜로 재사용**하기 위해서다. 새 필드를 안 만들어도 되고, 앱 쪽 코드도
"오늘 사용" 부분은 그대로 둘 수 있다. 다만 이 값은 UTC 기준으로 자정이
리셋되는 기존 버그(9절)의 영향을 그대로 받으므로, "오늘"이라는 라벨의
정확도가 필요하면 9절의 TZ 수정과 묶어서 처리해야 한다.

### 3-4. 충전 적립 (IAP, P1-4의 정확한 계약)

인계 스펙보다 구체적인 멱등 알고리즘을 제시한다. **`purchases` 문서 ID로
`transactionId`를 그대로 쓰고, Firestore 트랜잭션 안에서 `tx.create()`로
가드한다** — "먼저 조회해서 있으면 스킵" 방식(check-then-act)은 동시
재시도 시 경합 창이 생기지만, `tx.create()`는 Firestore가 같은 문서를
동시에 만들려는 두 트랜잭션 중 하나를 자동으로 충돌시켜 재시도하게
하므로 훨씬 안전하다.

```
purchaseRef = db.collection('purchases').doc(transactionId)  // ID = transactionId

db.runTransaction(tx => {
  existing = tx.get(purchaseRef)
  if existing.exists:
      return existing.data()  // 이미 처리됨 — 그대로 반환, 중복 지급 없음

  // (영수증 검증은 이 트랜잭션 밖에서 먼저 끝내 둔다 — 외부 HTTP 호출을
  // 트랜잭션 안에 넣지 않는다)
  tierCredits = config/billing.tiers에서 productId → credits 매핑(트랜잭션 밖에서 조회)

  userSnap = tx.get(userRef)
  newPaid = (userSnap.aiUsage.paidBalance ?? 0) + tierCredits   // 충전은 paid 버킷

  tx.create(purchaseRef, { priceKrw, credits: tierCredits, status: 'paid',
    purchasedAt: now, platform, transactionId, uid, email })
  tx.set(userRef, { aiUsage: { paidBalance: newPaid } }, merge: true)
  tx.create(creditGrantRef, {
    type: 'purchase', amount: tierCredits, bucket: 'paid',
    grantedAt: now, uid, email, by: null, reason: null,
    note: transactionId, balanceAfter: { free: userSnap.aiUsage.freeBalance ?? 0, paid: newPaid },
  })

  return { credits: tierCredits, newPaid }
})
```
이 설계는 **reset 모드에서도 그대로 켜 둘 수 있다**(잔액 필드가
`paidBalance`라 reset 모드의 소비 로직과 안 겹친다) — 다만 사업적으로는
"결제 버튼 자체를 wallet 모드가 될 때까지 비활성 유지"가 맞다(0-2절의
"가" 안 취지 — 결제가 가능해지는 시점과 무료가 끊기는 시점을 같은
타이밍으로 묶어야 "막다른 앱"이 안 생긴다).

**환불(refund) 처리 — 왜 2버킷 분리가 여기서 결정적인가**: App Store
Server Notifications(`REFUND`) / Google Play RTDN(`SUBSCRIPTION_
CANCELED` 계열이 아니라 소모성은 `voidedPurchases` API)로 환불 통지가
오면:
```
refundRef = purchases/{transactionId}
tx.get(refundRef) → credits, uid 확인
paid = users/{uid}.aiUsage.paidBalance ?? 0
clawback = min(credits, paid)   // paidBalance만 건드림 — freeBalance는 절대 안 건드림
tx.set(userRef, { aiUsage: { paidBalance: paid - clawback } }, merge)
tx.set(refundRef, { status: 'refunded' }, merge)
tx.create(creditGrantRef, { type: 'adjust', amount: -clawback, bucket: 'paid',
  note: `refund: ${transactionId}`, ... })
```
`clawback`이 `credits`보다 작으면(이미 그 구매분을 다 써버린 경우) 회수는
`paidBalance`가 0이 되는 선에서 멈춘다 — **무료로 받은 크레딧은 어떤
경우에도 환불로 인해 줄어들지 않는다.** 이건 소모성 재화 환불의 표준
관행(다 쓴 재화는 못 돌려받지만, 최소한 "환불이 무료분을 갉아먹는" 억지는
안 생기게 한다)과도 맞는다. 정확한 환불 **정책**(며칠 이내만 허용, 부분
소비 시 거부 등 법적 문구)은 P1-3 범위이며 이 문서는 그 정책을 구현할 수
있는 데이터 모델까지만 준비한다.

### 3-5. 고객응대 무료 지급 — `reason` 필수, 관리자만

`grantBonusCredits`를 **`grantSupportCredits(email, amount, reason)`으로
개명**하고 wallet 모드에서는 `freeBalance`에 가산(+ `creditGrants`
`type=support_free`, `bucket=free`, `by=관리자 이메일`, `reason=입력값`
기록)하도록 만든다.

- `reason`은 **서버가 강제**한다 — `amount<=0`이면 거부하던 기존 검증에
  `!reason?.trim()`이면 거부하는 검증을 추가한다. UI(관리자 콘솔 입력란)
  만으로 강제하면 나중에 다른 경로(스크립트, API 직접 호출)로 사유 없이
  지급될 수 있으므로 **서버 레벨에서 막는 게 원칙**(이 프로젝트가 이미
  여러 번 "코드는 맞는데 실물이 틀리다"를 겪은 것과 같은 유형의 방어).
- 회수(음수 지급)는 이 함수에서 더 이상 안 받는다 — 회수는 항상 특정
  사유(환불 등)가 있는 `adjust` 타입이므로 3-4절의 환불 경로나 별도
  `adjustCredits(email, amount, reason, bucket)` 콜러블로 분리하는 걸
  권장한다(지급과 회수를 같은 함수에 negative amount로 섞으면 "관리자가
  왜 깎았는지"가 `support_free` 사유 입력 UI에 안 맞게 강제되는 문제가
  생긴다).
- 이름을 바꾸는 이유: 함수 이름이 실제 동작과 어긋나면 다음 사람이 또
  오해한다(이 프로젝트가 이미 여러 번 겪은 유형의 문제) — `bonusCredits`
  라는 이름 자체도 "리셋 후 남는 오버플로우"라는 옛 의미를 담고 있어
  wallet 세계에선 부정확하다.

### 3-6. 레거시 `bonusCredits` 이월 — 왜 특별 처리가 필요 없는가

3-1절의 멱등 알고리즘이 `carryOver = aiUsage.bonusCredits ?? 0`을 무료
지급 트랜잭션 안에서 **`freeBalance`로** 자동 흡수한다(레거시
`bonusCredits`는 전부 관리자가 무료로 지급했거나 리셋 오버플로우였던
값이라 성격상 무료 버킷이 맞다). 즉 **"기존 계정에 무료를 얼마나
이월할지"라는 질문의 기본값이 설계에서 자연히 나온다**: 모든 기존 계정은
`freeGrantedAt`이 비어 있으므로 wallet 전환 후 첫 로그인 때 "표준 무료
N회 + 그동안 관리자가 지급해 둔 bonusCredits"를 그대로 받는다. 이건 7절
"결정 필요 ①"의 기본 옵션(B안)이다.

---

## 4. 관리자 콘솔

### 4-1. 어느 탭에 넣을지 — 기존 코드 확인 결과로 수정한 제안

**코드로 직접 확인한 현재 상태**(`docs/admin/admin.js`, 읽기만 함): 무료
회차 지급 UI는 이미 **"충전 관리" 탭이 아니라 "사용량·로그" 탭**
(`#tab-usage`, `loadUsageLogs()`, 501~570행 부근)에 있다. 이메일로 조회하면
오늘/이번 달 카운트와 `bonusCredits` 잔액이 뜨고, 바로 아래 "무료 회차
지급" 입력창(회차 숫자만, **사유 입력란 없음**, 음수 입력으로 회수도
가능)이 같은 카드 안에 있다(`grantBonusCreditsFn` 호출, 540~566행). 즉
"사용자 조회 → 그 자리에서 지급"이라는 흐름이 이미 이 탭에 구축돼 있다.

**제안(위 사실을 반영해 앞선 초안에서 정정)**: 새 히스토리도 **이
기존 흐름을 그대로 확장**하는 쪽을 권장한다 — 별도 탭이나 "충전 관리"
탭으로 옮기면 관리자가 이미 익힌 위치가 바뀌고, 조회 로직도 중복 구현해야
한다.
- `usageLookupBtn` 결과 카드에 `creditGrants`를 `grantedAt` 내림차순으로
  붙인다(서버: `getUserUsage` 응답에 `history: CreditGrant[]` 추가하거나
  전용 콜러블 신설 — 구현 단계에서 택일).
- 각 행: 타입 배지(무료 지급/고객응대 무료 지급/충전) + 회차 + 지급일시.
  `support_free`면 **사유**와 지급한 관리자를 함께 표시. `purchase`면
  가격·거래ID(=`purchases` 문서로 교차 링크)를 함께 표시.
- 기존 "무료 회차 지급" 폼에 **사유 입력란을 필수로 추가**하고, **음수
  입력(회수)은 이 폼에서 제거**한다 — 회수는 항상 사유가 다른 별개
  사건(환불 등)이므로 3-5절처럼 지급(`grantSupportCredits`, 항상 양수 +
  사유 필수)과 회수(`adjustCredits`, 환불 경로 등 별도)를 분리하는 게
  맞다. 지금 폼처럼 "지급"과 "회수"를 부호 하나로 뭉쳐 두면 회수할 때도
  사유 입력을 강제하게 만들기 애매해진다.

**"충전 관리" 탭은 결제 회계 전용으로 남긴다**: 그 탭의 "충전 내역
조회"(`purchases` 이메일 검색)는 그대로 두는 걸 권장 — 스토어 정산·CS
결제 확인이라는 좁은 목적에 맞게 이미 잘 동작하고 있고(2-3절에서
`purchases`가 결제 회계, `creditGrants`가 잔액 히스토리로 역할을 나눴다),
"사용량·로그" 탭에 통합 히스토리가 생기면 "이 결제가 실제로 크레딧에
반영됐는지"는 `creditGrants`의 `note`(=transactionId)로 교차 확인하면
된다.

### 4-2. `freeCredits`/`tiers` — 이미 있는 것 재사용

0-1절의 "관리자가 무료 상품·충전 상품을 등록한다"는 요구는 2026-08-11에
이미 구축된 `config/billing.freeCredits`/`tiers` + 관리자 콘솔 "충전 상품
설정" 화면이 그대로 충족한다. 새로 만들 게 없다 — 다만 `freeCredits`가
지금 서버에서 안 읽힌다는 사실(6절)만 문구로 못박으면 된다.

---

## 5. 앱 표시 (`AiUsageService`/`AiUsage`)

- 사용자에게는 **`freeBalance + paidBalance`를 더한 합산 숫자 하나만**
  보여준다(0-1절 요구). `getUserUsage`/`AiUsageService.fetch()` 응답에
  두 버킷을 각각 노출할 필요가 없다 — 서버가 이미 더한 값을 주거나, 앱이
  받은 두 숫자를 화면에 그리기 직전에 더하고 개별 값은 아예 안 쓴다(개별
  값을 API에 남겨 두더라도 **화면 어디에도 분리 표시하지 않는다**는 걸
  구현 시 명시할 것).
- **충전 구입 내역 화면은 만들지 않는다**(0-1절) — 지금 설계에도 그런
  화면이 없으며, 앞으로도 추가하지 않는다.
- `config/billing.model`을 읽어(이미 `BillingConfigRepository`가
  `config/billing`을 읽고 있으므로 `model` 필드만 추가로 파싱하면 됨)
  화면을 분기한다.
- **wallet 모드**: "오늘 남음 · 이번 달 남음" 2타일 표시를 없애고(리셋
  개념 자체가 없으므로), **"오늘 사용 M회 · 잔여 N회"**로 표시(3-3절의
  표시용 카운터 재사용, N = 합산값). 잔여 5회 미만이면 "충전 필요" 안내
  + 충전 화면 진입점(이미 `monetization-direction` 메모에 있는 계획과
  일치 — 이번에 처음 나온 결정이 아니라 이 스펙으로 공식화하는 것).
- **reset 모드**: 지금 화면 그대로. `AiUsage` 클래스의 공개 API
  (`totalRemaining`/`exhausted`/`lowBalance`)는 그대로 유지하고, 내부
  계산만 모드별로 분기하면 화면 위젯 쪽 수정을 최소화할 수 있다 —
  구현 시 `flutter-developer`에게 이 방향을 명시할 것.
- 잔액이 0인데 AI 브리핑을 시도하면, 서버 에러 메시지(3-2절)를 그대로
  화면에 보여주고 충전 화면 버튼을 함께 노출한다("0이면 거부 + 충전
  안내" 요구사항).

---

## 6. 관리자 콘솔 — 지금 당장 필요한 조치 (코드 변경 없이 문서로 먼저 못박기)

이번 세션은 코드를 안 건드리므로, **당장 할 수 있는 것은 이 문서에
사실을 명시하는 것까지다**: `config/billing.freeCredits`는 현재 (2026-08-12
기준) 서버 코드 어디에서도 읽지 않는다(전수 검색 결과 참조 0건,
`functions/src/index.ts` 전체). 관리자가 이 값을 "10"으로 저장해 둬도
지금은 **완전히 무효**하며, wallet 모드가 켜져야 처음으로 효력이 생긴다.
**다음 개발 세션에서 admin.js의 무료 제공 횟수 입력란 옆에 이 사실을
안내 문구로 추가하는 작업을 짧은 후속 작업으로 등록한다**(아래 9절
Phase 0에 포함). ⚠️ `docs/admin/` 파일 수정은 이번 세션 범위 밖 — 다른
세션이 그 디렉터리의 디자인 작업을 진행 중이므로, 이 요구사항은 그
세션과 조율한 뒤 반영한다.

---

## 7. 결정 필요 (사용자가 답할 것)

이미 사용자가 확정한 항목(재논의 불필요, 확인용으로만 재기재):
- 리셋 없음, 무료는 1회성 + 관리자 지급만 추가, 충전은 누적(0절).
- 사용자에겐 합산 잔액 하나만, 앱에 구매내역 화면 안 만듦, 관리자는
  출처별 히스토리(무료/고객응대무료/충전) + 지급일시·계정, 고객응대
  지급은 사유 필수, 히스토리는 관리자만(0-1절).
- "가" 안 채택 — 지금 라이브 안 바꿈(0-2절).
- 재가입 시 무료 재지급 허용(A안, 이미 수용됨, 3-1절).
- 플래그 방식 채택(1절).
- 잔액 구조는 2버킷(무료/충전) 내부 분리로 확정(2-1절 — 0-1절 요구를
  만족하는 유일한 방식이라 선택의 여지가 크지 않다고 판단, 이견 있으면
  재검토).

**① 전환 시점 기존 계정 무료 부여 방식 — ✅ 결정됨(2026-08-12, 사용자 확정)**

**기본값 그대로 간다. 예외 없이 전원 이월.** 즉 직원 테스터를 포함한 모든
기존 계정이 wallet 전환 후 첫 로그인 때 표준 무료 N회 + 그동안 쌓인 관리자
지급분을 자동으로 받는다(3-6절의 멱등 알고리즘에서 코드 추가 없이 자연히
나오는 동작).

**왜 이렇게 정했나**: 직원 테스터가 10명 내외(`config/testers`)라 표준 무료
회수(10회 안팎)를 한 번 더 주는 비용이 무시할 만하고, 예외를 두면 전환
시점에 `freeGrantedAt`을 미리 채우는 1회성 스크립트가 필요해진다 — **"스위치
켜기"로 끝내겠다는 이 설계의 목표에 예외 작업을 하나 더 얹는 셈**이라 얻는
것보다 잃는 게 크다.

**따라서 전환 체크리스트에 이 항목은 추가되지 않는다.** 5절 Phase 1은 그대로
`config/billing.model`을 바꾸는 것으로 끝난다.

**아직 답이 필요한 것: 없음.**

---

## 8. 관리자 콘솔 코드 조율 필요 사항 (다른 세션 영역, 이번엔 요구사항만)

`docs/admin/`는 다른 세션이 디자인 작업 중이라 이번 세션은 읽기만 하고
수정하지 않았다. 아래는 그 세션(또는 다음 개발 세션)에 전달할 구체적
요구사항 목록이다.

1. "사용량·로그" 탭(`#tab-usage`)의 사용자 조회 카드에 `creditGrants`
   히스토리 리스트 추가(4-1절).
2. 같은 카드의 기존 "무료 회차 지급" 폼(540~566행)에 **사유(reason)
   입력란을 필수 필드로 추가**하고, **음수 입력(회수) 경로를 제거**
   (4-1절 — 현재는 사유 입력란이 없고 음수로 회수까지 겸하는 구조임을
   코드로 확인함).
3. `freeCredits` 입력란("충전 관리" 탭) 옆 "현재 서버가 이 값을 읽지
   않습니다" 안내 문구(6절).
4. `config/billing.model` reset/wallet 토글 UI("충전 관리" 탭, 9절
   Phase 1의 실제 스위치).

---

## 9. 전환 체크리스트

### Phase 0 — 지금부터 언제든 안전하게 할 수 있는 것 (reset 모드 무영향)

1. 이 스펙 확정(7절 결정 ① 답변 받기).
2. 서버: wallet 분기 작성(3-1~3-6절) + `config/billing.model` 필드
   추가(기본값 `'reset'`) — **배포해도 reset 모드 동작 100% 동일**함을
   회귀 테스트로 증명 후 배포. `creditGrants` 규칙 추가.
3. 서버: `ensureFreeCreditsGranted` 콜러블 추가 + 앱이 로그인 시 호출하게
   배선(reset 모드에서는 사실상 아무 일도 안 함 — 무해).
4. 서버: IAP 적립 함수(3-4절) + 환불 처리 골격 작성(호출부가 없으니
   배포해도 영향 0, P1-4 선행 작업으로 미리 준비).
5. 서버: `grantBonusCredits` → `grantSupportCredits`로 개명 + `reason`
   필수화(3-5절).
6. 앱: wallet 모드 화면 분기(5절) 작성해 두되, `config/billing.model`이
   `'reset'`인 한 기존 화면 그대로 보이는 것을 확인. 합산 표시만 하고
   구매내역 화면은 만들지 않는다.
7. 앱: 충전 화면 구매 버튼을 `config/billing.model === 'wallet'`일 때만
   활성화하도록 조건 추가(지금은 항상 비활성 상태 유지).
8. 관리자 콘솔(8절 목록, 다른 세션과 조율 후 진행): 히스토리 조회 확장,
   사유 필수 입력란, `freeCredits` 미사용 안내, `model` 토글 UI.
9. **권장(별도, wallet 전환과 무관, 지금 해도 됨)**: 10절의 TZ 버그 수정.
10. IAP 클라이언트 연동(P1-2) + 서버 영수증 검증(P1-4) 실제 구현·QA —
    **wallet 전환 전에 반드시 끝나 있어야 한다**(0-2절의 "가" 안 취지).
11. 스토어 소모성 상품 등록 + 수수료 15% 신청(P1-1) — 마찬가지로 wallet
    전환 전에 끝나 있어야 한다.
12. `aiAuditLogs` 실측으로 티어별 회차 최종 확정, `config/billing.tiers`에
    최종값 입력(freeCredits도 이때 최종 확정치로 갱신).

### Phase 1 — 전환 당일(정식 스토어 출시와 같은 타이밍이 자연스러움)

이 순서를 반드시 지킬 것 — 뒤바뀌면 정식 사용자가 갑자기 막히거나
회사 비용이 새는 방향으로 사고가 난다.

1. **스토어 심사 통과 확인**(App Check가 정식 경로로 검증 가능해지는
   전제조건, P0-9의 잔여 절반).
2. **App Check 재강제**(`enforceAppCheck: true`) — P0-9 문서에 이미
   "스토어 배포 후 재확인" 잔여로 등록돼 있음, 이 타이밍에 처리.
3. **`config/testers` 비우기** — 정식 출시 후엔 전원이 스토어 경유이므로
   테스터 화이트리스트 우회가 더 이상 필요 없음.
4. **`config/billing.model`을 `'wallet'`로 변경**(관리자 콘솔 클릭 한 번).
   이 순간부터 모든 사용자가 다음 로그인 때 무료 지급 + wallet 소비로
   전환된다.
5. **충전 버튼 활성화 확인**(Phase 0-7에서 이미 조건부로 걸어 뒀다면
   자동으로 켜짐 — 별도 배포 불필요).
6. 실사용자 몇 명으로 E2E 확인: 신규가입 무료 지급 → 소진 → 충전 안내 →
   IAP 결제 → 잔액 반영 → 관리자 콘솔에서 그 계정의 히스토리 3종(무료/
   고객응대/충전)이 실제로 구분돼 보이는지, 전부 실기기로.

**P0-11(DAILY_LIMIT 10 복귀)과의 관계**: wallet 모드가 켜지면 reset
모드의 `DAILY_LIMIT`/`MONTHLY_LIMIT`은 더 이상 어떤 사용자에게도 적용되지
않는다(3-2절 분기가 wallet일 때 그 경로 자체를 안 탐). 즉 **P0-11은
"wallet 전환 완료 시 자동으로 무의미해진다."** 다만 wallet 전환이 예상보다
늦어지고 그사이 정식 스토어에 reset 모드로 먼저 나가야 하는 상황이
생기면, 그때는 P0-11을 그대로 별도 처리해야 한다(즉 "wallet 전환이
P0-11을 대체한다"가 아니라 "먼저 오는 쪽이 이긴다"). ⚠️ **`chore/p0-11-
daily-limit-10` 브랜치(커밋 `f5d8b1b`)는 그대로 병합하면 안 된다** — 이
브랜치는 `bonusCredits`/날씨 문구 개선 등 이후 main에 들어온 변경 이전
시점에서 갈라져 나가, 병합하면 그 기능들을 되돌리는 diff가 된다(직접
diff로 확인함). 되돌릴 때는 이 낡은 브랜치를 쓰지 말고 현재 main 기준으로
`DAILY_LIMIT`/`dailyLimit` 상수만 새로 고칠 것.

### 롤백

`config/billing.model`을 `'wallet'` → `'reset'`으로 되돌리면 소비 로직은
즉시 예전 방식으로 돌아간다. 단 이건 **응급 브레이크**이지 완전한
원상복구가 아니다 — wallet 모드에서 쌓인 `freeBalance`/`paidBalance`/충전
이력은 그대로 남지만 reset 모드 코드는 그 필드를 안 읽으므로, 되돌리는
순간 "돈 주고 산 크레딧이 화면에 안 보이는" 상태가 된다(데이터 유실은
아니지만 사용자 경험상 심각한 문제). **롤백은 결제가 이미 열린 뒤에는
쓰지 않는다는 전제**로 설계했다 — Phase 1의 순서(결제를 먼저 열고 나서
wallet을 켠다)를 지키면 롤백이 필요할 상황 자체가 최소화된다.

---

## 10. 부수 효과 — 시간대(TZ) 버그

**현재 버그**: `functions/src/index.ts:369` `nextMidnight.setHours(24, 0,
0, 0)`가 **Cloud Functions Node 런타임의 로컬 시간대(TZ 미지정 시 기본
UTC)** 기준으로 계산된다. 한국 시각 자정이 아니라 **UTC 자정(=한국시간
오전 9시)**에 무료 한도가 초기화된다. `nextMonth` 계산(`new
Date(now.getFullYear(), now.getMonth() + 1, 1)`)도 같은 이유로 월 경계
근처(한국시간 00~09시)에서 하루 어긋날 수 있다.

**wallet 전환이 이 버그를 자동으로 없애는가**: **소비 게이팅 관점에서는
그렇다** — wallet 모드는 리셋 자체가 없으므로 "언제 리셋되는지"가 더 이상
의미 있는 질문이 아니다. 다만 **3-3절 설계대로 `dailyCount`/
`dailyResetAt`을 "오늘 사용" 표시용으로 wallet 모드에서도 계속 갱신하기로
했으므로**, 표시 문구의 "오늘"이라는 경계는 wallet 전환 후에도 계속 UTC
기준으로 어긋난 채 남는다 — 돈이 걸린 버그에서 **표시 정확도 버그**로
격하될 뿐, 완전히 사라지지는 않는다.

**권장: wallet 전환과 별개로 지금 바로 고친다.** 근거:
1. **수정이 한 줄**이다 — `functions/src/index.ts` 최상단에
   `process.env.TZ = "Asia/Seoul";`을 추가하면 Node의 `Date` 로컬 시간
   메서드(`setHours`/`getFullYear`/`getMonth` 등)가 전부 KST 기준으로
   바뀐다(Cloud Functions Gen2/Cloud Run은 이 환경변수를 제약 없이
   존중한다).
2. **wallet 전환이 언제 끝날지 모른다** — "가" 안을 택한 이유 자체가
   "결제 인프라가 갖춰질 때까지 시간이 걸린다"는 것이었다. 그 사이
   매일 사용자의 무료 한도가 실제 자정보다 9시간 이르게 초기화되는
   채로 방치하면, 그만큼 회사가 의도한 것보다 더 많은 무료 사용을
   내주고 있다는 뜻이다(비용 누수 방향).
3. **wallet 로직과 독립적**이다 — reset 모드 코드 안에서 끝나는 수정이라
   이 스펙의 나머지 설계와 충돌하거나 선행조건이 되지 않는다. 별도의
   작은 PR로 지금 진행해도 무방하다고 판단한다(사용자 승인 시
   `flutter-developer`에게 바로 위임 가능한 크기).

**검증 방법**: 배포 후 `getUserUsage`가 반환하는 `dailyResetAt`이 그날
한국시간 자정(`YYYY-MM-DDT15:00:00.000Z`, UTC 표기로 오후 3시가 한국시간
자정)으로 찍히는지 확인.

---

## 11. 이번 세션에서 하지 않은 것 (범위 밖, 다음 작업)

- 실제 코드 구현 전부(서버/앱/규칙/관리자 콘솔) — 이 문서는 설계만.
- 환불 **정책**의 법적 문구(청약철회 조건, 환불 가능 기간 등) — P1-3
  범위, 이 문서는 정책을 담을 수 있는 데이터 모델만 준비했다.
- `docs/admin/` 파일 실제 수정 — 다른 세션이 관리자 콘솔 디자인 작업
  중이라 이번 세션은 건드리지 않았다(작업 지시 제약). 8절에 요구사항만
  정리해 뒀다.
- 6절/8절의 "안내 문구·UI 추가"는 문서로만 못박고 실제 코드 반영은
  다음 작업.

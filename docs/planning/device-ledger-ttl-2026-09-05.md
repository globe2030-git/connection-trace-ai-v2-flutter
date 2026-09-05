# `deviceLedger` 보관 기간 30일 — 켜는 순서와 명령 (2026-09-05)

> **결정**: `deviceLedger/{deviceHash}` 문서를 **30일** 보관하고 파기한다
> (globe2030님 확정, 2026-09-05).
>
> **왜**: 이 장부는 **탈퇴로 지우지 않는다** — 지우면 재가입으로 무료체험
> 상한이 초기화돼 장부를 둔 의미가 사라진다(`onUserDeletedCleanup` 이 일부러
> 안 건드린다, 스펙 §4-2). 그런데 지우는 사유가 **하나도 없었다** — 실측:
> `grep -rn "expiresAt" functions/src` 에 `deviceLedger` 는 **0건**이었다.
> 사실상 무기한 보관이고, 개인정보 보호법 §21①(목적 달성 시 지체 없이 파기)과
> 부딪힌다.
>
> **이 문서가 하는 일**: 켜는 **명령**과 **순서**를 적어 둔다. 🚨 **실행은
> globe2030님이 한다** — `gcloud`·`firebase deploy` 는 규약 6장이 *"전 팀·전
> 세션에 적용된다"* 고 못 박은 자리다. 이 문서를 쓴 세션은 **아무것도 배포하지
> 않았다.**

---

## 0. 순서 — **배포가 먼저, 정책이 나중** ⚠️ 2026-09-05에 뒤집혔다

> 🚨 **이 절은 처음에 정반대로 쓰여 있었다. 지우지 않고 무엇이 틀렸는지 남긴다.**
>
> 런북(`번호확인-알림톡-배포-런북`) 0단계를 인용해 *"🚨 TTL 은 소급되지 않는다.
> 함수를 먼저 배포하면 그 사이 쌓인 장부 문서는 `expiresAt` 이 있어도 정책이
> 없어 영영 안 지워진다"* 라고 적고, **① 정책 → ② 배포** 순서를 넣었다.
>
> **그 전제가 틀렸다.** 자세한 것은 아래 3절의 원문 인용 둘.

```
① 함수를 배포한다        expiresAt 을 심는 코드가 올라간다
② 첫 문서가 생긴다        그때부터 모든 새 문서가 필드를 갖는다
③ 그다음 TTL 을 켠다      ②의 문서들도 함께 대상이 된다
```

⭐ **필드를 갖고 있는 문서는 정책을 나중에 켜도 지워진다.** 그러므로 ①~③ 사이에
쌓인 것은 잃지 않는다. 안 지워지는 것은 `expiresAt` 이 **아예 없는** 문서뿐이고,
그것은 **배포 이전**에 쓰인 것이다 — **경계는 「정책」이 아니라 「배포」다.**

📌 **그리고 이 순서라야 애초에 켤 수 있다.** ③ 시점에는 컬렉션 그룹이 이미
존재한다 — 문서가 0건이면 콘솔 드롭다운에 뜨지도 않는다(3절 실측).

⚠️ **런북과 다르게 두지 않았다** — 런북 0단계도 같은 날 같은 근거로 함께 고쳤다
(추가 700). **둘이 다르면 그 자체가 함정이 된다.**

---

## 1. TTL 정책을 켜는 명령

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=deviceLedger \
  --enable-ttl
```

확인:

```bash
gcloud firestore fields ttls list --collection-group=deviceLedger
```

⚠️ **프로젝트를 먼저 확인한다** — `gcloud config get-value project`.
잘못된 프로젝트에 켜면 아무 일도 안 일어나고, **켠 줄 알고 넘어간다.**

📌 `phoneSendLedger` 도 같은 모양의 명령을 쓴다. 이미 켜져 있는지는 위
`list` 로 본다 — **켜져 있다는 기억이 아니라 조회 결과로 판단한다.**

---

## 2. 그다음 함수 배포

```bash
npx --yes firebase-tools@15.29.0 deploy --only functions
```

⚠️ `/opt/homebrew/bin/firebase` 는 `deploy` 만 SIGKILL 로 죽는다 — `npx` 로
우회한다(런북 `firebase deploy 가 죽는다` 절).

⚠️ 파이프를 걸지 않는다. `... | tail` 로 받으면 **종료 코드가 `tail` 것이라
실패를 놓친다**(규약 4-2). 로그 파일로 받는다.

---

## 3. 🚨 옛 문서는 이 작업으로 안 지워진다

TTL 은 **문서에 `expiresAt` 필드가 있어야** 동작한다. 배포 이전에 만들어진
`deviceLedger` 문서에는 그 필드가 없으므로 **정책을 켜도 그대로 남는다.**

```
배포 뒤에 새로 쓰이는 문서   expiresAt 이 붙는다 → 30일 뒤 파기 ✅
배포 전에 이미 있던 문서     필드가 없다 → 영영 안 지워진다 ❌
```

### ⭐ 그런데 **지금 그 대상이 0건이다** (2026-09-05 실측)

```
deviceLedger      0 건  — 서버 최상위 컬렉션 13개 목록에 **아예 없다**
phoneSendLedger   0 건  — 같음
cardSources       0 건  — #833 의 규칙이 미배포라 쓰기가 거부되고 있다
ocrStats         12 건  (살아 있는 계정 7 · 탈퇴한 계정 5)
```

📌 **출처**: globe2030님이 콘솔에서 컬렉션 그룹 드롭다운을 열어 **둘 다 목록에
없음**을 확인하셨고, **PM 이 Firestore REST 로 세어** 교차 확인했다. `ocrStats`
의 7/5 분해는 **개발A 가 잰 값**이다. ⚠️ **이 문서를 쓴 세션이 잰 값이 아니다** —
옮겨 적으면서 출처를 함께 옮긴다(규약 4절). **의심스러우면 다시 재라.**

⭐ **그래서 「지금 배포하면 필드 없는 문서가 하나도 안 생긴다.」** 미룰수록
사각지대가 커진다 — **이 창은 지금만 열려 있다.**

⚠️ **왜 0건인가**: `bootstrapAccount` 는 `config/billing.model === "wallet"`
일 때만 이 장부를 쓴다. 지금은 `reset` 이라 지급 블록 자체를 건너뛴다.

📌 **혹시 옛 문서가 생긴다면** 정리는 개발A 의 서버 정리 도구(#858)가 맡는다 —
다만 **「켰으니 다 지워진다」로 읽으면 안 된다.**

### 🚨 그리고 「TTL 은 소급되지 않는다」는 **틀린 말이었다**

이 문서의 0절이 런북을 인용해 *"TTL 은 소급되지 않는다"* 라고 적었는데,
**공식 문서 두 곳이 정반대를 말한다**(2026-09-05 확인, 원문):

- Firebase — *"Applying a TTL policy on an existing collection group results in
  a bulk deletion of all expired data according to the new TTL policy."*
- Cloud — *"If a document has an expiration time in the past and you add a new
  TTL policy to the collection, the document will be deleted within 24 hours of
  when the TTL policy finishes setup and becomes active."*

📌 **출처**: `docs.cloud.google.com/firestore/native/docs/ttl` ·
`firebase.google.com/docs/firestore/ttl` — **2026-09-05 확인, 원문 그대로 옮겼다.**
PM 이 `docs.cloud.google.com/firestore/docs/ttl` 로 따로 받아 **한 글자도 다르지
않음**을 교차 확인했다.

⬜ **안 잰 것**: `gcloud` 가 **문서 0건인 컬렉션 그룹**을 받아 주는지. 공식 문서는
**필드**가 미리 없어도 된다고만 적고(*"you can designate a field that you plan to
add later"*) **컬렉션 그룹에 대해서는 된다고도 안 된다고도 말하지 않는다.**
확실히 아는 길은 실제로 돌려 보는 것뿐인데 **안 돌렸다**(실행은 globe2030님 권한).
🚨 **이 줄을 지우지 말 것** — 지우면 「확인한 것」으로 읽힌다.

**필드를 갖고 있는 문서는 정책을 나중에 켜도 지워진다.** 안 지워지는 것은
`expiresAt` 이 **아예 없는** 문서뿐이고, 그것은 **코드 배포 이전**에 쓰인 것이다.
즉 **경계는 「정책」이 아니라 「배포」다.**

⭐ 그래서 실제로 가능한 순서는 **배포 → 첫 문서 → TTL** 이고, 그 시점에는
컬렉션 그룹이 이미 존재하므로 **드롭다운 문제도 사라진다.**
📌 자세한 경위와 런북 정정은
[`번호확인-알림톡-배포-런북-2026-09-04.md`](./번호확인-알림톡-배포-런북-2026-09-04.md)
0단계에 있다(추가 700).

---

## 4. ⚠️ 대가 — 30일마다 무료체험 상한이 풀린다

`DEVICE_TRIAL_GRANT_CAP = 1` 은 **「이 기기에 영구히 1회」**를 전제로 설계된
값이다. 보관 기간이 생기면 문서가 사라진 뒤 `trialGrantsIssued` 가 0으로
읽혀, **같은 기기에서 30일마다 무료체험을 다시 받을 수 있다.**

```
지급량   DEFAULT_FREE_CREDITS = 20   (freeGrant.ts:35 · 실측)
주기     30일마다
```

📌 **globe2030님이 이 대가를 알고 고르셨다.** 근거는 **지금 과금이 꺼져
있다는 것**이다 — `config/billing.model` 필드가 없어 `reset` 으로 떨어지고
(`walletCredits.ts`), `reset` 모드에서는 `bootstrapAccount` 의 지급 블록
자체를 건너뛴다. **즉 지금은 장부에 문서가 쌓이지도 않는다.**

🚨 **과금을 켤 때 이 자리를 다시 봐야 한다.** 켜는 순간부터 「30일마다 1회」가
실제 비용이 된다. 선택지는 셋이고 **결정은 globe2030님이다.**

```
① 기간을 늘린다
② 상한을 「기간당」이 아니라 「누적」으로 바꾼다 (해시 대신 카운터를 남긴다)
③ 그대로 둔다 (비용을 감수한다)
```

⚠️ **「과금이 꺼져 있다」는 이 문서를 쓴 세션이 잰 값이 아니다** — 코드의
폴백 경로(`walletCredits.ts`)와 `RESUME.md` 기록을 읽은 것이다. **서버
실물(`config/billing` 문서의 `model` 필드 유무)은 조회하지 않았다.**
**켜기 전에 반드시 다시 잰다.**

⭐ **다만 방증이 하나 생겼다** — `deviceLedger` 가 **0건**이다(위 3절). 이
장부는 `model === "wallet"` 일 때만 쓰이므로, **0건이라는 것은 지금까지 한 번도
wallet 이었던 적이 없다는 뜻**이다. ⚠️ **그래도 「지금 꺼져 있다」의 직접 증거는
아니다** — 조회한 값은 조회한 순간의 것이고, 이 방증은 과거만 말한다.

---

## 5. 무엇이 검사로 잠겨 있고 무엇이 안 잠겨 있나

```
✅ 잠김    보관 기간이 30일인 것            deviceLedger.test.ts
✅ 잠김    쓸 때마다 다시 계산되는 것        (미끄러지는 창)
❌ 안 잠김  index.ts 가 실제로 expiresAt 을 심는 것
```

🚨 **`index.ts` 를 import 하는 테스트가 0건이다**
(`grep -l 'from "./index"' functions/src/*.test.ts` → 0). 실측으로 확인했다:
**`expiresAt` 줄과 그 import 를 함께 지워도 272건이 전부 통과한다.**

```
줄만 지우면        빌드가 깨진다(안 쓰는 import) — 컴파일러가 잡는 것이지 검사가 아니다
줄+import 지우면    272 통과 · 0건 잡힘        ← 사각지대
```

📌 그래서 **배포 뒤 서버 실물로 확인해야 한다.**

```
과금을 켠 뒤 계정을 하나 만들고
  → deviceLedger/{hash} 문서에 expiresAt 이 있는지
  → 그 값이 대략 30일 뒤인지
```

---

작성: 개발C 세션 (2026-09-05) · 배분: PM(터미널) · 결정: globe2030님

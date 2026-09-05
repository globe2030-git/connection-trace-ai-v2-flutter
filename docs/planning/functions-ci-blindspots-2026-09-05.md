# `functions/` 자동 검사가 못 보는 것 (2026-09-05 점검)

> PM 배정. `#830` 이 `npm test` 를 CI 에 붙였는데 — **무엇을 안 덮는지는 아무도
> 안 봤다.** 그것을 재고 적는다.
>
> ⚠️ **이 문서는 고치지 않았다.** `functions/src` 는 한 줄도 안 건드렸다.
> 🚨 **그리고 이 기계에서 `npm test` 를 못 돌렸다**(아래 3번) — 그래서
> **「테스트가 몇 건인가」는 이 문서가 재지 않았다.** 재려면 CI 로그를 봐야 한다.

---

## 요약 — 넷이 나왔다

```
① index.ts 3,195줄 · 진입점 16개 · 테스트 0        왜 못 하는지까지 드러났다
② 순수 모듈은 전부 덮였고 **배선이 안 덮였다**      이 저장소가 이미 겪은 모양이다
③ npm test 가 파일 이름을 **손으로 나열**한다       #830 과 같은 뿌리가 한 층 아래에
④ 🚨 이 노트북에 **node 가 없다**                  런북에도 없다
```

---

## 1. `index.ts` — 전체의 38%에 테스트가 없다

```
functions/src 전체        8,315줄
index.ts                  3,195줄  (38%)
index.ts 의 테스트         **없다**
테스트가 없는 소스         index.ts · adminEmails.ts  (나머지 18개는 전부 있다)
```

📌 `adminEmails.ts` 는 상수 목록이고 `tool/check_admin_sync.py` 가 따로 본다.
**남는 것은 `index.ts` 하나다.**

### 진입점 16개 — 전부 여기 산다

```
onCall             generateBriefing · bootstrapAccount · storeAppleRefreshToken
                   getUserUsage · grantSupportCredits · verifyAndGrantPurchase
                   socialSignIn · revokeMySessions · phoneOtpRequest · phoneOtpConfirm
                   adminOtpRequest · adminOtpConfirm · adminSessionHeartbeat
onRequest          kakaoUnlinkWebhook                      ← 공개 HTTP
onDocumentCreated  onSocialUnlinkRequested
onDocumentDeleted  onUserDeletedCleanup
```

⚠️ **과금(`verifyAndGrantPurchase`·`grantSupportCredits`)과 인증
(`socialSignIn`·`phoneOtp*`·`adminOtp*`)이 전부 이 안에 있다.**

### 🚨 왜 못 덮나 — 모듈 로드 부작용

```
functions/src/index.ts:134   initializeApp();
```

**import 하는 순간 Admin SDK 가 초기화된다.** 그래서 `node --test` 로 이 파일을
불러오면 그 자체가 실행된다. 📌 **못 하는 것이 아니라 「지금 구조로는 못 하는
것」이다** — 진입점을 얇게 만들고 판단을 모듈로 빼면 덮인다. 실제로 **다른 18개가
이미 그 모양이다.**

---

## 2. 판정은 덮였고 **「부르는지」는 안 덮였다**

이 저장소가 이미 겪은 결함 모양이다 — `CLAUDE.md` 4장 표의
*"재시도 로직이 죽어 있음 — **서비스는 정상, 부르는 쪽이 없음**"*.

### 실제 예 — 공개 웹훅

```
kakaoUnlink.ts       adminKeyMatches() · appIdAllowed() · parseKakaoUnlinkPayload()
                     → kakaoUnlink.test.ts 가 덮는다  ✅
index.ts             그것들을 **부르고** 401/400 을 낸다
                     → 아무도 안 덮는다               ❌
```

⭐ **판정 함수를 지워도 테스트는 빨개지지만, 「부르는 줄」을 지우면 조용하다.**
`kakaoUnlinkWebhook` 은 **인증 없는 공개 HTTP 진입점**이라 그 줄이 유일한 문지기다.

### 진입점별 인증 가드 (실측 — grep)

```
auth 검사 있음   13개
auth 검사 없음    3개   kakaoUnlinkWebhook(웹훅 · 자체 키 검증)
                        onSocialUnlinkRequested(Firestore 트리거)
                        socialSignIn(로그인 자체라 있을 수 없다)
```

✅ **셋 다 설명이 된다 — 구멍은 안 나왔다.** ⚠️ 다만 이것은 **`request.auth`
문자열을 센 것**이라, *"검사는 하는데 판정이 틀린 것"* 은 이 방법이 못 본다.

---

## 3. `npm test` 가 파일 이름을 **손으로 나열한다**

```json
"test": "tsc && node --test lib/usageReset.test.js lib/briefingPrompt.test.js … (18개)"
```

**glob 이 아니다.** 새 테스트 파일을 만들고 이 줄에 안 적으면 **조용히 영원히
안 돈다.**

🚨 **`#830` 이 고친 것과 같은 뿌리다** — 그때는 *"`npm test` 에 등록까지 돼 있는데
**CI 가** 한 번도 안 불렀다"* 였고, 지금 남은 것은 *"파일은 있는데 **`npm test` 가**
안 부른다"* 이다. **한 층 아래로 같은 모양이 살아 있다.**

### 지금은 안 어긋나 있다 (실측)

```
나열된 것 18 · 디스크에 있는 것 18
있는데 안 적힌 것  없음
없는데 적힌 것    없음
```

📌 **지금 맞다는 것이 안전하다는 뜻이 아니다.** 어긋나는 순간 **아무 신호가
없다.** ⭐ 재는 법은 싸다 — `package.json` 의 목록과 `src/*.test.ts` 를 맞대면 된다.

⬜ **그것을 테스트로 박아 두는 것을 권한다.** 다만 **이 문서에서는 안 만들었다** —
아래 4번 때문에 **돌려 보고 올릴 수가 없다.**

---

## 4. 🚨 이 노트북에 `node` 가 없다 — 런북에도 없다

```
which node            없음
which npm             없음
런북의 node·npm 언급   **0건** (grep)
CI                    setup-node@v4 · node-version 22 를 **명시 설치**(#830)
```

⚠️ **그래서 규약 3장이 `functions/` 에는 성립하지 않는다.**

```
규약 3장   "로컬에서 먼저 돌린다. 자동 검사는 안전망이지 1차 검사가 아니다"
실제       functions 는 로컬에서 못 돌린다 → CI 가 1차 검사가 된다
```

🚨 **그리고 CI 는 PR 을 열어야 돈다**(규약 3장 표) — 즉 **PR 을 열기 전에는
`functions/` 변경을 아무도 검증할 수 없다.** `flutter` 쪽은 로컬에서 돌 수 있어
이 문제가 없다.

📌 **[추가 678] 의 「1-1 실제로 걸린 넷」에 다섯째로 들어갈 자리다.** 그 목록은
**겪은 것만 적는다**고 되어 있고, 이것은 오늘 겪었다.

```
① Android NDK 가 껍데기        ② Java 없음        ③ 소셜 키 위치
④ cmake (이번엔 있었다)         ⑤ **node 없음**   ← 새로 겪음
```

⚠️ **런북에 넣는 것은 이 문서의 몫이 아니다** — 런북은 다른 세션이 쥐고 있을 수
있어 **PM 확인 뒤에** 넣어야 한다.

---

## ⬜ 이 점검이 못 본 것

```
⬜ 테스트가 몇 건 도는가        이 기계에서 npm test 를 못 돌렸다.
                              CI 로그를 봐야 한다 — [추가 679] 는 251건,
                              PM 은 260건이라 했는데 **둘 다 여기서 확인 못 했다**
⬜ 덮인 18개의 테스트가 **무엇을 재는가**   파일이 있다는 것과 잘 잰다는 것은 다르다
                              깨뜨려 보기(변조)로 재야 알 수 있다
⬜ index.ts 진입점의 **판정이 맞는가**      인증 가드의 유무만 셌다
⬜ tsc 가 잡는 것과 못 잡는 것             npm test 가 tsc 를 먼저 부르므로
                              타입 오류는 걸리지만, 런타임 판단은 안 걸린다
```

⚠️ **첫 줄이 특히 중요하다** — 이 문서는 **「무엇이 안 덮였나」를 셌지 「덮인 것이
제대로 재는가」를 안 쟀다.** 두 번째 질문은 **변조를 넣어 봐야** 답이 나온다
(오늘 `verify_rules.py` 에서 실제로 그렇게 해서, **통과하던 케이스 하나가 아무것도
증명하지 않는다**는 것이 드러났다).

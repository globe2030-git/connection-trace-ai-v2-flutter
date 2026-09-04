# 번호 확인(알림톡) 배포 런북 (2026-09-04)

목표: **휴대전화번호 확인용 알림톡을 실제로 발송할 수 있는 상태**까지 가는 절차.
**「배포」와 「발송 개시」와 「게이트 켜기」를 셋으로 갈라** 한 번에 하나씩 연다.

**원칙**: 되돌리기 쉬운 스위치를 활성화 수단으로 삼는다. 배포·발송 개시·게이트
켜기의 go/no-go는 **전부 globe2030님 최종 결정**(CLAUDE.md 6절 최상위 지침).

표기: 🔒 = **globe2030님만 실행** · 📖 = 확인만 하는 것

> ⚠️ **이 런북은 원격 세션에서 썼다.** 그 세션에는 `firebase`·`gcloud` CLI 도
> 인증 정보도 **없다**(2026-09-04 실측). 아래 명령은 전부 **맥에서** 돌린다.
>
> ```
> cd /Volumes/Work/Claude/connection-trace-ai-v2-flutter
> ```

---

## 0. 왜 이렇게 하나 — 핵심 3줄

1. **코드는 이미 다 있다.** 서버(`phoneOtp.ts`·`phoneOtpSender.ts`)·앱
   (`phone_verify_view.dart`)·게이트(`phone_verification_service.dart`)가 다 붙어
   있고 테스트도 있다. **남은 것은 배포와 스위치뿐이다.**
2. **안전장치가 두 겹이다.** ① `config/phoneVerification` 문서가 없어 **인증
   화면이 안 뜨고** ② `ALIGO_TEST_MODE` 가 `"N"` 이 아니면 **실제 발송이 안 된다**
   (`index.ts:2683` — *"기본이 testMode다"*).
3. 그래서 **함수를 배포해도 아무 일도 안 일어난다.** 사람이 겪는 것이 바뀌는
   시점은 **게이트를 켜는 때** 하나다.

---

## 1. 선행조건

| 조건 | 상태 |
|---|---|
| 알림톡 템플릿 카카오 승인 | ✅ 2026-09-04 globe2030님 확인 |
| 코드 `main` 병합 | ✅ `phoneOtpRequest` · `phoneOtpConfirm` |
| Firebase Blaze 요금제(Functions 배포 가능) | ✅ 이미 전환됨 |
| 알리고 계정·발신번호 등록 | 🔒 확인 필요 |
| 개인정보처리방침 v2.7 게시 | ⬜ **아직 — 3단계까지는 없어도 된다.** 4·5단계 앞에 걸린다 |

### 📖 지금 상태를 재는 법 (이 런북을 열었을 때 먼저)

```bash
firebase functions:list --project connection-sense          # 함수가 올라가 있나
firebase functions:secrets:access ALIGO_API_KEY --project connection-sense   # 시크릿이 있나
```

`config/phoneVerification` 문서 유무는 **콘솔에서 눈으로** 본다 —
<https://console.firebase.google.com/project/connection-sense/firestore> → `config` 컬렉션.

⚠️ **빈 결과는 「없다」와 「권한이 없어 안 보인다」가 화면이 같다**(RESUME 실기기 함정).

---

## 2. 단계별 절차

### 0단계 — TTL 정책을 **먼저** 켠다 🔒

```bash
gcloud firestore fields ttls update expiresAt \
  --collection-group=phoneSendLedger --enable-ttl \
  --project=connection-sense
```

🚨 **순서를 바꾸지 마라 — TTL 은 소급되지 않는다.** 함수를 먼저 배포하면 그
사이 쌓인 장부 문서는 `expiresAt` 이 있어도 **정책이 없어 영영 안 지워진다.**
`index.ts:2755` 가 필드를 심고, TTL 정책이 그 필드를 읽는다.

📌 **`phoneSendLedger` 는 탈퇴해도 남는다 — 결함이 아니라 결정이다**(추가 642).
지우면 **탈퇴 → 재가입으로 하루 5통 상한이 초기화**된다
(`OTP_DAILY_SEND_CAP = 5`, `phoneOtp.ts:56`). **그래서 TTL 이 유일한 파기
수단이고, 방침 v2.7 의 「30일 파기」가 참이 되는 근거도 이것뿐이다.**

### 1단계 — 시크릿 6개 🔒

```bash
firebase functions:secrets:set ALIGO_API_KEY     --project connection-sense
firebase functions:secrets:set ALIGO_USER_ID     --project connection-sense
firebase functions:secrets:set ALIGO_SENDER_KEY  --project connection-sense
firebase functions:secrets:set ALIGO_TPL_CODE    --project connection-sense
firebase functions:secrets:set ALIGO_SENDER      --project connection-sense
firebase functions:secrets:set ALIGO_TEST_MODE   --project connection-sense
```

🚨 **`ALIGO_TEST_MODE` 는 이번엔 `Y`** — `"N"` 이 아닌 값이면 testMode 다.
**실제 발송은 4단계에서 연다.**

⚠️ **키 값을 문서·대화·커밋에 남기지 마라.** 위 명령이 터미널에서 직접 묻는다.

### 2단계 — 함수 배포, **둘만 좁혀서** 🔒

```bash
firebase deploy --only functions:phoneOtpRequest,functions:phoneOtpConfirm \
  --project connection-sense
```

🚨 **`--only functions` 만 쓰면 13개가 전부 나간다.** 그 안에는
`verifyAndGrantPurchase` · `bootstrapAccount` 같은 **과금·지갑 코드**가 있다.
꺼진 채로 나가지만, **그때부터 `config/billing.model` 필드 하나로 켜지는
상태**가 된다(CLAUDE.md 6절). **지금 필요한 것은 둘뿐이니 좁힌다.**

📌 **좁혀 배포하면 나머지 11개는 지금 올라가 있는 판 그대로 남는다** — 그것이
현 상태이므로 달라지는 것이 없다.

### 3단계 — testMode 로 실기기 확인 📖

앱에서 번호를 넣고 **알리고 콘솔의 발송 내역**에 testMode 건이 찍히는지 본다.
**이때는 실제 문자가 오지 않는다.**

⚠️ **게이트가 아직 없으므로 인증 화면이 자동으로 뜨지는 않는다.** 3단계를 보려면
게이트를 잠깐 켜야 하는데, 그 방법은 아래 「게이트를 안전하게 보는 법」에 있다.

### 4단계 — 실제 발송을 연다 🔒

```bash
firebase functions:secrets:set ALIGO_TEST_MODE --project connection-sense   # 값: N
firebase deploy --only functions:phoneOtpRequest,functions:phoneOtpConfirm \
  --project connection-sense
```

⚠️ **시크릿만 바꾸면 반영되지 않는다 — 함수를 다시 배포해야 한다.**

### 5단계 — 게이트를 켠다 🔒 **← 여기서부터 사람이 겪는 것이 바뀐다**

🚨 **이 단계 전에 방침 v2.7 이 게시돼 있어야 한다.** 아래 §4 참고.

---

## 3. 게이트를 안전하게 보는 법 — 아무도 안 걸린 채로

```
enforce = true · enforceFrom = 2030-01-01   →  전원 통과. 스위치가 도는지만 본다
enforceFrom 을 잠깐 과거로                   →  본인 계정으로 인증 화면 확인
다시 미래로                                  →  원복
```

🚨 **`config/phoneVerification` 문서를 잘못 만들면 테스터 전원이 인증 화면에
갇히고 나갈 길이 없다**(추가 645). **문서를 만드는 것 자체가 스위치다** —
값을 바꾸는 게 아니라 **없는 것을 만드는 것**이 켜는 동작이다
(`config/billing.model` 과 같은 성질).

---

## 4. 🚨 방침과의 순서 — 5단계 앞에 걸린다

```
지금            발송이 안 돈다 → 게시본 v2.6 의 「현재 재위탁은 없습니다」가 참이다
게이트를 켜면    카카오 재위탁이 실제로 생긴다 → 그 문장이 거짓이 된다
```

**v2.7(재위탁을 적은 판)은 아직 게시 전이다.** 초안은
[`../legal-drafts/privacy-policy-v2.7-draft.html`](../legal-drafts/privacy-policy-v2.7-draft.html)
에 있고 **파일 머리에 게시 절차 5단계**가 적혀 있다.

⭐ **2~4단계까지는 방침과 무관하다** — 발송 경로가 열려도 **게이트가 없으면
아무도 그 경로를 안 탄다.** 📌 **그러니 경계는 「배포」가 아니라 「게이트」다.**

⚠️ **게이트를 켜는 날과 v2.7 게시일이 벌어지면 그 사이에 방침이 거짓이 된다.**
붙여서 진행하거나, v2.7 을 먼저 게시한다.

---

## 5. 되돌리기(롤백)

| 무엇이 문제인가 | 되돌리는 법 | 되돌아가나 |
|---|---|---|
| 발송이 잘못된다 | `ALIGO_TEST_MODE` 를 `Y` 로 되돌리고 재배포 | ✅ 즉시 |
| 사람들이 인증 화면에 갇힌다 | `config/phoneVerification` 의 `enforceFrom` 을 먼 미래로 | ✅ 즉시 |
| 함수 자체가 문제다 | 이전 판으로 재배포 | ✅ |
| **장부가 쌓였다** | TTL 이 30일 뒤 지운다 | ⚠️ **즉시는 아니다** |

🚨 **되돌릴 수 없는 것 하나** — **TTL 을 켜기 전에 쌓인 장부**는 정책이 안 읽어
영영 남는다. **손으로 지워야 한다.** 그래서 0단계가 0단계다.

---

## 6. 켠 직후 스모크 체크

```
□ 번호를 넣으면 알림톡이 온다 (안 오면 대체문자가 오는지도 본다)
□ 인증번호를 넣으면 통과한다
□ 틀린 번호를 넣으면 막힌다
□ 같은 번호로 6번째 발송이 막힌다 (하루 5통 상한)
□ Firestore users/{uid} 에 phoneVerifiedAt · phoneHash 만 있고 원문이 없다
□ phoneSendLedger 문서에 expiresAt 이 찍혀 있다
```

⚠️ **마지막 둘은 콘솔 실물로 본다** — 이 저장소는 *"코드는 맞는데 실물이 틀린"*
결함을 반복해서 겪었다(CLAUDE.md 4절).

⭐ **대체문자는 우리가 두 번 부르지 않는다** — 알림톡이 실패하면 **알리고가 같은
호출 안에서** 문자로 떨어뜨린다(`phoneOtpSender.ts:82`).

---

## 7. 리스크 & 주의

- 🚨 **`--only functions` 로 넓게 배포하지 마라** — 과금·지갑 코드가 함께 나간다.
- 🚨 **TTL 을 나중에 켜지 마라** — 소급이 안 된다.
- 🚨 **게이트를 시험 삼아 켜지 마라** — 테스터 전원이 갇힐 수 있다. §3 방식으로.
- ⚠️ **시크릿 값을 문서·대화·커밋에 남기지 마라.**
- ⚠️ **번호 원문은 서버에 저장되지 않는다**(`phoneHash` HMAC-SHA256 + 시각만).
  이 사실이 방침 v2.7 문안의 근거이므로 **구현을 바꿀 때 방침도 함께 본다.**
- 📌 **「3분」이나 앱 이름이 바뀌면 템플릿 재심사 영업일 2일**이다. ⭐ 법인명은
  템플릿 문안에 안 들어가므로 표기 통일(추가 673)은 재심사 대상이 아니다.

---

## 8. 근거 — 이 런북이 어디서 나왔나

```
코드      functions/src/phoneOtp.ts · phoneOtpSender.ts · phoneRecordCleanup.ts
          functions/src/index.ts:2711(phoneOtpRequest) · :2815(phoneOtpConfirm)
          :2683(testMode 기본) · :2755(expiresAt) · :2734(phoneSendLedger)
          lib/core/services/phone_verification_service.dart
          lib/presentation/features/auth/views/phone_verify_view.dart
          lib/presentation/common/auth_gate.dart:489
경위      추가 642(장부·TTL) · 645(게이트 범위) · 673(알림톡 승인·법인명)
방침      docs/legal-drafts/privacy-policy-v2.7-draft.html (머리의 게시 절차)
```

⚠️ **이 문서의 상태 표시는 2026-09-04 기준이다.** 낡았을 수 있으니
**§1 「지금 상태를 재는 법」을 먼저 돌린다.**

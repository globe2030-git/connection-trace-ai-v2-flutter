# 서버가 받는 것 ↔ 앱이 보내는 것 — 축 ⑤ 전수 대조 (2026-09-06)

> PM 배정. [추가 717] 이 *"`request.data` 의 12개는 봤지만 **그 안의 중첩 필드는
> 안 봤다**"* 로 남긴 자리를 끝까지 팠다. 잰 커밋 `92d5445b`.
>
> 🚨 **코드를 안 고쳤다.** 검토만.

---

## 0. 요약 — **새 결함은 없다. 그리고 그 말이 뜻을 갖는다**

```
새로 찾은 어긋남   **0건**
이미 알려진 것     1건 — generateBriefing 의 fieldKey (개발D · #870)
                  ⭐ **내 방법이 그것을 잡았다** → 아래 「양성 대조군」
방어적인데 안 걸림  1건 — bootstrapAccount 의 조건부 deviceId (249건 중 **0회**)
의도된 미연결      3건 — 관리자 OTP 셋 (4단계 화면 대기)
내가 만든 허수     2건 — §3
```

🚨 **「없다」를 그냥 적으면 아무것도 아니다.** 오늘 규약에 들어간 그대로,
**「일어나는 쪽을 잠그는 짝」**이 있어야 뜻을 갖는다 — 그것이 §2 다.

---

## 1. 전수 대조표

| callable | 서버가 읽는 것 | 앱이 보내는 것 | |
|---|---|---|---|
| `generateBriefing` | communicationLogs · contactSummary · extraNote · **fieldKey** · interests · myProfileSummary · previousPoints · weatherSummary | 위에서 **`fieldKey` 만 빠짐** | 🚨 **알려진 것**(#870) |
| `bootstrapAccount` | deviceId | **조건부** — `deviceId == null ? null : {...}` | ✅ §4 |
| `storeAppleRefreshToken` | authorizationCode | 같음 | ✅ |
| `getUserUsage` | email | 같음 | ✅ |
| `grantSupportCredits` | amount · email · operationId · reason | 같음 | ✅ |
| `verifyAndGrantPurchase` | platform · productId · receiptData · transactionId | 같음 | ✅ |
| `socialSignIn` | `validateRequest(request.data)` 로 **위임** | code · provider · redirectUri · state | ✅ §5 |
| `phoneOtpRequest` / `Confirm` | phone / phone·code | 같음 | ✅ |
| `revokeMySessions` · `adminSessionHeartbeat` | (없음) | (없음) | ✅ |
| `adminOtpRequest` / `Confirm` | phone / phone·code | 🚨 **부르는 클라이언트가 없다** | §6 |

---

## 2. ⭐ 양성 대조군 — **내 방법이 「이미 있는 결함」을 잡았다**

```
generateBriefing  서버가 request.data.fieldKey 를 읽는다
                  앱 payload 에 fieldKey 가 **없다**
                  → 개발D 가 #870 에서 찾은 「분야 축이 한 번도 안 돈다」와 같은 것
```

🚨 **이것이 없으면 이 문서의 「나머지는 일치한다」가 아무 뜻이 없다.** 아무것도
못 잡는 방법으로 훑고 *"어긋남이 없다"* 고 적으면 **「전부 통과」가 안전처럼 보이는**
바로 그 자리다(오늘 규약 「초록이 무엇을 뜻하는가」).

⭐ **그러므로 이 문서의 결론은 이렇게 읽어야 한다**: *"`fieldKey` 를 잡아낸 방법으로
나머지 열둘을 훑었고, 거기서는 안 나왔다."*

---

## 3. 🚨 내가 만든 허수 둘 — 고치고 다시 쟀다

```
① .call<Map<String, dynamic>>(  의 **중첩 제네릭**
   `\.call(?:<[^>]*>)?\s*\(` 가 `Map<String, dynamic>` 의 안쪽 `>` 에서 멈춘다
   → **열 개 callable 전부 「앱이 아무것도 안 보낸다」**로 나왔다
   → `[^(]*` 로 고쳐서 다시 쟀다

② `'ios'` 를 **키로 오인**
   `platform: isIos ? 'ios' : 'android'` 의 **값**인데 `'\w+'\s*:` 패턴에 걸렸다
   → *"앱이 `ios` 를 더 보낸다"* 는 없는 어긋남이었다
```

📌 [추가 717] 에서 셋, 여기서 둘 — **오늘 이 축에서 허수를 다섯 만들었다.**
⚠️ **그래서 §2(양성 대조군)가 있어야 한다.**

---

## 4. ✅ `bootstrapAccount` 의 조건부 `deviceId` — **실측으로 닫았다**

```
앱     deviceId == null ? null : {'deviceId': deviceId}      ← 조건부
서버   rawDeviceId 가 없으면
       logger.warn("deviceId 없는 bootstrapAccount 호출 — **기기 가드 건너뜀**")
```

🚨 **「옵셔널이 가장 위험하다」는 자리다** — 안 와도 되고, 안 오면 **중복 무료체험
방지 가드가 통째로 꺼진다.** ⭐ **그런데 서버가 조용히 넘기지 않고 경고를 남긴다.**

**그래서 셀 수 있었다 (Cloud Logging · 90일):**

```
bootstrapAccount 총 호출   **249건**  (200이 243 · 500이 6)
「기기 가드 건너뜀」 경고    **0건**
```

✅ **한 번도 안 걸렸다.** 방어적으로 둔 분기이고 **실제로는 항상 `deviceId` 가 온다.**

⚠️ 덤으로 **500이 6건** 나왔다 — 이 문서의 축이 아니라 안 팠다. **⬜ 별건.**

---

## 5. ✅ `socialSignIn` — 위임이라 표면에서 안 보였다

`request.data.X` 가 **하나도 없어** 처음에 *"서버가 아무것도 안 읽는다"* 로 보였다.
실제로는 `validateRequest(request.data)`(`socialAuth.ts`)에 **통째로 넘긴다.**

📌 **이것이 PM 이 말한 「층」이다** — 표면만 보면 빈칸이고, **한 겹 들어가야** 보인다.
⭐ `socialAuth.test.ts` 가 그 모양을 고정하고 있어 **테스트가 명세 노릇**을 한다.

---

## 6. 🚨 관리자 OTP 셋 — **부르는 클라이언트가 어디에도 없다**

```
adminOtpRequest · adminOtpConfirm · adminSessionHeartbeat
  lib/         없음
  docs/admin/  없음
```

⭐ **의도된 것이다** — 4단계(관리자 콘솔 인증 화면)가 아직 없다([추가 682]).
⚠️ **다만 [추가 717] 의 `isGateEnabled` 와 같은 결이다** — **켜는 날 부를 자리를 잊으면
조용히 안 걸린다.** 📌 그쪽은 **테스트가 0건**이라 더 위험했고, 이쪽은 `adminAuth.test.ts`
12건이 판정을 잠그고 있어 사정이 낫다.

---

## 7. ⬜ 이 대조가 못 본 것

```
⬜ **중첩 객체의 안쪽**   communicationLogs 는 **리스트 안에 객체**가 들어간다.
                        그 안의 필드까지는 안 맞댔다 — 🚨 fieldKey 와 같은 층이 또 있을 수 있다
⬜ 문자열 키 접근        data['x'] 꼴은 `request.data.x` 패턴에 안 걸린다
⬜ 스프레드              ...payload 로 합쳐 보내면 키가 안 보인다
⬜ onRequest 웹훅        kakaoUnlinkWebhook 은 body 를 다르게 읽는다 — 안 봤다
⬜ 응답 방향             서버가 **돌려주는 것**을 앱이 다 읽는지는 안 봤다
```

⚠️ **첫 줄이 가장 크다.** `fieldKey` 가 **한 겹**이었는데, `communicationLogs` 는
**두 겹**이다. **같은 방법을 한 겹 더 들어가서 돌려야** 한다.

---

## 8. 제안 (고치지 않았다)

```
⬜ generateBriefing.fieldKey   개발D 축 — #870 에 있다. 여기서 안 다룬다
⬜ isGateEnabled 테스트         [추가 717] 의 제안 — **별건**
⬜ bootstrapAccount 500 6건     원인 미상 — 별건
⬜ communicationLogs 안쪽       한 겹 더 들어간 대조 — **이 문서의 가장 큰 ⬜**
```

# 커넥션센스 — 데이터 스키마 (테이블 설계)

|  |  |
|---|---|
| **문서** | Firestore 에 **무엇이 어디에 어떤 모양으로** 들어 있는가 |
| **짝 문서** | [`architecture.md`](./architecture.md) — 코드가 어떻게 짜여 있는가 |
| **잰 날** | 2026-09-05 |
| **무엇으로 쟀나** | `firestore.rules` 의 `match`·`clientWritableUserFields()` + 모델 코드 |

> ⚠️ **rules 를 1차 자료로 삼은 이유**: 이 프로젝트는 rules 가 촘촘해서
> **거기 없는 경로는 클라이언트 쓰기가 막힌다.** 즉 rules 에 있는 것이
> 「실제로 쓰이는 것」에 가장 가깝다. 다만 **Functions 는 Admin SDK 로
> rules 를 우회**하므로, 서버만 쓰는 필드는 rules 에 안 나온다.

---

## 0. 두 가지 원칙 — 표를 읽기 전에

### ① 🚨 개인정보는 **암호화해서 한 덩어리**로 넣는다

```
❌ { name: "홍길동", phone: "010-…" }        구조화된 필드로 나눠 넣기
✅ { encrypted: "<암호문>", schemaVersion: 2 }
```

**이유**(추가 72): 어차피 암호화하면 필드로 나눠 둘 값이 없다. 그리고
**나눠 두면 서버에서 필드만 골라 읽는 길이 생긴다** — 그 길을 아예 안 만든다.

⚠️ **대가**: 서버에서 질의·정렬·검색이 안 된다. 그래서 검색은 기기에서 한다.

### ② 🚨 명함은 **제3자(명함 주인)의 개인정보**다

이용자 본인 정보와 **무게가 다르다.** 명함 주인은 우리 서비스에 가입한 적도
동의한 적도 없다. 표에서 🚨 가 붙은 것이 그것이다.

---

## 1. `users/{uid}` — 계정

| 필드 | 무엇 | 누가 쓰나 | 비고 |
|---|---|---|---|
| `encryptionKeyB64` | AES-256 키 | 클라이언트 | 🚨 **한 번 쓰면 못 바꾼다**(`encryptionKeyUnchanged()`) |
| `profile` | 내 프로필 | 클라이언트 | `{encrypted, schemaVersion: 2}` |
| `groups` | 그룹 목록 | 클라이언트 | `{encrypted, schemaVersion: 1}` |
| `termsConsentAt` | 필수 동의 시각(서버 기준) | 클라이언트 | 🚨 **지우지 않는다** — 입증 자료 |
| `termsConsentedAtDevice` | 이용자가 답한 시각 | 클라이언트 | 참고값 |
| `termsConsentItems` | 동의한 항목 | 클라이언트 | |
| `adConsentEmail`·`adConsentPush` | 광고 수신 동의 | 클라이언트 | |
| `adConsentAt` | 최초 동의 시각 | 클라이언트 | 🚨 **철회해도 안 지운다** |
| `adConsentChangedAt`·`adConsentNotifiedAt` | 변경·통지 | 클라이언트 | 2년 재확인 기산점 |
| `photoImprovementConsent`(`At`) | 사진 개선 동의 | 클라이언트 | ⚠️ 철회 시 `At` 을 `null` 로 지운다 |
| `accountSwitches` | 계정 전환 기록 | 클라이언트 | |
| `aiUsage` | AI 호출 카운터 | **서버** | rules 의 쓰기 목록에 없다 |
| `cardPhotoQuota` | 사진 한도 | **서버** | |
| `phoneVerifiedAt`·`phoneHash` | 번호 인증 | **서버** | |
| `updatedAt` | | 클라이언트 | |

### 🚨 「동의 시각을 지우지 않는다」가 두 번 다르게 정해져 있다

```
adConsentAt                 철회해도 남긴다   입증자료·2년 재확인 기산점
photoImprovementConsentAt   철회하면 지운다
```

⚠️ **rules 주석이 *"그것을 여기 복사하면 안 된다"* 고 못 박아 두었다.**
비슷해 보인다고 한쪽 규칙을 다른 쪽에 옮기면 **법적 증적이 사라진다.**

### 🚨 쓰기 허용 목록에서 빠지면 **조용히 거부된다**

`clientWritableUserFields()` 에 없는 필드는 클라이언트 쓰기가 **실패하는데,
호출부가 실패를 삼키고 `debugPrint` 만 남기므로 화면에 안 드러난다.**

**실제로 두 번 겪었다** — `accountSwitches`(계정 전환 기록이 조용히 실패),
`termsConsentAt`(화면은 「동의 완료」로 넘어가는데 서버에 안 남음).

📌 **새 필드를 더할 때는 이 목록도 함께 고친다.**

---

## 2. `users/{uid}/contacts/{id}` — 🚨 명함

```
{ encrypted: "<암호문>", schemaVersion: 2 }
```

암호문 안(`ContactModel.toBackupJson()`):

| 갈래 | 필드 |
|---|---|
| 사람 | `name` `company` `title` `department` |
| 연락처 | `phone` `officePhone` `directPhone` `fax` `email` `website` |
| 주소 | `address` `addressDetail` `postalCode` |
| 분류 | `tags` `groupIds` `interests` `talkingPoints` |
| 기록 | `memo` `commLogs` `updatedAt` |
| 재연락 | `lastReconnectOutcome(At)` `nextFollowUpAt` `reconnectSnoozedUntil` `reconnectNoResponseStreak` |
| 이미지 | `cardImagePath` `useCardAsAvatar` `avatarUrl` |

🚨 **좌표(`geo`)는 서버에 안 올린다**(추가 75, C안). `toJson()` 이 아니라
`toBackupJson()` 을 쓰는 이유가 이것이다 — **바꿔 쓰면 좌표가 다시 올라간다.**
복원 후에는 기기에서 주소로 다시 계산한다.

> **왜 안 올리나**: 좌표는 주소에서 파생되는 값이라 보관할 이유가 없고,
> 보관하면 *"회사가 위치정보를 보유한다"* 는 해석 여지가 생긴다.

---

## 3. `users/{uid}/cardSources/{id}` — 🚨 파싱 원본 (2026-09-05 신설)

```
{ encrypted: "<암호문>", schemaVersion: 1 }
```

암호문 안(`CardSourceModel`):

| 필드 | 무엇 |
|---|---|
| `cardId` | 어느 명함에서 나왔나 (`contacts/{id}` 와 같다) |
| `rawText` | 🚨 OCR 원문 — **이름·전화·주소가 통째로** |
| `parserVersion` | 이 원본으로 파싱했을 때의 파서 판 |
| `scannedAt` | 스캔 시각 |

**왜 본문과 다른 문서인가**: 평소 명함첩을 열 때마다 **안 쓰는 원본이
딸려온다.** 원본은 파서를 고쳤을 때만 읽는다.

**왜 필요한가**: 파서를 고쳐도 옛 명함은 그대로다. 원본이 있으면
**사진 없이 파싱만 다시 돌린다**(OCR 은 기기에서 도는 비싼 단계).

🚨 **명함을 지울 때 함께 지운다.** 안 지우면 **이용자는 지웠다고 아는데
제3자 개인정보 원문이 서버에 남는다.**

⚠️ **좌표(`rawLineBoxes`)는 아직 안 담는다** — 크기를 못 쟀다(표본이 저장소
밖). `rawLines` 는 `rawText` 에서 다시 만들 수 있어 **일부러 안 담는다.**

---

## 4. 나머지 하위 컬렉션

| 경로 | 무엇 | 개인정보 |
|---|---|---|
| `deletedContacts/{id}` | 삭제 표식 `{deletedAt}` | 없음 — id·시각만 |
| `commLogs/{id}` | 연락 기록 | 🚨 있음 |

**`deletedContacts` 가 필요한 이유**: 삭제는 「없음」이라 그냥 두면 **다른 기기와
병합할 때 그 기기의 사본이 다시 살아난다**(P1-39 A안).

---

## 5. `phoneAccounts/{번호해시}` — 🚨 「사람」의 씨앗

```
{ uid, verifiedAt }
```

📌 **이것이 지금 유일한 「사람 → 계정」 매핑이다.** uid 를 **하나만** 담고,
다른 uid 가 오면 `taken` 으로 막는다.

⚠️ **번호 원문이 아니라 해시다.** salt 는 `PHONE_HASH_SALT` 시크릿이고
🚨 **한번 정해 데이터가 쌓이면 사실상 못 바꾼다** — 바꾸면 매핑이 전부
안 맞는다.

---

## 6. 관리자·운영

| 컬렉션 | 무엇 |
|---|---|
| `adminAuditLogs/{id}` | 관리자 조작 기록. append-only |
| `aiAuditLogs` · `ocrStats` | 사용량·품질 통계 |
| `inquiries` / `replies` | 1:1 문의 |
| `notices` · `legalDocs` | 공지·법적 문서 |
| `purchases` · `creditGrants` · `creditGrantAudits` | 결제·크레딧 |
| `deviceLedger` · `referralCodes` · `pilotEvents` | 기기·추천·이벤트 |
| `phoneOtpChallenges` · `phoneSendLedger` | 인증번호·발송 상한 |
| `config/billing` · `config/phoneVerification` | 🚨 **스위치** — 아래 |

### 🚨 `config` 는 「필드를 만드는 것」이 스위치다

```
config/billing.model            없음 → reset(무료). 만들면 과금이 켜진다
config/phoneVerification        없음 → 게이트 꺼짐
```

⚠️ **값을 바꾸는 게 아니라 「없는 필드를 만드는 것」이다.** 어느 세션도
globe2030님이 **직접** 지시하기 전에는 만들지 않는다(`CLAUDE.md` 6장).

📌 **꺼진 쪽이 기본값**이라, 설정을 깜빡한 것이 **기능이 열린 채로 나가는
일**이 되지 않는다.

---

## 7. C안이 바꾸는 것 (설계 — 아직 구현 전)

```
people/{personId}                     🆕 personId 는 영원히 불변
  uids        ["abc123", "kakao:99"]
  phoneHash · phoneChangedAt · createdAt
  ├── contacts/{id}       ← users/{uid} 밑에서 옮겨온다
  ├── cardSources/{id}    ← 함께 옮겨온다
  ├── deletedContacts/{id}
  └── commLogs/{id}

phoneAccounts/{번호해시} → { personId }   🔄 uid → personId
                                          번호 변경 = 이 문서 하나 옮기기
users/{uid}
  personId  "p_xxx"                    🆕 역참조 한 줄
  encryptionKeyB64                     그대로 — 키링이 여기서 키를 모은다
  동의 3종 · aiUsage · 사진 한도         ⬜ 사람/계정 어디에 둘지 미정
```

### 왜 `phoneAccounts` 를 그대로 「사람」으로 안 쓰나

**번호가 바뀌면 문서 이름이 바뀐다** → 사람의 정체성이 바뀐다 → 명함첩 경로가
통째로 바뀐다. **번호로 사람을 식별하는 것**과 **번호를 사람의 이름으로 쓰는
것**은 다르다.

### 왜 명함을 사람 밑으로 옮기나

```
🚨 Firestore 커서는 컬렉션을 가로지르지 못한다
   → uid 마다 흩어 두면 「최신순 20장씩」이 안 된다 (느린 게 아니라 안 된다)
🚨 rules 의 문서 접근 호출은 단일 요청당 10회 제한 + 호출마다 과금
   → 남의 uid 밑을 읽으려면 매번 「같은 사람인가」를 조회해야 한다
```

⭐ **그리고 「명함첩의 주인은 사람」이라는 방침이 구조에 그대로 드러난다.**

설계: [`specs/사람-레이어-C안-설계-2026-09-05.md`](./specs/사람-레이어-C안-설계-2026-09-05.md)

---

## 8. 스키마를 고칠 때 반드시 함께 볼 것

```
① firestore.rules              경로가 없으면 쓰기가 조용히 거부된다
   users 필드면 clientWritableUserFields() 도
② docs/legal/privacy-policy.html   새 항목을 저장하면 방침도 고쳐야 한다
   🚨 방침과 구현이 어긋나는 것 자체가 법적 리스크다
③ tool/verify_server_privacy.py    평문이 안 남았는지 검사한다
④ 삭제 경로                     새로 만든 것은 탈퇴·명함 삭제 때 함께 지워지나
```

🚨 **④를 빠뜨리면 「지웠는데 남아 있는」 상태가 된다.** 2026-09-05
`cardSources` 를 만들 때 이것 때문에 `deleteCardSource` 를 함께 붙였다.

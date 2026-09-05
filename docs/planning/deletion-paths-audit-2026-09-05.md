# 삭제·파기 경로 전수 점검 (2026-09-05)

> **무엇을 물었나**: 앱이 **「지운다」고 말하는 모든 자리**에서, 실제로 무엇이
> 지워지고 무엇이 남는가. 그리고 **화면 문구가 그 사실과 맞는가.**
>
> **왜 지금**: 2026-09-05에 「프로필 사진 지우기가 서버 사본을 안 지운다」가
> 나왔는데, **같은 모양이 다른 곳에도 있는지 아무도 안 봤다.** 이 저장소는
> 그 유형을 이미 두 번 겪었다 — *"재시도 로직이 죽어 있었다: 서비스는 정상,
> 부르는 쪽이 없음"*(추가 79), *"`forget()` 은 만들어져 있었는데 부르는 곳이
> 0건"*(추가 518).
>
> **범위**: 읽기만 했다. **코드는 한 줄도 안 고쳤다.** 고칠지는 globe2030님
> 결정이고 법무와도 맞물린다.
>
> **무엇으로 쟀나**: 워크트리 `ct-conflict-fix` · 브랜치
> `docs/deletion-paths-audit` (`origin/main` 에서 팜, 2026-09-05) ·
> `grep` + 해당 파일 직접 열람. **서버 실물은 조회하지 않았다**(권한 밖) —
> 아래 「못 잰 것」 절을 함께 볼 것.

---

## 0. 한눈에 — 결론 넷

```
🚨 결함 2   탈퇴해도 서버에 남는 것이 둘 있다 (cardSources · ocrStats)
            둘 다 방침이 「탈퇴 시 파기」라고 단언한 항목이다

🚨 결함 2   프로필 화면의 「사진 지우기」 둘이 아무것도 안 지운다
            명함 사진(보고된 것) + 아바타(이번에 함께 나온 것)

⚠️ 문구 3   화면이 실물과 다르게 말하는 자리 셋 (아래 §3)

✅ 정상 4   명함 삭제 · 그룹 삭제 · 계정 전환 30일 · 탈퇴 기기 정리
            넷 다 의도대로 돌고, 왜 그렇게 했는지가 주석에 남아 있다
```

⭐ **결함 넷 중 셋의 뿌리가 같다** — **지우는 함수는 있는데 부르는 곳이 없다.**
`deleteCardImage` 도, `cardSources` 삭제도, `ocrStats` 삭제도 **코드는 전부
존재한다.** 빠진 것은 **그것을 부르는 자리** 하나뿐이다.

---

## 1. 🚨 결함 — 회원 탈퇴 후 서버에 남는 것 둘

### 1-1. `users/{uid}/cardSources` — 명함 파싱 원문이 남는다 (가장 무겁다)

**무엇인가**: 명함을 만들어 낸 OCR 원문. **이름·전화·주소가 통째로** 들어
있고, 그것도 이용자 본인이 아니라 **제3자(명함 주인)의 것**이다.
`firestore.rules:736` 이 스스로 그렇게 적어 뒀다 —
*"개인정보 무게는 명함 본문과 똑같다 … 「부가 데이터니까 느슨하게」가 되면
안 되는 자리다."*

**무엇을 쟀나**

```
앱     data_backup_service.dart:441  deleteAllUserData(uid)
       → users/{uid}/contacts 문서들을 batch 로 지우고
       → users/{uid} 문서를 지운다.  cardSources 는 없다

서버   functions/src/index.ts:1685   onUserDeletedCleanup
       → grep -n "cardSources" functions/src/index.ts   = **0건**

사실   Firestore 는 문서를 지워도 하위 컬렉션을 지우지 않는다
       (같은 파일 1821행이 이 사실을 이미 적어 뒀다 — deletedContacts 때문에)

결과   탈퇴해도 users/{uid}/cardSources/{contactId} 가 그대로 남는다
```

**방침이 무엇을 약속했나**

| 자리 | 문장 |
|---|---|
| `privacy-policy.html:1036` | *"회원 탈퇴 시 … **명함 데이터 전체가 삭제**되며"* |
| `privacy-policy.html:623` | 명함(인맥) 정보 — *"그 전이라도 회원 탈퇴 시 전부 파기"* |

📌 **명함 **개별** 삭제 경로에는 이미 들어가 있다** —
`contacts_repository.dart:1073` 이 `DataBackupService.deleteCardSource` 를
부른다(2026-09-05 오늘 들어왔다). 그 함수 자신의 주석
(`data_backup_service.dart:108`)이 이유를 이렇게 적었다:

> 🚨 **이걸 빠뜨리면 지운 명함의 개인정보 원문이 서버에 남는다.** 이용자는
> 지웠다고 알고 있는데 이름·전화·주소가 그대로 있는 상태가 된다.

**그 문장이 탈퇴 경로에도 그대로 적용된다. 거기만 안 불렀다.**

### 1-2. `ocrStats/{uid}` — 인식 통계가 남는다

```
방침   privacy-policy.html:594
       "이 통계는 … 회원 탈퇴 시 함께 파기됩니다(서비스 이용약관 제9조의2 참조)"

실물   grep -n "ocrStats" functions/src/index.ts
       1609:  * ocrStats/{uid}              ← 주석(연결 해제가 지우는 목록)
       1651:  await db.collection("ocrStats").doc(uid).delete();
                                             ↑ onSocialUnlinkRequested 안이다

탈퇴   onUserDeletedCleanup(1685~) 안에 ocrStats 는 없다
```

⚠️ **개인정보 원문은 없다** — 항목별 카운트와 분류 경로 분포뿐이고, 그것도
방침이 그렇게 고지했다. **그래도 방침이 명시한 파기 약속과 어긋난다.**

### ⭐ 1-3. 둘의 뿌리는 하나다 — 그리고 **그 자리에 예고가 적혀 있었다**

`functions/src/index.ts:1613-1615` 는 연결 해제 파기를 설명하며 이렇게 썼다:

> 📌 `users/{uid}` 문서가 지워지면 `onUserDeletedCleanup` 이 깨어나 나머지를
> 이어서 지운다. 앱 안의 탈퇴와 **같은 경로를 그대로 쓴다** — **파기 대상이
> 두 벌로 갈라지면 한쪽만 고쳐지는 날이 온다.**

**그런데 실제로는 두 벌이다.**

| | 소셜 연결 해제 (`onSocialUnlinkRequested`) | 회원 탈퇴 (앱 → `onUserDeletedCleanup`) |
|---|---|---|
| `users/{uid}` 아래 | `db.recursiveDelete(userRef)` — **하위 전부** (1648행) | `contacts` 낱개 + user 문서 (**하위 나머지 남음**) |
| `ocrStats/{uid}` | 지운다 (1651행) | **안 지운다** |
| 그 밖 | 트리거가 이어서 지움 | 트리거가 이어서 지움 (동일) |

🚨 **예고한 날이 이미 왔다.** 갈라진 것을 **아무도 다시 안 봤다** — 주석이
경고까지 해 뒀는데도.

---

## 2. 🚨 결함 — 프로필 화면의 「사진 지우기」 둘

`lib/presentation/features/radar/views/my_profile_edit_modal_view.dart`

### 2-1. 내 명함 사진 (보고된 것 — 재확인했다)

```
:459  화면 문구  "이 사진은 이 기기에만 있어 지우면 되돌릴 수 없어요
                  — 다시 찍어야 합니다."
:450  주석       "사진 지우기 — 되돌릴 수 없다. 서버 백업이 꺼져 있어 …"
:478  실제 동작  setState(() { _cardImageCleared = true; ... })  ← 이것뿐
:566  저장 시    cardImagePath = _cardImageCleared ? null : _cardImagePath
```

**세 문장이 다 어긋난다.**

| 화면이 말한 것 | 실물 |
|---|---|
| "이 기기에만 있어" | **거짓.** 2026-08-26부터 서버에도 있다 (`card_photo_backup_service.dart:60` `kCardPhotoBackupEnabled = true`) |
| "지우면 되돌릴 수 없어요" | **거짓.** 경로만 끊길 뿐 아무것도 안 지워진다 |
| 주석 "서버 백업이 꺼져 있어" | **낡았다.** 08-26에 켜졌다(추가 687에서 같은 모양의 주석 둘을 이미 고쳤는데 **이 줄은 안 걸렸다**) |

**무엇이 남나** — `deleteCardImage` 호출부를 세었다(`grep -rn "deleteCardImage" lib` = 4건, 그중 호출은 3건):

```
lib/core/services/leftover_account_purge_service.dart:258   (계정 전환 30일)
lib/data/repositories/contacts_repository.dart:1055·1065    (명함 삭제)
my_profile_edit_modal_view.dart                             ← **0건**
```

따라서 다음 셋이 전부 남는다.

```
① 기기   contact_card__my_profile_card.enc  (앱 문서 폴더)
② 서버   Cloud Storage 의 사본
③ 장부   CardPhotoBackupStateService 의 "백업됨" 기록
         → 지운 사진이 **2,000장 한도를 계속 차지한다** (추가 518에서 겪은 것)
```

### 2-2. 아바타 — **이번에 함께 나온 것**

```
:544  void _removeAvatarPhoto() {
:546    _avatarPath = null;
:547    _avatarCleared = true;
      }                        ← 파일을 지우는 줄이 없다
:600  저장 시  avatarPath: _avatarCleared ? null : _avatarPath
```

**남는 것**: `<앱문서>/my_profile_avatar.jpg` — ⚠️ **평문 JPG 다.** 암호화돼
있지 않다(`settings_view.dart:2093` 이 탈퇴 정리에서 그렇게 부른다:
*"이건 암호화도 안 돼 있어(평문 JPG)"*).

⚠️ **확인 다이얼로그도 없다.** 명함 사진 쪽에는 「그대로 두기 / 사진 지우기」가
있는데(`:461-471`) 아바타는 누르면 바로 지워진 것처럼 보인다.

📌 **아바타는 이용자 **본인**의 사진이라 제3자 개인정보는 아니다.** 그래서
1절보다 가볍다. 다만 **재가입·계정 전환 시 앞 사람 얼굴이 남는 자리**이고,
탈퇴 정리(`settings_view.dart:2191`)는 이 파일을 **정확히 이 경로로 지운다** —
즉 **지우는 코드는 이미 있고 여기서만 안 부른다.** 1절과 같은 모양이다.

---

## 3. ⚠️ 화면 문구가 실물과 다른 자리 셋

**이번 결함의 본질이 여기다.** 아래 셋은 **동작은 의도대로**인데 **문구가
그 사실을 잘못 말한다.**

### 3-1. 소통 기록 삭제 — 「기기에만」이라고 했는데 서버에서도 지워진다

```
briefing_overlay_view.dart:393  "이 기기에 저장된 기록에서 삭제되며 되돌릴 수 없습니다."
실물 :410-414                   commLogs 를 뺀 ContactModel 로 updateContact
                                → contacts_repository.updateContact → _backup(stamped)
                                → 서버 users/{uid}/contacts/{id} 도 갱신된다
```

⚠️ **방향이 반대라 덜 나쁘지만 여전히 틀렸다.** 이용자는 *"서버 백업엔 남겠구나"*
로 읽는데 실제로는 서버에서도 사라진다. 방침(`privacy-policy.html:624`)은
*"이용자가 해당 기록을 삭제한 때 … 파기"* 라고 적어 **실물 쪽이 방침과 맞다.**
**문구만 좁다.**

### 3-2. 명함 인식 통계 「초기화」 — 서버 사본은 남는다

```
ocr_stats_view.dart:162   "지금까지 모은 명함 인식 통계를 지웁니다. 되돌릴 수 없습니다."
ocr_stats_service.dart:149  reset() → prefs.remove(_key)   ← 기기 캐시만
ocr_stats_service.dart:120  업로드 대상은 ocrStats/{uid}    ← 서버 문서는 그대로
```

⚠️ 다음 스캔이 일어나면 빈 집계로 덮어쓰이지만(`_uploadIfPossible`), **스캔을
안 하면 옛 집계가 서버에 계속 남는다.** 개인정보 원문은 없다.

### 3-3. 일괄/개별 명함 삭제 — 문구는 맞고 **주석이 낡았다**

```
wallet_view.dart:718   "선택한 명함과 기록이 기기와 서버에서 모두 삭제됩니다."  ← 맞다
wallet_view.dart:713   주석: "사진 서버 사본은 플래그를 켠 뒤 여기 문구에 함께
                              넣는다(2026-08-16, **지금은 올라간 사진이 없어
                              사실이 아니다**)"                                ← 낡았다
```

08-26에 켜졌고 지금은 사진도 함께 지워진다(`contacts_repository.dart:1055`).
**문구는 이미 맞는데 주석만 「아직 아니다」로 서 있다** — 다음 사람이 이 주석을
보고 문구를 되돌릴 수 있다.

---

## 4. ✅ 의도대로 도는 것 넷 — 무엇을 근거로 「의도」라고 했나

📌 **의도와 빠뜨림을 가르는 기준은 「주석·설계 문서에 그렇게 쓰여 있는가」**로
잡았다. 근거를 못 찾은 것은 §6에 「모르겠다」로 남겼다.

### 4-1. 명함 삭제 — 다섯 군데를 다 지운다

`contacts_repository.dart:1048 deleteContact`

| 어디 | 무엇 | 행 |
|---|---|---|
| 기기 파일 | `contact_card_<id>.enc` | 1055 |
| Cloud Storage | 서버 사진 사본 (`uid` 를 넘긴다) | 1055·1065 |
| 백업 장부 | `forget(contactId)` — 한도도 함께 돌려준다 | `contact_image_service.dart:612` |
| Firestore | `contacts/{id}` 문서 | 1071 |
| Firestore | `cardSources/{id}` 파싱 원문 | 1073 |
| Firestore | `deletedContacts/{id}` 묘비를 **남긴다** | 1076 |

⭐ **경로가 끊긴 명함까지 챙긴다**(1063-1065) — 서버 복원 직후처럼 로컬 경로가
없는 명함은 `deleteCardImage('', uid:…, contactId:…)` 로 **서버만** 지운다.
안 그러면 참조가 사라져 나중에 지울 수도 없는 고아가 된다.

**묘비를 남기는 것은 의도**다 — 다기기 동기화(P1-39 A안). 안 남기면 다른 기기의
사본이 되살아난다. 묘비 자체는 탈퇴 시 서버 트리거가 지운다(`index.ts:1831`).

### 4-2. 그룹 삭제 — 기기·서버·명함별 참조 셋 다

```
groups_view_model.dart:72  deleteGroup
  → groups_repository.deleteGroup(id)      그룹 자체 (:230)
  → _persist() → backupGroups(uid, …)      서버 users/{uid}.groups 를 **통째로 덮어씀** (:237·:240)
  → 참조하던 명함마다 updateContact        groupIds 에서 그 id 만 뺀다 (:74-79)
```

📌 **참조 정리를 저장소가 아니라 뷰모델이 하는 것은 의도**다 —
`groups_repository.dart:227` 주석: *"여기는 ContactsRepository 를 모른다."*

### 4-3. 계정 전환 — 30일 뒤 **이 기기의 것만** 지운다

`leftover_account_purge_service.dart`

```
지운다                              안 지운다
contact_card_<id>.enc (기기)        Firestore users/{uid}/contacts
enc_key_v1_<uid> (secure storage)   Cloud Storage users/{uid}/cards
```

🚨 **서버를 안 건드리는 것이 의도다**(`:38-42`) — *"서버를 지우면 「기기 정리」가
아니라 「A 몰래 A의 계정을 건드리는 일」이 된다. A가 다른 기기에서 멀쩡히 쓰고
있을 수 있다."* 그래서 `deleteCardImage` 를 **`uid` 없이** 부른다(`:258`).

⭐ **화면 문구가 이 사실을 정확히 말한다** — `auth_gate.dart:441-446`:
*"이전 계정의 명함은 그 계정의 서버 백업에 그대로 있습니다 … 이 기기에 남아
있는 이전 계정의 명함 사진은 30일 뒤 이 기기에서 삭제됩니다."*
**이번 점검에서 문구와 실물이 가장 잘 맞는 자리였다.**

📌 내 프로필 사진(`_my_profile_card`)은 **일부러 대상에서 뺐다**(`:88`·`:252`
양쪽에서 이중으로 막는다) — A와 B가 같은 파일을 공유하므로 넣으면 **B가 저장한
자기 사진을 30일 뒤에 지워 버린다.**

### 4-4. 회원 탈퇴 — 기기 정리는 빠짐없다

`settings_view.dart:2101 _cleanUpLocalArtifacts`

```
2130  명함 이미지 암호문 전부 + 서버 사본 (deleteAllCardImages(uid:))
2137  사진 개선 동의 기기 캐시
2144  명함 사진 백업 장부
2149  다른 계정에서 넘어온 명함 표시
2154  사진 한도 캐시
2159  "AI에 보낼 정보" 메모리 잔재
2173  스캔 임시 평문 (나이 안 따지고 전부)
2178  촬영 원본 CAP*.jpg · 갤러리 사본
2191  프로필 아바타 평문 JPG
2199  SharedPreferences (명함·프로필·마지막 uid)
2211  암호화 키   ← **반드시 마지막**
```

⭐ **순서가 안전을 결정한다**(`:2096`) — 키를 먼저 지우면 남은 암호문을 열
수도 지울 수도 없다. **하나가 실패해도 나머지는 계속 간다**(멈추면 더 남는다).

📌 **탈퇴 경로에서 서버 사진 삭제가 실패하는 것은 정상이고 버그가 아니다**
(`:2114-2121`) — 계정이 먼저 지워져 `request.auth` 가 null 이고
`storage.rules` 의 `isOwner(uid)` 가 거짓이 된다. **실물은 Cloud Functions 가
Admin SDK 로 지운다**(`cardPhotoCleanup.ts`). 순서를 바꿔 고치려 들지 말 것.

**서버 쪽(`onUserDeletedCleanup`, `index.ts:1685`)이 이어서 지우는 것**

```
appleAuth/{uid}             + Apple refresh_token 폐기 요청   1698-1710
socialTesterEmails/{uid}                                      1717
aiAuditLogs (uid 쿼리)                                        1729
inquiries (+ replies 하위)                                    1745
pilotEvents/{uid}/events/*                                    1779
Cloud Storage 명함 사진                                        1806
users/{uid}/deletedContacts/*                                 1831
phoneAccounts (uid 쿼리) + phoneOtpChallenges                 1868
```

---

## 5. 🚨 일부러 남기는 것 — 방침에 적혀 있나

| 남는 것 | 왜 (코드 근거) | 방침에 있나 |
|---|---|---|
| `deviceLedger/{deviceHash}` | 재가입×무료체험 무한 루프 방어 (`index.ts:1767-1771`, 설계 §4-2) | ❌ **못 찾았다** |
| `phoneSendLedger/{phoneHash}` | 지우면 탈퇴→재가입으로 하루 5통 상한이 초기화된다 (`index.ts:1859-1863`) | ❌ **못 찾았다** |
| `purchases/{transactionId}` | 전자상거래법 §6 — 5년 | ✅ `privacy-policy.html:639` 표 |

🚨 **코드가 스스로 그렇게 적어 뒀다** — `index.ts:1862`:
*"그래서 이 장부는 방침에 **「탈퇴 후에도 남는 것」으로 명시해야 한다**."*
**아직 안 됐다.** 방침의 「탈퇴 후에도 보존하는 항목」 표
(`privacy-policy.html:639-650`)에는 **전자상거래법 근거의 거래기록 둘뿐**이다.

⚠️ **지금은 데이터가 안 생길 수 있다** — 번호 확인 게이트와 지갑이 꺼져 있다고
기록돼 있다(`docs/planning/RESUME.md` 2026-09-04 기록). 🚨 **이것은 내가 잰
값이 아니라 문서에서 읽은 것이다** — 서버 실물(`config/phoneVerification`
문서 유무, `config/billing.model` 필드 유무) 조회는 이 세션의 권한 밖이다.
**켜기 전에 반드시 다시 잴 것.**

---

## 6. 못 갈랐다 — 「모르겠다」로 남기는 것

📌 **추정으로 채우지 않았다.** 아래는 **의도인지 빠뜨림인지 근거를 못 찾은**
것들이다.

### 6-1. `users/{uid}/contacts/{id}/commLogs/{logId}` — 규칙은 있는데 쓰는 곳이 0건

```
firestore.rules:728   match /commLogs/{logId} { allow read, write: if isOwner(uid); }
쓰는 곳                grep -rn "collection('commLogs')\|collection(\"commLogs\")" lib functions/src
                      = **0건**
실제 저장 위치         contact_model.dart:211 — 명함 **문서 안의 필드**로 들어간다
```

⚠️ **그래서 지금은 파기 누락이 아니다**(그 경로에 문서가 안 생긴다). 다만
**규칙만 남아 있으면 나중에 누가 그 경로에 쓰기 시작했을 때 파기 코드가 없다.**
`deleteAllUserData` 도 `onUserDeletedCleanup` 도 그 하위를 안 지운다 —
§1-1의 `cardSources` 와 **똑같은 함정**이 열려 있는 셈이다.
📌 규칙을 지울지, 파기 코드를 미리 넣을지는 **판단이 필요한 자리**다.

### 6-2. 지갑·관리자 계열 — 켠 뒤에 다시 봐야 한다

`creditGrants` · `creditGrantAudits` · `adminSessions/{uid}` · `referralCodes`
는 `onUserDeletedCleanup` 의 삭제 목록에 없다. **지금은 지갑이 꺼져 있어 데이터가
안 생긴다고 보이지만**(§5의 ⚠️ 와 같은 전언 기반), **켜는 날 이 표를 다시
채워야 한다.** 지금 「결함」이라고 부르지 않는다.

### 6-3. 서버 실물을 안 봤다

**이 점검은 코드만 읽었다.** `users/{uid}/cardSources` 에 지금 문서가 몇 건
있는지, 탈퇴한 uid 의 것이 실제로 남아 있는지는 **Firestore 를 열어야 안다.**

🚨 **이 저장소가 반복해서 겪은 것이 정확히 이 지점이다** — CLAUDE.md 4절의
표 첫 줄이 *"서버에 명함 개인정보 평문 3건 · 코드는 정상 · **Firestore 실물
조회**로 잡힘"* 이다. **코드가 맞다고 실물이 맞는 것이 아니다.**

---

## 7. 고칠 때 참고 — 우선순위와 주의점

⚠️ **아래는 제안이지 결정이 아니다.** 고칠지·어떻게 고칠지는 globe2030님
결정이고, §1은 방침 문구와도 맞물려 법무 확인이 필요하다.

```
1순위  §1-1  cardSources 탈퇴 파기       제3자 개인정보 원문 · 방침 §14 와 정면으로 어긋난다
2순위  §2    프로필 사진 지우기 둘        이용자가 「지웠다」고 아는데 안 지워진다
3순위  §1-2  ocrStats 탈퇴 파기          방침 문장과 어긋난다 (원문은 없음)
4순위  §3    문구 셋 · §5 방침 표 보강    실물은 맞고 말이 틀린 자리
```

📌 **고칠 때 「어디에 넣는가」가 이번 교훈이다.**
`index.ts:1613` 이 *"파기 대상이 두 벌로 갈라지면 한쪽만 고쳐지는 날이 온다"*
고 경고했고 **그 날이 왔다.** 그러니 §1을 고칠 때는

```
❌ 탈퇴 경로에 한 줄 더 넣는다        →  다음에 또 갈라진다
✅ 두 경로가 같은 함수를 부르게 한다   →  연결 해제처럼 recursiveDelete 로 모으거나,
                                        「uid 스코프 파기 목록」을 한 군데로 뺀다
```

⚠️ **그리고 일부러 깨뜨려 볼 것.** 통과만 확인한 검사는 안 잡는 검사일 수 있다
— `cardSources` 문서를 하나 만들어 두고 탈퇴시켜 **남는지**를 보는 쪽이,
지우는 코드를 넣고 테스트가 초록인 것을 보는 쪽보다 확실하다.

---

## 8. 이 문서를 어떻게 쟀나

```
워크트리   /Volumes/Work/Claude/ct-conflict-fix
브랜치     docs/deletion-paths-audit  (origin/main 에서 팜, 2026-09-05)
도구       grep -rn / sed -n 로 해당 파일 직접 열람
안 한 것   코드 수정 0건 · flutter test·analyze 미실행(코드 변경이 없다)
           **서버 실물 조회 0건** — Firestore·Cloud Storage 는 열지 않았다
```

⚠️ **`grep` 이 못 보는 것을 한 번 물었다**(CLAUDE.md 4절). 「호출부가 없다」를
`grep` 만으로 말하지 않으려고, `deleteCardImage`·`cardSources`·`ocrStats`
셋은 **호출 후보 파일을 직접 열어** 확인했다. 다만 **동적 호출·문자열 조립
경로는 여전히 못 본다** — 이 저장소는 `AccountPaths` 로 경로를 한 군데에 모아
두어 그 위험이 낮지만, **0이라고 단언하지는 않는다.**

작성: 개발C 세션 (2026-09-05) · 배분: PM(터미널)

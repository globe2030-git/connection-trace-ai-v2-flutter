# 커넥션센스 — 아키텍처

|  |  |
|---|---|
| **문서** | 이 앱이 **어떻게 짜여 있는가**. 다음 세션이 코드를 열기 전에 읽는 지도 |
| **왜 만들었나** | 2026-09-05까지 **전용 아키텍처 문서가 없었다** — 설명이 여러 문서에 흩어져 있어 같은 질문이 반복됐다 |
| **잰 날** | 2026-09-05 |
| **무엇으로 쟀나** | `lib/` 디렉터리 구조 · `main.dart` 의 Provider 조립 · `ChangeNotifier` 상속 `grep` · `pubspec.yaml` · `firestore.rules` 의 `match` 블록 |

> ⚠️ **숫자는 낡는 것이 정상이다.** `CLAUDE.md` 3장의 테스트 수와 같다 —
> **정확히 맞을 필요는 없고 「크게 벌어졌는지」만 보면 된다.** 크게 어긋났으면
> 그때 다시 재서 **잰 날짜와 함께** 고쳐 둔다.

---

## 1. 규모 (2026-09-05 실측)

```
lib/          193개 파일 · 62,618줄
  core/        100개   services 44 · utils 50 · models 2 · theme 2 · icons 1
  presentation/ 73개   features 56 · common 16 · navigation 1
  data/         18개   models 10 · repositories 7 · services 1

test/         209개
functions/     38개 (TypeScript)
```

---

## 2. 세 계층

```
┌─ presentation ──────────────────────────────────────────┐
│  features/    auth · wallet · radar · briefing · settings │
│  common/      공용 위젯                                    │
│  view_models  WalletViewModel · RadarViewModel            │
│               GroupsViewModel                             │
└───────────────────────┬─────────────────────────────────┘
                        │  ChangeNotifierProxyProvider
┌─ data ─────────────────▼────────────────────────────────┐
│  repositories  Contacts · MyProfile · Groups · Auth       │
│                Inquiry · Notice · BillingConfig           │
│  services      DataBackupService  (Firestore 전담)        │
│  models        ContactModel · CardSourceModel · …         │
└───────────────────────┬─────────────────────────────────┘
┌─ core ─────────────────▼────────────────────────────────┐
│  services 44   암호화 · OCR · 이미지 · 위치 · 인증 · 결제  │
│  utils 50      순수 함수 (identical_contacts 등)          │
└─────────────────────────────────────────────────────────┘
```

### ⭐ 뷰모델이 리포지토리를 직접 만들지 않는다

`main.dart` 에서 `ChangeNotifierProxyProvider` 로 **리포지토리를 주입**한다
(`:171`~`:185`).

```dart
ChangeNotifierProvider(create: (_) => ContactsRepository()),
ChangeNotifierProxyProvider<ContactsRepository, WalletViewModel>(…),
```

📌 **이 구조 덕분에 테스트에서 가짜 리포지토리를 꽂을 수 있다** — 209개 테스트가
여기에 기대고 있다. 🚨 **뷰모델 안에서 리포지토리를 `new` 하면 그 자리는
테스트가 못 닿는 자리가 된다.**

### 상태를 들고 있는 것 (실측 — `ChangeNotifier` 상속)

```
data/repositories   Contacts · MyProfile · Groups · Auth       ← 리포지토리가 곧 상태다
presentation        Wallet · Radar · Groups (뷰모델)
```

⚠️ **리포지토리가 `ChangeNotifier` 인 것은 의도다.** 명함 목록은 화면 여럿이
같이 보므로, 뷰모델마다 사본을 두면 어긋난다.

---

## 3. 🚨 저장 — **로컬이 원본, 서버는 백업**이다

```
쓰기   화면 → 뷰모델 → 리포지토리 ─┬→ SharedPreferences   원본 · 암호화
                                  └→ DataBackupService   서버 백업 · 암호화

읽기   로컬을 읽는다 → 비어 있으면 서버에서 통째로 내려받는다
```

🚨 **실시간 동기화가 아니다**(2026-08-04 결정, 추가 66). Firestore 를 쓰지만
**Firestore 를 소스 오브 트루스로 쓰지 않는다.**

📌 **이 한 줄이 많은 것을 설명한다.**

```
⭐ 오프라인에서 명함을 등록할 수 있다      지하철·행사장
⭐ 서버가 잠깐 안 되어도 앱이 멈추지 않는다
⚠️ 대신 병합을 우리가 해야 한다            mergeSync — 두 기기가 각자 쌓는다
⚠️ 삭제도 우리가 전파해야 한다             tombstone(deletedContacts)
```

🚨 **여기를 잘못 건드리면 명함이 사라진다.** `CLAUDE.md` 4장이
*"저장·복원·마이그레이션은 전체 테스트(실기기) 등급"* 이라고 정한 자리가
정확히 이곳이다.

---

## 4. 암호화가 지나는 길

```
ContactModel.toBackupJson()        ← 좌표(lat/lng) 제외 (추가 75, C안)
  → DataCryptoService.encryptJson    AES-256-GCM
  → EncryptionKeyService             키 두 곳: 기기 보안저장소 + Firestore
  → { encrypted, schemaVersion }     Firestore 문서
```

**암호문 형식**: `nonce(12B) + ciphertext + MAC(16B)` — **버전도 키 식별자도 없다.**

⭐ **그래도 키를 여럿 시도할 수 있다** — AES-GCM 의 MAC 이 틀린 키를 반드시
거른다. 그것이 **키링**(#826, `decryptJsonWithAny`)이고, 계정을 이을 때 쓴다.

⚠️ **제로-지식이 아니다.** 키가 암호문과 **같은 Firestore 프로젝트**에 있다
(`users/{uid}.encryptionKeyB64`). 코드 주석이 그 한계를 일부러 적어 두었다
(`encryption_key_service.dart:19`).

📌 **그래서 관리자 조회가 「가능」하다** — 2026-09-05에 *"관리자가 암호화된
명함을 못 본다"* 는 전제가 틀렸다는 것이 여기서 드러났다. 못 보는 것이 아니라
**보여 주는 화면이 없었다.**

---

## 5. 서버 — Cloud Functions

```
functions/src   38개 TypeScript
  순수 로직     phoneOtp · walletCredits · adminAuth · referralCode · …
  진입점        index.ts  (Callable · 트리거)
  테스트        17개  — 🆕 2026-09-05부터 CI 가 돈다 (#830)
```

### ⭐ 순수 함수를 따로 떼는 패턴

`phoneOtp.ts` 가 본보기다. **판정만** 담고 부수효과(문자 발송·Firestore 쓰기)는
`index.ts` 가 맡는다.

```
verifyOtp · phoneHash · decideSend        전부 순수 함수
  → 실제 시계·문자 없이 3분 만료를 테스트로 고정할 수 있다
```

📌 **`adminAuth.ts`(2026-09-05)도 같은 모양으로 만들었다** — 유휴 20분·절대
상한 12시간을 실제 시계 없이 고정한다. **새 서버 로직은 이 패턴을 따른다.**

🚨 **2026-09-05까지 이 17개를 CI 가 한 번도 안 돌렸다.** `npm test` 에 등록까지
돼 있는데 워크플로에 npm 단계가 없었다 — `flutter test` 가 1,977건까지 늘어나는
동안 **서버 쪽은 계속 0건**이었다.

---

## 6. Firestore 컬렉션 (rules 기준 = 실제로 존재하는 경로)

```
users/{uid}
  encryptionKeyB64 · profile · groups · 동의 3종 · aiUsage · 사진 한도
  phoneVerifiedAt · phoneHash
  ├── contacts/{id}         명함     {encrypted, schemaVersion}
  ├── cardSources/{id}      파싱 원본 {encrypted}   (2026-09-05 신설)
  ├── deletedContacts/{id}  삭제 표식
  └── commLogs/{id}         연락 기록

phoneAccounts/{번호해시}     번호 → uid          🚨 「사람」의 씨앗
adminSessions · config/admins · adminAuditLogs   관리자 (설계 중)
inquiries · notices · legalDocs · purchases · creditGrants · …
```

⚠️ **`grep` 이 못 보는 것**: 코드가 만들지만 rules 에 `match` 가 없는 경로.
다만 이 프로젝트는 rules 가 촘촘해 **그런 경로는 쓰기가 막히므로**, 여기서는
rules 를 실물로 읽어도 된다.

---

## 7. 🚨 C안이 건드리는 자리는 **한 층뿐**이다

```
presentation   그대로
data           ← 여기만 바뀐다 (명함 경로가 uid 밑 → 사람 밑)
core           그대로 (키링이 이미 자리를 냈다)
```

⭐ **그래서 C안 1단계가 「명함첩 경로를 함수 하나로 감싸기」다.** 21곳에 흩어진
`users/{uid}/…` 조립을 한 군데로 모으면 **그 한 군데만 바꿔서** 옮길 수 있다.

설계: [`specs/사람-레이어-C안-설계-2026-09-05.md`](./specs/사람-레이어-C안-설계-2026-09-05.md)

---

## 8. 이 구조에서 반복해서 나온 결함 유형

📌 **아키텍처를 아는 것보다 이걸 아는 것이 더 쓸모 있을 때가 많다.**

### ① 「있는데 아무도 안 부른다」

```
재시도 로직        서비스는 정상, 부르는 쪽이 없었다        (추가 79)
중복 판정기        만들어 두고 lib/ 안 호출 0건            (#820에서 연결)
Functions 테스트   npm test 에 등록됐는데 CI 가 안 돌렸다   (#830에서 연결)
```

🚨 **새 코드를 넣을 때 「부르는 곳까지」 이었는지 확인한다.** 계층이 셋이라
중간에서 끊기기 쉽다.

### ② 「코드는 맞는데 화면이 안 말한다」

```
복호화 실패        debugPrint 로만 남기고 빈 목록으로 시작   (#820)
광고 동의 뒤로가기  저장은 정상인데 화면이 그 사실을 안 말함
```

⭐ **`debugPrint` 는 릴리스에서 아무 데도 안 나온다.** 로그로 남긴 것은
**남긴 것이 아니다.**

### ③ 「소스를 문자열로 검사하는 테스트」가 리팩터링에 깨진다

화면 흐름 몇 개는 위젯 테스트 대신 **소스를 텍스트로 읽어** 검사한다
(`continue_scanning_flow_test` 등). 값이 싸지만 **인자 모양까지 넣어 찾으면
의도는 그대로인데 검사만 깨진다.**

📌 **찾는 문자열은 「의도」에 맞춰 최소한으로 잡는다.**

---

## 9. 이 문서가 판단하지 않는 것

실측하다 눈에 띈 것 둘을 적어 두되, **고치자고 하지 않는다.**

```
core/ 가 lib 의 절반이 넘는다        services 44 + utils 50
DataBackupService 가 혼자 다 맡는다   명함·프로필·그룹·원본 (data/services 1개)
```

⚠️ **「지금 문제」라는 뜻이 아니다.** 재보기만 했다. 지금 하는 일과 섞으면
둘 다 흐려진다 — **손대려면 그때 따로 재고 따로 정한다.**

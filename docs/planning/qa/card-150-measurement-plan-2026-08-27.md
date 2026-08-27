# 아이폰 명함 150장 등록 — 측정 계획 (2026-08-27 작성)

> ⚠️ **이 문서는 계획만 담았다.** 작성 세션은 실기기를 조작하지 않았다(사용자
> 취침 중). 아래 절차는 **내일 아침 사용자가 직접** 수행한다.
>
> 작성 근거는 전부 **코드를 읽고 확인한 것**이다(계산 아님) — 각 항목에
> 파일 경로를 남겨 다음 사람이 다시 확인할 수 있게 했다.

---

## 0. 먼저 알아야 할 것 — 이번 판단에 깔린 전제 셋

1. **명함을 인앱에서 지우면 서버(Firestore·Storage) 사본도 함께 지워진다.**
   (`lib/data/repositories/contacts_repository.dart:744~768` `deleteContact` —
   로컬 파일 + `DataBackupService.deleteContactBackup` + 서버 사진(`.enc`)
   삭제를 한 번에 한다.) 그래서 **계정을 지우지 않고도** 진짜 0장에서
   시작할 수 있다.
2. **앱을 지웠다 다시 깔면 복원된다 — 0장이 안 된다.**
   (`contacts_repository.dart`의 `restoreFromServerIfEmpty` — 로컬 명함
   목록이 비어 있으면 **로그인 시 서버 백업을 통째로 내려받는다.** 사진도
   `ContactImageService.downloadMissingCardImages`가 뒤따라 내려받는다.)
   즉 **"앱 삭제 후 재설치"만으로는 깨끗해지지 않는다** — 서버에 남아
   있는 한 그대로 되살아난다. 이번 지시서가 미리 경고한 함정이 실제
   코드로 확인됐다.
3. **계정 삭제(회원 탈퇴)는 되돌릴 수 없는 조작이라 자동화하지 않는다** —
   CLAUDE.md 4-2절. 아래 절차는 전부 **사용자가 직접 화면을 보고 누르는
   것**을 전제로 적었다.

---

## 1. 아침에 사용자가 그대로 따라 할 순서

전체 소요는 **명함 150장을 실제로 입력하는 시간(사용자 페이스, 가장 큼)을
빼면 15~20분** 안팎이다. 아래 번호대로 하면 된다.

### 1단계 — 시작 전 스냅샷 (약 5분)

1. **기기 연결 확인**: `xcrun devicectl list devices`로 아이폰이 잡히는지만
   확인한다(세션이 이미 확인함, 아침에 다시 한 번).
2. **지금 아이폰 계정의 이메일·uid 확인**: 설정 화면 상단(로그인 이메일
   표시 줄, 20초 뒤 자동으로 가려지니 그 안에 확인)에서 이메일을 본다.
   uid는 Firebase 콘솔 → Authentication에서 그 이메일로 검색하면 나온다.
3. **아래 "기록표 A(시작 전)"를 채운다**:
   - 지금 이 계정의 명함 수 — 앱의 "명함 지갑" 탭 상단 개수 배지로 바로
     보인다.
   - `설정 → OCR 통계` 화면을 열어 **우측 상단 "초기화" 버튼**을 눌러
     지금까지 쌓인 값을 비운다(`ocr_stats_view.dart`의 초기화 버튼 —
     이렇게 해야 오늘 150장만의 채움률/수정률이 나온다). 초기화 전 화면에
     찍힌 숫자가 있으면 그것도 참고로 기록해 둔다(오늘 이전 누적치이므로
     "이전 참고값"으로만 쓴다).
   - (선택, 시간 여유 있으면) Firebase 콘솔에서 `aiUsage.dailyCount`·
     `monthlyCount`·`bonusCredits` 값을 확인해 적어 둔다(경로는 2절 C-1
     참고). 오늘 등록 자체는 AI를 부르지 않으므로 이 값은 등록 전후로
     안 바뀌는 게 정상이다 — **바뀌면 그것 자체가 이상 신호**다.

### 2단계 — 명함 전부 지우기 (사용자 직접 조작, 카드 수에 비례 — 대략 1~3분)

⚠️ **삭제는 되돌릴 수 없다. 사용자가 직접 누른다.**

1. **명함 지갑** 탭을 연다.
2. **선택 모드**로 들어간다(우측 상단 진입 버튼).
3. **전체 선택**을 누른다.
4. 하단에 뜨는 **"N개 삭제"** 버튼을 누른다.
5. 확인 대화상자(*"선택한 명함과 기록이 기기와 서버에서 모두 삭제됩니다.
   되돌릴 수 없습니다."*)에서 **삭제**를 누른다.
6. 명함 지갑이 0장인지 눈으로 확인한다.

📌 **왜 이 방법인가**(3절에 비교표) — 계정을 지우지 않고, AI 사용 이력
(`aiAuditLogs`)도 그대로 남기면서, 서버 사진까지 확실히 지우는 유일한
방법이다.

### 3단계 — (선택) 나중에 정확도를 채점하고 싶다면, 등록 전에 결정할 것 (1분)

150장을 **아이폰 기본 카메라 앱으로 먼저 다 찍어 사진 앱에 남겨 두고**,
등록할 때 앱 카메라로 재촬영하지 않고 **"갤러리에서 선택"** 으로 그 사진들을
불러와 등록하면 — 나중에 그 원본 사진들이 그대로 사진 앱에 남아 있어
`설정 → 명함 일괄 스캔(관리자)` 화면에서 다시 불러와 채점할 수 있다
(2절 C-3 참고). **이 단계를 건너뛰고 앱 카메라로 바로 찍으면, 채점 가능한
원본이 남지 않는다**(release 빌드에서는 크롭본 보존 스위치가 아예 안
돈다 — `lib/core/utils/measure_sample_sink.dart`의 `kDebugMode` 게이트).
어느 쪽이든 등록 자체는 문제없다 — **이건 "나중에 정확도를 몇 %로 잴 수
있는가"에만 영향**을 준다.

### 4단계 — 150장 등록 (본 작업, 사용자 페이스)

평소 쓰던 방식대로 등록한다. 중간에 앱을 껐다 켜도 무방하다(등록된 것은
그때그때 로컬+서버에 남는다).

### 5단계 — 등록 직후 측정 (약 10분)

1. **사진 백업 숫자 갱신 확인** (2절 항목 2 상세) —
   - 등록을 마친 **그 상태 그대로**(앱을 재시작하지 않고) 설정 화면을
     열어 "명함 사진 백업" 줄의 숫자를 본다 → 캡처.
   - 그다음 **앱을 완전히 종료**한다(홈 버튼/제스처로 백그라운드로 보내는
     게 아니라, 앱 스위처에서 위로 스와이프해 종료). 다시 켜서 설정 화면을
     또 연다 → 캡처.
   - 두 숫자가 **같으면 이미 고쳐진 것**, **재시작 후에만 맞으면 아직
     안 고쳐진 것**이다(코드 근거는 2절 참고).
2. **OCR 채움률/수정률 확인** — `설정 → OCR 통계` 화면을 열어 그대로
   캡처하고 "기록표 C"에 옮겨 적는다.
3. **AI 사용 횟수·카드 수 스냅샷(2차)** — "기록표 A(등록 후)"를 채운다.
   카드 수는 150(±삭제/중복 처리로 살짝 다를 수 있음), `aiUsage` 값은
   등록 전과 **똑같아야 정상**이다(등록이 AI를 부르지 않으므로).
4. **서버 사진 업로드 확인** — Firebase 콘솔 → Storage →
   `users/<uid>/cards/` 폴더를 열어 파일 개수를 센다(또는 아래 2절 C-4의
   `gsutil` 명령). 등록한 사진 있는 카드 수와 맞는지 "기록표 D"에 적는다.

### 6단계 — 며칠 뒤 후속 확인 (당일 아님, 캘린더에 메모만)

명함 수 ↔ AI 사용 횟수의 **진짜 상관관계**는 하루 만에 안 나온다(등록
자체는 AI를 안 부르므로). 앞으로 며칠 이 계정으로 평소처럼 AI 브리핑을
쓰면서, 가끔 `aiAuditLogs`에서 이 uid의 누적 호출 수를 다시 세어 보면
"카드 150장인 계정이 카드가 적은 다른 테스터 계정보다 AI를 더/덜 쓰는가"를
볼 수 있다(2절 C-1).

---

## 2. 측정 항목별 상세

### C-1. 명함 수 ↔ AI 사용 횟수 상관관계

📌 **왜 아무도 못 쟀는지가 먼저 보였다** — `aiUsage.dailyCount`/
`monthlyCount`는 **매일/매달 리셋되는 값**이라(`functions/src/index.ts:165`
`DAILY_LIMIT = 20`, `:168` `MONTHLY_LIMIT = 100`), 그 값만으로는 "이 계정이
지금까지 AI를 총 몇 번 썼는지"를 알 수 없다. **누적치가 필요하면 다른
곳을 봐야 한다.**

| 무엇 | 어디서 읽나 | 비고 |
|---|---|---|
| **명함 수(누적, 현재)** | Firestore `users/{uid}/contacts` 서브컬렉션 문서 수 (`lib/data/services/data_backup_service.dart:40~42`) | 지금 남아 있는 카드 수. 지운 카드는 안 잡힘 |
| **AI 사용 횟수(누적, 전체 기간)** | Firestore 최상위 컬렉션 `aiAuditLogs`에서 `uid == 그 계정` 조건으로 문서 수 세기 (`functions/src/index.ts:632` `writeAiAuditLog`가 호출마다 한 건씩 적는다. 성공/실패 모두 남음 — `ok` 필드로 성공만 거를 수 있음) | **이게 진짜 누적 사용 횟수다.** 개인정보 없음(uid·성공여부·토큰 사용량뿐) |
| **오늘 시점 일/월 사용량(참고용)** | Firestore `users/{uid}.aiUsage.dailyCount`/`monthlyCount` | 리셋되는 값이라 "지금 얼마나 급하게 쓰고 있나"만 보여줌, 상관관계 분석에는 부적합 |

**방법**: 15개 테스터 계정 각각에 대해 위 두 숫자(명함 수, `aiAuditLogs`
누적 건수)를 뽑아 산점도 하나로 그리면 상관관계를 볼 수 있다. 계정 목록은
`tool/_firebase_admin.py`의 `list_users()`가 `users/{uid}` 문서를 전부
가져오므로(이미 이 저장소에 있는 도구), 여기에 `aiAuditLogs`를 `uid`로
필터링하는 쿼리만 더하면 된다(코드 작성은 이 세션 범위 밖 — 다음에
`flutter-developer`나 별도 스크립트 작업으로 넘길 것).

⚠️ **150장 등록 자체는 이 숫자를 안 바꾼다.** 카드를 등록하는 동작과 AI를
호출하는 동작은 별개라서, 등록 직후엔 "카드 150 / AI 사용 그대로"인
극단값 하나가 추가될 뿐이다. **진짜 상관관계(카드가 많으면 AI도 많이
쓰는가)는 이후 며칠 실사용을 관찰해야 나온다** — 1절 6단계.

### C-2. 사진 백업 숫자 갱신 (backlog 추가 513)

**원인 코드까지 확인했다** — 다른 세션이 아직 안 고친 상태다.

```
lib/presentation/features/settings/views/settings_view.dart
  _CardPhotoBackupStatusRowState._load()  — initState()에서 딱 한 번만 호출
  갱신을 트리거하는 리스너·스트림이 없다

lib/presentation/navigation/main_tab_screen.dart:160
  IndexedStack 사용 — 탭을 왔다갔다 해도 이 State가 파괴되지 않는다
  (didChangeDependencies도 다시 안 불림)
```

즉 **탭을 나갔다 들어와도 갱신되지 않는다.** 유일하게 다시 `initState()`가
불리는 시점은 **앱을 완전히 죽였다 다시 켰을 때**다. 1절 5-1단계의 절차가
정확히 이 차이를 이용한다.

**판정 기준**:
- 등록 직후(재시작 없이) 본 숫자와, 앱 완전 종료 후 재실행해서 본 숫자가
  **여전히 다르면 → 미수정**(코드 그대로).
- **같으면 → 고쳐졌다**(다른 세션이 리스너 기반으로 바꿨다는 뜻 — 이때는
  `_load()` 호출 방식이 바뀌었는지 코드로 한 번 더 확인해 볼 것).

### C-3. OCR 인식 정확도

**정답지 없이도 잴 수 있는 것**과 **정답지가 있어야 하는 것**이 다르다.

| | 무엇을 재나 | 어떻게 | 기존 기준선과 비교 가능? |
|---|---|---|---|
| **정답지 불필요** | 필드별 채움률·사용자 수정률(고쳤다/지웠다/그대로) | `설정 → OCR 통계` 화면(`ocr_stats_view.dart`), 실사용 중 자동 집계(`ocr_stats_service.dart` — `add_card_modal_view.dart:1051`에서 스캔마다, `:2881`에서 저장(수정 여부)마다 기록). **release 빌드에서도 정상 동작**(`kDebugMode` 게이트 없음) | 아니오 — 91장 76.9%는 **정답 대조** 방식이라 형태가 다르다. 다만 "고친 비율이 높다"는 "인식이 약하다"의 근사 신호는 된다 |
| **정답지 필요** | 정확한 "맞음/틀림" 정확도(76.9%와 같은 잣대) | `tool/ocr_review/index.html` + 사람이 한 장씩 정답 입력(README: `tool/ocr_review/README.md`) | 예 — **단, 아이폰에서는 사진을 모으는 단계가 하나 더 필요하다**(아래) |

⚠️ **아이폰에서 정답지 채점이 안드로이드보다 번거롭다.** 기존 절차
(`tool/ocr_review/README.md` "쓰는 순서")는 `adb shell run-as`로 기기 안의
`card_samples` 폴더를 통째로 꺼내는 방식인데, 이건 **안드로이드 전용**이다
— `ocr_batch_scan_view.dart`가 그 폴더를 앱 안에서 읽으려 시도할 때도
"안드로이드에서만 동작"이라고 스스로 알린다(`_scanFromAppFolder` 폴백
메시지). 아이폰에서 쓸 수 있는 경로는 그 화면의 **"갤러리에서 선택"**
버튼(`_pickAndScan`, `image_picker` 기반이라 iOS도 됨)뿐이고, 여기에
쓸 사진이 있으려면 **1절 3단계**(사진 앱에 원본을 남기는 방식으로 등록)를
따라야 한다. 안 따랐다면 이번 150장에 대한 정답지 채점은 사실상 불가능하다
— **다음 큰 표본 등록 때 미리 계획하자.**

기준선(정답지 91장, `docs/planning/backlog.md` 추가 409): **맞음 70·
틀림 14·빈값 7 → 76.9%**. 다음에 정답지를 만들면 이 문서의 방식(끝 쉼표·
라벨 제거 등 규칙)을 그대로 따라야 숫자가 왜곡되지 않는다.

### C-4. 사진 서버 백업이 실제로 올라가는지

```
저장 위치     Cloud Storage 버킷 connection-sense.firebasestorage.app
             경로 users/{uid}/cards/{contactId}.enc
             (lib/core/services/card_photo_backup_service.dart `_ref`)
켜진 시점    2026-08-26, kCardPhotoBackupEnabled = true (같은 파일)
확인 방법 ①  Firebase 콘솔 → Storage → users/<uid>/cards/ 폴더 열어 개수 육안 확인
확인 방법 ②  (정밀) gsutil ls gs://connection-sense.firebasestorage.app/users/<uid>/cards/ | wc -l
             (사전 준비: gcloud auth login 한 번 필요할 수 있음 — firebase login과 별개)
```

등록 **전/후** 개수를 비교한다. 사진 없이 등록한 명함(문자만 스캔)은
안 올라가는 게 정상이다 — 사진이 있는 카드 수와 맞춰서 봐야 한다.

⚠️ **여러 세션이 같은 기기·계정을 동시에 건드리면 개수로 판정하면 안
된다**(CLAUDE.md 4-2절, 2026-08-16 사고 전례) — 지금은 이 계정을 이
작업 하나만 쓰는 것이 전제다. 다른 세션이 같은 시간에 같은 계정으로
뭔가 등록·삭제하면 개수 비교가 무의미해진다.

---

## 3. 아이폰 초기화 절차 — 옵션별 대가 비교

| 방법 | 0장이 되나 | AI 이력(`aiAuditLogs`) | AI 무료/일·월 한도 | 걸리는 시간 | 되돌릴 수 있나 |
|---|---|---|---|---|---|
| **① 인앱에서 선택 삭제(전체 선택 → 일괄 삭제)** ✅ 권장 | ✅ 된다 — 서버 사본까지 지운다(`contacts_repository.dart:744~768`) | ✅ 그대로 남는다(계정을 안 지우므로) | ✅ 그대로(계정 안 바뀜, `aiUsage` 문서 안 건드림) | 1~3분 | ❌ (삭제 자체는 원복 불가, 단 계정은 유지) |
| ② 계정 삭제 후 재가입 | ✅ 된다 — `DataBackupService.deleteAllUserData` + 서버 트리거 `onUserDeletedCleanup`이 Firestore(`contacts`·`aiAuditLogs`·`inquiries`)와 Storage 사진까지 지운다 | ❌ **이 계정의 과거 이력이 통째로 사라진다**(uid가 바뀌므로 15개 테스터 상관분석의 "이전 데이터"를 잃는다) | ⚠️ 새 uid로 `aiUsage` 문서가 새로 생겨 `dailyCount`/`monthlyCount`가 0부터 시작한다(사실상 "무료 한도 리셋"으로 보임 — 메모 근거) | 재로그인 포함 5분+ | ❌ 완전 불가역 |
| ③ 앱 삭제 후 재설치(같은 계정으로 재로그인) | ❌ **안 된다** — 로컬이 비면 `restoreFromServerIfEmpty`가 서버 백업(글자+사진)을 통째로 되살린다 | ✅ 유지(계정 그대로) | ✅ 유지 | 재설치 포함 5분+ | 그대로 서버에 있던 게 다시 나타나므로 사실상 "초기화 아님" |

**결론**: **①을 쓴다.** 오늘 목적(카드만 비우고 계정·이력은 보존)에
정확히 맞고, 유일하게 부작용이 없다. ②는 "정말 완전히 새 계정처럼
써보고 싶다"는 별도 목적이 있을 때만 고려한다(그리고 그 경우 15개
테스터 상관분석에서 이 계정의 과거 데이터가 사라진다는 것을 감수해야
한다). ③은 이번 목적에 아예 안 맞는다(초기화가 안 됨).

---

## 4. 기록표 (빈 칸만 채우면 됨)

### 표 A — 카드 수 · AI 사용량 스냅샷

| 시점 | 명함 수(명함지갑 배지) | `aiUsage.dailyCount` | `aiUsage.monthlyCount` | `aiUsage.bonusCredits` | `aiAuditLogs` 누적 건수(uid 필터) |
|---|---|---|---|---|---|
| 등록 전 | | | | | |
| 삭제 직후(0장 확인) | 0 | | | | |
| 150장 등록 직후 | | | | | |
| +3일 후(선택) | | | | | |
| +7일 후(선택) | | | | | |

### 표 B — 사진 백업 숫자 갱신 확인 (backlog 513)

| 시점 | 화면에 보인 숫자(N/2000) | 실제 서버 개수(Storage 육안 확인) | 일치? |
|---|---|---|---|
| 등록 직후(재시작 안 함) | | | |
| 앱 완전 종료 후 재실행 | | | |

**판정**: 두 줄이 같으면 → 미수정 유지 중 / 첫 줄부터 맞으면 → 수정됨.

### 표 C — OCR 통계 (설정 → OCR 통계 화면 값 그대로 옮겨 적기)

| 필드 | 채움 건수 / 전체 스캔 수 | 채움률 |
|---|---|---|
| 이름 | / | |
| 회사 | / | |
| 직함 | / | |
| 휴대폰 | / | |
| 사무실 전화 | / | |
| 이메일 | / | |
| 주소 | / | |
| 상세주소 | / | |
| 우편번호 | / | |

| 수정 종류 | 건수 |
|---|---|
| 그대로 저장(unchanged) | |
| 고침(edited) | |
| 지움(cleared) | |

전체 스캔 수: ______ / 자동 인식을 한 곳이라도 고친 카드 수: ______

### 표 D — 서버 사진 백업 개수

| 시점 | Storage `users/<uid>/cards/` 파일 수 | 사진 있는 카드 수(앱 기준) | 차이 |
|---|---|---|---|
| 등록 전 | | | |
| 150장 등록 후 | | | |

---

## 5. 요약 보고

### ① 아침에 사용자가 할 일 — 몇 분짜리인가

```
시작 전 스냅샷 기록          약 5분
명함 전부 지우기(인앱 선택삭제)  카드 수에 비례, 대략 1~3분
(선택) 채점용 촬영 방식 결정    1분
150장 등록                   본 작업 — 사용자 페이스(가장 오래 걸림, 이 계획의 시간에서 제외)
등록 직후 측정 4가지 기록       약 10분
─────────────────────────────
등록 자체를 빼면 총 15~20분 안팎
```

### ② 150장으로 잴 수 있는 것 / 못 재는 것

**잴 수 있는 것**
- 사진 백업 숫자 갱신 버그(513)가 고쳐졌는지 — **즉시, 확실하게** 판정
  가능(표 B).
- 서버 사진 백업이 실제로 150장어치 새로 올라가는지 — **즉시** 확인 가능
  (표 D).
- OCR 채움률·사용자 수정률(정답지 없는 근사 정확도 신호) — **즉시** 확인
  가능(표 C), 단 76.9%와 **같은 잣대는 아니다**.
- 카드 수·AI 사용 누적치의 "한 시점 스냅샷" — **즉시** 기록 가능(표 A
  첫 두 줄), 이 계정이 15개 테스터 분포에서 "카드 150장" 쪽 극단값 하나를
  보태 준다.

**못 재는 것(오늘 하루로는)**
- 카드 수와 AI 사용 횟수의 **진짜 인과·상관관계** — 등록은 AI를 부르지
  않으므로 오늘은 "카드 150 / AI 사용 그대로"인 스냅샷 하나만 남는다.
  상관관계를 보려면 **여러 계정을 가로로 비교**(15개 테스터, 이번
  세션에서 방법만 확인)하거나 **이 계정을 며칠 관찰**해야 한다.
- 76.9% 기준선과 **직접 비교 가능한 정확한 인식률** — 정답지 채점이
  필요한데, 아이폰에서는 채점용 원본 사진을 사진 앱에 남기는 절차(1절
  3단계)를 **미리 따랐을 때만** 가능하다. 안 따랐다면 이번 150장은
  "채움률·수정률"이라는 근사치까지만 나온다.

---

## 참고 — 이 문서를 쓰며 읽은 파일

```
docs/planning/HANDOFF.md, docs/planning/tomorrow-2026-08-27.md, docs/planning/backlog.md(추가 409·513)
lib/core/services/ai_usage_service.dart
lib/core/services/card_photo_backup_service.dart
lib/core/services/card_photo_backup_state.dart
lib/core/services/card_photo_quota_service.dart
lib/core/utils/card_photo_quota.dart
lib/core/utils/measure_sample_sink.dart
lib/core/services/ocr_stats_service.dart
lib/presentation/features/settings/views/ocr_stats_view.dart
lib/presentation/features/settings/views/ocr_batch_scan_view.dart
lib/presentation/features/settings/views/settings_view.dart
lib/presentation/navigation/main_tab_screen.dart
lib/presentation/features/wallet/views/wallet_view.dart
lib/presentation/features/wallet/view_models/wallet_view_model.dart
lib/data/repositories/contacts_repository.dart
lib/data/services/data_backup_service.dart
lib/core/services/contact_image_service.dart
functions/src/index.ts (DAILY_LIMIT/MONTHLY_LIMIT, writeAiAuditLog, bootstrapAccount, onUserDeletedCleanup)
functions/src/freeGrant.ts, functions/src/deviceLedger.ts
tool/_firebase_admin.py, tool/verify_server_privacy.py, tool/check_admin_sync.py
tool/ocr_review/README.md
android/app/google-services.json, ios/Runner/GoogleService-Info.plist (버킷명)
```

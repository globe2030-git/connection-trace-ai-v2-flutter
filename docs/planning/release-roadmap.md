# 출시 준비 통합 실행 계획 (2026-08-04)

이 문서는 `flutter-planner`(기획 점검), `flutter-ui-designer`(UI 진단),
`flutter-qa`(회귀 테스트) 세 에이전트가 각각 보고한 내용을 하나로 묶어
"무엇이 남았고 어떤 순서로 처리하는지"를 정리한 실행 계획서다.
시간순 상세 기록은 `docs/planning/backlog.md`, 현재 상태 요약은
`docs/planning/HANDOFF.md`에 있고, 이 문서는 그 둘을 바탕으로 **다음 액션
플랜**만 다룬다.

---

## 1. 현황 요약

한 줄로: **핵심 기능(명함 스캔·근접 알림·AI 브리핑)은 이미 동작하고
디자인도 확정됐지만, "계정과 개인정보를 안전하게 다루는 인프라"와
"스토어 심사에 필요한 법적 문서·기능"이 통째로 비어 있어서 지금 그대로는
출시할 수 없다.**

- **가장 큰 구조적 문제(P0)**: 로그인은 되는데 로그아웃 후 다른 계정으로
  들어가면 이전 계정의 명함·연락처·AI API 키가 그대로 보이는 버그가 있다.
  이건 이번에 사용자가 확정한 "Firebase 서버 도입"으로 해결책이 이미
  설계돼 있고(`docs/planning/server-setup-plan.md`), 구현만 남았다.
- **법적/스토어 심사 문제(P0)**: 개인정보처리방침·이용약관이 없고,
  회원탈퇴(전체 데이터 삭제) 기능도 없다. 이것도 서버 도입 작업의
  일부로 같이 해결되도록 설계돼 있다.
- **UI 버그**: 대부분 화면은 잘 만들어졌지만(GlassCard 일관성, 5단계
  브리핑 상태 분기 등), AI 브리핑 화면에서 텍스트가 안 보이는 버그처럼
  당장 눈에 띄는 결함이 몇 개 있다.
- **QA**: 전체 회귀 테스트가 아직 진행 중이라 결과가 이 문서에는 반영되지
  않았다. 도착하면 8번 섹션에 채운다.

즉 지금부터 해야 할 일은 크게 두 갈래다: **(A) 서버(Firebase) 도입** —
계정 격리 P0, 회원탈퇴, 개인정보 문서의 근본 해결책이자 가장 오래 걸리는
작업(**2026-08-04 개정: AI 연동 서버 프록시 전환도 이 작업에 함께
포함됐다 — 8-6절, `server-setup-plan.md` 14번 섹션 참고**). **(B) 서버와
무관한 UI/UX·코드 정리** — 서버 작업 중 사용자의 Firebase 콘솔 설정을
기다리는 동안 병행할 수 있는 작업들.

---

## 2. 이슈 통합 목록

세 에이전트가 발견한 이슈를 하나로 묶었다. "발견 경로"에 여러 에이전트가
적혀 있으면 같은 문제를 서로 다른 각도에서 발견했다는 뜻이고, "해법
상태"에는 이미 설계가 끝난 것인지 아직 손 안 댄 것인지 표시했다.

### P0 — 출시 차단급

**⚠️ 2026-08-04 PM 우선순위 재감사로 갱신**: 아래 세 항목은 이 표가
작성된 뒤 실제로 구현이 끝났다(코드로 직접 확인). 최신 P0 목록(App
Store Connect 403, Apple 로그인 미제공, AI 실키 검증, 브리핑 오버레이
가독성 버그, 개인정보처리방침 담당자 정식화)은 `HANDOFF.md` "3. 해야 할
일 — P0" 표를 최신으로 볼 것 — 이 문서(release-roadmap.md)의 표는
아래처럼 상태만 갱신하고 원래 발견 맥락은 보존한다.

| ID | 이슈 | 발견 경로 | 관련 파일 | 해법 상태 |
|---|---|---|---|---|
| P0-1 | 계정 전환 시 이전 계정의 명함/프로필/AI 키 노출 | flutter-planner | `lib/data/repositories/auth_repository.dart:109-128`(signOut이 세션만 지움), `contacts_repository.dart`/`my_profile_repository.dart`/`ai_credentials_repository.dart`(전역 `_storageKey` 사용) | **완화 완료(추가 71, 2026-08-04)** — 단, 원래 설계(계정별 `::<uid>` 키 격리)가 아니라 로그인 시 "유지 vs 교체" 확인 다이얼로그로 완화하는 더 가벼운 방식. 저장소 키는 재감사 결과 여전히 전역 키로 확인됨 — QA 스트레스 테스트 필요(`HANDOFF.md` P1-10 참고) |
| P0-2 | 종합 개인정보처리방침/이용약관 부재 | flutter-planner | `location_consent_sheet.dart`(위치만 다룸), `login_view.dart`(약관 링크 없음) | **게시 완료**(`docs/legal/privacy-policy.html`, 추가 72 이전) — 단, 담당자·전용 문의메일은 아직 임시값(`HANDOFF.md` P0-5로 재분류) |
| P0-3 | 회원탈퇴/전체 데이터 삭제 기능 없음 | flutter-planner | 전 리포지토리에 clearAll류 메서드 0건 | **구현 완료(추가 71, 2026-08-04)** — 단, Cloud Functions 방식이 아니라 클라이언트가 Firestore 삭제 → Firebase Auth 삭제 → 로컬 초기화 순서로 직접 처리하는 방식 |

세 항목 모두 해결됐지만, 원래 설계보다 가벼운 방식으로 처리된 두 곳
(P0-1 저장소 격리, P0-3 Cloud Functions 미사용)은 완전한 무결성을
원한다면 후속 강화 대상이다(`HANDOFF.md` P1-10, P2-1 참고).

### P1 — 출시 전 권장

| ID | 이슈 | 발견 경로 | 관련 파일 | 비고 |
|---|---|---|---|---|
| P1-1 | 카메라 권한 거부 시 "설정 열기" 유도 없음 | **flutter-planner + flutter-ui-designer 이중 발견** | `camera_scan_modal_view.dart:99-105, 421-432` | 이미 같은 앱 안에 참고할 패턴이 있음 — `location_access_flow.dart` + `settings_view.dart:140-147`의 `handleLocationAccessAction(openSettingsWhenReady: true)`. 새로 설계할 필요 없이 이식하면 됨 |
| P1-2 | 접근성(Semantics) 커버리지 낮음 | **flutter-planner(전반) + flutter-ui-designer(구체 지점)** | ui-designer가 짚은 구체 지점: 전화 걸기 CTA, 지갑 화면 Dismissible, 브리핑 대화 포인트 카드 | planner는 전반적 부족을, ui-designer는 정확한 위치를 짚어 서로 보완됨. **주의(2026-08-04 추가)**: `ai_data_review_sheet.dart`를 이 작업에서 건드릴 계획이면 5번 섹션 "충돌 위험" 참고 — 같은 파일이 AI 프록시 전환(P1-7)에서도 수정된다 |
| P1-3 | 크래시 리포팅 전무 | flutter-planner | `main.dart`(FlutterError.onError/runZonedGuarded 없음, Crashlytics/Sentry 미도입) | Firebase 도입 시 같은 프로젝트에 Crashlytics를 얹으면 별도 계정 설정 없이 붙일 수 있어 **서버 작업과 묶어서 진행하는 게 효율적** |
| P1-4 | 최초 실행 온보딩 없음 | flutter-planner | `SplashGate → AuthGate → MainTabScreen` 직행 | 서버와 무관, 독립 작업 |
| P1-5 | 로컬 백업/내보내기 없음 | flutter-planner | 없음(신규 기능) | 서버 도입 후 진행 권장(4번 섹션 파일 충돌 근거 참고) |
| P1-6 | 기기 저장자료 암호화 감사 미착수 | HANDOFF "해야 할 일 1번" | `shared_preferences`(평문) vs `flutter_secure_storage`(AI 키만) | 서버와 별개 작업, 병행 가능 |
| **P1-7** | **AI 연동을 BYOK에서 서버 프록시 방식으로 전환(운영사가 AI 키 보유)** | **사용자 지시(QA 8-6절에 접수, 2026-08-04 스코프 확정)** | `ai_credentials_repository.dart`, `ai_briefing_service.dart`, `ai_data_review_sheet.dart`, `ai_connection_modal_view.dart`, 신규 `functions/src/generateBriefing.*` | **설계 완료** — `server-setup-plan.md` 14번 섹션(Cloud Functions AI 프록시, 사용자당 호출량 제한, 무료 등급 데이터 활용 위험 경고 + 유료 등급 권장, 기존 BYOK UI 처리 방침 두 안, 동의 문구 개정안). **Firebase 서버 구축(Phase 3)과 같은 인프라 위에서 함께 구현** — 4번 섹션 Phase 3에 단계 추가됨. 출시를 그 자체로 막는 결함은 아니지만(BYOK로도 출시는 가능), 사용자가 명시적으로 요청한 스코프 확장이라 P1로 편입 |

### P1 — UI 전용 (flutter-ui-designer 단독 발견)

| ID | 이슈 | 심각도 | 관련 파일 |
|---|---|---|---|
| UI-1 | 브리핑 오버레이 검정 배경 위에 검정에 가까운 텍스트색이라 사실상 안 보임 | 높음 | `briefing_overlay_view.dart:203-239`(배경 `Colors.black.withValues(alpha:0.85)` vs 헤더 텍스트 `AppColors.textPrimary` 0xFF171A21) |
| UI-2 | 위치 동의 시트에 리디자인 이전 블루 색상 잔존 | 중간 | `location_consent_sheet.dart:97`(`Color(0x332B76C5)`, 브랜드는 퍼플 0xFF6C5CE7) |
| UI-3 | 성공(초록) 색상 두 화면에서 서로 다름, AppColors에 success 토큰 없음 | 중간 | `settings_view.dart:589`(`Color(0xFF2D7D46)`) vs `camera_scan_modal_view.dart:538,600`(`Colors.greenAccent`) |
| UI-4 | 프로필 아바타 터치 영역이 권장 48×48 미달 | 중간 | `radar_view.dart:155-176`(40×40) |
| UI-5 | 태그 필터 칩 높이 고정 → 폰트 확대 시 클리핑 위험 | 중간 | `wallet_view.dart:97-98`(42px 고정) |
| UI-6 | 카드 그림자 색상 하드코딩(토큰화 안 됨) | 낮음 | `glass_card.dart:35`(`Color(0x0A111827)`) |
| UI-7 | `AppColors`의 `bgDarkSlate`/`cardDark` 등 변수명이 실제 값(흰색 계열)과 반대 | 낮음 | `app_colors.dart:5-7` — **정정**: 다크모드 미지원 버그가 아니라 라이트 테마가 2026-08 확정 리디자인의 의도된 설계. 기능 문제 아님, 나중에 리네이밍만 권장 |

### P2 — 여유 있을 때

| ID | 이슈 | 발견 경로 | 비고 |
|---|---|---|---|
| P2-1 | 죽은 코드: `communication_trace_test_modal_view.dart` + `comm_log_sync_service.dart` | flutter-planner | 서로만 참조, 진입점 없음. 삭제해도 안전 |
| P2-2 | 알림 파이프라인 본설계 미착수 | flutter-planner (HANDOFF "해야 할 일 9번"과 동일) | 중간 규모 신규 설계 필요, 이번 로드맵 범위 밖 |
| P2-3 | 다국어(i18n) | — | 사용자가 프로젝트 마지막 단계로 결정, 지금 손대지 않음 |

### 서버 설계 문서에서 추가로 확인된 사항 (참고용, 이슈라기보다 설계 전제)

- `ContactModel.avatarUrl` / `MyProfileModel.avatarPath`는 이름과 달리
  원격 URL이 아니라 기기 로컬 파일 경로 — 1단계 서버 설계에서 사진
  원본은 서버에 올리지 않기로 결정해 문제를 회피함. **2026-08-04
  갱신**: 이 사진들을 서버(Cloud Storage)에 올리는 작업을 막연한 후보가
  아니라 명확한 **2단계 계획**으로 승격했다(`server-setup-plan.md`
  15번 섹션) — 1단계 범위 자체는 바뀌지 않음, 8-6절 참고.
- 좌표(lat/lng)는 위치정보법상 재검토 필요 사유로 서버 미저장 결정
  (backlog 추가 40 근거) — 이 판단 자체가 P0-2(개인정보처리방침)의
  내용에 직결되므로 문서 작성 시 함께 반영해야 함.
- Firebase Authentication은 서울 리전 고정이 불가해 국외이전 고지가
  필요할 수 있음 — P0-2 처리 시 법무 검토 권장 항목.
- **2026-08-04 신규**: AI 연동을 BYOK에서 서버 프록시로 전환하기로
  확정하면서, Google Gemini API의 **무료 등급이 입력 데이터를 사람
  검수·모델 개선에 활용하는 정책**임을 확인했다(`server-setup-plan.md`
  14.2절 근거) — 서버가 보유할 AI 키는 반드시 유료 등급으로 발급해야
  한다는 경고가 이번에 새로 추가됐다.

---

## 3. 담당 에이전트 배정

| 작업 영역 | 담당 |
|---|---|
| Firebase 연동 코드(AuthRepository/ContactsRepository/MyProfileRepository 재작성, 마이그레이션, Firestore Rules, Cloud Functions 회원탈퇴) | **flutter-developer** |
| **AI 프록시 전환(Cloud Functions `generateBriefing`, 호출량 제한, `ai_briefing_service.dart`/`ai_data_review_sheet.dart`/`ai_connection_modal_view.dart`/`ai_credentials_repository.dart` 정리)** | **flutter-developer**(2026-08-04 추가, `server-setup-plan.md` 14번 섹션) |
| 크래시 리포팅 도입(Crashlytics + main.dart 훅) | **flutter-developer** |
| 카메라 권한 "설정 열기" 로직 이식(P1-1) | **flutter-developer** (기존 `location_access_flow.dart` 패턴 재사용이 핵심이라 로직 성격) |
| 로컬 백업/내보내기 기능 | **flutter-developer** |
| 기기 저장자료 암호화 감사·이전(P1-6) | **flutter-developer** |
| 죽은 코드 제거(P2-1) | **flutter-developer** |
| UI 버그 수정(UI-1~UI-6) | **flutter-ui-designer** |
| AppColors 변수명 리네이밍(UI-7) | **flutter-ui-designer** (단독, 별도 시점) |
| 접근성(Semantics) 보완(P1-2) | **flutter-ui-designer** |
| 온보딩 화면(P1-4) | **flutter-ui-designer**(화면·비주얼) → **flutter-developer**(SplashGate/AuthGate 연동, 완료 플래그 저장) 순차 협업 |
| 개인정보처리방침/이용약관 초안 작성 | 기획(이 세션) — `server-setup-plan.md` 9번 섹션 기반으로 초안 작성 가능, 최종 게시는 사용자 |
| 전 구간 QA(계정 격리, 회원탈퇴, 마이그레이션, UI 수정 검증, **AI 프록시 호출 한도 검증**) | **flutter-qa** |

---

## 4. 작업 순서 로드맵

의존관계, 사용자 대기 구간, 병행 가능/불가능 조합을 반영한 순서다.

### Phase 0 — 지금 바로 시작 (서버와 무관, 병행 가능)

사용자의 Firebase 콘솔 설정을 기다릴 필요 없이 지금 바로 착수 가능한
작업들. 서로 다른 파일을 건드리므로 대부분 동시 진행 가능하다.

1. **UI-1 (브리핑 텍스트 안 보임) 수정** — `flutter-ui-designer`, 최우선
   (사용자가 지금 당장 브리핑 화면을 못 읽는 상태이므로 체감 임팩트 큼).
2. **UI-2/UI-3/UI-4/UI-5/UI-6 개별 색상·터치영역 버그 수정** —
   `flutter-ui-designer`, 1번과 병행 가능하나 **UI-7(AppColors 리네이밍)과는
   동시 진행 금지**(아래 "충돌 위험" 참고). 먼저 개별 버그를 다 고친
   뒤 마지막에 리네이밍을 몰아서 한다.
3. **P1-1 (카메라 권한 설정 열기)** — `flutter-developer`, UI 작업들과
   파일이 겹치지 않아 병행 가능.
4. **P2-1 (죽은 코드 제거)** — `flutter-developer`, 완전 독립 작업.
5. **P1-6 (기기 저장자료 암호화 감사)** — `flutter-developer`. 단, 이
   작업이 만지는 파일(`contacts_repository.dart` 등)이 Phase 2~3의 서버
   전환 작업과 겹치므로 **Phase 2 착수 전에 끝내거나, 감사 결과를 서버
   전환 설계에 반영하고 나서 함께 진행**하는 게 안전.

### Phase 1 — 사용자 대기 구간: Firebase 콘솔 준비 (사용자 작업)

`server-setup-plan.md` 10번 섹션 "준비 단계"(1~5번). 이 구간은 사람이
직접 브라우저로 클릭해야 하는 작업이라 **코드로 대신할 수 없다** —
사용자가 완료할 때까지 서버 관련 개발은 시작할 수 없다.

- Firebase 프로젝트 생성, Blaze(종량제) 요금제 전환, Firestore 리전을
  `asia-northeast3(서울)`로 생성, Authentication에서 Google 로그인 활성화.
- **2026-08-04 추가**: 이 대기 구간에 AI 프록시용 준비도 함께 끝내는 걸
  권장 — Anthropic/OpenAI/Google AI Studio 콘솔에서 운영사 명의 계정으로
  키 발급 및 **결제(유료 등급) 연결**(6번 섹션 체크리스트 참고).

**이 대기 중 병행할 작업**: Phase 0에서 못다 한 UI 작업, P1-4(온보딩
화면 디자인 — 로직 연동 없이 화면만 먼저 그려둘 수 있음), P1-2(접근성
보완). Phase 0과 마찬가지로 서버 관련 파일은 건드리지 않는 작업들이라
안전하게 병행 가능.

### Phase 2 — 앱-Firebase 연결 (flutter-developer, 순차 필수)

`server-setup-plan.md` 10번 섹션 6~9번. `flutterfire configure` 실행,
`firebase_core`/`firebase_auth`/`cloud_firestore`/`cloud_functions`
패키지 추가, `main.dart`에 `Firebase.initializeApp()` 추가.

- **주의**: `main.dart`를 건드리는 작업이므로, 같은 파일을 만지는
  **P1-3(크래시 리포팅)과는 동시에 진행하지 말고 이 Phase 안에서
  같이 처리**하는 게 효율적(파일 충돌 방지 + 두 번 열 필요 없음).
  즉 "Firebase 초기화 + Crashlytics 초기화"를 한 커밋 단위로 묶는다.

### Phase 3 — 서버 전환 코드 구현 (flutter-developer, 순차 필수)

`server-setup-plan.md` 10번 섹션 10~15번. **P0-1/P0-2/P0-3이 여기서
동시에 해결된다.**

1. `AuthRepository`를 Firebase Auth 기반으로 재작성.
2. `ContactsRepository`/`MyProfileRepository`를 Firestore 기반으로
   재작성 + 계정별 로컬 캐시 격리(P0-1 수정 본체).
3. 마이그레이션 서비스 구현(기존 로컬 데이터 → 서버, 소유권 확인
   다이얼로그 포함).
4. `firestore.rules` 작성·배포, Rules Playground로 "타 계정 읽기 차단"
   시뮬레이션.
5. Cloud Functions `deleteAccountData` 작성·배포(P0-3 회원탈퇴 본체).
6. 설정 화면에 "회원 탈퇴" UI 신규 구현.
7. **(2026-08-04 추가, P1-7) Cloud Functions AI 프록시(`generateBriefing`)
   구현·배포** — `server-setup-plan.md` 14.3~14.4절 설계 반영. 실제
   AI API 키는 서버 환경변수/Secret Manager에만 등록(유료 등급 키인지
   반드시 확인), 사용자당 일/월 호출량 제한 로직 포함.
8. **(2026-08-04 추가, P1-7) `ai_briefing_service.dart`를 콜러블 함수
   호출로 교체, `ai_data_review_sheet.dart` 동의 문구 개정(14.7절 초안
   반영), 기존 BYOK 설정 화면(`ai_connection_modal_view.dart`)을 채택된
   처리 방침(14.6절 옵션 A 또는 B)에 맞춰 정리.**

- **충돌 위험**: 이 Phase는 `contacts_repository.dart` /
  `my_profile_repository.dart` / `auth_repository.dart`를 대규모로
  재작성하므로, **P1-5(로컬 백업/내보내기)처럼 같은 리포지토리를 읽는
  신규 기능은 이 Phase가 끝난 뒤에 시작**해야 한다(재작성 중인 인터페이스
  위에 새 기능을 얹으면 충돌·재작업 위험).
- 이 Phase가 끝나면 UI-1~UI-7, P1-1~P1-4 등 Phase 0~1에서 진행한 UI
  작업들과 자연스럽게 합류(서로 다른 레이어라 충돌 없음).

### Phase 4 — 실기기 검증 (flutter-qa)

- 다중 계정 전환 시 데이터 격리(P0-1 해소 확인) — 반드시 실기기.
- 오프라인 등록 후 온라인 동기화.
- 마이그레이션 확인 다이얼로그(소유권 확인) 플로우.
- 회원탈퇴 흐름(즉시 삭제).
- **AI 회차 소진 시나리오 — 잔액 0에서 안내 문구가 뜨고 요청이 차단되는지
  확인.** ⚠️ **2026-08-18 갱신**: 일/월 호출 한도 제도는 폐지됐다(충전형 확정,
  추가 303). 지갑 전환(P1-5) 전까지는 코드에 `DAILY_LIMIT`/`MONTHLY_LIMIT`이
  남아 있으므로, 그때까지는 한도 초과 경로도 함께 확인한다.**
- **AI 브리핑이 서버 프록시를 거쳐 정상 생성되는지, 앱 바이너리에 AI
  API 키가 하드코딩돼 있지 않은지 확인(2026-08-04 추가).**
- Phase 0~1에서 수정한 UI 버그들의 회귀 확인(UI-1~UI-6).
- `server-setup-plan.md` 13번 섹션 체크리스트 전체 실행.

### Phase 5 — 출시 전 사용자 전용 작업 (사용자만 할 수 있음)

- 개인정보처리방침·이용약관 게시(법률 검토 권장, 특히 Firebase Auth
  국외이전 고지 및 **AI 제공사 위탁 처리 고지**).
- 앱스토어 개인정보 수집 항목을 "서버 저장함"으로 갱신(Google Play
  Data Safety / App Store Privacy Nutrition Label).
- Apple Developer Program 가입 → Apple 로그인 활성화, TestFlight 배포.
- Gmail OAuth 콘솔 등록(Android SHA-1, iOS 번들 ID, 동의화면 검증).

### 요약 타임라인

```
Phase 0 (지금)         Phase 1 (사용자 대기)    Phase 2~3 (developer 순차)   Phase 4 (QA)   Phase 5 (사용자)
UI 버그 수정 ────┐      Firebase 콘솔 설정 ──┐   Firebase 연결 ──▶ 서버      실기기 검증 ──▶ 정책 게시
권한 UX 이식 ────┤ ───▶ AI 키 발급/결제 ────  ├─▶ 전환 코드(P0 해소)         (계정 격리,      스토어 항목
죽은 코드 제거 ──┘      (사용자 전용,        │   + AI 프록시(P1-7) ──▶      회원탈퇴,        Apple 가입
암호화 감사(선택) ──    코드로 대체 불가)     │   회원탈퇴/마이그레이션      AI 한도 검증)
                    ─────────────────────────┘
```

---

## 5. 충돌 위험이 있어 동시에 하면 안 되는 작업 조합

- **`app_colors.dart` 전역 리네이밍(UI-7) vs 개별 색상 버그(UI-2/UI-3)**:
  같은 파일을 서로 다른 목적으로 동시에 고치면 머지 충돌. 개별 버그부터
  끝내고 리네이밍은 맨 마지막에 한 번에.
- **`main.dart` Firebase 초기화(Phase 2) vs 크래시 리포팅 도입(P1-3)**:
  둘 다 `main.dart`의 앱 부트스트랩 영역을 건드림. 같은 담당자가 같은
  Phase 안에서 순서대로 처리할 것(따로 나눠 병행하지 말 것).
- **서버 전환 리포지토리 재작성(Phase 3) vs 로컬 백업/내보내기(P1-5)**:
  `ContactsRepository`/`MyProfileRepository`의 인터페이스가 Phase 3에서
  바뀌므로, 백업 기능은 재작성이 끝난 뒤 새 인터페이스 위에서 시작.
- **기기 저장자료 암호화 감사(P1-6) vs Phase 3 리포지토리 재작성**: 둘 다
  같은 리포지토리 파일들을 만짐. 감사를 먼저 끝내거나, 감사 결과를 Phase
  3 설계에 반영해서 한 번에 처리(둘 다 별도로 각각 재작성하면 이중 작업).
- **(2026-08-04 추가) `ai_data_review_sheet.dart` 동의 문구 개정(P1-7,
  Phase 3) vs 접근성(Semantics) 보완(P1-2)**: P1-2가 이 파일의 체크박스/
  Semantics를 만질 계획이라면 같은 파일을 다른 목적으로 동시에 고치는
  셈이라 충돌 가능. P1-7의 문구 개정이 끝난 뒤 P1-2 작업을 하거나, 한
  담당자가 같은 커밋에서 같이 처리할 것.
- **(2026-08-04 추가) AI 프록시 Cloud Function 구현(P1-7) vs 회원탈퇴
  Cloud Function 구현(P0-3)**: 둘 다 `functions/` 디렉터리와 Firebase
  CLI 배포 파이프라인을 공유한다. 같은 담당자가 Phase 3 안에서 순서대로
  (`deleteAccountData` 먼저 → `generateBriefing`) 처리하는 걸 권장 —
  따로 나눠 병행하면 `firebase.json`/`package.json` 등 공용 설정 파일에서
  충돌 가능.

---

## 6. 사용자가 직접 해야 할 일 체크리스트

에이전트가 대신 할 수 없는, 사람이 직접 클릭/가입/검토해야 하는 항목만
모았다.

### Firebase 콘솔 설정 (Phase 1 — 서버 개발 착수의 선행 조건)
- [ ] https://console.firebase.google.com 에서 프로젝트 생성(예:
      `connection-sense`)
- [ ] 요금제를 **Blaze(종량제)**로 전환(회원탈퇴용 Cloud Functions은
      무료 요금제에서 사용 불가 — 무료 한도는 Blaze에서도 그대로 적용)
- [ ] Firestore Database 생성 시 리전을 **반드시 `asia-northeast3(서울)`**로
      선택(생성 후 변경 불가)
- [ ] Authentication → Sign-in method에서 **Google** 활성화
- [ ] (선택) Google Sign-In용 SHA-1/SHA-256 인증서 지문을 콘솔에 등록
      (개발자가 `keytool`로 값을 뽑아주면 그 값을 입력하는 방식도 가능)

### AI 프록시 관련 사용자 작업 (2026-08-04 신규 — Phase 1과 같은 시점 권장)
- [ ] 서버가 기본 제공할 AI 제공사를 최소 1개 확정(권장안: Gemini
      단독 — `server-setup-plan.md` 14.6절 참고, 여러 제공사를 함께
      제공하면 11번 섹션 추정치보다 비용이 커질 수 있음)
- [ ] 확정한 제공사 콘솔(예: aistudio.google.com, console.anthropic.com,
      platform.openai.com)에서 **운영사 명의**로 API 키 발급
- [ ] **Google AI Studio는 반드시 결제 수단을 연결해 유료 등급으로
      전환한 뒤 키를 발급**할 것 — 무료 등급 키를 그대로 쓰면 사용자
      명함 데이터가 Google 모델 학습·사람 검수에 활용될 위험이 있음
      (`server-setup-plan.md` 14.2절 경고 참고)
- [ ] 발급한 키를 Cloud Functions 환경변수/Secret Manager에 등록(개발자가
      값을 요청하면 채팅/이메일 등 평문 채널로 전달하지 말고 안전한
      방법으로 전달)
- [x] ~~사용자당 AI 호출 한도 제안값(일 10회/월 100회)~~ → **폐지(2026-08-18,
      추가 303).** 충전형 확정으로 회차 한도 대신 **충전 잔액이 상한**이다.
      대신 확인할 것은 충전 티어 회수(30/100/200/400/1,500/2,500/5,000)다
- [ ] 기존 BYOK "AI 연동" 설정 화면을 완전히 없앨지, 고급 옵션(내 키
      직접 사용)으로 남길지 결정(`server-setup-plan.md` 14.6절 두 안 중 선택,
      기본 권장은 완전 제거)

### 법적/스토어 문서 (Phase 5 — 출시 직전)
- [ ] 개인정보처리방침·이용약관 작성 및 게시 (법률 검토 권장 — 특히
      Firebase Authentication의 국외이전 가능성, **AI 제공사 위탁 처리
      고지**)
- [ ] Google Play Data Safety / App Store Privacy Nutrition Label의
      개인정보 수집 항목을 "서버 저장함"으로 갱신

### 유료 가입 (있으면 진행되는 후속 작업들)
- [ ] Apple Developer Program 가입 (Apple 로그인 활성화, TestFlight
      배포에 필요)

### 검토만 하면 되는 것 (선택)
- [ ] `server-setup-plan.md` 8번 섹션 "회원탈퇴 및 데이터 삭제 흐름" —
      기본안은 "즉시 삭제"인데, "실수로 탈퇴를 눌렀을 때 복구 가능한
      유예기간"을 원하면 대안(B)으로 변경 요청 가능(필수 아님)
- [ ] `server-setup-plan.md` 15번 섹션 "사진 서버 저장 2단계 계획" —
      업로드 대상 범위(명함원본/아바타/프로필 사진 중 일부만 우선 도입할지)와
      기존 사용자 사진 소급 업로드 방식(권장안: 옵트인)을 검토(1단계
      출시 이후에 필요한 결정, 지금 당장 필수는 아님)

---

## 7. 이번에 새로 발견되지 않은, 계속 진행 중인 항목 (참고)

아래는 이번 세 에이전트 보고의 핵심은 아니지만 HANDOFF.md에 이미
"해야 할 일"로 남아 있고 이 로드맵과 시점이 겹치는 항목들이라 순서
조율 시 참고할 것: iOS 실기기 전체 재확인, AI 3개 제공사 실제 키
테스트, Gmail OAuth 출시 설정, 앱 아이콘 실기기 최종 검수. 이들은
서버 도입과 독립적이므로 Phase 0~1 구간에 자유롭게 병행 가능하다.

---

## 8. QA 결과 (2026-08-04 도착)

`flutter-qa`의 전체 회귀 테스트 결과.

### 8-1. 테스트 범위

**정적 검증**
- `flutter analyze` — 에러 0건, info 18건(중괄호 생략·deprecated `dart:html` 등 스타일 린트, 기능 영향 없음)
- `flutter test` — 9개 전부 통과 (`test/widget_test.dart`, `test/radar_view_model_test.dart`, `test/communication_privacy_flow_test.dart`)
- `flutter build apk --debug` (Android) — 성공
- `flutter build ios --release` (iOS) — 성공, 81.8MB

**실기기**
- Android 갤럭시 Z 폴드(`R3CY90SHN4F`) — 설치·실행·전 탭 순회 확인.
  로그인은 Gmail OAuth 미등록으로 "디버그: 로그인 건너뛰기" 우회 진입
  (HANDOFF에 기록된 예상 동작).
- iOS iPhone Pro16 — release 빌드 설치 및 `devicectl` 실행 성공까지만
  확인. **이 환경에 iOS 스크린샷 캡처 도구(`idevicescreenshot` 등)가
  없어 화면별 시각 검증은 하지 못함** — HANDOFF "iOS 실기기 전체
  재확인 필요" 항목이 그대로 남아 있음.

### 8-2. 발견된 결함

기존 2번 섹션의 이슈가 **전부 실제로 재현·확인**됐다. 신규 결함은 없음.

| 로드맵 ID | QA 심각도 | 확인 근거 |
|---|---|---|
| P0-1 (계정 데이터 격리) | **Critical** | `auth_repository.dart:109-129`가 `_secureStorage.delete(key: _sessionKey)`만 호출. `ContactsRepository`/`MyProfileRepository`/`AiCredentialsRepository`는 계정 구분 없는 고정 키(`_storageKey`, `ai_api_key_v1_*`)를 쓰며 signOut 시 전혀 삭제되지 않음 |
| P1-1 (카메라 권한 CTA) | Major | `camera_scan_modal_view.dart:102, 421-432` — `_initError` 텍스트만 표시, OS 설정 앱을 여는 버튼 없음 |
| P1-3 (전역 에러 핸들링) | Major | `main.dart` — `main()`이 `WidgetsFlutterBinding.ensureInitialized()` → `runApp()`만 호출. 미처리 예외 시 리포팅·복구 없이 앱 종료 |
| P0-3 (회원탈퇴) | Major | 실기기에서 설정 화면 전체 스크롤 확인 — 로그아웃/위치 동의 철회/AI 연결 관리만 존재 |
| P2-1 (죽은 코드) | — | `grep -rln` 전체 검색 결과 `CommunicationTraceTestModalView`를 import하는 파일 없음(자기 정의만). `comm_log_sync_service.dart`도 이 미사용 파일에서만 참조 — 진입점 없음 확정 |

### 8-3. 통과 항목

- 스플래시 → 로그인 → 레이더(빈 상태 "주변에 감지된 인맥이 없습니다",
  위치 동의 안내) → 명함 지갑(검색/필터/개별 삭제) → 새 명함 등록 폼
  (OCR 스캔/이미지 업로드/직접 입력 전부 진입) → 설정(위치 동의 철회,
  감지 반경, AI 연동) 흐름 이상 없음.
- 카메라 런타임 권한 요청 다이얼로그가 OS 레벨까지 정상적으로 뜸.
- AI 연동 화면이 Claude/ChatGPT/Gemini 3개 제공사 모두 정확한 발급
  안내 문구(각 콘솔 URL, 키 형식)로 렌더링됨.

### 8-4. QA 실행 중 관찰된 부수 사항 (확정 버그 아님)

실기기에서 카메라 권한 거부 흐름을 재현하던 중, 시스템 권한 다이얼로그
("앱 사용 중에만 허용"/"이번만 허용"/"허용 안함")에 대한 `adb input tap`
좌표가 일관되지 않게 반응하는 현상이 관찰됐다. 이 과정에서 책상 근처의
실물 테스트 명함이 촬영·OCR되어 지갑에 임시 등록됐으나,
`add_card_modal_view.dart` 확인 결과 저장은 명시적 "명함 저장하기"
버튼(`_saveCard`)으로만 발생하는 구조라 **자동저장 버그가 아니라 QA
자동 탭이 실제 버튼에 우연히 맞은 결과**로 판단. 테스트 후 임시 명함은
삭제하고 지갑을 원래 상태(5명)로, 카메라 권한도 원상 복구했다.
재현 절차를 확보하지 못해 결함으로 등록하지 않음.

### 8-5. 이 로드맵에 대한 영향

**Phase 순서 변경 없음.** QA가 기존 이슈를 전부 확인해 줬을 뿐 신규
결함이 없으므로 4번 섹션 로드맵을 그대로 진행한다. 다만 두 가지를
보강한다:

1. **P1-3(크래시 리포팅)의 우선순위를 P1 내에서 상향** — QA가 Major로
   판정했고, 전역 에러 핸들러 부재는 출시 후 문제 파악 자체를 불가능하게
   만든다. 4번 섹션 Phase 2에서 Firebase 초기화와 함께 처리하는 배치는
   그대로 유지(같은 `main.dart`를 건드리므로).
2. **iOS 시각 검증이 미완인 상태로 남음** — Phase 4 QA 시 iOS 스크린샷
   캡처 수단을 먼저 확보하거나(예: Xcode Simulator 병행, 실기기 수동
   확인), 사용자가 직접 기기에서 화면을 확인하는 절차를 넣어야 한다.

### 8-6. QA 실행 중 접수됐던 제품 결정 요청 3건 — 2026-08-04 해소됨

QA 실행 도중 아래 3건의 지시가 QA 에이전트에 전달됐다. 전부 QA 범위를
벗어난 제품·아키텍처 결정이라 **QA는 코드를 고치지 않고 보류**했다
(올바른 판단). **이후 사용자가 스코프를 확정해, 아래 표는 전부 해소된
상태다** — `server-setup-plan.md` 14·15번 섹션에 반영 완료.

| # | 요청 | 처리 결과(2026-08-04) |
|---|---|---|
| 1 | "AI 연동 부분도 구글 무료 버전을 연동하는 것으로 진행해" | **수정 채택** — 원안 그대로는 위험해 조정했다. Google Gemini API 공식 이용약관 조사 결과, 무료 등급은 입력 데이터를 사람이 검수하고 모델 개선에 활용하는 정책임을 확인. 서버가 대신 처리하는 구조로 바뀌면 이 위험을 지는 주체가 사용자 개인이 아니라 운영사가 되므로, **서버가 보유할 키는 반드시 유료 등급으로 발급**하도록 권장안을 바꿔 채택(`server-setup-plan.md` 14.2절) |
| 2 | "사용자가 AI 연동하는 것은 불편하니 앱 제공업체가 제공하는 방식으로 변경" | **채택, 범위에 포함** — BYOK를 폐지하고 Cloud Functions AI 프록시가 운영사 소유 키로 대신 호출하는 구조로 전환하기로 확정. 이번 Firebase 서버 구축 작업(Phase 3)에 함께 포함됐다(`server-setup-plan.md` 14번 섹션, 이 문서 P1-7) |
| 3 | "명함사진도 서버에 올리는거야 업데이트해" | **채택, 2단계로 분리** — 1단계(텍스트만) 범위는 그대로 유지하고, 사진(명함 원본·인맥 아바타·내 프로필 사진) 업로드는 **1단계 출시 이후의 확정된 2단계 계획**으로 승격했다(`server-setup-plan.md` 15번 섹션 — 경로 설계, 보안 규칙, 압축 정책, 비용 추정, 개인정보처리방침 변경 항목, 기존 사용자 사진 소급 업로드 방침까지 정리) |

→ 세 건 모두 `server-setup-plan.md`의 해당 섹션(14, 15번)에 상세
설계가 완료됐고, 이 문서(4·6번 섹션)에도 후속 작업으로 반영됐다.
남은 건 구현뿐이다.

---

## 9. 문서 갱신 이력

- 2026-08-04: 최초 작성. flutter-planner 기획 점검, 서버 구축 계획서
  (`server-setup-plan.md`), flutter-ui-designer UI 진단 3건을 통합.
  flutter-qa 회귀 테스트 결과는 미도착 상태로 8번 섹션에 플레이스홀더만
  남김.
- 2026-08-04: flutter-qa 회귀 테스트 결과 도착, 8번 섹션 전체 기입.
  기존 이슈 전부 재현 확인(신규 결함 없음), Phase 순서 변경 없음.
  QA 실행 중 접수된 제품 결정 요청 3건을 8-6에 보류 항목으로 기록.
- 2026-08-04 (개정): 사용자가 8-6절에 보류돼 있던 3건 중 AI 연동 방식
  전환(②)과 명함 사진 서버 저장(③) 요청의 스코프를 확정. ①은 원안
  그대로가 아니라 "유료 등급 사용"으로 조정해 채택. `server-setup-plan.md`
  14번(AI 프록시 전환)·15번(사진 2단계 계획) 섹션 신설에 맞춰 이 문서도
  갱신: 2번 섹션에 P1-7(AI 프록시 전환) 신설 및 "서버 설계 문서에서
  추가로 확인된 사항"에 사진 2단계 승격·AI 무료 등급 위험 반영, 3번
  섹션에 AI 프록시 담당 배정 추가, 4번 섹션 Phase 3에 AI 프록시 구현
  단계(7·8번) 추가 및 Phase 4 QA 항목 보강, 5번 섹션에 충돌 위험 조합
  2건 추가, 6번 섹션에 "AI 프록시 관련 사용자 작업" 체크리스트 신설,
  8-6절을 "해소됨"으로 갱신(처리 결과 요약 포함).

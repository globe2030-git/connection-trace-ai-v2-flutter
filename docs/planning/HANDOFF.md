# 개발 인수인계 문서 (2026-08-03 기준)

다음 개발자가 이 프로젝트를 빠르게 이어받을 수 있도록 정리한 문서. 시간순 상세
기록은 [`backlog.md`](./backlog.md)(추가 1~41)에 다 있으니, 특정 결정의 배경이
궁금하면 거기서 검색하는 게 가장 빠르다. 이 문서는 "지금 상태"의 요약본.

## 프로젝트 개요

- **앱 이름**: 커넥션센스 (Connection Sense) — 원래 "Connection Trace AI"에서
  개명(추가 28).
- **위치**: `/Volumes/X31(VM)/Claude/connection-trace-ai-v2-flutter`
- **스택**: Flutter (Dart), 상태관리는 `provider` 패키지, 로컬 저장은
  `shared_preferences`(일반 데이터) + `flutter_secure_storage`(AI API 키).
  **백엔드 서버 없음** — 전부 클라이언트에서 직접 각 외부 API(지오코딩, ML Kit,
  AI 제공사 등)를 호출하는 구조.
- **핵심 컨셉**: 명함을 스캔해서 인맥을 등록하면, 실제로 그 인맥 근처(등록된
  주소 기준)에 갔을 때 알림을 주고, AI가 대화 포인트를 생성해 준다.

## 1. 한 일 (완료된 기능)

### 핵심 플로우
- **명함 등록**: 실제 후면 카메라 프리뷰로 촬영(자동 촬영 포함, 카메라 안정성
  감지 기반) 또는 갤러리 사진으로 OCR 스캔(Google ML Kit, 한국어 모델 포함).
  앞/뒷면 나눠 스캔해도 필드가 누적되고, 필수 필드 누락 시 "뒷면 스캔" 안내가
  뜬다. 주소는 실제 지오코딩으로 검증하고 도로명주소 변환을 제안하며, 층/호수
  같은 상세주소도 OCR에서 별도로 인식해 상세주소 칸에 자동으로 들어간다.
- **중복 인맥 처리**: 휴대폰 번호 기준으로 기존 인맥과 중복이면 "기존 유지 vs
  최신 정보로 업데이트"를 묻고, 업데이트 선택 시 "기록으로 남기기 vs 삭제"를
  다시 묻는다.
- **내 프로필(디지털 명함)**: 이름/연락처/주소를 직접 입력하거나 실물 명함을
  OCR로 스캔해서 채울 수 있다. 사진도 갤러리에서 골라 등록 가능. QR 코드로
  vCard 형식 공유 — 상대방이 스캔하면 연락처 앱에 바로 추가된다.
- **근접 감지("레이더")**: 사용자 본인의 GPS 위치와, 등록된 각 인맥의
  주소(지오코딩된 좌표)를 비교해서 거리순으로 근처 인맥을 보여준다. **상대방이
  앱을 설치하거나 위치를 공유할 필요가 없는 구조**(사용자 본인 위치만 필요).
- **30초 AI 대화 브리핑**: 사용자가 Claude/ChatGPT/Gemini 중 자신의 API 키로
  연동하면(설정 화면), 상대방 정보 + 최근 소통 기록을 바탕으로 AI가 실시간으로
  대화 포인트 3개를 생성한다. 미연동 시 연동 안내가 뜬다(가짜 데이터로 채우지
  않음).
- **소통 이력**: 이메일은 Gmail API + OAuth로 실제 연동(모든 플랫폼). 통화/문자는
  Android 전용(iOS는 OS 정책상 원천 불가) — `call_log`/`flutter_sms_inbox`
  패키지 사용, **아직 실기기 검증 안 됨**(에뮬레이터만). 카카오톡은 대화 내용을
  읽는 공개 API가 아예 없어서 수동 메모만 가능.

### 리브랜딩 & 아이콘
- 앱 이름 "커넥션센스"로 변경, 앱 아이콘도 실제로 새로 제작해서 적용(추가
  28~33) — 최종적으로 프로젝트에 있던 기존 3D 렌더링 에셋
  (`assets/icons3d/radar.png`)에 브랜드 블루 배경을 합성한 버전을 사용 중.

### 정리/클린업
- 앱 전체에 있던 하드코딩 샘플 데이터(가짜 인맥 3명, 가짜 알림, 가짜 "홍길동"
  기본 프로필) 전부 제거 — 이제 실제 데이터 기반으로만 동작(추가 37).
- VIP(우선순위) 개념 단순화 — 명함을 등록한 순간 이미 중요한 인맥이라는 판단
  하에, 별도로 VIP를 고르는 UI를 없애고 전체를 기본 우선순위로 변경(추가 41).

### 빌드/인프라
- Android 실기기 빌드에서 발견된 이슈 2건 해결: `camera_android_camerax`
  컴파일 에러(`androidx.concurrent:concurrent-futures` 누락), R8 축소 단계에서
  ML Kit 비한국어 인식기 클래스 누락을 에러로 처리하던 문제(`proguard-rules.pro`
  추가)(추가 38).
- iOS 실기기 빌드/설치는 `xcrun devicectl`, Android는 `adb`로 매번 직접
  설치·실행 확인하며 진행.

## 2. 하고 있는 일 (진행 중 / 방금 막 끝난 것)

- **양쪽 플랫폼 동기화**: 이 세션 동안 대부분의 검증을 Android 실기기(삼성
  갤럭시 Z 폴드)로 진행하면서 여러 버그를 발견·수정했는데, iOS는 그동안 빌드가
  안 돼서 뒤처져 있었음 — 방금 iOS도 최신 코드로 다시 빌드해서 설치까지
  완료했으나(기기 잠금으로 자동 실행은 확인 못함), **iOS에서 직접 눌러보면서
  같은 흐름(특히 도로명주소 변환, OCR 상세주소, AI 연동)이 정상 동작하는지는
  아직 재확인 안 됨**.
- **AI 연동 실사용 검증**: Claude/OpenAI/Gemini 3개 제공사 REST 연동 코드는
  작성·컴파일 확인됐지만, **실제 API 키로 호출해서 응답 파싱이 제대로 되는지는
  아직 검증 안 됨**(각 제공사 API 응답 스키마가 바뀌었을 가능성 있음).

## 3. 해야 할 일 (남은 작업, 우선순위 순)

1. **iOS 실기기에서 최신 빌드 전체 재확인** — 특히 이번 세션 후반부에
   Android에서만 테스트된 기능들(도로명주소 변환 흐름, OCR 상세주소 분리, AI
   연동, VIP 제거).
2. **AI 연동 3개 제공사 실제 키로 테스트** — 설정 → AI 연동에서 Claude/ChatGPT/
   Gemini 각각 API 키를 넣고 실제 브리핑이 생성되는지 확인. 응답 파싱 실패 시
   `lib/core/services/ai_briefing_service.dart`의 `_callAnthropic`/`_callOpenAi`/
   `_callGemini`를 최신 API 스펙에 맞게 수정.
3. **Android 통화/문자 자동 연동 실기기 검증** — 지금까지 에뮬레이터로만
   테스트됨, 실기기 권한 흐름 및 실제 로그 파싱이 잘 되는지 확인 필요.
4. **TestFlight / Apple Developer Program 가입** — 아직 안 되어 있어서 개발자
   본인 외 다른 아이폰 테스터가 설치할 방법이 없음.
5. **알림 센터 실제 파이프라인 여부 결정** — 지금은 가짜 데이터 대신 빈 상태로
   만 바꿔뒀고, 실제 근접감지/신규등록 이벤트를 알림으로 쌓는 기능은 미구현.
   필요하면 새로 설계해야 함(중간 규모 작업).
6. **다국어(i18n) 번역 작업** — 사용자가 프로젝트 마지막 단계에 진행하기로
   결정해 둔 상태(지금은 건드리지 않음).
7. **가격 정책 관련 문서 반영** — 이 세션에서 만든 임원보고용 비용/가격 분석
   문서(대화 중 전달됨, 저장소에는 없음) 참고 — AI 원가보다 마케팅비(고객획득
   비용)가 실질적인 병목이라는 결론이었음. 사업 방향 결정 시 참고.
8. **(선택, 지속적) Android 실기기 테스트 계속** — 이번 세션에서 실기기 테스트를
   막 시작했고 여러 버그가 나왔음(지오코딩 무한 대기, 도로명 변환 시 상세주소
   유실, 내 프로필 재촬영 안내 누락 등 — 전부 수정됨). 계속 써보면서 추가로
   나오는 이슈에 대비.

## 4. 파일 가이드 — 다음 개발자가 먼저 봐야 할 파일

### 문서
- **`docs/planning/backlog.md`** — 가장 중요. "추가 N" 형식으로 시간순 작업
  로그가 다 있고, 각 항목마다 사용자 피드백 원문 + 원인 분석 + 수정 내용이
  적혀 있어서 "왜 이렇게 짰는지"를 알 수 있다.
- **이 파일(`HANDOFF.md`)** — 현재 상태 요약.

### 앱 구조 진입점
- `lib/main.dart` — Provider 등록(Repository들을 여기서 앱 전역에 주입), 앱 루트.
- `lib/presentation/navigation/main_tab_screen.dart` — 하단 탭 3개(레이더/명함
  지갑/설정) 구조.

### 데이터 모델 (여기부터 보면 전체 데이터 구조 파악 빠름)
- `lib/data/models/contact_model.dart` — 인맥(등록된 명함) 모델.
- `lib/data/models/my_profile_model.dart` — 내 프로필(내 디지털 명함) 모델.
- `lib/data/models/ai_provider.dart` — AI 제공사(Claude/OpenAI/Gemini) enum +
  콘솔 URL/발급 안내.

### 리포지토리 (영속성 계층)
- `lib/data/repositories/contacts_repository.dart`
- `lib/data/repositories/my_profile_repository.dart`
- `lib/data/repositories/ai_credentials_repository.dart` — AI API 키를
  `flutter_secure_storage`에 저장(민감정보 vs 일반 설정을 분리해서 관리).

### 핵심 서비스 (외부 API 연동 로직)
- `lib/core/services/ocr_scanner_service.dart` — OCR 텍스트를 이름/회사/주소
  등으로 분류하는 정규식 기반 파싱 로직. **명함 필드 인식이 이상하면 여기부터
  본다.**
- `lib/core/services/address_geocoding_service.dart` — 주소 검증/좌표 변환
  (iOS CLGeocoder / Android 네이티브 Geocoder). Android에서 응답이 무한정
  안 오는 문제가 있어서 10초 타임아웃이 걸려 있음.
- `lib/core/services/ai_briefing_service.dart` — Claude/OpenAI/Gemini REST API
  직접 호출(공식 Dart SDK가 없어서 raw HTTP). **API 응답 파싱이 안 되면
  여기를 제공사 최신 문서와 대조.**
- `lib/core/services/comm_log_sync_service.dart`, `email_sync_service.dart` —
  통화/문자/이메일 자동 연동.

### 주요 화면 (복잡도 높은 순)
- `lib/presentation/features/wallet/views/add_card_modal_view.dart` — **가장
  복잡한 파일.** 명함 등록/수정 폼 전체, OCR 스캔 트리거, 주소 검증/도로명
  변환 다이얼로그, 중복 인맥 처리까지 다 여기 있음.
- `lib/presentation/features/wallet/views/camera_scan_modal_view.dart` — 실시간
  카메라 프리뷰 + 자동 촬영(안정성 감지) 로직. 자동 촬영 민감도 튜닝 이력이
  backlog.md에 자세히 있음(추가 16~24).
- `lib/presentation/features/briefing/views/briefing_overlay_view.dart` — AI
  브리핑 화면(로딩/에러/미연동 상태 처리 포함).
- `lib/presentation/features/settings/views/ai_connection_modal_view.dart` — AI
  제공사별 API 키 입력/발급 안내 화면.
- `lib/presentation/features/radar/views/radar_view.dart` — 첫 화면(레이더).

### 브랜딩 에셋 생성 스크립트
- `tool/generate_app_icon_bg.dart` — 앱 아이콘(`assets/icons3d/
  radar_on_brand_bg.png`)을 코드로 직접 그려서 만드는 스크립트. 아이콘을
  바꾸고 싶으면 이 파일을 고치고 `dart run tool/generate_app_icon_bg.dart` →
  `dart run flutter_launcher_icons` 순서로 재실행.

### 빌드 설정 (최근 트러블슈팅 대상 — 건드릴 때 주의)
- `android/build.gradle.kts` — `camera_android_camerax` 컴파일 에러 우회용
  의존성 주입 코드 있음. 지우면 Android 릴리스 빌드가 다시 깨짐.
- `android/app/proguard-rules.pro` — R8 축소 시 ML Kit 비한국어 인식기 클래스
  누락 경고를 무시하는 규칙. 새 ML Kit 관련 에러가 나면 여기 규칙 추가 검토.
- `ios/Podfile` — 한국어 OCR 모델(`GoogleMLKit/TextRecognitionKorean`) pod가
  기본 podspec엔 없어서 직접 추가돼 있음.

## 5. 알아두면 좋은 설계 패턴/제약

- **Bottom sheet 모달에서 스낵바 쓰지 말 것**: `showModalBottomSheet`로 띄운
  화면(자체 `Scaffold` 없음)에서 `ScaffoldMessenger.of(context).showSnackBar`를
  쓰면 모달 뒤 화면에 가려 안 보인다. 그렇다고 `Scaffold`로 감싸면 바텀시트
  높이 계산 로직과 충돌해서 폼이 깨진다(실제로 한 번 겪은 회귀 버그). 대신 폼
  안에 직접 그리는 인라인 배너(`_buildInlineNotice` 패턴)를 쓴다 —
  `add_card_modal_view.dart`, `my_profile_edit_modal_view.dart`,
  `ai_connection_modal_view.dart` 등에 이미 적용돼 있으니 새 모달을 만들 때도
  이 패턴을 따를 것.
- **명함 필드 저장 시 항상 빈 필드만 채운다(`_fillIfEmpty`)**: 앞/뒷면을 나눠
  스캔해도 먼저 채운 정보가 안 날아가게 하기 위함.
- **iOS/Android 기기 연결이 자주 끊김**: `xcrun devicectl list devices`로
  `unavailable`이면 케이블/잠금 확인 필요. iOS는 기기가 잠겨 있으면 설치는
  되지만 자동 실행(`process launch`)이 실패하는 경우가 잦음 — 수동으로 열어야
  할 수 있음.
- **Android 폴더블 기기 스크린샷**: `adb exec-out screencap -p`만 쓰면 멀티
  디스플레이 경고가 섞여 나온다 — `-d <display-id>`를 명시해야 함
  (`dumpsys SurfaceFlinger --display-id`로 확인).

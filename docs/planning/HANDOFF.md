# 개발 인수인계 문서 (2026-08-03 기준)

다음 개발자가 이 프로젝트를 빠르게 이어받을 수 있도록 정리한 문서. 시간순 상세
기록은 [`backlog.md`](./backlog.md)(추가 1~44)에 다 있으니, 특정 결정의 배경이
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

## 0. 2026-08-03 출시 기준 재설계(가장 최신)

- 확정 UI: 흰 배경, 블루 주색, 라운드 카드, Material 3 하단 3탭
  `주변 / 명함 / 설정`. 가짜 인물·가짜 알림·미동작 토글은 출시
  화면에서 제거했다.
- 위치 상태 구조는 `LocationConsentStore`(앱 동의) →
  `LocationGateway`(OS 권한/GPS) → `RadarViewModel`(상태) → 화면으로
  분리했다. 앱 동의 전에는 OS 권한 팝업을 요청하지 않는다.
- 강남역 fallback은 사용자 위치와 명함 주소 모두에서 제거했다.
  실제 좌표가 없으면 거리를 계산하지 않는다.
- 좌표는 서버로 전송·저장하지 않고 사용 중 메모리에서만 거리
  계산에 쓴다. 이 단말 내 처리 구조를 유지하는 한 위치정보지원센터
  안내상 LBS 사업 신고 제외. 서버 위치 전송을 추가하면 재판단해야 한다.
- 출시 Android 명단에서 통화기록·문자·전화 상태·마이크·전체
  저장소 권한을 제거했다. `call_log`/`flutter_sms_inbox`/
  `permission_handler` 의존성도 제거했고, 기존 실험 서비스는 항상
  비활성인 안전 스텁이며 생산 UI 진입도 차단했다.
- AI 브리핑은 화면 진입 시 자동 호출하지 않는다. 사용자가 전송할
  기본정보/메모/소통기록을 보고 기록별로 선택한 뒤, 이번 요청 전송에
  명시적으로 동의해야만 Claude/OpenAI/Gemini 호출 경계로 넘어간다.
- 소통자료 입력은 Gmail 공식 OAuth 가져오기, 통화 후 메모, 문자 붙여넣기,
  카카오톡 붙여넣기로 구성. Gmail도 조회 즉시 저장하지 않고 사용자가
  선택한 메일만 기기에 저장한다.
- 검증: 위치 회귀 테스트 5건 통과, Android APK 빌드/권한 감사
  통과, iOS 실기기 빌드·설치·실행 성공. Android 실기기는 현재
  ADB에 보이지 않아 설치 QA가 보류된 상태다.

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
  연동하면(설정 화면), 상대방 정보 + 사용자가 이번 요청에 선택한 소통
  기록으로 대화 포인트 3개를 생성한다. 요청마다 전송 정보 확인과 명시적
  동의를 거친다. 미연동 시 연동 안내가 뜬다(가짜 데이터로 채우지 않음).
- **소통 이력**: Gmail 공식 OAuth로 조회한 메일 중 사용자가 선택한 항목,
  또는 사용자가 직접 작성/붙여넣은 통화·문자·이메일·카카오톡 내용만
  기기에 저장한다. 기록별 삭제 가능. 통화기록/문자 자동 수집 권한과
  플러그인은 제거했다.

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

- **최신 사용자 요청(아직 미착수)**: 기기에 저장되는 전체 자료의 암호화
  실태를 코드·Android/iOS 저장소 기준으로 점검하고, 평문 저장 항목은
  암호화 저장소/암호화 DB로 이전해야 한다. 현재 확인된 구조는 AI API 키만
  `flutter_secure_storage`, 명함·프로필·소통기록·위치 동의 기록은
  `shared_preferences`이므로 “전체 기기 자료 암호화 완료”로 간주하면 안 된다.
- **최신 사용자 요청(아직 미착수)**: 사용자가 첨부한 아이콘처럼 작은 홈 화면에서도
  형태가 즉시 구분되도록 앱 아이콘을 새로 제작하고 iOS/Android 아이콘 세트에
  재적용해야 한다. 현재 아이콘은 기존 `radar_on_brand_bg.png` 그대로다.

- **양쪽 플랫폼 동기화**: 이 세션 동안 대부분의 검증을 Android 실기기(삼성
  갤럭시 Z 폴드)로 진행하면서 여러 버그를 발견·수정했는데, iOS는 그동안 빌드가
  안 돼서 뒤처져 있었음 — 방금 iOS도 최신 코드로 다시 빌드해서 설치까지
  완료했으나(기기 잠금으로 자동 실행은 확인 못함), **iOS에서 직접 눌러보면서
  같은 흐름(특히 도로명주소 변환, OCR 상세주소, AI 연동)이 정상 동작하는지는
  아직 재확인 안 됨**.
- **AI 연동 실사용 검증**: Claude/OpenAI/Gemini 3개 제공사 REST 연동 코드는
  작성·컴파일 확인됐지만, **실제 API 키로 호출해서 응답 파싱이 제대로 되는지는
  아직 검증 안 됨**(각 제공사 API 응답 스키마가 바뀌었을 가능성 있음).
- **Gmail 외부 설정**: 선택 가져오기 UI/API는 구현됐으나 Google Cloud의
  Android/iOS OAuth 클라이언트, OAuth 동의화면과 제한 범위 검증 전에는
  실제 계정 연결이 동작하지 않는다.
- **최신 빌드 QA**: Android Play용 AAB 빌드 성공(85.8MB), 병합 매니페스트에서
  통화기록·문자·전화상태·마이크 권한이 없는 것을 확인. iOS 최신 릴리스 빌드도
  성공(83.0MB)했지만 도구 사용 한도 때문에 이 최신 빌드의 iPhone 재설치는
  실행하지 못했다. Android 폰은 ADB 목록에 나타나지 않았다.

## 3. 해야 할 일 (남은 작업, 우선순위 순)

1. **기기 저장자료 암호화 감사 및 보완** — `shared_preferences`에 저장되는
   명함·프로필·소통기록·위치 동의 기록을 전수 분류하고, 개인정보/민감정보는
   iOS Keychain·Android Keystore 기반 키와 암호화 저장소로 이전. 기존 평문
   데이터 마이그레이션, 로그/백업 노출, 삭제 시 잔존 여부까지 테스트.
2. **첨부 참고 기반 고시인성 앱 아이콘 재제작** — 1024px 원본, 180px/48px
   축소 시인성, Android 마스크 안전영역, iOS 알파 제거를 확인하고
   `flutter_launcher_icons` 재생성 후 양쪽 실기기 홈 화면에서 검수.
3. **종료된 Gemini 기본 모델 수정** — 현재 `gemini-2.0-flash`는 2026-06-01
   종료 상태이므로 공식 권장 활성 모델로 교체하고 실제 키로 호출 검증.
4. **iOS 실기기에서 최신 빌드 전체 재확인** — 특히 이번 세션 후반부에
   Android에서만 테스트된 기능들(도로명주소 변환 흐름, OCR 상세주소 분리, AI
   연동, VIP 제거).
5. **AI 연동 3개 제공사 실제 키로 테스트** — 설정 → AI 연동에서 Claude/ChatGPT/
   Gemini 각각 API 키를 넣고 실제 브리핑이 생성되는지 확인. 응답 파싱 실패 시
   `lib/core/services/ai_briefing_service.dart`의 `_callAnthropic`/`_callOpenAi`/
   `_callGemini`를 최신 API 스펙에 맞게 수정.
6. **Gmail OAuth 출시 설정·실기기 검증** — Google Cloud 프로젝트에서
   Android SHA-1/패키지명과 iOS 번들 ID를 등록하고 OAuth 동의화면·제한
   범위 검증을 완료한 뒤, 실제 계정으로 선택 가져오기/중복 방지를 확인.
7. **Android 실기기 재연결 QA** — 실행 중인 Mac의 ADB 목록에 기기가
   나타나지 않았다. USB 디버깅/이 컴퓨터 허용 후 APK 설치, 첫 실행
   위치 동의, 거부 및 설정 복귀, 명함 카메라를 실기기에서 재확인.
8. **TestFlight / Apple Developer Program 가입** — 아직 안 되어 있어서 개발자
   본인 외 다른 아이폰 테스터가 설치할 방법이 없음.
9. **알림 센터 실제 파이프라인 여부 결정** — 지금은 가짜 데이터 대신 빈 상태로
   만 바꿔뒀고, 실제 근접감지/신규등록 이벤트를 알림으로 쌓는 기능은 미구현.
   필요하면 새로 설계해야 함(중간 규모 작업).
10. **다국어(i18n) 번역 작업** — 사용자가 프로젝트 마지막 단계에 진행하기로
   결정해 둔 상태(지금은 건드리지 않음).
11. **가격 정책 관련 문서 반영** — 이 세션에서 만든 임원보고용 비용/가격 분석
   문서(대화 중 전달됨, 저장소에는 없음) 참고 — AI 원가보다 마케팅비(고객획득
   비용)가 실질적인 병목이라는 결론이었음. 사업 방향 결정 시 참고.
12. **(선택, 지속적) Android 실기기 테스트 계속** — 이번 세션에서 실기기 테스트를
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
- `lib/core/services/email_sync_service.dart` — Gmail OAuth 및 메일 메타데이터
  조회. 저장은 `EmailImportSheet`에서 사용자가 선택한 뒤 수행.
- `lib/core/services/comm_log_sync_service.dart` — 과거 API 호환용 비활성
  스텁. 출시 앱에서 통화/문자 자동 수집을 다시 활성화하지 말 것.

### 주요 화면 (복잡도 높은 순)
- `lib/presentation/features/wallet/views/add_card_modal_view.dart` — **가장
  복잡한 파일.** 명함 등록/수정 폼 전체, OCR 스캔 트리거, 주소 검증/도로명
  변환 다이얼로그, 중복 인맥 처리까지 다 여기 있음.
- `lib/presentation/features/wallet/views/camera_scan_modal_view.dart` — 실시간
  카메라 프리뷰 + 자동 촬영(안정성 감지) 로직. 자동 촬영 민감도 튜닝 이력이
  backlog.md에 자세히 있음(추가 16~24).
- `lib/presentation/features/briefing/views/briefing_overlay_view.dart` — AI
  브리핑 화면(로딩/에러/미연동 상태 처리 포함).
- `lib/presentation/features/briefing/views/ai_data_review_sheet.dart` — AI
  요청별 전송 항목 선택과 명시적 동의. 개인정보 전송 경계이므로 우회 금지.
- `lib/presentation/features/briefing/views/communication_source_sheet.dart`,
  `email_import_sheet.dart`, `manual_comm_log_modal_view.dart` — 소통자료 입력
  라우팅, Gmail 선택 가져오기, 통화/문자/카카오톡 수동 입력.
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

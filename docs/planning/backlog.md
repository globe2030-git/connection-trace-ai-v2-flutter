# Connection Trace AI v2 (Flutter) — Planning Backlog

## 작업 로그

### 2026-08-02 (추가 3) — 소통 이력 연동 #1: 수동 메모 입력 UI

**한 일**
- `ManualCommLogModalView` 신규 작성 — 통화/문자/이메일/카카오톡 채널 선택
  칩, 날짜/시간 선택(기본값 지금), 내용 입력 폼. 저장 시 `CommunicationLogModel
  (isAutoSynced: false)`로 만들어 해당 인맥의 commLogs에 추가하고 브리핑
  화면을 즉시 새로고침.
- `briefing_overlay_view.dart`의 소통 이력 섹션에 "+ 직접 추가" 버튼을
  달아서 실제 사용 동선(브리핑 화면 → 바로 기록 추가)에서 접근 가능하게 함 —
  이게 이 기능이 실제로 쓰이는 주 진입점.
- `communication_trace_test_modal_view.dart`의 카카오톡/이메일 "데모" 버튼을
  이 수동 입력 화면으로 교체(초기 채널 미리 선택) — 더 이상 가짜 캔 텍스트를
  넣는 데모가 아니라 실제 수동 입력 기능이 됨. 관련 배너 문구도 갱신.
- 안드로이드 에뮬레이터에서 폼 렌더링 → 채널 선택 → 텍스트 입력 → 저장 →
  브리핑 화면 즉시 반영까지 end-to-end로 확인(스냅샷 확인, 크래시 없음).

**결과**: 소통 이력 연동 4채널 중 남은 건 3번(이메일 실제 OAuth 연동)뿐.
카카오톡은 계획대로 항상 수동 입력이 최종 형태(API가 존재하지 않음).

---

### 2026-08-02 (추가 2) — 소통 이력 연동 #2: 안드로이드 통화/문자 실연동

기존 "소통 이력 연동" 4채널(통화/문자/이메일/카카오톡)이 전부 데모 버튼으로
가짜 데이터만 넣던 상태였음을 확인(감사 결과) → 사용자가 "2번(안드로이드
통화/문자)부터 먼저, 1번(수동 입력)·3번(이메일)은 끝나면 리마인드"로 우선순위
결정.

**한 일**
- `CommLogSyncService` 신규 작성 — `call_log`/`flutter_sms_inbox` 패키지로
  실제 통화기록·문자 메시지를 읽어와 선택된 인맥의 전화번호와 매칭(국가번호
  차이를 흡수하기 위해 뒤 9자리로 비교), `CommunicationLogModel`로 변환. 안드로이드
  전용 — iOS/웹에서는 `UnsupportedError`.
- `permission_handler`로 통화기록/SMS 권한 요청 흐름 추가. Android permission
  (READ_CALL_LOG, READ_PHONE_STATE, READ_SMS) 및 `call_log`가 요구하는 core
  library desugaring 활성화.
- `CommunicationLogModel`에 `isAutoSynced` 필드 추가 — 실제 연동된 항목과
  데모/수동 항목을 구분.
- **UI/UX 사용자 피드백 반영**: 아이폰에서 브리핑 화면에 통화/카톡/이메일/문자가
  다 보여서 "이게 실제로 되는 건가?"로 오해할 수 있다는 지적 → 플랫폼별로 명확히
  다른 UI로 분리:
  - `communication_trace_test_modal_view.dart`: "🔄 자동 연동(실제 기기 데이터)"
    섹션(통화/문자, 안드로이드 전용)과 "📝 수동/데모 항목(준비 중)" 섹션(카카오톡/
    이메일)을 시각적으로 분리. 안드로이드가 아니면 배너 색상부터 빨간색으로
    바뀌고 버튼이 잠금 아이콘과 함께 비활성화됨.
  - `briefing_overlay_view.dart`: 소통 이력 섹션에 플랫폼별 안내 문구 추가,
    실제 연동된 항목에는 "🔄 자동 연동" 배지 표시.
- 안드로이드 에뮬레이터에서 실제 권한 팝업(통화기록/SMS 둘 다) → 실제
  `CallLog.get()`/`SmsQuery` API 호출까지 end-to-end로 확인(크래시 없음,
  로그에 `CALL_LOG onMethodCall` 정상 실행 확인). 에뮬레이터라 실제 기록은
  없어서 "일치하는 기록 없음" 경로까지만 확인 — 실제 통화/문자 이력이 있는
  진짜 기기에서 매칭 결과 자체는 아직 미검증.

**다음에 할 일 (사용자가 리마인드 요청함)**
1. 수동 메모 입력 UI (모든 플랫폼 기본, 카카오톡은 항상 이 방식) — 아직 시작 안 함.
3. 이메일 실제 연동 (Gmail API 등 OAuth 필요, 큰 작업) — 아직 시작 안 함.

---

### 2026-08-02 (추가) — 안드로이드 실기기 검증 완료

사용자가 웹에서 OCR 스캔 버튼이 안 눌린다고 제보 → 원인은 웹이 ML Kit을
지원 안 하는 것(의도된 제약, UX로 명확히 안내하도록 개선) → "그럼 실기기에서
해보자"는 흐름으로 안드로이드 에뮬레이터에 이 프로젝트 최초로 설치해서
`adb`로 직접 조작하며 명함 촬영 → OCR 전체 흐름을 end-to-end 검증함.

- GPS 권한 요청 팝업이 실제로 뜨는 것 확인(허용 시 실제 위치 시도).
- 카메라 권한 요청 → 실제 네이티브 카메라 앱 실행 → 촬영 → 확인까지 정상.
- **크래시 발견 및 수정**: 한글 OCR 모델이 앱에 번들링 안 돼 있어서 촬영
  직후 `NoClassDefFoundError`로 앱 전체가 죽는 심각한 버그를 잡음(한글
  명함이 기본 시나리오인 이 앱에선 사실상 전원이 겪었을 버그).
  자세한 원인은 [error-notes.md](error-notes.md) 참고.
- 수정 후 재검증: 촬영 → 실제 ML Kit 텍스트 인식 성공(`OCR process
  succeeded`) → 인식된 텍스트가 없으면(에뮬레이터라 실제 명함이 아니었음)
  크래시 없이 "텍스트를 인식하지 못했습니다"로 정상 폴백하는 것까지 확인.
- 부수적으로 `geocoding` 패키지도 5.0.0으로 올려야 했음(구버전이 최신
  안드로이드 빌드 도구와 호환 안 됨) — API가 바뀌어서 호출부도 같이 수정.
- iOS는 시뮬레이터가 Apple Silicon arm64를 ML Kit이 지원 안 해서 설치 자체가
  안 됨(Google 쪽 알려진 제약) → 사용자가 실제 아이폰(16 Pro)으로 테스트하는
  방향으로 진행 중, 개발자 모드 활성화 단계 안내함.

---

### 2026-08-02

**한 일 — "다음에 할 일" 백로그 4건 전부 완료**
1. **스플래시 페이드아웃 전환** — `main.dart`에서 `FlutterNativeSplash.preserve()`
   호출, 새 [SplashGate](../../lib/presentation/common/splash_gate.dart) 위젯이
   네이티브 스플래시와 동일한 배경색/로고를 첫 프레임에 그대로 덮어 두었다가
   `.remove()` 후 500ms 페이드아웃. `flutter_native_splash`를
   `dev_dependencies` → `dependencies`로 이동 완료.
2. **실제 GPS 연동** — `geolocator` 패키지로 [location_service.dart](../../lib/core/services/location_service.dart)
   신규 작성. 권한 없음/위치서비스 꺼짐 등 실패 시 예외 없이 null 반환 →
   `RadarViewModel`이 기존 fallback(강남역) 좌표로 조용히 폴백. 화면 진입 시
   자동으로 한 번 시도.
3. **실제 지오코딩 연동** — `geocoding` 패키지로 `address_geocoding_service.dart`를
   비동기로 전면 재작성(정방향 지오코딩 + 역지오코딩으로 도로명 주소 조합 생성).
   호출부(`add_card_modal_view.dart`의 `_saveCard`)를 async로 변경하고 저장
   버튼에 "주소 확인 중..." 로딩 상태 추가.
4. **실제 OCR 연동** — `google_mlkit_text_recognition`(온디바이스 텍스트 인식) +
   `image_picker`(실제 카메라/갤러리 접근)로 `ocr_scanner_service.dart` 전면
   재작성. 정규식 기반으로 전화/이메일/주소는 정확히, 이름/회사/직함은 "가장
   그럴듯한 남은 줄" 휴리스틱으로 채움(완벽한 필드 분류는 전용 명함 파싱 모델
   없이는 한계 — 사용자가 폼에서 직접 수정 가능). `camera_scan_modal_view.dart`
   (기존 가이드 UI 유지, 촬영은 네이티브 카메라로)와 `file_picker_modal_view.dart`
   (가짜 갤러리 그리드 제거하고 실제 `image_picker` 갤러리 선택으로 교체) 반영.
   iOS/Android 권한 문자열(카메라·사진·위치) 추가.
5. **2색 팔레트 전 화면 점검** — 전 lib/ 대상 하드코딩 hex 색상 grep 감사 →
   2건 발견해 `AppColors` 토큰으로 교체(`camera_scan_modal_view.dart`,
   `radar_view.dart`). 점검 중 발견한 별도 버그도 수정: 설정 화면의 "주변 인맥
   감지 알림" 스위치가 `onChanged: (val) {}`로 아무 동작도 안 하던 것을
   `radarViewModel.toggleDetection()` 연결로 수정.

**검증 관련 메모**
- `flutter analyze` 전체 통과(에러 0, 기존에 있던 info성 경고만 남음).
- 웹 빌드로 콘솔 에러 없이 로드되는 것 확인(스플래시/GPS 폴백 정상 동작).
- 이번 기회에 **이 프로젝트 최초로 iOS 시뮬레이터 빌드**를 시도해 실제
  네이티브 툴체인 이슈를 하나 잡음 — 자세한 원인·해결은
  [error-notes.md](error-notes.md) 참고(`path_provider_foundation` 2.6.0의
  objective_c 네이티브 에셋 관련 Flutter 툴체인 크래시, iOS 배포 타겟 상향
  필요 등). `flutter build ios --simulator` 최종 성공.
- 다만 이 세션에서는 시뮬레이터 화면에 대한 Claude 접근 권한이 사용자에게
  승인되지 않아("Let Claude use it") 빌드된 앱을 실제로 실행해서 눈으로
  확인하지는 못했음 — 다음에 시뮬레이터 패널에서 권한을 승인해주면 실제
  기기 동작(카메라 촬영→OCR, 실제 GPS 권한 프롬프트, 지오코딩)을 직접
  확인할 수 있음. 또한 Google ML Kit iOS SDK가 Apple Silicon(arm64)
  시뮬레이터 아키텍처를 지원하지 않는다는 경고가 빌드 로그에 떴음(Google
  쪽 알려진 제약) — OCR을 시뮬레이터에서 테스트하려면 실기기이거나 Rosetta
  시뮬레이터가 필요할 수 있음. 실기기(iPhone)에서는 문제 없음.

---

### 2026-08-01

**한 일**
- UI/UX 2색(다크 뉴트럴 + 액센트 #004EA2) 리디자인 — `app_colors.dart`,
  `app_theme.dart`, `glass_card.dart`, `action_circle_button.dart`,
  `radar_view.dart` 등 컬러 토큰 정리 및 그림자/두꺼운 선 제거.
- CREAMHOUSE 로고를 앱 첫 로딩 스플래시 이미지로 적용(`flutter_native_splash`),
  이후 사용자가 더 큰 원본(`assets/CI.png`)을 제공해 교체·업스케일.
- 코드 정적 감사로 메모리 누수 여부 확인(누수 없음, 최적화 여지 3건은
  아래 백로그에 기록).
- **명함 등록 폼 Tab 키 필드 건너뛰기 + Assertion 크래시 버그 완전 해결**
  (6차 시도 끝에 해결 — 원인·과정은 [error-notes.md](error-notes.md) 참고).
  최종적으로 `lib/core/utils/web_tab_guard*.dart`를 새로 추가해 브라우저
  네이티브 keydown을 직접 가로채고, 한글 IME 조합 종료 시점까지 기다렸다가
  포커스를 옮기는 방식으로 정착.
- 명함 등록 모달에 입력 취소(X) 버튼 추가.
- GitHub 원격 저장소(`connection-trace-ai-v2-flutter`, private) 생성 및 push.

**다음에 할 일 (우선순위 순)**
1. 스플래시 화면 페이드아웃 전환 구현 — `FlutterNativeSplash.preserve()`를
   `main.dart`에서 호출하고, 커스텀 위젯으로 스플래시를 복제해 보여준 뒤
   `.remove()` 후 opacity를 0으로 애니메이션하는 표준 패턴. 설명만 하고
   구현 전에 Tab 버그 우선순위에 밀려 중단된 상태 — 다음 세션에서 이어서
   진행.
   (참고: 이 작업을 하게 되면 `flutter_native_splash`를 `pubspec.yaml`의
   `dev_dependencies`에서 `dependencies`로 옮겨야 함 — `.preserve()`/
   `.remove()`를 런타임에 `main.dart`에서 호출하려면 필요.)
2. 실제 기능 전환: OCR(Tesseract/ML Kit) · GPS(Geolocator) · 지오코딩
   (Nominatim 등)을 실제 구현으로 교체 — 현재는 전부 mock. 이 작업과 함께
   아래 "메모리/최적화" 3건 및 소통 이력 연동도 같이 정리하기로 함.
3. 나머지 화면(명함 지갑/설정/각종 모달)이 2색 팔레트로 올바르게 렌더링되는지
   `flutter run -d chrome`으로 직접 확인 필요(아래 항목 참고).

   *(이 3건 전부 2026-08-02에 완료 — 위 로그 참고)*

---

## 향후 후보 (미착수)

- **(2026-08 메모리/최적화 감사에서 파생, 실제 기능 작업 때 같이 정리하기로 결정)**
  코드 정적 감사 결과 메모리 누수는 없었음(AnimationController/TextEditingController/
  FocusNode 전부 정상 dispose, ChangeNotifier 리스너 등록/해제 쌍 정확, Timer/
  StreamSubscription 사용 자체가 없음, OCR 비동기 흐름에 `mounted` 가드 있음).
  다만 다음 3가지는 "누수는 아니지만 최적화 여지"로 확인됨 — 실제 기능(OCR/GPS/
  지오코딩 등) 붙이는 작업과 함께 정리하기로 사용자가 결정:
  1. `radar_view.dart`의 "근접 인맥 리스트"가 `ListView.builder`가 아니라
     `Column` + `.map()`으로 전부 즉시 렌더링됨(`wallet_view.dart`는 이미
     `ListView.builder` 사용 중이라 대조됨). 인맥 수가 늘어나면 스크롤 성능에
     영향 줄 수 있음.
  2. `context.watch<RadarViewModel>()`/`context.watch<WalletViewModel>()`가 각
     화면 최상단에서 호출돼 뷰모델 값 하나만 바뀌어도 화면 전체가 리빌드됨.
     `Selector`나 좁은 범위 `Consumer`로 좁히면 리빌드 범위 최적화 가능.
  3. `RadarViewModel.filteredContacts`/`nearbyAlertContact` getter가 호출될
     때마다 전체 인맥 거리 계산을 캐싱 없이 다시 수행 — 같은 프레임에 두 getter가
     같이 호출되면 거리 계산이 중복됨.
- ~~**(2026-08 실제 기능 전환 결정)** OCR/GPS/지오코딩 실제 구현 교체~~ →
  **2026-08-02 완료** (위 작업 로그 참고).
- **(2026-08 결정)** 소통 이력(통화/문자/이메일/카카오톡) 연동: 기본은 수동 메모,
  통화/문자/이메일은 사용자가 선택적으로 연동 가능하게 구성. 아이폰은 OS 정책상
  통화/문자 로그 접근이 원천적으로 불가해 수동 메모만 가능(편의성 고려해서 설계
  필요) — 안드로이드는 `READ_CALL_LOG` 등 권한으로 제한적으로 가능하나 Play
  Store 심사 반려 리스크 있음. 카카오톡은 어느 플랫폼에서도 개인 대화 읽기 API가
  존재하지 않아 연동 자체가 불가(수동 메모만 가능).
- ~~**(2026-08 UI 리디자인에서 파생)** 나머지 화면 2색 팔레트 렌더링 확인~~ →
  **2026-08-02 완료**(grep 기반 전수 감사로 하드코딩 색상 2건 발견·수정 — 이
  개발 환경은 여전히 Flutter Web 클릭/키보드 이벤트를 인식 못 해 클릭 기반
  화면 전환 검증 자체는 못 함, 알려진 툴링 제약).
- **(2026-08-02 iOS 최초 빌드에서 발견)** Google ML Kit iOS SDK가 Apple
  Silicon(arm64) 시뮬레이터를 지원하지 않음(Google 쪽 알려진 제약) — OCR을
  시뮬레이터에서 테스트하려면 Rosetta 시뮬레이터가 필요할 수 있음. 실기기는
  문제 없음. 사용자가 실기기 또는 Rosetta 시뮬레이터로 테스트할 때 참고.

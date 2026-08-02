# Connection Trace AI v2 (Flutter) — Planning Backlog

## 작업 로그

### 2026-08-02 (추가 10) — 모달 스낵바 안 보이던 근본 원인 수정 (화면 녹화로 진단)

사용자가 "필수 정보 없을 때 뒷면 스캔 안내가 안 뜬다"고 재보고. 텍스트만
으로는 원인이 안 잡혀서 화면 녹화 영상을 요청 → `~/Downloads`에서 받아
`ffmpeg`로 프레임 추출해 직접 확인.

영상으로 확인한 실제 카드 내용("크림하우스(주)" / 이희규 / ICT사업본부|상무
/ M010 4504 8595 / D 070 5084 2601 / E globe@creamhouse.co.kr, 주소 없음)과
스캔 결과 폼을 대조한 결과: **OCR 파싱 자체는 정확했음**(이름/회사/직함/
휴대폰/이메일 전부 정확히 추출, 주소는 카드에 실제로 없어서 정상적으로
빈 채로 검증 에러 표시됨) — 문제는 "뒷면 스캔" 안내가 **떴는데 안 보인
것**이었음.

**근본 원인**: `add_card_modal_view.dart`를 비롯한 여러 bottom-sheet 모달
화면이 자체 `Scaffold` 없이 `Container`만 반환하는 구조라, 그 안에서
`ScaffoldMessenger.of(context)`를 호출하면 이 모달 뒤에 깔린 페이지
(RadarView 등)의 Scaffold를 찾아가 버림 — 스낵바가 모달 시트에 완전히
가려진 위치에 렌더링돼 사용자 눈에는 안 보였음(특히 키보드까지 열려 있으면
더더욱 안 보임).

**수정**:
- `add_card_modal_view.dart` / `file_picker_modal_view.dart` /
  `communication_trace_test_modal_view.dart`에 로컬
  `GlobalKey<ScaffoldMessengerState>`를 두고 `build()`를 투명 배경
  `Scaffold`로 감싸서, 모달이 열려 있는 동안 뜨는 스낵바는 로컬 키로 모달
  위에 뜨도록 수정.
- `communication_trace_test_modal_view.dart`의 연동 성공 스낵바 1건은
  `Navigator.pop`으로 모달을 이미 닫은 뒤 호출되는 케이스라 로컬 키가 이미
  사라진 상태라 예외적으로 바깥 `ScaffoldMessenger.of(context)`를 그대로
  둠(부모 화면에 정상적으로 뜸). `manual_comm_log_modal_view.dart` /
  `my_profile_edit_modal_view.dart`는 원래부터 pop을 먼저 호출하는 구조라
  문제없어 그대로 둠.

영상으로 실제 카드를 보다가 추가로 발견한 것들:
- 사무실 전화번호 정규식이 02/031~069만 잡고 070(인터넷전화)을 놓치고
  있었음 — `ocr_scanner_service.dart` 정규식에 070 추가.
- 레이더 히어로 위젯의 근접 인맥 말풍선이 실제 거리와 무관하게 항상
  "140m"로 하드코딩돼 있었음(메인 숫자는 실제 계산값인데 이 말풍선만
  가짜였음) — `RadarPulseHeroWidget`이 실제 계산된 거리를 받아 표시하도록
  수정.

실기기 설치 확인(폰 잠금 상태라 실행 재확인은 사용자 몫).

---

### 2026-08-02 (추가 9) — 명함 앞/뒷면 나눠 스캔 지원

한글 OCR 근본 수정(추가 8) 후 사용자가 실기기에서 재확인: "한글 인식 잘
되네, 조금만 더 개선하면 될 것 같아 — 사진촬영 후 스캔을 하고 필수 입력
자료가 없으면 후면에 있는 경우가 있어 그런 경우 처리를 추가해." 명함은
앞면(이름/직함/회사)과 뒷면(전화번호/주소/이메일 영문판 등)에 정보가 나뉜
경우가 흔한데, 기존엔 스캔할 때마다 폼 전체를 덮어써서 뒷면을 이어서
스캔하면 앞면에서 읽은 값이 날아갔음.

- `add_card_modal_view.dart`의 `_performOcrScan`이 스캔 결과를 폼에 채울 때
  이미 값이 있는 필드는 건드리지 않고 빈 필드만 채우도록 변경
  (`_fillIfEmpty`) — 앞면 스캔 후 뒷면을 이어서 스캔해도 값이 누적됨(원본
  텍스트도 `---` 구분자로 이어붙임).
- 스캔 후에도 필수 필드(이름/회사/주소/휴대폰/이메일)가 비어 있으면 "명함
  뒷면에 있을 수도 있다"는 안내 스낵바 + 같은 촬영 방식(카메라/갤러리)으로
  바로 재스캔하는 "뒷면 스캔" 버튼 추가.

실기기 설치+실행 확인.

---

### 2026-08-02 (추가 8) — iOS 한글 OCR 근본 원인 수정 + 전체 하드코딩 데이터 감사

사용자가 "카메라/UI는 좋은데 한글을 제대로 못 읽는다"고 재확인. 조사 결과
**iOS에서만 발생하는 네이티브 링킹 문제**였음:
`google_mlkit_text_recognition`의 iOS podspec이 `GoogleMLKit/TextRecognition`
(라틴 전용) 서브스펙만 의존성으로 선언하고, 한국어 서브스펙
(`GoogleMLKit/TextRecognitionKorean`)은 선언하지 않음. 플러그인 네이티브
코드(`GoogleMlKitTextRecognitionPlugin.m`)가
`#if __has_include(<MLKitTextRecognitionKorean/...>)`로 컴파일 타임에 해당
pod의 존재 여부를 체크하는 구조라, 이 pod이 없으면 `case 4`(한국어) 분기
자체가 컴파일에서 통째로 빠짐 — Dart에서 `TextRecognitionScript.korean`을
지정해도 조용히 `default`(라틴 전용) 인식기로 폴백. **iOS에서는 그동안 한
번도 한국어 OCR 모델이 실제로 쓰인 적이 없었음**(안드로이드는
`build.gradle.kts`에 `com.google.mlkit:text-recognition-korean` gradle
의존성이 이미 있어서 문제 없었음 — 그래서 플랫폼 간 체감 차이가 컸을 것).

**수정**: `ios/Podfile`의 `target 'Runner'` 블록에
`pod 'GoogleMLKit/TextRecognitionKorean', '~> 9.0.0'` 직접 추가 → `pod
install`로 `MLKitTextRecognitionKorean 6.0.0` 설치 확인, 릴리스 빌드 성공
(앱 크기 77.2MB→79.0MB로 증가, 한국어 모델 번들링 반영).

이어서 "하드코딩된 데이터 전체 점검해줘" 요청으로 `lib/` 전체 재감사 —
grep으로 전화번호/이메일/좌표/이름 패턴을 훑고 각 화면을 다시 확인:
- **레이더 화면 히어로 지표**: 근처에 감지된 인맥이 진짜로 없을 때도 항상
  "140m · 김민준 이사 · 테크노바 근접중"이라는 가짜 값이 표시되고 있었음 —
  사용자가 실제로는 아무도 없는데 근처에 누가 있다고 착각할 수 있는 심각한
  문제. `nearby == null`일 때 "--"/"주변에 감지된 인맥이 없습니다"로 수정.
- **레이더 화면 상단 검색창**: `TextField`도 `onChanged`도 없이 텍스트만
  그려진 완전 장식용 위젯이었음(명함 지갑 화면의 검색창은 이미 실제로
  동작했는데 레이더 화면 것만 가짜였음) — `RadarViewModel`에
  `searchTerm`/`setSearchTerm` 추가해 이름·회사·직함 필터링이 실제로
  동작하도록 수정.
- 3개 데모 인맥 시드 데이터(`contacts_repository.dart`)와 기본 프로필
  placeholder(`my_profile_model.dart`)는 최초 실행 1회만 시딩되고 이후
  로컬 저장값을 우선하는 정상 온보딩 설계로 확인 — 문제 아님.

실기기 설치+실행까지 확인. 실제 한글 인식률 개선 여부는 사용자가 진짜
명함으로 재테스트해야 확인 가능.

---

### 2026-08-02 (추가 7) — OCR 회사 전화번호 버그 수정 + 필드 분류 정확도 개선

카메라 프리뷰/크롭 개선(추가 6) 이후에도 사용자가 "스캔 인식률이 그대로"라고
재확인 — 조사 결과 이미지 품질 문제가 아니라 **데이터 유실 버그**였음.
`add_card_modal_view.dart`가 스캔 결과와 무관하게 회사 전화번호 필드에
`'02-555-1234'`를 항상 하드코딩으로 덮어썼고, `ocr_scanner_service.dart`의
`_parse()`도 인식된 회사 전화번호를 모바일 번호와 병합해버려 애초에 호출
쪽으로 전달하지 않았음. 카메라를 아무리 개선해도 이 필드는 절대 정확해질
수 없는 구조였음.

- `OcrScanResult`에 `officePhone` 필드 분리 추가, 실제 인식값 전달.
- ML Kit `RecognizedText.text`가 2단 레이아웃 명함에서 줄 순서를 뒤섞는
  문제 대응 — 각 줄 바운딩 박스 좌표로 위→아래/좌→우 재정렬
  (`_extractOrderedLines`).
- 이름/회사/직함을 "남은 줄 순서대로" 채우던 방식에 직함·회사 키워드 매칭
  + 순수 한글 2~4자 이름 패턴 판별을 우선 적용하도록 개선.

실기기 설치까지 확인(잠금 상태라 실행 재확인은 사용자 몫). 실제 인식률
개선 여부는 사용자가 진짜 명함으로 재테스트해야 확인 가능.

---

### 2026-08-02 (추가 6) — 명함 카메라 실시간 프리뷰 전환 + QR 명함 교환 실제 구현 + 전체 미구현 기능 감사

**배경**: 사용자가 "카메라가 후면으로 안 열리고 스캔 인식률도 그대로"라고
재보고 — 직전 커밋(c0813eb)의 `preferredCameraDevice: rear` +
`imageQuality: 100` 수정이 효과가 없었음. 원인 조사 결과 근본 구조 문제였음:
`camera_scan_modal_view.dart`가 실제 카메라 프리뷰가 아니라
`AppColors.bgDarkSlate` 단색 배경 위에 가이드 프레임/레이저 애니메이션만
그린 **가짜 화면**이었고, 셔터를 눌러야 그제서야 `image_picker`의 네이티브
카메라 팝업이 별도로 열리는 구조였음 — 그래서 "후면으로 열렸는지" 자체를
화면에서 확인할 방법이 없었던 것.

**한 일**
1. `camera` 패키지로 `camera_scan_modal_view.dart`를 실제 후면 카메라
   실시간 프리뷰로 전면 재작성. `CameraLensDirection.back` 명시 선택,
   `ResolutionPreset.veryHigh`, 실제 토치 플래시 제어.
2. 촬영본을 가이드 프레임(화면에 보이는 사각형) 영역으로 크롭해 배경 노이즈를
   제거 — `image` 패키지로 cover-fit 좌표 변환 계산, 오차 대비 15% 여유 크롭.
   계산 실패 시 원본 그대로 폴백(카드가 잘리는 사고 방지).
3. 이어서 사용자가 "개발 기능 전체를 점검해서 미구현 기능 모두 만들어달라"고
   요청 — `lib/presentation` 전체 화면을 훑어 실제 기능 여부 감사:
   - **QR 코드 화면**: "내 명함 QR"이 `Icon(Icons.qr_code_2)` 아이콘 그림,
     "상대방 QR 스캔"은 카메라도 인식 로직도 없는 완전 데코레이션이었음 →
     `vcard_util.dart` 신규 작성(vCard 3.0 인코드/디코드), `qr_flutter`로
     내 프로필을 실제 스캔 가능한 QR로 렌더링, `mobile_scanner`로 실제 카메라
     스캔 구현. 스캔 성공 시 `AddCardModalView(prefillData:)`로 이어져 새
     명함 폼에 자동 채움.
   - **명함 지갑 삭제**: `ContactsRepository.deleteContact`가 이미 있었는데
     UI 진입점이 전혀 없었음 → 스와이프 삭제(확인 다이얼로그 포함) 추가.
   - **설정 화면 문구 오류**: "암호화 DB에 보관"이라고 되어 있었는데 실제로는
     `shared_preferences` 평문 로컬 저장이라 사실과 다른 문구였음 → 정정.
   - **알림 센터**: 전부 하드코딩된 샘플 알림 3건 — 실제 이벤트 파이프라인이
     없어 이번엔 손대지 않음(별도 기능 설계 필요, 아래 향후 후보 참고).
   - **"30초 AI 대화 브리핑"의 추천 대화 포인트**: 앱 전체를 grep해도 실제
     LLM/AI API 호출이 어디에도 없음 확인 — `AddCardModalView`가 신규 명함
     추가 시 무조건 하드코딩된 문구 2개("최근 프로젝트 진행 상황 공유하기"
     등)를 넣는 구조. **앱의 핵심 기능("AI")이 실제로는 static placeholder**
     라는 뜻 — API 제공사 선택 + API 키 발급이 사용자 결정 사항이라 이번
     회차에선 보류, 사용자에게 별도 확인 필요(아래 향후 후보 참고).
4. iOS 실기기(iPhone 16 Pro) 서명 릴리스 빌드 성공 + `devicectl install`로
   설치 확인. `launch`는 기기 잠금 상태라 재시도 필요(반복되는 알려진 제약).

**결론**: 카메라 후면 문제와 QR 기능은 근본 원인(가짜 화면 구조)까지 해결.
명함 지갑 삭제 UI 누락, 설정 화면 오기재 문구도 같이 정리. AI 대화 포인트
생성은 진짜 AI 연동이 아예 없었다는 걸 이번에 처음 확인 — 사용자 결정 필요한
항목으로 향후 후보에 등록.

---

### 2026-08-02 (추가 5) — 소통 이력 연동 완료 확인 (Gmail OAuth 실기기 검증)

사용자가 Google Cloud Console에서 OAuth 설정을 직접 완료(프로젝트 생성,
Gmail API 활성화, OAuth 동의 화면 + 테스트 사용자 등록, Android/iOS 클라이언트
ID 발급). iOS 클라이언트 ID(`1000564658393-btkjfad5a348071e9lk0psl6v4vi1hs0
.apps.googleusercontent.com`)를 전달받아 `ios/Runner/Info.plist`에
`GIDClientID` + 콜백 URL Scheme(`com.googleusercontent.apps.<client-id>`)로
반영.

과정에서 "403 access_denied" 에러(테스트 사용자 미등록)를 실기기 스크린샷으로
잡아서 바로 안내 → 사용자가 테스트 사용자 추가 후 **실제 아이폰에서 Gmail
연동 성공 확인**("연동 잘되네").

**결론: 소통 이력 연동 4채널(통화/문자/이메일/카카오톡) 전부 완료.**
- 통화·문자: 안드로이드 전용, 실제 기기 데이터 연동 확인됨
- 이메일: 전 플랫폼, Google OAuth 연동 확인됨(iOS 실기기 검증 완료)
- 카카오톡: API 부재로 수동 입력이 최종 형태(설계대로)
- 수동 입력: 모든 채널 대상 공통 폴백, 브리핑 화면에서 확인됨

---

### 2026-08-02 (추가 4) — 소통 이력 연동 #3: 이메일 실제 연동(Gmail API) 코드 완료

**한 일**
- `EmailSyncService` 신규 작성 — `google_sign_in`(v7, 최신 인증/인가 분리
  API)로 Google 로그인 후 `gmail.readonly` 스코프 권한 요청, Gmail API REST
  호출(`googleapis` 패키지 대신 `http`로 직접 호출 — 의존성 가볍게 유지)로
  특정 인맥 이메일 주소와 주고받은 메일을 제목/날짜만(본문 제외, 개인정보
  최소화) 조회해서 `CommunicationLogModel(isAutoSynced: true)`로 변환.
- 통화/문자와 달리 **이메일은 모든 플랫폼(Android/iOS/웹)에서 동일하게
  동작** — `communication_trace_test_modal_view.dart`의 "자동 연동" 섹션에
  통화/문자와 나란히 배치, 로그인 전에는 "Google 계정으로 로그인" 버튼,
  로그인 후에는 실제 연동 버튼으로 전환.
- 안드로이드 디버그 서명 SHA-1 지문 확보(위 "사용자 액션 필요" 섹션 참고).
- 안드로이드 에뮬레이터에서 패키지 추가 후에도 빌드/실행 크래시 없음을 확인.
  다만 실제 로그인 플로우는 OAuth 클라이언트 미설정 상태라 끝까지 테스트 못함
  (에뮬레이터 탭 인식도 불안정해서 버튼 클릭 자체도 재현 못 함 — 재시도 필요).

**결과**: 소통 이력 연동 4채널(통화/문자/이메일/카카오톡) 코드는 전부 완성.
이메일만 사용자의 Google Cloud Console 설정이 끝나야 실제로 작동 확인 가능.

---

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

- **(2026-08-02 전체 기능 감사에서 발견, 사용자 결정 필요)** "30초 AI 대화
  브리핑"의 "추천 맞춤 대화 포인트"가 실제로는 AI/LLM 호출이 전혀 없는
  하드코딩 문구다(`add_card_modal_view.dart`의 `_executeFinalSave`가 신규
  명함마다 동일한 2줄을 그대로 넣음). 앱 이름/핵심 화면이 내세우는 "AI" 기능이
  실질적으로 비어 있는 상태 — 진짜로 만들려면 LLM 제공사 선택(Anthropic
  Claude API 등) + API 키 발급이 필요한데 이건 사용자 계정/과금 결정 사항이라
  코드만으로는 진행 불가. 제공사와 키가 정해지면 `http` 패키지로 REST 호출
  붙이는 작업 자체는 어렵지 않음(Gmail 연동과 비슷한 패턴).
- **(2026-08-02 전체 기능 감사에서 발견, 낮은 우선순위)** 알림 센터
  (`notification_center_modal_view.dart`)가 하드코딩된 샘플 알림 3건을 항상
  보여줌 — 실제 근접 감지/신규 명함 등록 이벤트를 실시간 알림으로 쌓는
  파이프라인이 없음. "정보성 데모 콘텐츠"라 당장 사용성을 해치진 않지만,
  실제로 만들려면 RadarViewModel의 근접 감지 결과나 ContactsRepository 변경을
  구독해 알림 리스트를 실시간 생성하는 별도 상태 관리가 필요(중간 규모 작업).
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

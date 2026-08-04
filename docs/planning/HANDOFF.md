# 개발 인수인계 문서 (2026-08-04 밤 기준)

다음 개발자(또는 다음 대화창)가 이 프로젝트를 빠르게 이어받을 수 있도록 정리한
문서. 시간순 상세 기록은 [`backlog.md`](./backlog.md)(추가 1~67)에 다 있으니,
특정 결정의 배경이 궁금하면 거기서 검색하는 게 가장 빠르다. 이 문서는 "지금
상태"의 요약본.

**새 대화창/CLI에서 이어받는 경우**: 이 문서(HANDOFF.md) → "2-0. 사용자가
결정할 일" → "2. 하고 있는 일" → "3. 해야 할 일" 순서로 읽으면 됨.

**서브에이전트로 나눠서 작업하려면(추가 65)**: 이 프로젝트 전용 서브에이전트
4개가 `connection-trace-ai-v2-flutter/.claude/agents/`에 있다 —
`flutter-planner`(PM/오케스트레이터), `flutter-developer`(로직/데이터),
`flutter-qa`(실기기 검증), `flutter-ui-designer`(시각/스타일). 같은 이름의
커스텀 슬래시 커맨드(`/flutter-planner` 등, `.claude/commands/`)도 있어서
CLI에서 바로 쓸 수 있다 — **단, 이 저장소 디렉터리(`connection-trace-ai-v2-
flutter`)를 작업 디렉터리로 `claude`를 실행했을 때만 인식된다**(프로젝트
로컬 등록이라 다른 경로에서 켜면 안 보임). 작업량이 많으면 우선
`flutter-planner`에 먼저 맡기고, 그게 필요한 곳에 나머지 세 에이전트를
위임하는 방식을 권장.
(예전엔 `ct-planner` 등 전역 에이전트가 있었지만, 그건 지금은 삭제된 옛
React/Vite/Capacitor 프로토타입 저장소용이었다 — 이 Flutter 프로젝트와는
무관했고 2026-08-04에 저장소·에이전트 둘 다 정리됨.)

## 프로젝트 개요

- **앱 이름**: 커넥션센스 (Connection Sense) — 원래 "Connection Trace AI"에서
  개명(추가 28).
- **위치**: `/Volumes/X31(VM)/Claude/connection-trace-ai-v2-flutter`
- **스택**: Flutter (Dart), 상태관리는 `provider` 패키지, 로컬 저장은
  `shared_preferences`(일반 데이터) + `flutter_secure_storage`(AI API 키).
  **현재 코드 기준으로는 아직 백엔드 서버 없음** — 전부 클라이언트에서 직접
  각 외부 API(지오코딩, ML Kit, AI 제공사 등)를 호출하는 구조. 단,
  2026-08-04에 사용자가 명함/인맥 데이터를 Firebase 서버에 저장하기로
  확정했고(추가 66) 설계 문서(`docs/planning/server-setup-plan.md`)까지
  완료된 상태 — 구현 착수 전까지는 이 설명이 유효함.
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

## 0-1. 2026-08-04 밤 — iOS 배포 트러블슈팅 + 계정/데이터 안전장치 + 암호화 (가장 최신)

이 세션(위 "0"번 섹션 이후 이어진 대화)에서 실제로 끝낸 것. 상세 에러 원인·
해결 과정은 전부 [`error-notes.md`](./error-notes.md)의 2026-08-04 항목들에
있음 — 같은 증상 재발 시 거기부터 볼 것.

- **iOS Bundle ID 충돌 해결**: `com.connectiontrace.connectionTraceAiFlutter`가
  예전 개인 Apple ID(무료 Personal Team)에 선점돼 있어 회사 계정(CreamHouse
  Co., Apple Developer Program 유료 가입 완료)으로 서명이 안 되던 문제.
  `com.creamhouse.connectionsense`로 변경, Firebase에 새 iOS 앱 재등록,
  `GoogleService-Info.plist`/`firebase_options.dart`/`Info.plist`의
  `GIDClientID`·URL 스킴 전부 동기화. Android는 영향 없음(패키지명 그대로).
- **Firebase iOS 15.0 배포타겟 충돌 해결(Flutter 툴체인 자체 버그)**:
  `FlutterGeneratedPluginSwiftPackage`가 iOS 13.0으로 하드코딩 생성돼
  Firebase 요구사항(15.0+)과 항상 충돌 — 프로젝트 설정으론 못 고치는 SDK
  버그(Flutter 3.44.8). `pubspec.yaml`에 `flutter.config.enable-swift-
  package-manager: false`로 이 프로젝트만 SPM을 끄고 기존 CocoaPods
  경로로 전환해서 해결.
- **iOS/Android 실기기 전체 파이프라인 재검증 완료**: Google 로그인 → Firebase
  Auth → Firestore 백업 → 로그아웃/재로그인 → 서버 복원까지 양쪽 플랫폼
  실기기(iPhone, 갤럭시 Z 폴드)에서 직접 확인. Android는 `adb`로 로컬
  shared_preferences 실제 내용까지 직접 열어서 검증(문정순/더자안 테스트
  명함으로 확인).
- **계정 삭제 기능 구현(추가 71)**: 설정 화면에 위험 표시된 "계정 삭제" 항목.
  Firestore 데이터 먼저 삭제 → Firebase Auth 계정 삭제 → 로컬 초기화 순서.
  "최근 로그인 필요" 에러 시 Google 재인증 후 자동 재시도까지 구현. 에러를
  조용히 삼키지 않고 사용자에게 명확히 표시(다른 백업 로직과 다른 부분).
- **다중 계정 전환 안전장치 구현(추가 71)**: 마지막 로그인 uid를 기기에 저장,
  다른 계정으로 로그인했는데 기존 로컬 데이터가 있으면 "유지 vs 교체" 다이얼로그로
  명시적 선택 요구(강제 선택, 바깥 탭으로 안 닫힘).
- **개인정보처리방침 작성·게시(추가 72 이전)**: 코드 전수 조사 기반으로 작성
  (`docs/legal/privacy-policy.html`) — 통화/SMS/카카오톡은 자동 수집 안 함
  (수동 입력만), Gmail은 제목+미리보기까지 수집, 명함 사진은 서버 미전송 등
  실제 구현과 정확히 일치하도록 작성. 사업자등록증 기준 회사 정보(등록번호
  220-86-89511, 대표 최우진, 서울 영등포구 양평로21가길 19) 반영 완료.
  **아직 임시**: 개인정보 보호책임자 담당자·전용 문의메일(현재 대표자/
  creamhouseapp@gmail.com로 임시 지정, 문서 안에 명시돼 있음).
- **명함/프로필 로컬+서버 AES-256-GCM 암호화 적용(추가 72)**: 실기기에서
  `adb run-as`로 명함 데이터가 평문으로 그대로 읽히는 걸 발견(문정순 님
  전화번호·이메일·주소가 그대로 노출) → 로컬(shared_preferences)과
  서버(Firestore) 양쪽 다 암호화하도록 전환. 키는 계정(uid)당 1개, 기기
  Keystore/Keychain(`flutter_secure_storage`)에 캐시 + Firestore
  `users/{uid}.encryptionKeyB64`에도 보관(기기 변경 시 복원 흐름 유지 위함).
  **한계(의도된 설계, 과장 금지)**: 키가 Firestore 안에 데이터와 함께 있어서
  완전한 제로-지식 암호화는 아님 — 기기 분실/로컬 유출/백업 파일 유출/DB
  일부 유출은 방어되지만, Firestore 프로젝트 전체 접근 권한이 있는 사람은
  이론상 키+암호문 둘 다 볼 수 있음. 진짜 키 분리(Cloud Functions/KMS)는
  Blaze 인프라(아래 "해야 할 일" 1번)가 갖춰진 뒤 가능. 레거시 평문 데이터는
  로그인 시 자동으로 감지돼 투명하게 재암호화됨(데이터 유실 없음, 기존
  "문정순" 테스트 명함으로 마이그레이션 확인 완료). 명함 원본 사진(JPG)
  암호화는 이번 범위 밖(별도 백로그 항목).
- **Android 실기기 정식 테스트 완료(추가 71)**: 갤럭시 Z 폴드(SM F966N,
  Android 16)에 debug APK 빌드·설치·실행, Flutter/Dart 크래시 없음 확인.
  (참고: 이 기기는 폴더블이라 `adb input tap`으로 화면 내 버튼 자동 클릭이
  좌표계 어긋남 때문에 잘 안 됨 — 화면별 상세 동작 확인은 실제로 폰을 쥐고
  하는 게 정확함.)
- **미해결 — 다음 세션에서 이어갈 것**: **App Store Connect 빌드 업로드
  403 권한 에러**. Xcode에 로그인된 계정은 `apps@creamhouse.net`(choi
  woojin, CreamHouse Co. 팀, Developer Portal에서는 Admin 역할 확인됨).
  앱 레코드 생성/조회는 성공하는데 실제 빌드 업로드(`CREATE BUILD` API)만
  `FORBIDDEN_ERROR.ROLE_NOT_VALID`로 거부됨 — Developer Portal 권한과
  App Store Connect 권한은 별개 시스템이라, App Store Connect 웹사이트의
  "사용자 및 접근"에서 이 이메일 계정 자체의 역할을 확인해야 함(목록에
  없으면 신규 초대 필요). 아래 "해야 할 일" 2번 참고.

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
  Gemini 기본 모델은 2026-06-01 종료된 `gemini-2.0-flash`에서 현재 공식
  안정 모델인 `gemini-3.6-flash`로 교체했다(추가 46) — 단, 실제 키로
  호출 검증은 아직 안 됐음(3.해야 할 일 6번).
- **소통 이력**: Gmail 공식 OAuth로 조회한 메일 중 사용자가 선택한 항목,
  또는 사용자가 직접 작성/붙여넣은 통화·문자·이메일·카카오톡 내용만
  기기에 저장한다. 기록별 삭제 가능. 통화기록/문자 자동 수집 권한과
  플러그인은 제거했다.

### 로그인/회원가입
- SNS 로그인으로 앱 진입을 막는 `AuthGate`를 추가했다(`SplashGate` 다음,
  `MainTabScreen` 앞). 카카오는 이번 범위에서 제외했고, Google/Apple 중
  **Google을 먼저 구현**했다 — 이미 Gmail 가져오기에서 쓰던
  `google_sign_in` 패키지·OAuth 설정을 그대로 재사용할 수 있어 추가 콘솔
  설정 없이 가장 빨리 붙일 수 있었기 때문. Apple은 버튼은 보이지만
  비활성화(`(준비 중)` 표시) — 유료 Apple Developer Program 가입 후 활성화
  예정(3.해야 할 일 참고). 네이버/페이스북은 아직 미착수(카카오처럼 별도
  개발자 콘솔 등록·검수 절차가 있어 우선순위가 낮음).
- **주의**: 아직 회원 서버(계정 DB)가 없다. 로그인은 SNS 신원 확인 후
  기기에 세션을 `flutter_secure_storage`로 암호화 저장하는 방식이라,
  앱을 지우거나 다른 기기로 옮기면 다시 로그인해야 하고 서버 쪽에 남는
  "회원" 레코드는 없다. 진짜 계정 시스템(다중 기기 동기화 등)은 서버가
  생긴 뒤로 미뤄둔 상태.
- `GoogleSignIn.instance.initialize()`는 앱 전체에서 정확히 한 번만
  호출해야 하는 제약이 있어서, 로그인(`AuthRepository`)과 Gmail 가져오기
  (`EmailSyncService`)가 공유 초기화 가드(`GoogleAuthGateway`)를 함께
  쓴다 — 새로운 Google Sign-In 관련 코드를 추가할 때도 반드시 이 가드를
  거쳐야 한다.
- **Android 실기기 전체 QA 완료(추가 47)** — 로그인 화면부터 명함 지갑·명함
  수정 모달·설정까지 실기기(갤럭시 Z 폴드)에서 확인, 전부 정상. 다만 Gmail
  OAuth 미등록으로 Google 로그인이 항상 실패해 로그인 게이트를 못 넘기는
  문제가 발견돼, `signInAsGuest()` 디버그 우회를 임시로 추가했다(3.해야 할
  일 7번 — OAuth 설정 끝나면 지울 것).

### 디자인 톤앤매너·화면 구조 재설계(추가 49)
- 사용자가 제공한 디자인 시안(퍼플 톤)에 맞춰 `app_colors.dart`의 accent
  계열을 블루→퍼플(#6C5CE7)로 교체 — `ColorScheme.primary`가 여기서
  파생되는 구조라 다른 코드 변경 없이 앱 전체에 반영됨.
- 레이더(주변)/명함 지갑/설정 화면을 시안 구조(요약카드, 사진 아바타
  대표카드, "주변 인맥 감지" 토글 등)에 맞춰 재설계. 새 UI 요소는 전부
  실제 데이터·실제 상태에 연결했다(예: 토글은 실제 위치 동의 상태와
  연동, "최근 연락"은 실제 소통기록에서 계산).
- 이 작업 중 명함 등록 화면의 "프로필 사진 선택"이 실제로는 Unsplash
  스톡 사진 4장을 순환 표시하는 가짜 구현이었던 걸 발견해서, 실제
  갤러리 사진 선택(`image_picker`)으로 교체했다. 인맥 사진 렌더링은
  `lib/presentation/common/contact_avatar.dart` 공용 위젯으로 통일.
- Android 실기기에서만 확인됨 — **iOS에서는 아직 재확인 안 됨**(3.해야
  할 일 참고).

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

## 2-0. 사용자가 결정할 일 (2026-08-04, 아래 항목 결정 완료 — 보류 해제)

~~1. 명함/인맥 정보를 서버에 저장할지~~ → **결정됨: Firebase(Firebase
Auth + Cloud Firestore, 서울 리전 asia-northeast3)에 저장하기로
확정(추가 66) → 실제로 구축·구현까지 완료됨(추가 67).**

~~2. 서버 없이 앱 업데이트를 어떻게 처리할지~~ → 1번이 "서버 있음"으로
확정되면서 이 질문 자체가 해소됨.

**⚠️ 중요 — 설계 문서와 실제 구현이 다르다**: `docs/planning/
server-setup-plan.md`(다른 세션/에이전트가 작성)는 Cloud Functions
기반 회원탈퇴 처리, 다중 계정 오염 방지 확인 다이얼로그, AI 프록시
전환까지 포함한 큰 설계다. **실제로 이 세션에서 구현·배포·실기기
검증까지 마친 것은 그보다 훨씬 가벼운 MVP**: 클라이언트가 Firestore에
직접 읽고 쓰는 백업/복원(Cloud Functions 없음, 회원탈퇴 기능 없음,
계정 오염 방지 다이얼로그 없음). 구현 상세는 "1. 한 일"과 backlog
추가 67 참고. `server-setup-plan.md`를 "지금 상태"로 착각하지 말 것 —
그 문서에 있는 나머지 기능(회원탈퇴, 마이그레이션 안전장치, 사진
저장 2단계, AI 프록시)은 전부 아직 미구현이며, "3. 해야 할 일"에
남은 항목으로 정리해 둠.

**⚠️ 2026-08-04 밤 갱신**: 아래 "2. 하고 있는 일"에 나열된 항목 중 iOS
빌드·설치·테스트, 복원 흐름 검증, 명함 백업 실제 확인, 기기 저장자료
암호화는 전부 위 "0-1"번 섹션에서 완료됨. 회원탈퇴·다중 계정 오염 방지
다이얼로그·개인정보처리방침 게시도 완료(단, Cloud Functions 기반은 아니고
클라이언트 로직 + Firestore 직접 처리 방식). 아래 내용은 "그 결정이 왜
나왔는지"의 기록으로 남겨두고, 실제 최신 상태는 "0-1"과 "3. 해야 할 일"을
볼 것.

## 2. 하고 있는 일 (진행 중 / 방금 막 끝난 것 — 2026-08-04 낮 시점 기록)

- **서버(Firebase) 구축 계획서 작성 완료, 구현은 미착수(추가 66)**:
  사용자가 명함/인맥 정보를 Firebase(Firebase Auth + Cloud Firestore +
  Cloud Storage, 서울 리전)에 저장하기로 확정 — 아키텍처, Firestore
  스키마(실제 `ContactModel`/`MyProfileModel` 필드 기준), 보안 규칙,
  인증 연동, 앱 코드 변경 범위, 마이그레이션 절차(다중 계정 데이터
  오염 방지 확인 다이얼로그 포함), 회원탈퇴 흐름, 개인정보 처리 관점,
  단계별 구축 절차, 비용 추정까지 전 과정을 담은 문서를
  `docs/planning/server-setup-plan.md`로 작성. **명함 사진 원본과 좌표
  (lat/lng)는 서버에 올리지 않는 쪽으로 설계**(OCR 텍스트 필드만
  Firestore에 저장) — 특히 좌표는 backlog 추가 40의 "서버로 전송하면
  위치정보사업자 신고 재검토 필요" 경고를 근거로 보류. 실제 구현은
  다음 단계로, "3. 해야 할 일" 2번 참고.
- **서버 구축 계획서 개정(추가 67, 2026-08-04)**: QA 진행 중 사용자가
  전달한 지시 2건을 반영해 `server-setup-plan.md`를 개정 —
  ① **AI 연동을 BYOK에서 서버 프록시 방식으로 전환하기로 확정하고
  이번 서버 구축 범위 안에 포함**(14번 섹션 신설. Cloud Functions AI
  프록시, 사용자당 호출량 제한 일 10회/월 100회 제안, Google Gemini
  무료 등급이 데이터를 모델 개선에 활용하는 정책임을 확인해 서버는
  반드시 유료 등급으로 키를 발급하도록 경고, 기존 BYOK UI 처리 방침
  2안, `ai_data_review_sheet.dart` 동의 문구 개정안까지 설계). ②
  **명함 사진 서버 저장을 1단계(텍스트만, 기존 유지)와 분리된 확정
  2단계 계획으로 승격**(15번 섹션 신설. Cloud Storage 경로·보안 규칙·
  압축 정책·비용 추정·개인정보처리방침 변경 항목·기존 사용자 사진
  소급 업로드는 옵트인 권장까지 설계). `release-roadmap.md`도 함께
  갱신(P1-7 신설, Phase 3에 AI 프록시 구현 단계 추가, 8-6절 보류 항목
  전부 "해소됨"으로 갱신).
- **명함/프로필 서버 백업·복원 — 실제 구현·배포·실기기 검증 완료(추가
  67, 2026-08-04)**: 위 계획서(`server-setup-plan.md`)의 축소 MVP
  버전을 실제로 만들고 확인까지 끝냈다.
  - Firebase 콘솔 작업(사용자와 함께 단계별로): 프로젝트 `connection-sense`
    생성(`creamhouseapp@gmail.com` 공식 계정), Firestore 서울 리전
    생성, Google 로그인 활성화. **Storage(사진)는 Blaze 유료 요금제가
    필요하다는 걸 발견해 이번 범위에서 제외**(카드 등록은 사용자가
    나중에 하기로 함 — 15번 섹션 "사진 2단계"는 아직 시작 전).
  - 코드: `pubspec.yaml`에 `firebase_core`/`firebase_auth`/
    `cloud_firestore` 추가, `lib/data/services/data_backup_service.dart`
    (신규, Firestore 백업/복원 헬퍼), `AuthRepository`가 Google 로그인과
    동시에 Firebase Auth에도 로그인해 `firebaseUid` 확보,
    `ContactsRepository`/`MyProfileRepository`가 저장 시 서버 백업 +
    로그인 직후 로컬이 비어있으면 서버에서 복원, `AuthGate`가 두
    리포지토리에 uid를 배선.
  - **Cloud Functions·회원탈퇴·다중 계정 오염 방지 다이얼로그는 이번에
    구현 안 함** — `server-setup-plan.md`가 설계한 범위보다 작은 MVP다
    (아래 "3. 해야 할 일"에 남은 항목으로 정리).
  - 실기기(Android, 갤럭시 Z 폴드) 검증: Google 로그인 → Firebase Auth
    계정 생성 확인(Identity Toolkit API로 직접 조회) → 프로필 저장 →
    **Firestore에 실제 데이터 반영을 REST API로 직접 확인**(이름/회사/
    직함/이메일/주소 전부 정상). 명함(contacts) 저장도 같은 코드
    경로라 구조적으로는 검증됐지만 실제 명함 등록으로는 아직 미확인.
  - **발견한 이슈**: 실기기 SHA-1 인증서를 Firebase에 등록하려는데
    "이미 다른 프로젝트에 등록됨" 충돌 발생 — 예전 `globe2030@gmail.com`
    계정(이제 안 씀) 쪽에 남은 등록으로 추정, 접근 불가해 **디버그
    키스토어를 새로 생성**해 우회(기존 키스토어는 백업해 둠, 위치는
    backlog 추가 67 참고). 이 때문에 기존 설치본과 서명이 달라져
    재설치가 필요했음 — 이후 다른 세션/기기에서 같은 문제가 재발하면
    같은 방법(새 디버그 키스토어 생성 → SHA-1 재등록) 반복.
  - `analysis_options.yaml`에 `build/**` 분석 제외 규칙 추가(Firebase
    패키지 추가 후 발견 — `flutter pub get`이 복사해두는 플러그인
    테스트 소스가 analyzer에 잘못 포함돼 가짜 에러 수백 건이 나던 문제).
- **기기 저장자료 암호화(설계 논의만 완료, 구현 미착수)**: 현재 확인된 구조는
  AI API 키만 `flutter_secure_storage`, 명함·프로필·소통기록·위치 동의 기록은
  `shared_preferences`(평문)이므로 "전체 기기 자료 암호화 완료"로 간주하면
  안 된다. 별개로 "서버에 명함 원본 사진을 올리면 암호화되나"라는 질문에
  답한 결론(추가 62 참고)도 함께 반영: Firebase Storage는 저장 시
  자동으로 AES-256 암호화되고 전송도 TLS라 **서버 쪽 암호화는 기본 제공**이며,
  진짜 위험은 접근 제어(Security Rules로 본인 파일만 본인이 읽게 강제)다.
  기기 로컬 평문 저장(`shared_preferences`) 감사·이전은 여전히 미착수.
- **앱 아이콘 A(라벤더 글라스) 실제 적용 + Android 실기기 검증 완료(추가
  63~64)**: 샘플 5종 중 사용자가 A를 최종 선택.
  `assets/icons3d/radar_lavender_full_bleed.png`(풀블리드 정사각형, OS
  마스킹용)를 `flutter_launcher_icons` 소스로 지정해 재생성 — Android
  `mipmap-*/ic_launcher.png`, iOS `AppIcon.appiconset` 모두 새 아이콘으로
  교체됨. **Android 실기기(갤럭시 Z 폴드)에서 스크린샷으로 직접 확인**:
  홈 화면 앱 아이콘이 라벤더로 정상 표시되고, 앱 열기 애니메이션도 새
  아이콘으로 나옴. iOS도 같은 코드로 재빌드·재설치 완료했으나 기기
  연결이 끊겨 자동 실행 확인은 못함 — **사용자가 직접 열어서 최종 확인
  권장**(코드는 Android와 100% 동일하므로 문제 없을 것으로 예상).
- **스플래시(로딩 화면) 이미지 교체 + 타이밍 수정 완료(추가 63~64)**: 기존엔
  앱 아이콘이 아니라 퍼블리셔 CI 로고(`assets/CI.png`, "CREAMHOUSE"
  워드마크)가 로딩 화면에 떠 있었다는 걸 발견 — 라벤더 아이콘(둥근 모서리·
  투명 배경 버전, `assets/icons3d/radar_lavender_splash.png`)으로 교체.
  처음엔 `Curves.easeOut`을 애니메이션 시작부터 적용해서 2초를 다 채우기
  전에 첫 화면이 비쳐 보이는 문제가 있었음(사용자 제보) — `Interval(0.85,
  1.0, curve: Curves.easeOut)`로 바꿔서 2초 중 1.7초는 완전히 불투명하게
  떠 있다가 마지막 0.3초에만 빠르게 페이드아웃하도록 수정. Android
  실기기에서 0초/1초/2.3초 스크린샷으로 의도한 타이밍 확인 완료. `CI.png`
  파일 자체는 삭제하지 않고 보존.
- **관리 콘솔(데이터 관리·통계) 화면설계서 — 목업 완료, 서버/실제 화면 구현은
  미착수(추가 61)**: "서버 구축을 전제로" 한 관리자 대시보드 6개 화면
  (대시보드/이벤트 퍼널/사용자/명함 데이터/스토리지/컴포넌트 시트)을 HTML
  목업으로 제작(`docs/planning/design/admin_console_mockup.html`, 아티팩트
  https://claude.ai/code/artifact/60d32895-ade3-4f2d-892f-4c34d81a9dc8).
  "6. 화면별 통계 지표 제안"의 3개 퍼널을 그대로 시각화했고, 컴포넌트 시트에
  컬러 토큰·타입 스케일·버튼/배지 변형을 Figma로 옮길 수 있게 정리해 둠.
  **서버(해야 할 일 2번)가 실제로 생기기 전까지는 화면만 있고 데이터 연동은
  없음** — 표시된 수치는 전부 예시.

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

## 3. 해야 할 일 (2026-08-04 밤 기준, 우선순위 순)

### 🔴 막힌 지점 (사용자 본인 계정 작업 필요)

1. **Firebase Blaze 요금제 카드 등록** — Cloud Functions(AI 서버 프록시)·
   Storage(사진 백업) 둘 다 이게 선행 조건. creamhouseapp@gmail.com 계정,
   connection-sense 프로젝트에서 진행.
2. **App Store Connect 빌드 업로드 403 권한 에러 해결** — 위 "0-1"번 섹션
   마지막 항목 참고. `apps@creamhouse.net`(choi woojin) 계정을 App Store
   Connect "사용자 및 접근"에서 찾아 역할 확인(Developer Portal 역할과는
   별개 시스템). 이게 풀려야 TestFlight 배포 가능.

### 🟠 1번(Blaze) 대기 중

3. **회사 명의 Gemini 유료 API 키 발급** → **Secret Manager 등록 + Cloud
   Functions 배포**(`functions/src/index.ts` 이미 작성·컴파일 확인됨,
   배포만 남음) → **AI 연동 화면(`ai_connection_modal_view.dart`) 서버
   프록시 방식으로 개편**(지금은 "API 키는 이 기기에만 저장, 서버 전송
   안 함"이라는 BYOK 전용 문구 그대로라 서버 프록시 결정과 안 맞음).
4. **명함 원본 사진 서버 백업(2단계)** — Storage 활성화 후 진행.

### 🟠 2번(App Store Connect) 대기 중

5. **App Store Connect / Google Play Console 구독 상품(SKU) 등록**
6. **인앱결제(IAP) 클라이언트 연동** (`in_app_purchase` 패키지)
7. **구독 결제 동의/고지 UI** — 2026년 개정 전자상거래법 대응(무료→유료 전환·
   요금 인상 시 결제 30일 전 동의 필수, 다크패턴 규제). 손익분석 문서
   (`docs/planning/business/pnl-analysis-freemium.html`) 11번 섹션에서
   비교한 시나리오 중 "C안(₩1,000/월, 무료 등급 없이 유료 전용)"이 구조적으로
   가장 안전하다는 결론이었음 — 최종 가격 확정 후 5·6번과 함께 진행.
8. **서버측 구독 영수증 검증 + Firestore 구독상태 동기화** — App Store
   Server Notifications V2 / Google Play RTDN 수신용 Cloud Function.
9. **AI 호출 한도를 구독 등급별로 차등 적용** — 지금 `functions/src/index.ts`의
   `DAILY_LIMIT`/`MONTHLY_LIMIT`은 고정값, 구독 상태 반영 안 됨.

### 🟢 지금 바로 가능 (계정/인프라 무관)

10. **명함 원본 사진 로컬 암호화** — 이번 세션에서 명함/프로필 JSON은
    AES-256-GCM 암호화했지만(위 "0-1" 참고), `cache/CAP*.jpg` 같은 원본
    사진 파일은 아직 평문. 별도 암호화 필요(백로그에 항목만 추가된 상태,
    구현은 아직).
11. **완전한 키 분리(제로-지식화)** — 지금 암호화 키는 Firestore
    `users/{uid}.encryptionKeyB64`에 데이터와 함께 있음. Cloud
    Functions/KMS로 키를 완전히 분리하면 한 단계 더 강화됨(1번 Blaze
    완료 후가 자연스러운 타이밍).
12. **알림 센터 실제 파이프라인 여부 결정** — 지금은 빈 상태만 있고, 실제
    근접감지/신규등록 이벤트를 알림으로 쌓는 기능은 미구현. 필요하면 새로
    설계해야 함(중간 규모 작업).
13. **네이버/카카오 SNS 로그인 추가 검토** — 사용자가 "google만 먼저
    진행"으로 명시적으로 보류한 상태. 필요해지면 재검토.

### ⚪ 보류 (사용자가 이미 결정)
- **다국어(i18n) 번역** — 프로젝트 마지막 단계에 진행하기로 확정.

### ✅ 최근 완료(2026-08-04 밤, 위 "0-1" 참고 — 여기 다시 안 적음)
iOS 빌드 문제 전체, iOS/Android 실기기 로그인·백업·복원 검증, 계정 삭제
기능, 다중 계정 안전장치, 개인정보처리방침 게시, 명함/프로필 암호화,
Android 실기기 QA, Apple Developer Program 가입.

## 4. 파일 가이드 — 다음 개발자가 먼저 봐야 할 파일

### 문서
- **`docs/planning/backlog.md`** — 가장 중요. "추가 N" 형식으로 시간순 작업
  로그가 다 있고, 각 항목마다 사용자 피드백 원문 + 원인 분석 + 수정 내용이
  적혀 있어서 "왜 이렇게 짰는지"를 알 수 있다.
- **이 파일(`HANDOFF.md`)** — 현재 상태 요약.
- **`docs/planning/server-setup-plan.md`** — 명함/인맥 데이터를
  Firebase(Firebase Auth + Cloud Firestore + Cloud Storage)에 저장하는
  전 과정 설계 문서(추가 66, 추가 67에서 개정). 아키텍처·Firestore
  스키마·보안 규칙·마이그레이션·회원탈퇴·개인정보 처리·단계별 구축
  절차·비용 추정에 더해 **AI 연동 BYOK→서버 프록시 전환(14번 섹션)**과
  **명함/아바타/프로필 사진 서버 저장 2단계 계획(15번 섹션)**까지
  포함. **서버 구축("3. 해야 할 일" 2번)에 착수할 때 가장 먼저 읽을
  문서.**
- **`docs/planning/design/`** — 코드 구현 전 단계의 디자인 목업(정적 HTML,
  서버·API 연동 없음). `admin_console_mockup.html`(관리 콘솔 데이터
  관리·통계 화면설계서, Figma 이전용 컴포넌트 시트 포함),
  `app_icon_samples.html`(앱 아이콘 밝은 계통 샘플 5종). 브라우저로 그냥
  열면 됨.

### 앱 구조 진입점
- `lib/main.dart` — Provider 등록(Repository들을 여기서 앱 전역에 주입), 앱 루트.
- `lib/presentation/navigation/main_tab_screen.dart` — 하단 탭 3개(레이더/명함
  지갑/설정) 구조.

### 데이터 모델 (여기부터 보면 전체 데이터 구조 파악 빠름)
- `lib/data/models/contact_model.dart` — 인맥(등록된 명함) 모델.
- `lib/data/models/my_profile_model.dart` — 내 프로필(내 디지털 명함) 모델.
- `lib/data/models/ai_provider.dart` — AI 제공사(Claude/OpenAI/Gemini) enum +
  콘솔 URL/발급 안내.
- `lib/data/models/sns_auth_provider.dart` — SNS 로그인 제공사(Google/Apple)
  enum. `isAvailable`이 `false`인 동안은 로그인 화면에서 버튼이 비활성화됨.

### 리포지토리 (영속성 계층)
- `lib/data/repositories/contacts_repository.dart`
- `lib/data/repositories/my_profile_repository.dart`
- `lib/data/repositories/ai_credentials_repository.dart` — AI API 키를
  `flutter_secure_storage`에 저장(민감정보 vs 일반 설정을 분리해서 관리).
- `lib/data/repositories/auth_repository.dart` — SNS 로그인 세션(제공사/이름/
  이메일/사진)을 `flutter_secure_storage`에 저장. 서버 계정 시스템이 생기면
  세션을 서버 발급 토큰으로 교체할 지점.

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
- `lib/core/services/google_auth_gateway.dart` — `GoogleSignIn.instance.
  initialize()`를 앱 전체에서 한 번만 호출하도록 감싸는 공유 게이트웨이.
  `AuthRepository`와 `EmailSyncService`가 같이 쓴다 — Google Sign-In을
  직접 다시 초기화하는 코드를 새로 추가하지 말 것(undefined behavior).

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
- `lib/presentation/features/radar/views/radar_view.dart` — 첫 화면(레이더),
  퍼플 톤 디자인 시안 구조로 재설계됨(추가 49).
- `lib/presentation/common/contact_avatar.dart` — 인맥 사진 아바타 공용
  위젯(사진 있으면 표시, 없으면 이니셜). 새 아바타 표시 코드는 반드시
  이걸 재사용할 것 — 예전 Unsplash 스톡사진 프리셋 같은 가짜 사진을
  다시 넣지 말 것.
- `lib/presentation/features/auth/views/login_view.dart`,
  `lib/presentation/common/auth_gate.dart` — SNS 로그인 화면과 앱 진입
  게이트(`SplashGate` → `AuthGate` → `MainTabScreen` 순서로 `main.dart`에
  연결돼 있음).

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
- **iOS 실기기에서 debug 빌드를 홈 화면에서 단독 실행하면 즉시 죽는다
  (signal 11)**: debug 모드 앱은 Flutter 툴이 계속 붙어 있어야 엔진이 뜨는
  구조라, `flutter build ios --debug` + `xcrun devicectl device process
  launch`처럼 따로 설치·실행하면 크래시한다. 그렇다고 `flutter run -d
  <device>`를 쓰면 이 환경에서는 Xcode 자동화 제어 권한(macOS 설정 →
  개인정보 보호 및 보안 → 자동화) 이슈로 "Xcode가 디버깅 시작에 예상보다
  오래 걸림"에서 무선·USB 상관없이 무한 대기한다(추가 48). **실기기에서
  그냥 눌러보는 용도라면 `flutter build ios --release` (또는 `--profile`) +
  `xcrun devicectl device install app` + `xcrun devicectl device process
  launch`로 우회할 것** — release/profile 앱은 툴 연결 없이 홈 화면에서
  독립 실행되므로 이 문제 자체를 피해간다. `flutter run`으로 핫리로드까지
  쓰며 디버깅하려면 위 macOS 자동화 권한을 직접 켜야 한다(터미널에서는
  대신 눌러줄 수 없는 시스템 팝업).
- **iOS release 빌드가 "Module Verifier" 관련 CocoaPods 에러로 실패하면**
  (`could not build module 'google_mlkit_commons'`/`'Test'` 등) `cd ios &&
  pod install`을 다시 실행해 볼 것 — `ios/Podfile`의 `post_install`에 이미
  `CLANG_ENABLE_MODULE_VERIFIER`/`ENABLE_MODULE_VERIFIER`를 끄는 우회가
  있지만, Pods 프로젝트가 그 설정 적용 전 상태로 캐시돼 있으면 재발한다.

## 6. 화면별 통계 지표 제안 (수집 로직은 아직 미구현 — 서버가 생긴 뒤 착수)

사용자 요청으로 "무엇을 측정하면 유익할지"만 먼저 정리해 둔 목록. 실제
이벤트 전송 코드나 집계 서버는 **아직 없다** — 3.해야 할 일 2번(서버 구축)에서
구현할 때 이 목록을 이벤트 설계의 출발점으로 쓰면 된다. 서버 자체 집계
대신 Firebase Analytics/Amplitude 같은 SaaS를 붙이면 서버 없이도 클라이언트
SDK만으로 상당수는 먼저 수집할 수 있다는 점도 참고(사용자는 "서버 구축은
해야 할 일로 남겨 달라"고 했으므로, 여기서는 지표 설계만 하고 SDK/서버
연동은 하지 않았다).

### 화면별 지표

- **로그인/회원가입 화면**(`login_view.dart`, 신규): 로그인 시도 수, 제공사별
  선택 비율(Google vs Apple), 로그인 성공/실패율과 실패 사유, 앱 설치 →
  최초 로그인 완료까지 걸린 시간(온보딩 이탈 지점 파악).
- **레이더(첫 화면)**: DAU/WAU, 화면 진입당 평균 체류시간, 근접 알림 노출
  횟수와 알림→앱 재진입 전환율(리텐션의 핵심 지표), 위치 동의 화면 도달률·
  동의율·거부율(퍼널).
- **명함 지갑(목록)**: 사용자당 등록 명함 수 분포, 검색/필터 사용률, 목록→
  상세 진입율.
- **명함 등록/스캔**(`camera_scan_modal_view.dart`, `add_card_modal_view.dart`):
  촬영 시도 대비 성공률, 자동 촬영 vs 수동 촬영 비율, OCR 필드별 자동 인식
  성공률(사용자가 직접 수정한 필드가 무엇인지 — 파싱 로직 개선의 근거),
  도로명주소 변환 제안 수락률, "뒷면 스캔" 안내 노출 후 실제 재촬영 비율,
  등록 시작→저장 완료까지 소요 시간(퍼널 이탈 지점).
- **내 프로필**: 프로필 항목별(이름/연락처/주소/사진) 채움 비율, QR 공유
  횟수.
- **AI 브리핑**(`briefing_overlay_view.dart`, 설정 → AI 연동): 제공사별
  연동률(Claude/OpenAI/Gemini), 브리핑 요청 수와 성공/실패율, 실패 시
  오류 유형 분포(응답 파싱 실패 등 — 7번 항목의 실사용 검증과 직결),
  데이터 전송 동의 화면(`ai_data_review_sheet.dart`)에서의 동의율.
- **소통기록 입력**(`communication_source_sheet.dart` 등): 채널별(통화/문자/
  이메일/카카오톡) 입력 비중, Gmail 선택 가져오기 사용률.
- **설정**: 위치 감지 반경 변경 분포, 위치 동의율/철회율, 위치정보 이용
  안내 열람율, 로그아웃 빈도.
- **공통/전체**: 크래시율, 화면별 로딩 실패율, 세션당 평균 체류시간,
  리텐션(D1/D7/D30), 설치 후 첫 명함 등록 완료까지 걸린 시간(핵심 활성화
  지표 — 위 "명함 등록/스캔" 퍼널과 함께 봐야 함).

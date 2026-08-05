# 개발 인수인계 문서 (2026-08-05 기준 — 최신 상황은 "0-2" 섹션, 우선순위는 "3. 해야 할 일" 참고)

다음 개발자(또는 다음 대화창)가 이 프로젝트를 빠르게 이어받을 수 있도록 정리한
문서. 시간순 상세 기록은 [`backlog.md`](./backlog.md)(추가 1~74)에 다 있으니,
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
  주소 기준)에 갔을 때 알림을 주고, AI가 대화 포인트를 생성해 준다. **주의**:
  "알림을 준다"는 이 컨셉 문구와 실제 구현(앱을 열어야 보이는 인앱 레이더
  목록, 백그라운드 푸시 없음) 사이에 괴리가 있다 — "2-0" 아래 사용자 결정
  질문 3번 참고.

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

## 0-1. 2026-08-04 밤 — iOS 배포 트러블슈팅 + 계정/데이터 안전장치 + 암호화

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
  명시적 선택 요구(강제 선택, 바깥 탭으로 안 닫힘). **주의(2026-08-04 재감사에서
  확인)**: 이건 uid별 저장소 키 격리(원래 `server-setup-plan.md` 설계)가 아니라
  다이얼로그 확인 절차로 완화하는 방식이다 — `contacts_repository.dart`의
  로컬 저장 키(`saved_contacts_v2`)는 여전히 전역 키. 기능은 동작하지만 원
  설계보다 가벼운 안전장치이므로 "3. 해야 할 일"에 QA 스트레스 테스트 항목으로
  남겨둠.
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
  Blaze 인프라(아래 "해야 할 일" 참고)가 갖춰진 뒤 가능. 레거시 평문 데이터는
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
  없으면 신규 초대 필요). 아래 "해야 할 일" P0-1 참고.

## 0-2. 2026-08-05 — 법적 고지 문서 체계 정비 + 플랫폼별 현황 재조사 (가장 최신)

상세 경위는 [`backlog.md`](./backlog.md) 추가 75에 있음. 이번 세션은 **문서
작업만** 했고 앱 코드는 건드리지 않았다.

### 문서 작업 — `docs/legal/`이 1개 → 6개로

리멤버(주식회사 리멤버앤컴퍼니)의 공개 문서 체계를 벤치마크로 조사한 뒤,
우리 앱에 필요한 문서를 확정해 작성했다.

- **`privacy-policy.html` v1.0 → v2.0 전부개정** (14항목 → 19항목).
  가장 중요한 건 **BYOK 서술 제거**다 — 커밋 `ed6b4b7`에서 BYOK가 삭제되고
  서버 프록시로 전환됐는데 방침은 여전히 "이용자가 직접 발급한 API 키는
  회사 서버를 거치지 않습니다", "향후 서버 경유로 전환할 계획"이라고 적혀
  있었다. **개인정보 전송 경로를 사실과 다르게 고지한 상태**였고, Apple
  심사 5.1.1 / Play 사용자 데이터 정책 위반 소지였다. 그 밖에 국외 이전·
  자동수집장치·행태정보·개인위치정보·가명정보·권익침해 구제 6개 항목을
  신설하고, 위탁 표를 Firebase 1행 → 4행(Gemini / OS 지오코딩 / 카카오
  우편번호 추가)으로 확대했다.
- **`terms-of-service.html` 신규**(19개조). 결제가 없어도 필요한 이유는
  결제가 아니라 **이용자가 제3자 명함 정보를 입력하는 구조**(제8조)다.
- **`app-permissions.html` 신규**. 정보통신망법 §22-2. 위치·카메라·사진
  3종을 전부 "선택" 권한으로 고지.
- **`account-deletion.html` 신규 — 조사 중 발견한 누락 블로커.** Google
  Play는 앱 내 삭제 기능과 **별개로 계정 삭제 안내 웹 URL**을 요구하는데
  지금껏 어느 문서에도 없었다. 없으면 Play "앱 콘텐츠" 제출이 막힌다.
- **`index.html`, `legal.css` 신규**. 인덱스 + 사업자 정보 푸터, 공통 스타일.
- **`firebase.json`에 `hosting` 섹션 추가**. `public: "docs/legal"`로 지정한
  이유는 `public: "docs"`로 하면 `docs/planning/**` 기획 문서가 전부 웹에
  노출되기 때문. Hosting은 **Spark(무료) 요금제로 가능**해서 Blaze(P1-7)
  대기 없이 배포할 수 있다.

**⚠️ 게시 순서 제약**: 방침은 아래 C안 기준으로 "좌표를 서버에 보관하지
않는다"고 쓰여 있다. **코드는 2026-08-05에 반영 완료**(추가 76)됐지만
**실기기에서 마이그레이션이 실제로 도는지는 확인되지 않았다** — 게시 전에
Firestore 문서를 직접 열어 좌표가 남아 있지 않은지 확인할 것(각 HTML 상단에
화면 미표시 주석으로 박아 둠). 같은 이유로
"AI 모델 학습에 사용되지 않습니다"류 문장은 넣지 않았다 — Gemini 무료 등급은
입력을 서비스 개선에 활용하므로 유료 등급 결제(P1-7) 전에는 못 쓴다.

### 사용자 결정 4건

1. **좌표 C안 확정** — 명함 주소를 변환한 좌표를 서버 백업에서 제외한다.
2. **Firebase Hosting**에 배포.
3. **보호책임자 = 최우진(대표이사) + `connectsense@creamhouse.net`**.
4. **위치기반서비스 이용약관은 만들지 않는다** — 방침의 "개인위치정보의
   처리" 항목으로 커버.

### 좌표 C안 — 구현 완료 (추가 76, 2026-08-05)

**핵심 착안점: 좌표는 독립적인 데이터가 아니라 주소에서 파생되는 값이다.**
따라서 백업 대상이 아니라 **필요할 때 다시 계산하면 되는 값**이다. 재계산
경로는 명함을 처음 등록할 때 쓰는 것과 동일하다
(`AddressGeocodingService.validateAndConvert`).

기기 변경·계정 재연결 시 흐름: 서버에서 복원 → 주소는 있고 좌표만 빈 상태 →
`GeoBackfillService`가 주소를 지오코딩해 채움 → **기기에만** 저장(암호화된
`saved_contacts_v2`). 기기당 1회.

- `ContactModel.toJson()`(기기용, 좌표 포함) / **`toBackupJson()`(서버용,
  좌표 제외)** 분리. 서버 백업에는 반드시 후자를 쓸 것.
- 이미 서버에 올라간 문서는 좌표가 **암호문 안에** 있어 필드만 지울 수 없다 →
  로그인 시 `rebackupAllContacts()`로 통째로 덮어써 걷어낸다(계정당 1회,
  플래그 `geo_stripped_from_backup_v1_<uid>`).
- `GeoBackfillService`가 막는 실패 모드: 지오코더 몰아치기(순차+400ms), 대량
  처리(1회 30건 상한), 오프라인에서 타임아웃 낭비(연속 3건 실패 시 중단),
  못 찾는 주소 무한 재시도(3회 후 포기, **주소가 바뀌면 초기화**), 시도 기록에
  주소 평문 저장(SHA-256 해시 12자만).
- 복원 직후 화면이 "주변에 인맥 없음"으로 보이지 않도록 레이더에 진행 안내
  카드를 추가했다.

**검증**: 단위 테스트(`test/geo_backfill_test.dart` 10건,
`test/fresh_install_test.dart` 6건), `flutter analyze` 새 이슈 0건,
`flutter test` 37건 통과. **양쪽 실기기 검증 완료** —
- **iPhone 16 Pro**(추가 77·78): 마이그레이션, 복원, 기기 변경 시나리오(키를
  Firestore에서 내려받기)까지 화면으로 확인.
- **갤럭시 Z 폴드**(추가 79): `adb run-as`로 기기 저장소를 열어 암호문을
  복호화, **같은 명함이 기기에는 좌표가 있고 서버에는 없다**는 것을 양쪽
  저장소에서 직접 확인. 이 과정에서 **재시도가 사실상 죽어 있던 결함**을
  발견·수정했다(복원 경로에서만 호출 → 로그인할 때마다 이어서 처리).

**서버 문서를 자동으로 검증하는 법**(재사용): Firebase CLI가 로그인돼 있으면
`~/.config/configstore/firebase-tools.json`의 refresh token을 액세스 토큰으로
교환해 Firestore REST를 관리자 권한으로 읽을 수 있다. 문서는
`users/{uid}.encryptionKeyB64`로 AES-256-GCM 복호화한다(base64(nonce 12B +
암호문 + MAC 16B)). 개인정보 값은 출력하지 말고 `lat`/`lng` 키 존재 여부만
볼 것. 상세는 추가 77.

**⚠️ 이번 검증에서 드러난 것 3가지**(전부 P1로 등록):
- 서버에 **명함 개인정보가 평문으로 남아 있었다**(5건 중 3건). 추가 72의
  암호화는 "다음에 저장될 때" 재암호화되는 구조라 한 번도 다시 저장되지 않은
  서버 문서는 계속 평문이었다. 이번 마이그레이션으로 로그인한 계정은 해소.
- **iOS Keychain은 앱을 삭제해도 안 지워진다** → 재설치 후 로그인 세션과
  암호화 키가 남았다. **2026-08-05 해결 완료**(추가 78, `FreshInstallService`).
  이 수정으로 재설치가 곧 새 기기와 같은 조건이 되어, 그동안 미검증이던
  **기기 변경 시 Firestore에서 암호화 키를 내려받는 경로까지 실기기에서
  검증됐다**(앱 삭제 → 재설치 → 로그인 화면 → 재인증 → 명함 복원 + 거리 표시).
- **Apple 로그인은 별도 uid를 만든다**(P1-24).

### 좌표 문제 — 추가 40의 경고를 정정

이 앱에는 성격이 다른 두 좌표가 있는데 그동안 섞여 기록돼 있었다.
**(a) 이용자 실시간 GPS** — 기기 메모리에서 거리 계산만, 저장·전송 없음.
**(b) `ContactModel.geo`** — 명함에 적힌 주소를 지오코딩한 값으로,
`contact_model.dart:112-113`의 `toJson()`에 포함돼 Firestore에 저장 중.
위치정보법 §2 1호는 "특정한 시간에 존재하거나 존재하였던 장소"를 위치정보로
정의하므로 (b)는 시점 요건을 충족하지 않아 해당하지 않을 가능성이 크다.
따라서 **C안의 가치는 "법적 의무 제거"가 아니라 설계 결정과 코드를 일치시켜
"회사는 어떤 좌표도 보유하지 않는다"를 코드로 입증 가능하게 만드는 것**이다.
(최종 판단은 법무 검토 필요.)

### 플랫폼별 개발 현황 — iOS/Android 비교

**⚠️ 먼저 알아야 할 것: Apple 로그인 구현이 전부 커밋되지 않은 작업 트리
상태다.** `sns_auth_provider.dart`, `auth_repository.dart`(124-208행에
`signInWithApple`, 287-332행에 Apple 재인증 + `reauthenticateCurrentProvider`),
`login_view.dart`, `pubspec.yaml`(`sign_in_with_apple: ^8.1.0`),
`project.pbxproj`, 신규 `ios/Runner/Runner.entitlements`. 아래 P0-2와 추가
73의 "`isAvailable`이 여전히 false" 기록은 **이미 낡았다**.

플랫폼별로 다른 것만:

| 항목 | iOS | Android |
|---|---|---|
| Apple 로그인 | ✅ 코드 구현 + entitlements 3개 config 연결 | ⛔ 의도적 미지원(버튼 미렌더) |
| 릴리스 서명 | ✅ 정식 팀 서명(`77L7BH2M2W`) | ❌ **debug 키 사용 중**(`build.gradle.kts:38-40`) |
| 전화 걸기 | ✅ 제약 없음 | ⚠️ `<queries>`에 DIAL 인텐트 누락 → Android 11+ 실패 가능 |
| adaptive icon | ✅ 22개 사이즈셋 | ❌ 레거시 PNG만 |
| 수출규정 키 | ❌ `ITSAppUsesNonExemptEncryption` 누락 | 해당 없음 |
| 스토어 업로드 | ⛔ App Store Connect 403 | ⛔ debug 키라 Play 업로드 불가 |

실기기 검증 격차(여기가 본질):

| 항목 | iOS | Android |
|---|---|---|
| Google 로그인 → 백업/복원 | ✅ | ✅ (`adb`로 저장 내용까지) |
| **Apple 로그인** | ❌ **빌드조차 안 됨** — `Podfile.lock`에 `sign_in_with_apple` pod 없음, `pod install` 미실행 | ✅ 빌드 성공 |
| 명함 등록 전체 플로우 | ❌ 로그인 화면까지만 | ✅ 전 플로우 QA |
| 퍼플 리브랜딩 UI | ❌ 미확인 | ✅ |
| 아이콘/스플래시 | ⚠️ 재빌드만, 육안 미확인 | ✅ 스크린샷 확인 |
| 암호화 실측 | ❌ 근거 없음 | ✅ `adb run-as` |
| Gmail OAuth | ✅ | ❌ 근거 없음 |

**한 줄 요약**: Android는 기능 검증이 앞서고 배포 준비(서명)가 뒤처짐.
iOS는 배포 준비가 앞서고 기능 검증이 크게 뒤처짐 — 특히 **iOS는 Apple
로그인 코드가 들어간 뒤 한 번도 빌드된 적이 없다.**

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
  **주의**: 지금은 앱을 열어야 갱신되는 인앱 목록만 있고, 앱이 닫혀 있을 때
  울리는 백그라운드 푸시 알림 파이프라인은 없다.
- **30초 AI 대화 브리핑**: 사용자가 Claude/ChatGPT/Gemini 중 자신의 API 키로
  연동하면(설정 화면), 상대방 정보 + 사용자가 이번 요청에 선택한 소통
  기록으로 대화 포인트 3개를 생성한다. 요청마다 전송 정보 확인과 명시적
  동의를 거친다. 미연동 시 연동 안내가 뜬다(가짜 데이터로 채우지 않음).
  Gemini 기본 모델은 2026-06-01 종료된 `gemini-2.0-flash`에서 현재 공식
  안정 모델인 `gemini-3.6-flash`로 교체했다(추가 46) — 단, 실제 키로
  호출 검증은 아직 안 됐음(3.해야 할 일 P0 참고).
- **소통 이력**: Gmail 공식 OAuth로 조회한 메일 중 사용자가 선택한 항목,
  또는 사용자가 직접 작성/붙여넣은 통화·문자·이메일·카카오톡 내용만
  기기에 저장한다. 기록별 삭제 가능. 통화기록/문자 자동 수집 권한과
  플러그인은 제거했다. **주의**: Gmail 가져오기는 `gmail.readonly`라는
  Google의 "제한된 범위(restricted scope)"를 쓰는데, 이 스코프는 별도
  보안 심사(CASA) 없이는 실제로 동작하지 않는다 — 아직 그 심사/등록이
  끝났다는 기록이 없다(3.해야 할 일 P1 참고).

### 로그인/회원가입
- SNS 로그인으로 앱 진입을 막는 `AuthGate`를 추가했다(`SplashGate` 다음,
  `MainTabScreen` 앞). 카카오는 이번 범위에서 제외했고, Google/Apple 중
  **Google을 먼저 구현**했다 — 이미 Gmail 가져오기에서 쓰던
  `google_sign_in` 패키지·OAuth 설정을 그대로 재사용할 수 있어 추가 콘솔
  설정 없이 가장 빨리 붙일 수 있었기 때문. Apple은 버튼은 보이지만
  비활성화(`(준비 중)` 표시) — Apple Developer Program 유료 가입은 이미
  완료됐으나 실제 Sign in with Apple 구현은 아직 안 됨. **2026-08-04 재감사에서
  격상**: 이 상태로 App Store 심사에 내면 "제3자 로그인을 제공하면서 Apple
  로그인은 없음"이라는 이유로 가이드라인 4.8 위반 반려 가능성이 있어
  App Store Connect 403 문제와 나란한 P0로 재분류(3.해야 할 일 참고).
  네이버/페이스북은 아직 미착수(카카오처럼 별도 개발자 콘솔 등록·검수
  절차가 있어 우선순위가 낮음).
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
  수정 모달·설정까지 실기기(갤럭시 Z 폴드)에서 확인, 전부 정상. 로그인
  화면에는 `kDebugMode`로 감싼 "디버그: 로그인 건너뛰기" 버튼이 있는데
  **release 빌드에는 포함되지 않으므로 출시 리스크 아님**(2026-08-04
  재감사에서 코드로 재확인 — 별도로 지울 필요 없음).

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
- **2026-08-04 재감사에서 남은 잔재 재확인**: 퍼플 리브랜딩 이후에도
  `location_consent_sheet.dart`에 구 블루 색상(`0x332B76C5`)이 남아 있고,
  `settings_view.dart`(`0xFF2D7D46`)와 `camera_scan_modal_view.dart`
  (`Colors.greenAccent`)의 "성공" 색이 서로 다르며, `app_colors.dart`의
  `bgDarkSlate`/`cardDark` 등 변수명이 실제 값(흰색 계열)과 반대로 남아
  있음 — 기능 문제는 아니고 전부 P2 정리 대상(3.해야 할 일 참고).

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

## 2-0. 사용자가 결정할 일

**⚠️ 신규(2026-08-04 PM 우선순위 재감사) — 아직 답 없음, 아래 4건은 구현에
들어가지 않고 사용자 답을 기다린다**:

1. **v1 출시 스코프 — 무료 단독 출시 vs 구독(유료) 포함 출시.** 손익분석
   문서(`docs/planning/business/pnl-analysis-freemium.html` 11번 섹션)는
   "C안(₩1,000/월, 무료 등급 없이 유료 전용)"이 구조적으로 가장 안전하다는
   결론이었지만 최종 승인은 아직 없다. 이 답에 따라 아래 "3.해야 할 일"의
   구독 SKU/IAP/결제동의/영수증검증/AI 호출 한도 차등(5건)이 v1에 포함되는
   P1인지, v1.1 이후로 완전히 미뤄지는 P2인지가 갈린다.
2. **Gmail 가져오기를 v1에 꼭 포함해야 하는지.** `gmail.readonly`는 Google
   심사(CASA)가 필요한 제한된 범위라 등록·검증 기간이 불확실하다. 이 심사가
   끝날 때까지 Gmail 버튼만 "준비 중"으로 잠그고 나머지 3개 소통 입력 경로
   (통화 후 메모/문자 붙여넣기/카카오톡 붙여넣기)만으로 먼저 출시할지, 아니면
   Gmail 검증 완료까지 v1 출시 자체를 미룰지.
3. **"근처 인맥에 갔을 때 알림을 준다"는 앱 핵심 컨셉 문구와 실제 구현 간
   정합성.** 지금은 앱을 열어야 보이는 인앱 레이더 목록만 있고, 앱이 닫혀
   있을 때 실제로 울리는 백그라운드 푸시 알림 파이프라인은 없다(중간 규모
   신규 개발, 배터리/OS 권한 이슈 동반). v1을 이 "패시브 레이더" 상태로
   출시하고 마케팅 문구를 "앱을 열면 근처 인맥을 보여준다"로 조정할지,
   아니면 실제 백그라운드 알림 기능을 v1 출시 조건에 포함할지.
4. **명함 사진 서버 백업(2단계) 관련, 기존 사용자 로컬 사진을 로그인 시
   자동으로 소급 업로드할지, 사용자가 직접 켜는 옵트인 방식으로 할지.**
   `server-setup-plan.md` 15.8절에 이미 "⚠️ 사용자 결정 필요"로 표시돼
   있었지만 아직 답이 없다 — 문서는 옵트인을 권장안으로만 제안해 둔 상태.

**이전에 결정 완료된 항목(보류 해제)**:

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
직접 읽고 쓰는 백업/복원(Cloud Functions 없음, 회원탈퇴는 클라이언트
로직으로 별도 구현 완료, 계정 오염 방지는 Cloud Functions가 아니라
확인 다이얼로그로 완화). 구현 상세는 "1. 한 일"과 backlog 추가 67 참고.
`server-setup-plan.md`를 "지금 상태"로 착각하지 말 것 — 그 문서에 있는
나머지 기능(마이그레이션 안전장치의 uid별 키 격리, 사진 저장 2단계,
AI 프록시)은 전부 아직 미구현이며, "3. 해야 할 일"에 남은 항목으로
정리해 둠.

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
  다음 단계로, "3. 해야 할 일" 참고.
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
  소급 업로드는 옵트인 권장까지 설계 — 이 소급 업로드 방침은 아직
  사용자 최종 확인 전, 위 "2-0" 질문 4번 참고). `release-roadmap.md`도
  함께 갱신.
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
  - **Cloud Functions·uid별 저장소 키 격리는 이번에 구현 안 함** —
    `server-setup-plan.md`가 설계한 범위보다 작은 MVP다(회원탈퇴와
    다중 계정 안전장치는 이후 추가 71에서 더 가벼운 방식으로 별도
    구현 완료, 아래 "3. 해야 할 일" 참고).
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
- **기기 저장자료 암호화**: 이번 세션에서 명함/프로필 JSON은 AES-256-GCM
  암호화 완료(추가 72). `cache/CAP*.jpg` 같은 명함 원본 사진 파일은 아직
  평문 — "3. 해야 할 일" 참고. 별개로 "서버에 명함 원본 사진을 올리면
  암호화되나"라는 질문에 답한 결론(추가 62 참고): Firebase Storage는 저장
  시 자동으로 AES-256 암호화되고 전송도 TLS라 **서버 쪽 암호화는 기본
  제공**이며, 진짜 위험은 접근 제어(Security Rules로 본인 파일만 본인이
  읽게 강제)다.
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
  **서버가 실제로 생기기 전까지는 화면만 있고 데이터 연동은 없음** —
  표시된 수치는 전부 예시.
- **AI 관여 화면 설계서(AS-IS) 작성 완료, 구현 변경 없음(추가 74,
  2026-08-04)**: "AI 대화 브리핑" 기능이 걸쳐 있는 화면 7개(레이더/설정
  진입점, AI 연동(BYOK) 설정, 브리핑 오버레이, 전송 동의 시트, 소통기록
  추가 방법 선택, Gmail 가져오기, 수동 입력)를 실제 코드 근거로 문서화
  (`docs/planning/design/ai_screens_asis_spec.md`) — 화면별 상태 분기,
  에러/빈상태/로딩 처리, 화면 간 이동을 표로 정리. 조사 중
  `ai_briefing_screens_spec.html`(P1-8 이후를 가정한 To-Be 스펙,
  커밋 `070e405`)이 이미 있었는데 backlog/HANDOFF에 기록이 누락돼 있던
  걸 발견해 함께 보완. "확인이 필요할 수 있는 사항"으로 2건만 가볍게
  남김(선택된 대화 포인트 카드가 시각적 강조 외 기능이 없는 점, 모델
  오버라이드 UI 부재) — 둘 다 구현을 막는 결정은 아니라 "3. 해야 할 일"에
  새 P0/P1로 올리지 않고 여기 기록만 해 둠.
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
  Android/iOS OAuth 클라이언트, OAuth 동의화면과 제한 범위(`gmail.readonly`)
  검증(CASA) 전에는 실제 계정 연결이 동작하지 않는다.
- **최신 빌드 QA**: Android Play용 AAB 빌드 성공(85.8MB), 병합 매니페스트에서
  통화기록·문자·전화상태·마이크 권한이 없는 것을 확인. iOS 최신 릴리스 빌드도
  성공(83.0MB)했지만 도구 사용 한도 때문에 이 최신 빌드의 iPhone 재설치는
  실행하지 못했다. Android 폰은 ADB 목록에 나타나지 않았다.

## 3. 해야 할 일 (2026-08-04 PM 우선순위 재감사 기준 — P0/P1/P2)

각 항목에 근거·규모·담당을 붙였다. "담당"은 실제 작업 실행자(에이전트) 기준.
사용자 본인 계정/결제 작업은 "사용자"로 표시.

### 🔴 P0 — 릴리즈 블로커

이 7건은 코드가 완벽해도 출시 자체를 막거나("금지/반려"), 핵심 기능이
실사용자 눈앞에서 망가진 채로 나가게 만든다. (P0-6·P0-7은 2026-08-05
법적 고지 정비 중 추가됨 — 0-2 섹션 참고.)

| # | 항목 | 근거 | 규모 | 담당 |
|---|---|---|---|---|
| P0-1 | App Store Connect 빌드 업로드 403 권한 에러 해결 | `apps@creamhouse.net` 계정의 App Store Connect "사용자 및 접근" 역할 확인/재초대 필요(0-1 섹션 참고) — 이게 안 풀리면 iOS 빌드를 물리적으로 업로드할 수 없다 | 불명(계정 이메일 왕복, 코드 작업 아님) | 사용자 |
| P0-2 | Apple 로그인 — iOS 빌드 검증 + 콘솔 설정 | **2026-08-05 갱신: 코드 구현은 끝났으나 커밋되지 않은 작업 트리 상태**(0-2 섹션 참고). 남은 것은 ① iOS `pod install`·빌드·실기기 검증(현재 `Podfile.lock`에 `sign_in_with_apple` pod이 없어 **한 번도 빌드된 적 없음**) ② Apple 버튼 HIG 스타일링(지금은 Google과 같은 흰 버튼이라 심사 지적 소지) ③ Apple Developer 콘솔 Capability + Firebase Apple 제공사 활성화 | 중 | 개발(빌드·검증) + 사용자(콘솔 설정) |
| P0-3 | AI 서버 프록시(Gemini) 검증 — **전제 정정됨** | ⚠️ **원래 항목("AI 3사 실키 E2E")은 무효**: 커밋 `ed6b4b7`에서 BYOK가 삭제돼 `ai_provider.dart`·`ai_credentials_repository.dart` 파일 자체가 없고, `ai_briefing_service.dart`는 `httpsCallable('generateBriefing')` 하나로 대체됨. 검증 대상은 `functions/src/index.ts`(Gemini 단독)이며, `kAiServiceDeployed=false` + Blaze 미가입(P1-7)이라 **실키 E2E는 물리적으로 불가**. 별도로 발견된 코드 결함(thinking 토큰이 `MAX_OUTPUT_TOKENS=400`을 잠식해 빈 응답이 되는 문제 등)은 P1-8 착수 시 함께 처리 | 중 | 개발 → QA |
| P0-4 | 브리핑 오버레이 텍스트 가독성 버그 | `briefing_overlay_view.dart`가 `Colors.black.withValues(alpha:0.85)` 배경 위에 `AppColors.textPrimary`(어두운 색)를 그대로 써서 핵심 화면 텍스트가 사실상 안 보임(코드로 재현 확인) | 소(색상 토큰 1곳) | UI디자이너 |
| P0-5 | ~~개인정보처리방침 담당자·전용 문의메일 정식화~~ → **법적 고지 문서 게시** | **2026-08-05 갱신: 문서 작성은 완료**(0-2 섹션). 보호책임자·문의메일 임시값은 최우진(대표이사) + `connectsense@creamhouse.net`으로 정식화했고, 방침 v2.0 전부개정·이용약관·접근권한 안내·계정삭제 안내까지 작성 완료. 남은 것은 ① **`connectsense@creamhouse.net` 메일 계정 생성**(사용자) ② C안 코드 구현 후 Firebase Hosting 배포 ③ 스토어 콘솔에 URL 등록 | 소 | 사용자(메일 개설) + 개발(배포) |
| P0-6 | 계정 삭제 안내 웹페이지 게시 | **신규(2026-08-05 발견)**. Google Play는 앱 내 삭제 기능과 **별개로** 계정 삭제 안내 웹 URL을 "앱 콘텐츠"에 요구한다 — 없으면 제출 자체가 진행되지 않는다. 문서(`docs/legal/account-deletion.html`)는 작성 완료, Hosting 배포와 콘솔 등록만 남음 | 소 | 개발(배포) + 사용자(콘솔 입력) |
| P0-7 | Play Data safety / Apple App Privacy 양식 작성 | 양식과 개인정보처리방침이 **불일치하면 즉시 반려**된다. 방침 v2.0에서 수집 항목·국외이전·위탁·삭제 경로가 크게 바뀌었으므로 양식을 그 기준으로 새로 채워야 함 | 중 | 기획 + 사용자(콘솔 입력) |

### 🟡 P1 — 출시 전 권장 (블로커는 아니지만 방치하면 출시 품질·리스크에 직결)

| # | 항목 | 근거 | 규모 | 담당 |
|---|---|---|---|---|
| P1-1 | 구독 SKU 등록(App Store Connect/Play Console) | P0-1(App Store Connect)이 풀려야 진행 가능. **위 "2-0" 사용자 결정 1번(v1 스코프)이 확정돼야 착수 여부·시점이 정해짐** | 소 | 사용자 |
| P1-2 | 인앱결제(IAP) 클라이언트 연동(`in_app_purchase`) | 위와 동일 — 스코프 결정 대기 | 중 | 개발 |
| P1-3 | 구독 결제 동의/고지 UI(2026 개정 전자상거래법 대응) | 손익분석 문서 "C안" 채택 시 필요. 무료→유료 전환/요금 인상 시 결제 30일 전 동의 필수 | 중 | UI디자이너 + 개발 |
| P1-4 | 서버측 구독 영수증 검증 + Firestore 구독상태 동기화 | App Store Server Notifications V2 / Google Play RTDN 수신용 Cloud Function 필요 | 대 | 개발 |
| P1-5 | AI 호출 한도를 구독 등급별로 차등 적용 | 지금 `functions/src/index.ts`의 `DAILY_LIMIT`/`MONTHLY_LIMIT`은 고정값, 구독 상태 반영 안 됨 | 중 | 개발 |
| P1-6 | Gmail 가져오기 프로덕션 OAuth 등록·동의화면 검증(CASA) | `gmail.readonly`는 Google이 제한된 범위로 분류해 별도 보안 심사가 필요한 스코프 — 코드는 완성됐지만 여전히 미등록 상태로 보임(backlog 옛 기록 기준, 재확인 필요). 소통기록 4개 입력 경로 중 1개일 뿐이라 핵심 플로우를 막지는 않음 | 중~대(Google 심사 기간 변수) | 사용자(콘솔 설정) + 개발(검증 대응) |
| P1-7 | Firebase Blaze 요금제 카드 등록 | AI 서버 프록시(Cloud Functions)·사진 서버 백업·완전한 키 분리 3가지의 공통 선행조건. 카드 등록 자체는 즉시 가능, P0로 안 둔 이유는 없어도 v1이 BYOK 그대로 정상 출시 가능하기 때문 | 소 | 사용자 |
| P1-8 | AI 연동 BYOK→서버 프록시 전환 구현 | 사용자가 이미 방향을 결정했고 `functions/src/index.ts` 코드까지 작성됨, 배포만 P1-7 대기 중. 지금 BYOK 상태로도 기능은 정상 동작하므로 급하진 않지만 방치하면 "결정 vs 실제 코드"가 계속 어긋남 | 중(배포 + `ai_connection_modal_view.dart` 문구 개편) | 개발 |
| P1-9 | 명함 원본 사진 로컬(기기) 암호화 | JSON 텍스트 필드는 이미 AES-256-GCM 암호화(추가 72)했지만 `cache/CAP*.jpg` 원본 이미지는 평문. 텍스트 데이터 평문 노출을 이미 실기기에서 발견한 전례(추가 72)가 있어 사진도 같은 방식으로 뚫릴 수 있음 | 중 | 개발 |
| P1-10 | 다중 계정 전환 안전장치 — 스토리지 격리 여부 QA 스트레스 테스트 | 코드 확인 결과 로컬 저장 키가 uid별로 분리되지 않고 여전히 전역 키(`saved_contacts_v2`) — "유지 vs 교체" 다이얼로그 하나로만 계정 간 데이터 혼입을 막고 있음. 다이얼로그 로직의 엣지케이스(앱 강제 종료, 빠른 재로그인 등)를 실기기에서 검증 필요 | 소~중 | QA (필요 시 개발) |
| P1-11 | UI-2~UI-6 시각 일관성 버그 | 구 블루 잔존 색상(`location_consent_sheet.dart`), 성공색 불일치(`settings_view.dart` vs `camera_scan_modal_view.dart`), 아바타 터치영역, 태그칩 클리핑, 카드 그림자 하드코딩 — 전부 코드로 재확인함, 기능 블로커는 아니나 최근 퍼플 리브랜딩 이후 정리 안 된 잔재 | 각 소 | UI디자이너 |
| P1-12 | 접근성(Semantics) 보완 | 전화 걸기 CTA, 지갑 화면 Dismissible, 브리핑 대화 포인트 카드 등 커버리지 낮음 | 중 | UI디자이너 |
| P1-13 | 크래시 리포팅 도입(Firebase Crashlytics) | 같은 Firebase 프로젝트에 얹으면 별도 계정 설정 없이 가능. 지금은 실사용자 크래시가 발생해도 아무 데도 안 남음 | 소 | 개발 |
| ~~P1-14~~ | ~~좌표 C안 구현~~ → ✅ **완료(구현 + 실기기 검증)** | 2026-08-05 구현(추가 76) + iPhone 16 Pro 실기기 검증 완료(추가 77). 로그인 계정 명함 3건이 전부 "암호화 + 좌표 없음"으로 전환됐고, 앱 삭제→재설치→복원 후 거리가 다시 표시되는 것까지 확인. 재계산된 좌표가 서버로 되돌아가지 않는 것도 확인 | — | 완료 |
| ~~P1-22~~ | ~~앱 재설치 시 iOS Keychain 잔존 데이터 정리~~ → ✅ **완료(구현 + 실기기 검증)** | 2026-08-05 발견·해결(추가 78). `FreshInstallService`가 `shared_preferences` 설치 표식으로 재설치를 감지해 보안 저장소를 비운다. 기존 사용자가 업데이트만으로 로그아웃되지 않도록 "`shared_preferences`가 통째로 비어 있을 때만 재설치로 판단"하는 보완도 포함. **부수 효과: 이 수정 덕분에 재설치가 곧 새 기기와 같은 조건이 되어, 그동안 미검증이던 "기기 변경 시 Firestore에서 암호화 키를 내려받는 경로"가 실기기에서 검증됐다** | — | 완료 |
| ~~P1-23~~ | ~~로그인하지 않은 계정의 서버 문서 정리~~ → ✅ **완료** | 2026-08-05 사용자가 남아 있던 테스트 계정 `MmNZjpID…`를 **계정 삭제로 정리**(문서 + 하위 명함 2건 통째로 삭제 — 부수적으로 계정 삭제 기능이 실제로 동작하는 것도 확인됨). **서버 전체가 명함 3건 / 평문 0건 / 좌표 0건**이 됐다. ⚠️ 다만 **구조적 한계는 그대로 남는다** — 마이그레이션은 그 계정으로 로그인해야 돌고, `rebackupAllContacts`는 로컬에 있는 명함만 덮어쓴다. 실사용자가 생긴 뒤 같은 상황이 발생하면 서버 측 일괄 마이그레이션(Cloud Functions, P1-7 선행)이 필요하다 | — | 완료 |
| P1-24 | Google/Apple 로그인 계정 분리 문제 | Apple 로그인을 하면 **별도의 Firebase 계정(uid)이 생긴다**. 같은 사람이 두 방식을 섞어 쓰면 명함 데이터가 계정별로 분리돼 "데이터가 사라졌다"고 느낀다. 계정 연결(linkWithCredential) 또는 안내 문구 필요. (※ 추가 77에서 빈 계정 `SRsffKQf…`를 Apple 로그인 탓으로 추정했으나 추가 79에서 **갤럭시의 다른 Google 계정 로그인** 때문으로 정정됨 — 계정 분리 문제 자체는 여전히 유효) | 중 | 개발 + UI디자이너 |
| P1-25 | 지오코딩 영구 실패 시 사용자 안내 | **신규(2026-08-05, 추가 79)**. 좌표를 서버에서 뺀 뒤로는 주소 지오코딩이 3회 모두 실패한 명함이 **영구적으로 주변 인맥 목록에서 빠지는데 사용자에게 아무 표시도 나가지 않는다**(좌표를 서버에 두던 때는 없던 실패 모드). 명함 상세에 "주소 위치를 확인할 수 없습니다 · 주소 수정" 같은 안내가 필요한지 판단 필요 | 소~중 | UI디자이너 + 개발 |
| P1-15 | 앱 내 법적 문서 진입점 | 지금 `lib/presentation/` 전체에 방침·약관 링크가 **0개**다. 설정 화면에 "약관 및 정책" 섹션 신설(기존 `_SectionTitle`/`_GroupedCard`/`_SettingsRow` 재사용) + `LegalDocumentView`(WebView 원격 우선, asset 폴백). **`address_search_view.dart:40-89`가 정확히 같은 `WebViewController` + `loadFlutterAsset` 패턴이라 골격 복제 가능** | 중 | 개발 |
| P1-16 | 로그인 화면 약관 고지 문구 | `login_view.dart`에 약관 동의 체크박스도 고지 문구도 없음. v1은 체크박스 대신 "계속하기를 누르면 [이용약관]과 [개인정보처리방침]에 동의하는 것으로 봅니다" 형태 권장(결제·마케팅 도입 시 체크박스 게이트로 승격) | 소 | 개발 |
| P1-17 | 약관 동의 기록(`TermsConsentService`) | 동의 사실 입증과 문서 개정 시 재동의를 위해 필요. **`location_consent_service.dart`의 `currentPolicyVersion` 불일치 시 재동의 패턴(L35·L44)을 그대로 복제**하고, 기기 변경 시 이력이 사라지지 않도록 `users/{uid}.consents`에도 기록 | 소~중 | 개발 |
| P1-18 | 오픈소스 라이선스 화면 + 앱 버전·사업자 정보 표시 | `showLicensePage`/`LicensePage` 사용 0건 — OSS 라이선스 고지 화면이 아예 없다. 앱 버전은 `package_info_plus`로 자동 반영 권장(하드코딩은 릴리즈마다 갱신 누락 위험) | 소 | 개발 + UI디자이너(테마 확인) |
| P1-19 | Android 릴리스 서명 키 설정 | `android/app/build.gradle.kts:38-40`이 `signingConfig = signingConfigs.getByName("debug")` + `// TODO: Add your own signing config` — **debug 키로 서명된 빌드는 Play에 업로드할 수 없다.** iOS의 App Store Connect 403(P0-1)에 대응하는 Android 쪽 배포 블로커 | 소 | 사용자(키스토어 생성·보관) + 개발 |
| P1-20 | Android `<queries>`에 전화 인텐트 추가 | `AndroidManifest.xml:57-62`에 PROCESS_TEXT만 있고 DIAL/`tel:` 인텐트가 없어, Android 11+에서 `canLaunchUrl(tel:)`이 false를 반환해 **전화 걸기가 조용히 실패**할 수 있음(`phone_call_service.dart:9-15`). 실기기 검증 기록 없음 | 소 | 개발 → QA |
| P1-21 | iOS 수출규정 키 추가 | `ios/Runner/Info.plist`에 `ITSAppUsesNonExemptEncryption` 키가 없어 업로드마다 수출규정 질문에 수동 응답해야 함. 앱이 AES-256-GCM을 쓰므로 값 판단 후 명시 필요 | 소 | 개발 |

### 🟢 P2 — 여유 있을 때

| # | 항목 | 근거 | 규모 | 담당 |
|---|---|---|---|---|
| P2-1 | 완전한 키 분리(제로-지식화, Cloud Functions/KMS) | 지금 암호화 키가 Firestore `users/{uid}.encryptionKeyB64`에 데이터와 함께 있음. P1-7(Blaze) 완료 후가 자연스러운 타이밍 | 중~대 | 개발 |
| P2-2 | 알림 센터 실제 파이프라인(근접/신규 등록 이벤트를 실시간 알림으로) | 지금은 빈 상태만 있음. **위 "2-0" 사용자 결정 3번(알림 문구 정합성)에 따라 P1로 격상될 수 있음** — 그 답이 나올 때까지는 P2로 둠 | 중~대 | 개발 → UI디자이너 |
| P2-3 | 네이버/카카오 SNS 로그인 추가 | 사용자가 "Google만 먼저 진행"으로 명시적으로 보류. 필요해지면 재검토 | 중 | 개발 |
| P2-4 | 최초 실행 온보딩 화면 | `SplashGate → AuthGate → MainTabScreen` 직행, 서버와 무관한 독립 작업 | 중 | UI디자이너 → 개발 |
| P2-5 | 로컬 백업/내보내기 기능 | 신규 기능, 서버 도입 후 진행 권장 | 중 | 개발 |
| P2-6 | 카메라 권한 거부 시 "설정 열기" 유도 | `camera_scan_modal_view.dart` — 같은 앱 안에 참고 패턴(`location_access_flow.dart`) 이미 있어 이식만 하면 됨 | 소 | 개발 |
| P2-7 | 죽은 코드 제거 | `communication_trace_test_modal_view.dart`, `comm_log_sync_service.dart` — 서로만 참조, 진입점 없음(코드로 존재 재확인함) | 소 | 개발 |
| P2-8 | `AppColors` 변수명 리네이밍(UI-7) | `bgDarkSlate`/`cardDark` 등 이름이 실제 값(흰색 계열)과 반대 — 기능 영향 없음, 유지보수성 문제 | 소 | UI디자이너 |
| P2-9 | 관리 콘솔(통계 대시보드) 실제 서버 연동 | 목업(`admin_console_mockup.html`)만 있고 데이터 연동 없음. P1-7/서버 인프라 이후 자연스러운 순서 | 대 | 개발 |

### ⚪ 보류 (사용자가 이미 결정)
- **다국어(i18n) 번역** — 프로젝트 마지막 단계에 진행하기로 확정.

### ✅ 최근 완료(2026-08-04 밤, 위 "0-1" 참고 — 여기 다시 안 적음)
iOS 빌드 문제 전체, iOS/Android 실기기 로그인·백업·복원 검증, 계정 삭제
기능, 다중 계정 안전장치(다이얼로그 방식), 개인정보처리방침 게시, 명함/프로필
JSON 암호화, Android 실기기 QA, Apple Developer Program 가입(단, 이 가입을
실제 Apple 로그인 활성화로 이어붙이는 작업은 위 P0-2로 아직 남아 있음).

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
  포함. **서버 구축("3. 해야 할 일" P1-7)에 착수할 때 가장 먼저 읽을
  문서.**
- **`docs/planning/release-roadmap.md`** — 2026-08-04 낮에 세 에이전트
  합동으로 만든 이슈 통합 로드맵. P0 표는 이번 재감사로 갱신했지만
  Phase 순서/담당 배정 섹션은 그대로 참고 가능.
- **`docs/planning/design/`** — 코드 구현 전 단계의 디자인 목업/설계서.
  `admin_console_mockup.html`(관리 콘솔 데이터 관리·통계 화면설계서,
  Figma 이전용 컴포넌트 시트 포함), `app_icon_samples.html`(앱 아이콘
  밝은 계통 샘플 5종) — 서버·API 연동 없는 정적 HTML, 브라우저로 그냥
  열면 됨. **AI 대화 브리핑 관련 화면설계서 2종(짝을 이루는 전/후
  스냅샷)**: `ai_screens_asis_spec.md`(추가 74, 2026-08-04 코드 그대로의
  AS-IS — BYOK 방식 유지 상태) vs `ai_briefing_screens_spec.html`(추가
  기록 누락돼 있던 걸 이번에 발견, P1-8 서버 프록시 전환 이후를 가정한
  To-Be). P1-8 착수 시 두 문서를 나란히 비교해서 시작할 것.
- **`docs/legal/`** — 실제로 게시할 법적 고지 문서(추가 75, 2026-08-05).
  `index.html`(인덱스 + 사업자 정보 푸터), `privacy-policy.html`(v2.0
  전부개정, 19항목), `terms-of-service.html`(19개조), `app-permissions.html`
  (정보통신망법 §22-2 접근권한 고지), `account-deletion.html`(Google Play
  필수 제출 URL), `legal.css`(공통 스타일). **각 HTML 상단에 화면에는 안
  보이는 `<!-- -->` 주석으로 "게시 전 확인 사항"이 박혀 있으니 배포 전
  반드시 읽을 것** — 특히 방침은 좌표 C안(P1-14) 코드 구현이 끝나기 전에
  게시하면 허위 기재가 된다. 배포 설정은 `firebase.json`의 `hosting` 섹션
  (`public: "docs/legal"`, Spark 무료 요금제로 가능).

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
  Apple은 아직 `false` — P0-2 참고.

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
  조회. 저장은 `EmailImportSheet`에서 사용자가 선택한 뒤 수행. `gmail.readonly`
  스코프 상태는 P1-6 참고.
- `lib/core/services/comm_log_sync_service.dart` — 과거 API 호환용 비활성
  스텁. 출시 앱에서 통화/문자 자동 수집을 다시 활성화하지 말 것. P2-7에서
  삭제 후보로 분류됨.
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
  브리핑 화면(로딩/에러/미연동 상태 처리 포함). **P0-4 가독성 버그 위치.**
- `lib/presentation/features/briefing/views/ai_data_review_sheet.dart` — AI
  요청별 전송 항목 선택과 명시적 동의. 개인정보 전송 경계이므로 우회 금지.
- `lib/presentation/features/briefing/views/communication_source_sheet.dart`,
  `email_import_sheet.dart`, `manual_comm_log_modal_view.dart` — 소통자료 입력
  라우팅, Gmail 선택 가져오기, 통화/문자/카카오톡 수동 입력.
- `lib/presentation/features/settings/views/ai_connection_modal_view.dart` — AI
  제공사별 API 키 입력/발급 안내 화면. BYOK 문구가 여기 있음 — P1-8에서
  서버 프록시 전환 시 함께 개편.
- `lib/presentation/features/radar/views/radar_view.dart` — 첫 화면(레이더),
  퍼플 톤 디자인 시안 구조로 재설계됨(추가 49).
- `lib/presentation/common/contact_avatar.dart` — 인맥 사진 아바타 공용
  위젯(사진 있으면 표시, 없으면 이니셜). 새 아바타 표시 코드는 반드시
  이걸 재사용할 것 — 예전 Unsplash 스톡사진 프리셋 같은 가짜 사진을
  다시 넣지 말 것.
- `lib/presentation/features/auth/views/login_view.dart`,
  `lib/presentation/common/auth_gate.dart` — SNS 로그인 화면과 앱 진입
  게이트(`SplashGate` → `AuthGate` → `MainTabScreen` 순서로 `main.dart`에
  연결돼 있음). Apple 로그인 활성화(P0-2) 작업 시 여기를 건드리게 됨.

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
이벤트 전송 코드나 집계 서버는 **아직 없다** — 3.해야 할 일 P1-7(서버 구축)
이후 구현할 때 이 목록을 이벤트 설계의 출발점으로 쓰면 된다. 서버 자체 집계
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
  오류 유형 분포(응답 파싱 실패 등 — P0-3의 실사용 검증과 직결),
  데이터 전송 동의 화면(`ai_data_review_sheet.dart`)에서의 동의율.
- **소통기록 입력**(`communication_source_sheet.dart` 등): 채널별(통화/문자/
  이메일/카카오톡) 입력 비중, Gmail 선택 가져오기 사용률.
- **설정**: 위치 감지 반경 변경 분포, 위치 동의율/철회율, 위치정보 이용
  안내 열람율, 로그아웃 빈도.
- **공통/전체**: 크래시율, 화면별 로딩 실패율, 세션당 평균 체류시간,
  리텐션(D1/D7/D30), 설치 후 첫 명함 등록 완료까지 걸린 시간(핵심 활성화
  지표 — 위 "명함 등록/스캔" 퍼널과 함께 봐야 함).

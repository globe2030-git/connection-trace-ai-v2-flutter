# Connection Trace AI v2 (Flutter) — 오류노트

발생한 까다로운 버그와 원인·해결 과정을 기록해서, 같은 유형의 문제가 다시
나타났을 때(또는 다른 화면/다른 프로젝트에서) 바로 참고할 수 있게 남긴다.

---

## 2026-08-02 — iOS 실기기 최초 연결: 모듈 검증 빌드 실패 + "로고 뜨다 죽음"

### 증상 1 — 실기기 빌드가 "double-quoted include ... expected angle-bracketed" 에러로 실패
시뮬레이터 빌드는 되는데 실제 아이폰(iphoneos 타겟) 빌드만 nanopb,
GTMSessionFetcher, google_mlkit_commons/text_recognition 쪽에서 각각
"expected angle-bracketed instead" 에러가 나며 실패.

**원인**: 최신 Xcode의 "모듈 검증(Module Verifier)" 기능. 이 pod들의 헤더가
`#import "Header.h"`(큰따옴표)를 쓰는데, Module Verifier가 프레임워크 헤더는
`#import <Framework/Header.h>`(꺾쇠괄호)여야 한다고 엄격하게 검사함 — 기능
문제가 아니라 새로 생긴 검사가 오래된 pod들과 안 맞는 것. 게다가 관련 빌드
설정 키가 **두 개**(`CLANG_ENABLE_MODULE_VERIFIER`와 `ENABLE_MODULE_VERIFIER`)
라서, 하나만 끄면 나머지 하나가 여전히 켜져 있어서 google_mlkit_* pod
자체에서 "Flutter/Flutter.h 못 찾음" 에러가 남아 있었음(Module Verifier가
격리된 상태로 검증을 시도하다 보니 Flutter.framework를 못 찾는 것).

**해결**: `ios/Podfile`의 `post_install`에서 두 키 다 `'NO'`로 설정.
```ruby
config.build_settings['CLANG_ENABLE_MODULE_VERIFIER'] = 'NO'
config.build_settings['ENABLE_MODULE_VERIFIER'] = 'NO'
```
확인 방법: `xcodebuild -showBuildSettings -project Pods/Pods.xcodeproj -target <pod이름> | grep -i verifier`로 실제 적용됐는지 볼 수 있음.

### 증상 2 — 빌드/설치는 됐는데 앱이 "로고만 보이다가 바로 죽음"
`flutter run`이 "Timed out waiting for CONFIGURATION_BUILD_DIR to update"로
실기기에 자동 실행을 못 시켜서, `xcrun devicectl device install app` +
`process launch`로 직접 설치·실행했더니 로고(네이티브 스플래시)까지는 뜨는데
그 직후 죽음.

**원인**: **디버그 모드로 빌드된 앱은 `flutter run` 툴링이 실행 내내 붙어있어야만
Flutter 엔진이 초기화된다**(디버그 모드는 커널 스냅샷을 툴링이 실시간으로
공급하는 구조). `devicectl`로 독립 실행시키면 네이티브 스플래시(=로고)는 뜨지만
Flutter 엔진 초기화 시점에 "Cannot create a FlutterEngine instance in debug
mode without Flutter tooling or Xcode"로 즉시 죽음(콘솔에 `--console` 옵션으로
보면 이 메시지가 정확히 찍힘).

**해결**: `flutter build ios --release`(디버그 아님, AOT 컴파일이라 툴링
필요 없음)로 빌드한 뒤 `devicectl`로 설치·실행하면 정상 동작. `flutter run`
의 Automation 관련 타임아웃 자체는 별도 macOS 권한 이슈로 보이며, 이 우회
방법으로는 막히지 않음.

### 다시 만날 수 있는 패턴 (교훈)
- 실기기 빌드가 안 되면 Xcode 버전이 새로 올라간 뒤 생긴 "Module Verifier"류
  엄격한 검사를 의심해볼 것 — 오래된(특히 Google/Firebase 계열) pod에서 흔함.
- `flutter run`으로 실기기 실행이 막히면(Automation 타임아웃 등),
  `flutter build ios --release`(또는 `--profile`) + `xcrun devicectl device
  install app` / `process launch`로 우회 가능 — 단 **디버그 빌드는 이 방식으로
  절대 못 띄운다**(항상 크래시). release/profile 빌드만 독립 실행 가능.

---

## 2026-08-02 — 안드로이드 실기기(에뮬레이터) 최초 검증: 한글 OCR 즉시 크래시

### 증상
사용자가 웹 미리보기에서 "이미지 업로드 후 스캔 버튼이 안 눌린다"고 제보 —
확인해보니 웹은 ML Kit 자체가 지원 안 되는 게 원인(별도 UX 개선으로 해결).
그런데 "그럼 실기기에서 확인해보자"고 안드로이드 에뮬레이터에 처음 설치해서
실제로 명함 촬영 → OCR 스캔까지 돌려보니, **카메라로 사진을 찍고 확인을 누르는
순간 앱이 통째로 죽었음**(`adb`로 실시간 로그 보면서 재현).

### 원인
`google_mlkit_text_recognition`이 라틴 문자 인식 모델만 앱에 기본 포함하고,
한글/중국어/일본어/데바나가리 인식 모델은 플러그인 자체 build.gradle에
`compileOnly`로만 선언돼 있음(컴파일은 되지만 APK에 실제로 안 들어감 — APK
용량을 줄이려고 앱이 필요한 스크립트만 직접 opt-in하게 만든 설계).
`TextRecognitionScript.korean`으로 인식기를 만들면 컴파일은 통과하지만, 실행
시점에 `KoreanTextRecognizerOptions$Builder` 클래스를 찾지 못해
`NoClassDefFoundError`로 즉시 크래시(`java.lang.AndroidRuntime: FATAL
EXCEPTION`). **이 앱은 한글 명함이 기본 시나리오라, 이 버그가 그대로 나갔으면
실사용자 전원이 카메라 스캔을 쓰자마자 크래시를 겪었을 것.** 에뮬레이터에서
직접 재현해보지 않았으면 놓쳤을 버그.

### 해결
`android/app/build.gradle.kts`에 `implementation("com.google.mlkit:text-recognition-korean:16.0.1")`
를 명시적으로 추가.

### 다시 만날 수 있는 패턴 (교훈)
- Flutter 플러그인이 `compileOnly` 의존성을 갖고 있으면 "컴파일은 통과하는데
  실기기에서만 터지는" 클래스라, `flutter analyze`/Dart 레벨 테스트로는 절대
  못 잡는다 — 실제 기능을 실기기(또는 에뮬레이터)에서 한 번은 눌러봐야 확실히
  드러난다.
- 지역화(다국어) 관련 SDK는 "기본 옵션 = 라틴/영어만" 인 경우가 흔하다 — 앱의
  주 사용 언어가 영어가 아니면, 해당 언어 스크립트가 실제로 런타임에 번들링
  되는지 별도로 확인해야 한다.
- 이번 세션에서 웹 프리뷰만으로는 못 잡을 버그가 이걸로 두 번째다(①IME 조합
  중 Tab 처리, ②이 크래시). 플랫폼 고유 동작(IME, 네이티브 SDK 모델 번들링)이
  관여하는 기능은 웹 검증만으로 "완료"라고 판단하면 안 된다는 걸 재확인.

---

## 2026-08-02 — iOS 시뮬레이터 최초 빌드 시 Flutter 툴체인 크래시

### 증상
실제 OCR/GPS/지오코딩 기능을 붙이면서 이 프로젝트 최초로
`flutter build ios --simulator`를 시도했더니, CocoaPods까지는 통과했는데
Flutter 자체가 "Oops; flutter has exited unexpectedly: Null check operator
used on a null value"로 죽으면서 빌드가 실패함(`parseOtoolArchitectureSections`
in `native_assets_host.dart`).

### 원인
새로 추가한 패키지(`geolocator`/`image_picker`/`google_mlkit_text_recognition`)
때문이 아니라, 기존에 이미 있던 `google_fonts` → `path_provider` →
`path_provider_foundation` 체인이 원인이었음. `path_provider_foundation`
2.6.0부터 `objective_c`(Dart의 네이티브 에셋/FFI 브리징 패키지)에 의존하게
됐는데, 이 Flutter SDK(3.44.8, `enable-native-assets` 실험적 기능 켜진 채널)의
otool 아키텍처 파싱 로직이 `objective_c` xcframework의 아키텍처별 프레임워크
이름 불일치(`objective_c.framework` vs `objective_c1.framework`)를 처리하다
죽는, Flutter 툴체인 자체의 버그였음. 이 프로젝트는 지금까지 계속 Flutter Web
으로만 테스트해왔기 때문에(이 개발 환경 자체가 iOS 실기기/시뮬레이터 접근이
제한적) 이 잠재적 문제가 이번에 처음 iOS 빌드를 시도하면서 드러난 것.

### 해결
`pubspec.yaml`에 `dependency_overrides`로 `path_provider_foundation`을
`objective_c` 의존이 생기기 직전 버전인 `2.5.1`로 고정. 부수적으로 iOS 배포
타겟도 13.0 → 15.5로 올려야 했음(`google_mlkit_commons`가 15.5 이상을 요구,
`ios/Podfile`의 `platform :ios` 및 `ios/Runner.xcodeproj/project.pbxproj`의
`IPHONEOS_DEPLOYMENT_TARGET` 둘 다 수정).

### 다시 만날 수 있는 패턴 (교훈)
- Flutter Web에서만 테스트해온 프로젝트라도, 네이티브 플랫폼(iOS/Android)
  전이 의존성 체인 어딘가에 "빌드 자체가 안 되는" 잠재 문제가 숨어 있을 수
  있다 — 새 네이티브 플러그인을 추가하는 시점이 그걸 처음 발견하기 좋은
  때임(플러그인 자체 문제가 아니어도).
- `flutter pub upgrade`로 안 올라가는 패키지를 특정 버전에 묶고 싶을 땐
  `dependency_overrides:`가 표준적인 방법. `dart pub deps --style=compact`로
  전이 의존 트리에서 문제 패키지를 요청하는 실제 상위 패키지를 찾을 수 있다.
- Google ML Kit iOS SDK는 Apple Silicon(arm64) 시뮬레이터를 지원하지 않는다
  (Google 쪽 알려진 제약, Flutter 문제 아님) — 시뮬레이터에서 OCR을 테스트하려면
  Rosetta 시뮬레이터가 필요할 수 있고, 실기기는 문제 없음.

---

## 2026-08-01 — 명함 등록 폼 Tab 키 필드 건너뛰기 + Assertion 크래시

### 증상
`add_card_modal_view.dart`(새 명함 직접 등록 폼)에서 "이름" 필드를 입력하고
Tab을 누르면 "회사명"을 건너뛰고 "직함/부서"로 포커스가 넘어감. Shift+Tab(역방향)은
문제없이 정상 동작. 이후 시도에서는 심할 때 회사명·직함/부서를 모두 건너뛰고
"회사 주소"까지 한 번에 3칸이 점프하고, 그 직전 브라우저 콘솔에
`Assertion failed` 예외가 발생하기도 함.

React 버전(변환 전 원본)에서는 동일한 Tab 이동에 아무 문제가 없었음 — 순수
Flutter Web 특유의 문제.

### 왜 어려웠나
- Dart 레벨 디버그 로그로 확인한 `currentIndex`(포커스 순서 계산)는 Tab을 누를
  때마다 정확히 1씩 증가 — 로직 자체는 항상 정상이었음. 그런데도 화면에 보이는
  실제 포커스는 어긋남. 즉 "우리 코드가 틀렸다"가 아니라 "우리 코드 다음에
  뭔가 다른 게 한 번 더 포커스를 옮긴다"가 진짜 원인이었음.
- 재현이 이 개발 환경의 브라우저 자동화로는 안 됨(Flutter Web html renderer에
  클릭/키보드 이벤트가 전달되지 않는 알려진 한계). 그래서 사용자가 화면 녹화
  영상을 남겨주면 `ffmpeg`로 프레임 단위(최대 30fps)로 잘라서 시각적으로
  분석하는 방식으로 진행함.

### 시도했지만 실패한 방법들 (순서대로)
1. `FocusTraversalOrder` + `OrderedTraversalPolicy` — 변화 없음.
2. 필드별 `Focus(onKeyEvent: ...)` 가로채기 — 변화 없음.
3. 폼 전체를 감싸는 `Shortcuts` + `Actions`로 `NextFocusIntent`/
   `PreviousFocusIntent` 재정의 — 이게 Flutter가 공식적으로 권장하는 "Tab의
   의미를 바꾸는" 방법인데도 변화 없음. 디버그 로그로 로직은 정상 실행됨을 확인.
4. 위 방식에 "포커스 이동 직후 한 번 더 지연 재확인(`Future.delayed`)해서
   덮어씌우기" 추가 — 로그상 `hasFocus=false`가 여러 번 찍혀서 "브라우저 기본
   동작이 우리보다 늦게 한 번 더 끼어든다"는 심증은 얻었지만 화면상 완전히
   고쳐지진 않음.
5. `autofocus: true`를 이름 필드에 추가 — 모달이 열릴 때 이름 필드가 Flutter
   FocusManager 레벨에서 진짜로 focus를 갖지 못했을 수 있다는 가설이었으나
   근본 해결은 아니었음.

### 진짜 원인 (두 가지가 겹쳐 있었음)

**① 브라우저 네이티브 Tab 동작이 Flutter Dart 레벨 처리보다 늦게 한 번 더 실행됨.**
Flutter의 `Shortcuts`/`Actions`/`Focus.onKeyEvent`는 모두 "Dart 레벨"에서
`KeyEventResult.handled`를 반환하는 방식인데, Flutter Web(html renderer)에서는
이걸 반환해도 브라우저 자체의 keydown 기본 동작(네이티브 Tab 포커스 이동)이
항상 확실하게 억제되지는 않았음. 즉 Dart 코드가 옳은 필드로 포커스를 옮긴 바로
뒤에, 브라우저가 "원래 하려던" 자기 방식의 Tab 이동을 한 번 더 실행해서 최종
결과가 한 칸 더 밀려버림.

**② 한글(IME) 조합 중 상태에서 강제로 포커스를 옮기면 크래시.**
①을 근본적으로 막으려고 `document`의 `keydown`을 capture 단계에서 직접
가로채 `preventDefault()` + `stopImmediatePropagation()`으로 브라우저 기본
동작 자체를 원천 차단하는 방식(`WebTabGuard`)을 도입했더니 ①은 해결됐지만,
새로운 문제가 나타남: 이름에 한글을 입력한 직후 Tab을 누르면, 마지막 글자가
아직 "조합 중"(예: "김" 완성 전 자모 결합 단계)인 경우가 많은데 이 상태에서
곧바로 `requestFocus()`로 포커스를 옮기면 Flutter의 `TextInputClient`
조합(composing) 상태가 어긋나면서 `Assertion failed` 예외가 발생하고, 그
여파로 포커스가 여러 칸 튀는 현상까지 나타남.

첫 시도로 "조합 중(`e.isComposing == true`)이면 이 핸들러가 아예 관여하지
않는다"로 우회했더니 크래시는 사라졌지만, 정확히 그 "조합 중이던 첫 Tab"만
다시 브라우저 기본 동작(=버그 있는 원래 경로)으로 빠져서 이름→직함/부서로
건너뛰는 원래 증상이 부분적으로 되살아남(그 이후 필드들은 조합 중이 아니므로
정상).

### 최종 해결
`lib/core/utils/web_tab_guard_web.dart`에 `WebTabGuard` 도입:

- Tab 키는 **조합 중이어도 항상** capture 단계에서 가로채 `preventDefault()` +
  `stopImmediatePropagation()`으로 브라우저 기본 동작과 Flutter 엔진 자체
  키 처리를 원천 차단한다(관여를 포기하지 않음 — 이게 ②의 첫 우회안과 다른 점).
- 조합 중이 아니면: 같은 콜스택에서 곧바로 포커스를 옮기지 않고
  `Timer(Duration.zero, ...)`로 한 틱 미뤄서 처리한다. 네이티브 DOM 이벤트
  핸들러 안에서 곧바로 Dart 포커스 API를 재진입 호출하는 데서 오는 불안정성을
  피하기 위함.
- 조합 중이면: `compositionend`(조합이 실제로 끝나는 시점) 이벤트를 기다렸다가
  포커스를 옮긴다. 혹시라도 `compositionend`가 오지 않는 경우를 대비해 200ms
  안전 타임아웃도 둔다.
- 포커스 이동 로직 자체(`_moveFocus`, `_fieldFocusOrder` 순서 배열)는
  `add_card_modal_view.dart`에 그대로 유지 — 여기는 원래도 문제가 없었음.
- 기존에 있던 폼 전체 `Shortcuts`+`Actions`(시도 3번)는 새 방식과 중복
  처리될 위험이 있어 제거함.
- 모바일(Android/iOS) 빌드에는 영향 없도록 `dart:html`을 조건부 export로
  분리(`web_tab_guard.dart` / `_stub.dart` / `_web.dart`) — 웹이 아닌
  플랫폼에서는 아무 것도 하지 않는 빈 구현이 대신 쓰임.

### 다시 만날 수 있는 패턴 (교훈)
- Flutter Web에서 "Tab/Enter 등 특정 키의 기본 동작을 완전히 내가 정의하고
  싶다"는 요구는 `Shortcuts`/`Actions`/`Focus.onKeyEvent`만으로는 부족할 수
  있다 — 브라우저 native keydown 기본 동작 자체를 막아야 확실하다.
- 다만 그렇게 막을 때 텍스트 필드가 **한글/일본어/중국어 등 IME 조합형 입력** 중일
  가능성을 반드시 고려해야 한다. `KeyboardEvent.isComposing`을 체크하지 않고
  조합 중에 강제로 blur/포커스이동을 시키면 크래시나 예상 밖의 동작으로 이어질
  수 있다. "조합 중이면 무시"가 아니라 "조합 중이면 끝날 때까지 기다렸다가
  처리"가 맞는 패턴이다.
- 네이티브 브라우저 이벤트 핸들러 콜백 안에서 Dart 프레임워크 API(특히 포커스
  변경처럼 빌드/렌더 파이프라인에 영향을 주는 API)를 동기적으로 호출하는 건
  피하는 게 안전하다 — 최소 `Timer.zero`로 한 틱 미루기.

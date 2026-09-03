---
name: run-app
description: 커넥션센스 Flutter 앱을 실기기·데스크톱에 띄우고 화면을 눈으로 확인한다. "앱 띄워줘", "실행해줘", "스크린샷 찍어줘", "이 변경이 실제로 되는지 봐줘" 같은 요청에 쓴다. 테스트만 돌리는 것과는 다르다 — 실물 화면을 보는 것이 목적이다.
---

# 앱 실행

`flutter test`는 통과하는데 실물이 틀린 결함이 이 프로젝트에서 반복해서 나왔다
(CLAUDE.md "코드 리뷰로는 안 잡히는 결함"). 저장·복원·마이그레이션·재설치에
관련된 변경은 **반드시 아래 절차로 실기기에서 눈으로 확인한다.**

## 0. 이 환경의 함정 두 가지 (먼저 읽을 것)

**`adb`가 PATH에 없다.** `adb`를 그냥 치면 `command not found`가 난다.
항상 전체 경로로 부른다:

```bash
ADB=~/Library/Android/sdk/platform-tools/adb
```

**주 테스트 기기가 폴더블이라 화면이 2개다.** `screencap`에 화면 ID를 주지
않으면 PNG 앞에 경고 문구가 섞여 들어가 **파일이 깨진다**(이미지로 못 읽는다).
증상은 "PNG인데 JSON/text로 감지됨"이고, 원인은 화면 ID 누락이다.

## 1. 기기 확인

```bash
ADB=~/Library/Android/sdk/platform-tools/adb
flutter devices
$ADB devices
```

기대 결과 — 보통 4개가 잡힌다:

| 기기 | ID | 쓰임 |
|---|---|---|
| SM F966N (갤럭시 폴드, USB) | `R3CY90SHN4F` | **기본 선택.** 배선이 안정적이고 `adb`로 저장소 덤프까지 된다 |
| iPhone 16 Pro (**유선 USB**) | `00008140-001971541862201C` | iOS 특유 문제(키체인 잔존 등) 볼 때만. `flutter run` 으로 붙는다(2026-09-03 확인). 막히면 §2-1 |
| macOS 데스크톱 | `macos` | 실기기가 없을 때. 카메라·명함 스캔은 확인 불가 |
| Chrome (웹) | `chrome` | 레이아웃만 급히 볼 때. 네이티브 플러그인 대부분 안 돎 |

기기 ID는 사람마다 다르므로 `flutter devices` 출력에서 실제 값을 쓴다.
위 표의 ID는 이 저장소 주 개발자의 기기 값이다.

🚨 **아이폰을 「무선」이라고 적어 두었던 것은 틀렸다 — 2026-09-03 사용자 확인으로
유선(USB)이다.** 결론만 고치지 않고 경위를 남긴다(CLAUDE.md 4장): `flutter devices`
가 아이폰을 `wireless` 로 분류한 것을 보고 **한 세션이 실행 실패의 원인을 *"무선이라서"*
라고 단정**했고, PM 이 그대로 옮겨 적었다. 사용자 확인 결과 **처음부터 유선이었다**
(추가 475 ②, 그 세션이 자진 정정). 📌 **그 틀린 라벨이 이 표에 남아 있어서 2026-09-03
에 같은 오진이 한 번 더 나올 뻔했다** — 낡은 기록은 조용히 사람을 속인다.

## 2. 실행

```bash
cd /Volumes/X31/Claude/connection-trace-ai-v2-flutter
flutter run -d R3CY90SHN4F --debug
```

- **백그라운드로 돌리고 로그를 파일로 받는다.** `flutter run`은 붙어 있는
  동안 계속 출력하므로 포그라운드로 두면 막힌다.
- 첫 빌드는 Gradle이 몇 분 걸린다. 완료 판정은 로그에
  `Flutter run key commands.`가 뜨는 시점이다. 실패 감시는 함께 잡는다:

```bash
until grep -qE "Flutter run key commands|FAILURE|Gradle task .* failed|Error" "$LOG"; do sleep 3; done
```

- 붙어 있는 동안 `r`(핫 리로드) / `R`(핫 리스타트) / `q`(종료)가 쓸 수 있다.
- **테스터에게 줄 빌드는 이 방식으로 만들지 않는다.** debug 빌드에는 로그인
  화면에 "로그인 건너뛰기" 버튼이 그대로 보인다. 배포는 `tool/build_app.sh`.

## 2-1. 아이폰이 `Error launching application` 으로 막히면 — Xcode 를 먼저 올린다

```
Xcode build done.                    ← 빌드는 성공한다
The Dart VM Service was not discovered after 60 seconds...
Installing and launching...
Error launching application on ... iPhone
```

✅ **2026-09-03 해결됐다 — Xcode 를 업데이트하니 `flutter run` 으로 앱이 떴다.**
추가 475 ② 에 「원인 미상」으로 남아 있던 자리다. 확인 순서는 이랬다.

| 후보 | 어떻게 됐나 |
|---|---|
| 기기 잠금 | ❌ 지워졌다 — **화면이 잠기지 않은 상태**에서 같은 실패가 났다(사용자 확인) |
| 무선 연결 | ❌ 지워졌다 — **유선(USB)** 이었다. 이 후보는 애초에 `flutter devices` 의 `wireless` 표시를 보고 한 세션이 단정한 추측이었다 |
| **Xcode 가 기기의 iOS 를 지원 못 함** | ✅ **Xcode 를 올리니 앱이 떴다** |

⚠️ **실측한 것과 설명을 구분해 적는다**(CLAUDE.md 4장). **잰 것은 「Xcode 를
올리니 됐다」** 하나다. *"Xcode 가 기기의 iOS 를 지원하지 못해서"* 는 그것을 설명하는
가장 그럴듯한 이야기이고 — 컴파일은 되고 **설치·실행에서만** 막히는 증상과 맞고,
실패 로그에 `iOS 26` 이 언급됐다 — **기제 자체를 직접 재지는 않았다.**

📌 **그래서 다음에 또 막히면 Xcode 버전과 기기 iOS 버전을 먼저 맞춰 본다.**
`xcodebuild -version` 과 기기의 설정 → 일반 → 정보를 같이 본다.

### 그래도 남는 사실 — `debug` 빌드는 홈 화면에서 안 열린다

이건 위 문제와 **별개이고 여전히 참이다.** 디버그 모드는 `flutter run` 툴링이 붙어
있어야만 Flutter 엔진이 초기화되므로, 독립 실행하면
`Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode`
로 즉시 죽는다(`docs/planning/error-notes.md` 「증상 2」). 과거에 이걸 모르고 설치했다가
**사용자가 *"앱이 죽어요"* 라고 알려 줘서** 알았다.

**그러므로 `flutter run` 을 끊고도 앱을 홈 화면에서 열어야 한다면** — 명령을 끊으면
`flutter run` 으로 띄운 앱도 닫힌다 — `profile` 이나 `release` 로 빌드해 `devicectl`
로 깐다:

```bash
tool/build_app.sh ios profile                      # ① debug 아님
xcrun devicectl list devices                       # ② UDID 확인
xcrun devicectl device install app \
  --device <UDID> build/ios/Profile-iphoneos/Runner.app   # ③ ⚠️ 경로 주의
xcrun devicectl device process launch \
  --device <UDID> com.creamhouse.connectionsense   # ④ 또는 홈 화면에서 아이콘을 누른다
```

**함정 둘** (추가 475 ②):

| 무엇 | 어떻게 읽나 |
|---|---|
| `Build succeeded but the expected app … not found` | **빌드는 성공한 것이다.** profile 산출물이 `build/ios/iphoneos` 가 아니라 `build/ios/Profile-iphoneos` 에 나와서 그렇다. **실패로 읽으면 안 된다** |
| `device was not unlocked` | 기기 잠금을 풀고 다시 `launch` 한다 |

📌 `flutter clean` 은 습관적으로 돌리지 않는다 — `pod install` 부터 다시 돌아
2026-09-03 에 **빌드만 376초**를 썼다. 코드만 고친 경우엔 그냥 다시 돌린다.

## 3. 화면 보기 (스크린샷)

폴더블의 화면 ID를 먼저 확인한다:

```bash
$ADB shell dumpsys SurfaceFlinger --display-id
```

이 기기의 값:

| 화면 | ID | 해상도 |
|---|---|---|
| 내부(펼친) 화면 | `4630946449689556883` | 1968 x 2184 |
| 커버 화면 | `4630946872173396372` | 1080 x 2520 |

접혀 있으면 내부 화면은 까맣게 나온다. **까만 스크린샷은 "실행 실패"가 아니라
"그 화면이 꺼져 있음"일 수 있으니** 두 화면을 다 찍어보고 판단한다.

```bash
D=4630946449689556883
$ADB exec-out screencap -p -d $D > shot.png
file -b shot.png   # "PNG image data"가 나와야 정상
```

찍은 뒤에는 **반드시 Read로 이미지를 열어 눈으로 본다.** 파일이 생겼다는 것은
앱이 떴다는 증거가 아니다.

## 4. 조작하기

띄우기만 하고 끝내면 "진입점이 해석된다"는 것만 확인한 셈이다. 사용자가 볼
지점까지 실제로 눌러본다.

```bash
$ADB shell input tap <x> <y>      # 좌표는 내부 화면(1968x2184) 기준
$ADB shell input text "검색어"
$ADB shell input keyevent KEYCODE_BACK
```

하단 탭 좌표(내부 화면, 세로):

| 탭 | 좌표 | 뜨는 화면 |
|---|---|---|
| 주변 | `330 2003` | "주변 인맥" — 감지된 사람 수, 검색창 |
| 명함 | `981 2003` | "명함 지갑" — 등록된 명함 목록 |
| 설정 | `1634 2003` | "설정" — 계정, 위치 서비스, 감지 반경, 앱 버전 |

탭 한 번마다 1.5초쯤 기다린 뒤 찍는다.

## 5. 정상 판정 기준

- 하단 탭 3개가 모두 열리고 각 화면 제목이 위 표와 맞는다.
- 데이터가 없을 때 **빈 상태가 그대로 보인다** — "주변에 감지된 인맥이 없습니다",
  "아직 등록된 명함이 없습니다". 여기에 예시 인물이 보이면 그 자체가 결함이다
  (CLAUDE.md "가짜 데이터를 만들지 않는다").
- 로그에 Dart 예외가 없다:

```bash
grep -nE "EXCEPTION|Unhandled|FlutterError|E/flutter|RenderFlex|overflow" "$LOG"
```

- `I/AdrenoVK-0: Shader compilation failed` / `Pipeline create failed`는
  **무시해도 된다.** Android GPU 드라이버가 찍는 것으로 앱 문제가 아니다.

## 6. 더 깊이 볼 때

- 어느 빌드인지 확인: 앱의 **설정 → 앱 버전**에 커밋 해시가 박혀 있다
  (`tool/build_app.sh`로 빌드한 경우). 낡은 빌드를 버그로 오인한 전례가 있다.
- 기기 저장소 실물 덤프·서버 실물 조회 절차는 `tool/README.md`와
  `docs/planning/sessions/2026-08.md` "0-2"에 있다. 저장·복원 관련 변경은 화면만 보고
  끝내지 말고 여기까지 간다.
- 앱 패키지명: `com.creamhouse.connectionsense`

## 7. 안 될 때

| 증상 | 원인 | 조치 |
|---|---|---|
| `adb: command not found` | PATH에 없음 | 0절의 전체 경로 사용 |
| 스크린샷이 이미지로 안 읽힘 | 화면 ID 누락 | `-d <display-id>` 추가 |
| 내부 화면이 까맣게 나옴 | 기기가 접혀 있음 | 커버 화면 ID로 찍거나 사용자에게 펴 달라고 요청 |
| iPhone이 목록에 안 뜸 | 케이블·신뢰 설정·Xcode 연결 문제 | 케이블을 다시 꽂고 기기에서 「이 컴퓨터를 신뢰」를 확인. 안 되면 Android로 진행 |
| iPhone에서 `Error launching application` | **Xcode 가 기기 iOS 보다 낡았을 때 이렇게 된다**(2026-09-03 실측) | **Xcode 를 업데이트한다 → §2-1.** 빌드는 성공했는지(`Xcode build done`) 먼저 본다 |
| Gradle 빌드 실패 | 캐시 문제가 잦다 | `flutter clean` 후 재시도 |

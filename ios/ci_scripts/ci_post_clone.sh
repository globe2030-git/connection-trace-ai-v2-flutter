#!/bin/sh
# Xcode Cloud가 저장소를 clone한 직후에 도는 스크립트.
#
# ── 왜 필요한가 (2026-09-04, Archive - iOS 실패) ────────────────────────────
# Xcode Cloud는 clone한 뒤 곧바로 xcodebuild를 돌린다. 그런데 빌드가 이렇게
# 죽었다:
#
#   Could not resolve package dependencies: the package at
#   '.../ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage'
#   cannot be accessed (... doesn't exist in file system)
#
# 🚨 이것은 코드가 깨진 것이 아니라 **Flutter를 돌리는 단계가 없던 것**이다.
# `ios/Flutter/ephemeral/`은 `ios/.gitignore:22`로 제외돼 있고, 그 안의
# FlutterGeneratedPluginSwiftPackage는 `flutter pub get`이 **만들어 내는**
# 것이라 clone 결과에는 없다. 그런데 `Runner.xcodeproj`는 그것을
# XCLocalSwiftPackageReference로 참조한다(project.pbxproj의
# XCLocalSwiftPackageReference 절). 그래서 xcodebuild가 먼저 죽는다.
#
# 📌 로컬에서 안 터진 이유는 그 폴더가 **디스크에 남아 있어서**다. 저장소에
#    있어서가 아니다 — 이 구분이 없으면 "로컬은 되는데?"에서 막힌다.
#
# ⚠️ pubspec.yaml은 `enable-swift-package-manager: false`다(Firebase 최소
#    iOS 버전 충돌 때문, fbddcd5c). 그래서 *"SPM을 껐으니 pub get이 저 패키지를
#    안 만들 것"*이라고 볼 수 있는데 **실측하니 만든다**(2026-09-04: Packages/를
#    치우고 `flutter pub get` → 재생성됨). 그래서 pbxproj는 건드리지 않았다.
#
# ── 이 스크립트가 하지 않는 것 ─────────────────────────────────────────────
# `pod install`을 따로 부르지 않는다. `flutter build ios --config-only`가
# 반환하기 **전에** processPodsIfNeeded를 부른다(flutter_tools의
# ios/mac.dart:362 → :363). 즉 이미 돈다.
set -e

# 로컬과 같은 태그로 고정한다. 3.44.8의 리비전은 058e0af2c2로, 2026-09-04에
# 개발 노트북의 flutter와 같은 것임을 확인했다. ⚠️ 로컬 Flutter를 올릴 때는
# 이 줄도 함께 올린다 — 안 맞으면 CI만 다른 SDK로 빌드된다.
FLUTTER_VERSION=3.44.8

echo "▶ Flutter $FLUTTER_VERSION 설치"
git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"
flutter --version

# iOS 아티팩트를 미리 받는다.
#
# ⚠️ 처음에는 이 줄을 뺐다 — `build ios --config-only` 가 필요한 것을 알아서
# 받는다고 봤기 때문이다. 그런데 2026-09-04 에 #821·#822 두 빌드가 연속으로
# `Command PhaseScriptExecution failed` 로 죽었고, 그 단계는
# `xcode_backend.sh build`(= Flutter SDK 를 직접 부르는 자리)다.
# 🚨 **아직 원인을 확정하지 못했다** — 로그의 실제 실패 줄을 못 봤다. 그래서
# 이 줄은 「고쳤다」가 아니라 **「후보 하나를 지웠다」**로 읽어야 한다.
# 아래 진단 출력이 다음 빌드에서 나머지를 가른다.
flutter precache --ios

cd "$CI_PRIMARY_REPOSITORY_PATH"

echo "▶ flutter pub get — ephemeral/Packages가 여기서 생긴다"
flutter pub get

# 커밋 해시를 앱에 심는다. 없으면 「설정 → 앱 버전」으로 어느 빌드인지 갈리지
# 않아, 이미 고친 것을 "아직 그대로"라고 오인한다(backlog 추가 77·P1-30).
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

# 지도·주소·소셜 로그인 키. tool/build_app.sh와 **같은 목록**이어야 한다.
#
# 🚨 이 키들은 Xcode Cloud 워크플로의 환경 변수에 등록해야 들어간다
#    (App Store Connect → Xcode Cloud → 워크플로 편집 → Environment Variables).
#    등록하지 않으면 빌드는 성공하는데 **로그인 화면에 카카오·네이버 버튼이
#    아예 안 보이고**(sns_auth_provider.dart의 isAvailable) 지도는 좌표가
#    안 온다. 08-24에 안드로이드·아이폰에서 한 번씩 실제로 빠졌다.
#    ⚠️ 그래서 아래에서 빠진 키를 **경고로 남긴다** — 로그를 안 보면 못 잡는다.
DEFINES=""
for KEY_NAME in VWORLD_KEY KAKAO_JS_KEY KAKAO_REST_KEY NAVER_CLIENT_ID JUSO_SEARCH_KEY JUSO_COORD_KEY; do
  KEY_VALUE="$(eval "printf '%s' \"\${$KEY_NAME:-}\"")"
  if [ -n "$KEY_VALUE" ]; then
    DEFINES="$DEFINES --dart-define=$KEY_NAME=$KEY_VALUE"
    echo "  $KEY_NAME: 환경 변수에서 넘김"
  else
    echo "  ⚠️ $KEY_NAME: 없음 — 이 키가 필요한 기능이 빠진 빌드가 됩니다"
  fi
done

echo "▶ flutter build ios --config-only  (커밋 $COMMIT)"
# --config-only: Generated.xcconfig에 --dart-define을 기록하고 pod install까지
# 한 뒤 멈춘다. 실제 컴파일·서명은 Xcode Cloud의 Archive 단계가 한다.
#
# 🚨 그래서 Xcode에서 Product → Archive를 직접 누르면 안 된다 — 그 경로는
#    --dart-define을 거치지 않아 키가 하나도 안 들어간다(테스터 배포 런북 6장).
# shellcheck disable=SC2086  # DEFINES는 공백 없는 단일 옵션들이라 분리 확장이 맞다
flutter build ios --release --no-codesign --config-only \
  --dart-define=GIT_COMMIT="$COMMIT" $DEFINES

# ── 진단 출력 ─────────────────────────────────────────────────────────────
#
# 🚨 이 블록은 **고치기 위한 것이 아니라 다음 실패를 읽기 위한 것**이다.
# Xcode Cloud 실패 메일은 "PhaseScriptExecution failed" 한 줄뿐이라 어느
# 단계인지 알 수 없다. Archive 가 죽기 전에 아래 넷이 로그에 찍혀 있으면
# 원인을 재지 않고도 가를 수 있다.
#
# ⚠️ `set -e` 아래이므로 실패해도 빌드를 멈추지 않게 `|| true` 를 붙인다 —
#    진단이 빌드를 죽이면 본말이 뒤집힌다.
echo "── 진단 ─────────────────────────────"
echo "FLUTTER_ROOT(기록된 값): $(grep '^FLUTTER_ROOT=' ios/Flutter/Generated.xcconfig || echo '🚨 없음')"

if [ -d ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage ]; then
  echo "SPM 패키지: ✅ 있음"
else
  echo "SPM 패키지: 🚨 없음 — 이게 없으면 패키지 해결 단계에서 죽는다"
fi

if [ -d ios/Pods ]; then
  echo "Pods 폴더: ✅ 있음"
else
  echo "Pods 폴더: 🚨 없음 — pod install 이 안 돈 것이다"
fi

# 🚨 Runner 타깃의 Run Script 둘이 이 둘을 비교해 어긋나면 그 자리에서
#    `exit 1` 을 낸다("The sandbox is not in sync with the Podfile.lock").
#    PhaseScriptExecution 실패의 가장 흔한 원인이라 여기서 미리 가른다.
if diff -q ios/Podfile.lock ios/Pods/Manifest.lock >/dev/null 2>&1; then
  echo "Podfile.lock == Manifest.lock: ✅ 일치"
else
  echo "Podfile.lock == Manifest.lock: 🚨 불일치 — Archive 가 여기서 죽는다"
fi
echo "─────────────────────────────────────"

echo "✅ ci_post_clone 완료 — 커밋 $COMMIT"

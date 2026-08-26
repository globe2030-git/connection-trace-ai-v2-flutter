#!/usr/bin/env bash
# 커밋 해시를 심어서 앱을 빌드한다.
#
# 왜 이 스크립트를 쓰나(backlog 추가 77, P1-30): 기기에 깔린 앱이 어느 시점의
# 코드인지 알 수 없어, 이미 고친 문제를 "아직 그대로"라고 오인한 적이 있다.
# 설정 → 앱 버전에 커밋 해시가 함께 뜨면 그 자리에서 확정된다.
#
# `flutter build`를 직접 쓰면 해시가 안 들어간다(버전·빌드번호만 표시됨).
# 손으로 --dart-define을 붙이는 건 잊기 쉬우니 이 스크립트를 쓴다.
#
# 사용법:
#   tool/build_app.sh apk release     # Android 릴리스(테스터 배포용)
#   tool/build_app.sh apk debug       # Android 디버그(기기 저장소 점검용)
#   tool/build_app.sh ios release     # iOS 릴리스
#   tool/build_app.sh appbundle release
#
#   세 번째 인자로 appcheck-debug를 주면 App Check를 debug 제공자로 빌드한다:
#   tool/build_app.sh ios release appcheck-debug
#   tool/build_app.sh apk release appcheck-debug
#
#   세 번째 인자 measure: OCR 측정 빌드(추가 405). 명함별 인식 줄·이름 경로를
#   기기 파일로 남기고 등록은 하지 않는다. 릴리스에는 절대 쓰지 않는다.
#   tool/build_app.sh apk release measure
#
#   세 번째 인자로 cleanup을 주면 명함 폼의 필수 입력 검증을 전부 푼
#   정리용 빌드가 나온다(card_form_validation.dart 참고). 테스터 배포·
#   스토어 업로드에는 쓰지 않는다. appcheck-debug와 동시에 쓸 필요는
#   없다 — 둘 중 하나만 준다.
#   tool/build_app.sh apk debug cleanup
#
#   세 번째 인자로 groups를 주면 그룹 기능(추가 427) UI를 켠 채로 빌드한다
#   (group_model.dart의 kGroupsFeatureEnabled 참고). 방침 v2.3 시행일
#   (2026-08-30) 전 테스터 빌드는 이 인자 없이(기본 꺼짐) 빌드한다 — 개발·
#   시행일 확인용으로만 쓴다.
#   tool/build_app.sh apk debug groups
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-apk}"
MODE="${2:-release}"

case "$MODE" in
  release|debug|profile) ;;
  *) echo "빌드 모드는 release / debug / profile 중 하나여야 합니다: $MODE" >&2; exit 2 ;;
esac

# 릴리스 서명 확인 — 워크트리마다 다르다.
#
# android/key.properties 는 .gitignore 대상이라 git 이 워크트리 사이로 옮겨
# 주지 않는다. 없으면 build.gradle.kts 가 **경고 없이 debug 키로 폴백**한다
# (android/app/build.gradle.kts 의 buildTypes.release 참고). 그 폴백은
# `flutter run --release` 가 서명 파일 없는 환경에서도 돌게 하려고 일부러
# 둔 것이라 빼지 않는다 — 대신 배포용 산출물을 만드는 이 진입점에서 막는다.
#
# 2026-08-25 실측: 워크트리 15개 중 key.properties 가 있는 곳은 4개뿐이었다.
# 즉 아무 워크트리에서나 릴리스를 빌드하면 debug 서명본이 나올 확률이
# 그때 기준 11/15 였다. 2026-08-16 기록은 "넷 중 하나"였으니 나빠졌다.
#
# debug 서명본은 스토어에 올라가지 않고, 업로드 키로 서명한 기존 설치본
# 위에 덮이지도 않는다. 그런데 빌드는 성공하므로 파일을 손에 쥘 때까지
# 모른다 — 그래서 "경고"가 아니라 "중단"이다.
if [ "$MODE" = "release" ] && { [ "$TARGET" = "apk" ] || [ "$TARGET" = "appbundle" ]; }; then
  if [ ! -f android/key.properties ]; then
    here="$(pwd)"
    cat >&2 <<SIGNERR
🚨 릴리스를 빌드할 수 없습니다 — android/key.properties 가 없습니다.

   이대로 빌드하면 빌드는 성공하지만 debug 키로 서명된 산출물이 나옵니다.
   스토어에 올라가지 않고, 기존 설치본 위에 덮이지도 않습니다.

   지금 위치: $here

   해결:
     · 본체 워크트리에서 빌드하거나
     · 이 워크트리에 android/key.properties 를 두십시오
       (업로드 키 자체는 ~/keys/connectionsense-upload.jks 에 있습니다)

   ⚠️ 서명 파일을 워크트리마다 복사하면 비밀번호가 담긴 파일이 그만큼
      늘어납니다. 릴리스는 한 곳에서만 빌드하는 편이 낫습니다.

   debug/profile 빌드는 이 검사를 받지 않습니다.
SIGNERR
    exit 3
  fi
  echo "✅ 릴리스 서명: android/key.properties 확인됨"
fi

COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  # 커밋되지 않은 변경이 섞여 있으면 해시만으로는 코드를 특정할 수 없다.
  COMMIT="${COMMIT}+수정중"
  echo "⚠️  커밋되지 않은 변경이 있습니다 — 버전 표시에 '+수정중'을 붙입니다."
fi

# App Check 제공자 선택. 스토어(Play/App Store)를 거치지 않는 빌드는 정식
# 무결성 검증기(Play Integrity / App Attest)를 통과할 수 없어서, 이 플래그로
# debug 제공자를 쓰고 기기별 디버그 토큰을 Firebase에 등록해 쓴다.
# 근거와 주의사항은 lib/core/services/app_check_service.dart 주석 참고.
# ⚠️ **x86_64(에뮬레이터용)를 뺀다** (2026-08-17 사용자 결정).
#
# OpenCV가 들어오면서 ABI마다 네이티브가 붙는다. 실측으로 x86_64가 APK의
# **103.6MB**를 차지했다(기성 OpenCV 시절 전체 230MB 중). 스토어는 기기에 맞는
# ABI 하나만 내려보내므로 **실사용자 용량과는 무관**하지만, **테스터 배포는
# APK를 통째로 보내서** 그대로 걸린다 — 지금이 테스터 배포 단계다.
#
# 잃는 것: **에뮬레이터에서 앱을 못 돌린다.**
# ⚠️ 다만 이 저장소는 ML Kit이 arm64 시뮬레이터를 지원하지 않아 **이미
# 에뮬레이터에서 OCR을 못 돌린다.** OCR 말고 다른 화면은 돌아가므로
# "아예 못 쓴다"는 아니다 — 잃는 범위가 그만큼이다.
#
# ⚠️ **`build.gradle.kts`의 `ndk { abiFilters }`로는 안 된다.** Flutter가
# ABI를 `--target-platform`으로 직접 정하기 때문에 그쪽 설정은 덮인다
# (2026-08-17 실측 — 넣고 빌드했더니 x86_64가 그대로 들어 있었다).
ABI_FLAG=""
if [ "$TARGET" = "apk" ] || [ "$TARGET" = "appbundle" ]; then
  ABI_FLAG="--target-platform=android-arm,android-arm64"
fi

EXTRA_DEFINES=""
if [ "${3:-}" = "appcheck-debug" ]; then
  EXTRA_DEFINES="--dart-define=APP_CHECK_DEBUG=true"
  echo "⚠️  App Check를 debug 제공자로 빌드합니다 — 스토어 업로드용 빌드에는 쓰지 마세요."
elif [ "${3:-}" = "cleanup" ]; then
  EXTRA_DEFINES="--dart-define=RELAX_REQUIRED_FOR_CLEANUP=true"
elif [ "${3:-}" = "measure" ]; then
  # OCR 측정 빌드(추가 405). 명함별 인식 줄과 이름 경로를 기기 파일로 남기고
  # **등록은 하지 않는다.** 파서를 고칠 때 명함 단위로 전후를 대조하는 용도다.
  #
  # ⚠️ 떨군 파일에는 OCR 원문(제3자 개인정보)이 담긴다. 꺼낸 뒤 기기 쪽 파일을
  # 지우고, 보관은 명함데이터/(700) 규칙을 따른다.
  EXTRA_DEFINES="--dart-define=OCR_MEASURE_DUMP=true"
  echo "⚠️  필수 입력 검증이 풀린 정리용 빌드입니다 — 테스터 배포·스토어 업로드에 쓰지 마세요."
elif [ "${3:-}" = "groups" ]; then
  EXTRA_DEFINES="--dart-define=GROUPS_FEATURE=true"
  echo "⚠️  그룹 기능(추가 427) UI를 켠 채로 빌드합니다 — 방침 v2.3 시행일(2026-08-30) 전 테스터 배포에는 쓰지 마세요."
elif [ -n "${3:-}" ]; then
  echo "세 번째 인자는 appcheck-debug · cleanup · measure · groups만 쓸 수 있습니다: ${3}" >&2; exit 2
fi

# 지도·좌표 키는 저장소에 안 넣는다(nearby_map_view.dart·address_search_view.dart
# 주석 참고). 환경변수에 있으면 자동으로 넘기고, 없으면 조용히 건너뛴다 —
# 없어도 앱은 돈다(브이월드 없으면 OSM 타일, 카카오 없으면 좌표만 안 옴).
#
# ⚠️ 예전에는 이 스크립트가 키를 안 넘겨서 **손으로 --dart-define을 붙여야**
# 했고, 그러면 잊기 쉽다. 이 스크립트를 쓰는 이유가 원래 그것이다(위 9행).
# 소셜 로그인 키(KAKAO_REST_KEY·NAVER_CLIENT_ID)도 같은 방식으로 넘긴다.
#
# ⚠️ **비밀값이 아니다.** 인증 화면 주소에 그대로 실려 나가는 공개 식별자라
# 숨길 수 없다. 안전장치는 콘솔에 등록한 redirect_uri다. 진짜 비밀값
# (client_secret)은 서버(Cloud Functions 비밀값)에만 있고 앱에 넣지 않는다.
#
# 📌 키가 없으면 **로그인 화면에서 그 버튼이 아예 안 보인다**
# (sns_auth_provider.dart 의 isAvailable). 눌러도 안 되는 버튼을 두지 않기
# 위해서다 — 그래서 키를 빠뜨리면 "버튼이 없다"로 나타난다.
for KEY_NAME in VWORLD_KEY KAKAO_JS_KEY KAKAO_REST_KEY NAVER_CLIENT_ID JUSO_SEARCH_KEY JUSO_COORD_KEY; do
  KEY_VALUE="$(eval "printf '%s' \"\${$KEY_NAME:-}\"")"
  if [ -n "$KEY_VALUE" ]; then
    EXTRA_DEFINES="$EXTRA_DEFINES --dart-define=$KEY_NAME=$KEY_VALUE"
    echo "  $KEY_NAME: 환경변수에서 넘김"
  else
    echo "  $KEY_NAME: 없음 (건너뜀)"
  fi
done

echo "빌드: $TARGET ($MODE)  커밋: $COMMIT"
# shellcheck disable=SC2086  # ABI_FLAG·EXTRA_DEFINES는 공백 없는 단일 옵션이라 분리 확장이 맞다
flutter build "$TARGET" "--$MODE" --dart-define=GIT_COMMIT="$COMMIT" $ABI_FLAG $EXTRA_DEFINES

echo
echo "완료. 설정 → 앱 버전에서 '$COMMIT'이 보이면 이 빌드입니다."

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
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-apk}"
MODE="${2:-release}"

case "$MODE" in
  release|debug|profile) ;;
  *) echo "빌드 모드는 release / debug / profile 중 하나여야 합니다: $MODE" >&2; exit 2 ;;
esac

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
EXTRA_DEFINES=""
if [ "${3:-}" = "appcheck-debug" ]; then
  EXTRA_DEFINES="--dart-define=APP_CHECK_DEBUG=true"
  echo "⚠️  App Check를 debug 제공자로 빌드합니다 — 스토어 업로드용 빌드에는 쓰지 마세요."
elif [ -n "${3:-}" ]; then
  echo "세 번째 인자는 appcheck-debug만 쓸 수 있습니다: ${3}" >&2; exit 2
fi

echo "빌드: $TARGET ($MODE)  커밋: $COMMIT"
# shellcheck disable=SC2086  # EXTRA_DEFINES는 공백 없는 단일 옵션이라 분리 확장이 맞다
flutter build "$TARGET" "--$MODE" --dart-define=GIT_COMMIT="$COMMIT" $EXTRA_DEFINES

echo
echo "완료. 설정 → 앱 버전에서 '$COMMIT'이 보이면 이 빌드입니다."

#!/usr/bin/env bash
# 커넥션센스 대표 사이트(connectionsense.co.kr)의 배포용 디렉터리를 만든다.
#
# 왜 이 스크립트가 필요한가: 대표 사이트(docs/site)와 법적 고지(docs/legal)는
# 원본이 서로 다른 두 디렉터리다. 법적 고지 원본은 **하나만** 둬야 한다 —
# connection-sense.web.app(legal 타깃)이 이미 이용자·구글 플레이 콘솔·카카오·
# 네이버에 등록돼 있어서 절대 없애면 안 되기 때문이다(CLAUDE.md 4장). 그래서
# docs/legal 을 docs/site 밑으로 옮기지 않고, 배포 직전에 이 스크립트가
# 결과 디렉터리 아래 legal/ 로 "복사해 합친다." 원본은 항상 docs/legal 하나다.
#
# 결과 디렉터리(기본 build/site)는 빌드 산출물이라 커밋하지 않는다.
# 루트 .gitignore 의 `/build/` 가 이미 덮는다(실측 확인됨).
#
# 사용법:
#   tool/build_site.sh                # build/site 에 만든다
#   tool/build_site.sh <출력경로>      # 다른 경로에 만든다(테스트용)
#
# firebase.json 의 site 타깃 predeploy 훅이 배포 직전마다 이 스크립트를
# 돌린다 — 사람이 직접 돌리는 것은 로컬 확인용이다.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/build/site}"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# docs/site 를 그대로 복사한다(대표 홈페이지 원본).
cp -R "$REPO_ROOT/docs/site/." "$OUT_DIR/"

# docs/legal 을 legal/ 아래로 복사한다(법적 고지 원본 — 옮기지 않고 더한다).
mkdir -p "$OUT_DIR/legal"
cp -R "$REPO_ROOT/docs/legal/." "$OUT_DIR/legal/"

# README.md 는 문서지 배포 대상이 아니다(firebase.json 의 ignore 목록과
# 같은 이유). docs/legal 에는 지금 README.md 가 없지만, 나중에 생겨도
# 조용히 배포되지 않도록 여기서도 지운다.
rm -f "$OUT_DIR/README.md" "$OUT_DIR/legal/README.md"

echo "빌드 완료: $OUT_DIR"
find "$OUT_DIR" -maxdepth 2 -type f | sort

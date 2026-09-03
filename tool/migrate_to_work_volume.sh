#!/usr/bin/env bash
# 외장 X31 아래 개발 자료 전체를 내장 Work 볼륨으로 옮긴다.
#
# 왜 이 스크립트를 쓰나: 손으로 Finder 로 끌어다 놓으면 **세 가지가 조용히
# 깨진다.** 셋 다 옮긴 직후에는 티가 안 나고, 며칠 뒤 엉뚱한 증상으로
# 나타난다(CLAUDE.md 4장 "코드는 맞는데 실물이 틀린" 유형).
#
#   ① git worktree      .git 파일과 .git/worktrees/*/gitdir 에 **절대경로**가
#                       박혀 있다. 옮기면 워크트리가 통째로 죽는다.
#   ② .dart_tool        package_config.json 이 패키지 경로를 절대경로로 적는다.
#                       옮기면 flutter 가 옛 경로를 계속 찾는다.
#   ③ 명함데이터 권한    제3자 개인정보라 700 이어야 한다(CLAUDE.md 4장).
#                       복사 방식에 따라 755 로 풀린다.
#
# 그리고 **git 에 없는 것**이 있다. key.properties(서명), .env, scan_result*.tsv
# (제3자 개인정보), stash, 원격에 push 안 된 브랜치 — 이것들은 원격에서 다시
# 받을 수 없으므로 옮기기 전에 목록으로 확인해야 한다. 그게 survey 단계다.
#
# 사용법 — **순서대로** 돌린다:
#
#   tool/migrate_to_work_volume.sh survey            # ① 읽기만. 무엇이 있는지 조사
#   tool/migrate_to_work_volume.sh copy --yes        # ② 복사(원본은 그대로 둔다)
#   tool/migrate_to_work_volume.sh repair            # ③ 옮겨서 깨진 것 고치기
#   tool/migrate_to_work_volume.sh verify            # ④ 원본과 대조
#   tool/migrate_to_work_volume.sh sync              # ⑤ GitHub 과 맞춘다(계획만)
#
# 🚨 **이 스크립트는 아무것도 지우지 않는다.** X31 은 손대지 않는다.
#    복사가 끝나고 verify 가 통과한 뒤에 사람이 직접 정리한다.
#
# 경로를 바꾸려면:
#   CS_SRC=/Volumes/X31/Claude CS_DST=/Volumes/Work tool/migrate_to_work_volume.sh survey
set -uo pipefail

SRC="${CS_SRC:-/Volumes/X31/Claude}"
DST="${CS_DST:-/Volumes/Work}"
MODE="${1:-survey}"
shift || true

ASSUME_YES=0
DO_FETCH=0
ONLY=()
SYNC_REMOTE=""
REPORT=""
for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --fetch) DO_FETCH=1 ;;
    --out=*) REPORT="${arg#--out=}" ;;
    --only=*) IFS=',' read -r -a ONLY <<< "${arg#--only=}" ;;
    --remote=*) SYNC_REMOTE="${arg#--remote=}" ;;
    *) echo "모르는 인자: $arg" >&2; exit 2 ;;
  esac
done

# ─────────────────────────────────────────────────────────────────────────────
# 공통

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

# 보고서를 파일로도 남긴다 — 조사 결과를 눈으로만 보면 다음에 또 조사해야 한다.
#
# 🚨 파일 이름에 **시각**을 넣는다. 날짜+단계만 쓰면 같은 날 두 번 돌릴 때 **나중
#    실행이 앞 기록을 조용히 덮는다.** 2026-09-04 에 실제로 그랬다 — 전체 copy 로그가
#    뒤이은 `--only` 실행에 덮여, 무엇이 복사됐는지 되짚을 수 없게 됐다.
#    ⚠️ 덮어쓴 것은 「틀린 기록」이 아니라 **없어진 기록**이라 더 나쁘다.
if [ -z "$REPORT" ]; then
  STAMP="$(date +%Y-%m-%d_%H%M%S)"
  if [ -d "$DST" ] && [ -w "$DST" ]; then
    REPORT="$DST/이전보고서_${STAMP}_${MODE}.txt"
  else
    REPORT="$HOME/X31이전보고서_${STAMP}_${MODE}.txt"
  fi
fi

need_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    red "이 스크립트는 macOS 전용이다 — ditto·diskutil·BSD stat 을 쓴다."
    red "현재: $(uname -s)"
    exit 2
  fi
}

# 최상위에서 건너뛸 시스템 항목. macOS 볼륨 루트에는 항상 있다.
skip_top() {
  case "$1" in
    .Spotlight-V100|.fseventsd|.Trashes|.TemporaryItems|.DocumentRevisions-V100|\
    .DS_Store|.apdisk|lost+found|.PKInstallSandboxManager*|.vol) return 0 ;;
  esac
  return 1
}

# ONLY 가 지정되면 그 목록에만 손댄다.
in_scope() {
  [ "${#ONLY[@]}" -eq 0 ] && return 0
  local n
  for n in "${ONLY[@]}"; do [ "$n" = "$1" ] && return 0; done
  return 1
}

kb_of()    { du -sk "$1" 2>/dev/null | cut -f1; }
human_kb() { awk -v k="$1" 'BEGIN{ if(k>1048576) printf "%.1fGB", k/1048576; else if(k>1024) printf "%.0fMB", k/1024; else printf "%dKB", k }'; }

# 🚨 세는 법은 **하나만** 둔다. 2026-09-03 시험에서 위쪽 표는 .dart_tool 을 세고
#    아래 유실 목록은 빼서, **유실이 0건인데도 「다르다」** 가 떴다 — 헛경보로 verify 가
#    실패로 끝났다(CLAUDE.md 「세는 도구가 못 보는 것」). 그래서 개수·바이트·유실 목록이
#    전부 **같은 목록**을 쓴다.
#
# 다시 만들어지는 것들은 애초에 세지 않는다 — repair 가 지우므로 세면 전부 유실로 나온다.
walk() {
  ( cd "$1" 2>/dev/null || exit 0
    find . \
      \( -type d \( -name .dart_tool -o -name build -o -name Pods \
                    -o -name node_modules -o -name .gradle \) -prune \) -o \
      \( \( -type f -o -type l \) ! -name .DS_Store -print \) ) 2>/dev/null
}
list_rel()  { walk "$1" | LC_ALL=C sort; }
rel_count() { walk "$1" | wc -l | tr -d ' '; }
# ⚠️ 파일명에 개행이 들어 있으면 이 합계는 틀린다. 그때는 아래 유실 목록이 잡는다.
rel_bytes() {
  ( cd "$1" 2>/dev/null || exit 0
    walk . | tr '\n' '\0' | xargs -0 stat -f%z 2>/dev/null ) \
  | awk '{s+=$1} END{printf "%d", s+0}'
}

# 파일 안의 옛 볼륨 경로를 새 볼륨 경로로 바꾼다. 권한·소유를 유지하려고
# 덮어쓰기(cat >)로 되돌린다 — sed -i 는 macOS 와 GNU 의 문법이 다르다.
rewrite_path_in() {
  local f="$1" t
  t="$(mktemp)" || return 1
  if sed "s|$SRC|$DST|g" "$f" > "$t" && ! cmp -s "$f" "$t"; then
    cat "$t" > "$f"; rm -f "$t"; return 0
  fi
  rm -f "$t"; return 1
}

# 원본 쪽 git 연결 파일들의 체크섬 목록. repair 전후로 비교해 **원본 무개변**을 잰다.
snapshot_src_git() {
  find "$SRC" -maxdepth 8 \( \( -name .git -type f \) -o \( -path '*/.git/worktrees/*/gitdir' -type f \) \) 2>/dev/null \
    | LC_ALL=C sort | while read -r f; do
        printf '%s  %s\n' "$(cksum < "$f" 2>/dev/null | awk '{print $1}')" "$f"
      done
}

# ─────────────────────────────────────────────────────────────────────────────
# 저장소 찾기 — .git 은 폴더(본체)일 수도 파일(워크트리)일 수도 있다

find_repos() {
  # ① 보통 저장소와 워크트리 — .git 은 폴더(본체)일 수도 파일(워크트리)일 수도 있다.
  #    깊이 6 까지 — Claude/<repo>/.claude/worktrees/<name>/.git 을 잡으려면 필요하다.
  find "$SRC" -maxdepth 6 \( -name .git \) \( -type d -o -type f \) 2>/dev/null \
    | while read -r g; do dirname "$g"; done
  # ② 베어 저장소 — **`.git` 이라는 이름이 없다.** 이름으로 찾으면 통째로 놓친다
  #    (2026-09-03 시험 트리에서 upstream.git 을 「git 아닌 폴더」로 잘못 분류했다).
  #    그래서 이름이 아니라 **구조**로 판정한다: objects/ + HEAD + refs/ 가 함께 있는 곳.
  find "$SRC" -maxdepth 6 -type d -name objects 2>/dev/null | while read -r o; do
    local d; d="$(dirname "$o")"
    case "$d" in */.git) continue ;; esac      # 보통 저장소의 .git 은 ①이 이미 잡았다
    [ -f "$d/HEAD" ] && [ -d "$d/refs" ] && echo "$d"
  done
}
# 위 목록을 한 번만 만들어 두고 재사용한다 — 두 번 세면 두 번 어긋난다.
REPO_LIST=""
load_repos() { REPO_LIST="$(find_repos | sort -u)"; }

# 어떤 경로가 이미 알려진 저장소 안에 있는지 — 「git 밖 폴더」를 가릴 때 쓴다.
under_repo() {
  local q="$1" r
  while read -r r; do
    [ -z "$r" ] && continue
    case "$q" in "$r"|"$r"/*) return 0 ;; esac
  done <<< "$REPO_LIST"
  return 1
}

remote_kind() {
  # 원격 URL 을 보고 GitHub / GitLab / 기타로 가른다.
  # 회사 GitLab 은 자체 호스팅일 수 있어 호스트명에 gitlab 이 없을 수도 있다 —
  # 그래서 **분류하지 못한 것은 「기타」로 그대로 보여 준다.** 숨기지 않는다.
  case "$1" in
    *github.com*) echo "GitHub" ;;
    *gitlab*)     echo "GitLab" ;;
    *)            echo "기타" ;;
  esac
}

survey_repo() {
  local p="$1" name="$2"
  local gitfile="$p/.git" kind="본체"
  [ -f "$gitfile" ] && kind="워크트리"
  if [ "$(git -C "$p" rev-parse --is-bare-repository 2>/dev/null)" = "true" ]; then
    kind="베어"
  fi

  echo "  종류      : $kind"
  echo "  크기      : $(human_kb "$(kb_of "$p")")"

  local br
  br="$(git -C "$p" branch --show-current 2>/dev/null)"
  echo "  브랜치    : ${br:-（분리 상태 또는 브랜치 없음）}"
  echo "  HEAD      : $(git -C "$p" rev-parse --short HEAD 2>/dev/null || echo '?')"

  # ── 원격: GitHub / GitLab 비교의 출발점
  local had_remote=0
  while read -r rname rurl _; do
    [ -z "${rname:-}" ] && continue
    had_remote=1
    echo "  원격      : $rname → $rurl   [$(remote_kind "$rurl")]"
  done < <(git -C "$p" remote -v 2>/dev/null | awk '$3=="(fetch)"')
  if [ "$had_remote" -eq 0 ]; then
    echo "  원격      : ⚠️ 없음 — 이 저장소는 **여기에만 있다**"
  fi

  if [ "$DO_FETCH" -eq 1 ]; then
    git -C "$p" fetch --all --quiet 2>/dev/null \
      && echo "  fetch     : 방금 갱신함" \
      || echo "  fetch     : ⚠️ 실패(네트워크·인증) — 아래 비교는 낡은 값이다"
  else
    echo "  fetch     : 안 함 — 아래 비교는 **마지막으로 받아 둔 상태 기준**이다"
  fi

  # ── 원격에 없는 것들. 이걸 놓치면 옮기고 나서 사라진다.
  local risky=0

  # 🚨 워크트리는 본체와 refs·stash 를 **공유한다.** 여기서 다시 세면 같은 것이
  #    두 번 보고되고, 「stash 가 2건」처럼 읽힌다(2026-09-03 시험 트리에서 실제로
  #    그랬다). 그래서 워크트리는 자기 작업트리의 미커밋만 본다.
  if [ "$kind" = "워크트리" ]; then
    local wdirty
    wdirty="$(git -C "$p" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${wdirty:-0}" -gt 0 ]; then
      echo "  🚨 미커밋  : $wdirty 건 — 이 워크트리의 변경"
      echo "  ⇒ 판정    : 🚨 미커밋 변경이 있다. 본체와 함께 옮긴다"
    else
      echo "  ⇒ 판정    : ✅ 깨끗함 (브랜치·stash 는 본체 쪽에 함께 표시된다)"
    fi
    return 0
  fi

  # 베어 저장소는 작업트리가 없다 — 미커밋·stash 개념이 없다.
  if [ "$kind" = "베어" ]; then
    echo "  브랜치수  : $(git -C "$p" for-each-ref --format=x refs/heads 2>/dev/null | wc -l | tr -d ' ')"
    echo "  ⇒ 판정    : 🔒 베어 저장소 — 원격 역할을 하고 있을 수 있다. 통째로 옮긴다"
    return 0
  fi

  local dirty
  dirty="$(git -C "$p" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${dirty:-0}" -gt 0 ]; then
    echo "  🚨 미커밋  : $dirty 건 — 커밋도 push 도 안 된 변경"
    risky=1
  fi

  local stashes
  stashes="$(git -C "$p" stash list 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${stashes:-0}" -gt 0 ]; then
    echo "  🚨 stash   : $stashes 건 — stash 는 push 되지 않는다"
    risky=1
  fi

  # 브랜치별로 원격보다 앞선 커밋 / 업스트림 없는 브랜치
  local bl up ahead
  while read -r bl; do
    [ -z "$bl" ] && continue
    up="$(git -C "$p" rev-parse --abbrev-ref --symbolic-full-name "${bl}@{u}" 2>/dev/null)"
    if [ -z "$up" ]; then
      echo "  🚨 브랜치  : $bl — 업스트림 없음(원격에 올라간 적 없을 수 있다)"
      risky=1
    else
      ahead="$(git -C "$p" rev-list --count "${up}..${bl}" 2>/dev/null || echo 0)"
      if [ "${ahead:-0}" -gt 0 ]; then
        echo "  🚨 브랜치  : $bl — $up 보다 $ahead 커밋 앞섬(push 안 됨)"
        risky=1
      fi
    fi
  done < <(git -C "$p" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)

  # ── git 이 추적하지 않는데 없으면 안 되는 것들.
  #    ⚠️ grep 으로 「없다」를 말하지 않는다 — 파일 존재를 직접 본다(CLAUDE.md).
  local f found_secret=0
  for f in android/key.properties android/local.properties .env functions/.env \
           ios/Flutter/Generated.xcconfig; do
    if [ -e "$p/$f" ]; then
      echo "  🔑 비추적  : $f — .gitignore 대상이라 원격에 없다"
      found_secret=1
    fi
  done
  # 제3자 개인정보가 들어 있는 검수 파일
  while read -r f; do
    [ -z "$f" ] && continue
    echo "  🔒 개인정보: ${f#$p/} — 제3자 개인정보(원격에 없음)"
    found_secret=1
  done < <(find "$p" -maxdepth 2 \( -name 'scan_result*.tsv' -o -name 'ocr_truth*.tsv' \
             -o -name 'ocr_review_progress*.json' -o -name '*.jks' -o -name '*.keystore' \
             -o -name '*.p8' -o -name '*.p12' \) 2>/dev/null)
  [ "$found_secret" -eq 1 ] && risky=1

  # key.properties 의 storeFile 이 X31 을 가리키면 옮긴 뒤 서명이 깨진다
  if [ -e "$p/android/key.properties" ]; then
    local sf
    sf="$(awk -F= '/^storeFile/{sub(/^[ \t]+/,"",$2); print $2}' "$p/android/key.properties" 2>/dev/null)"
    if [ -n "${sf:-}" ]; then
      echo "  🔑 storeFile: $sf"
      case "$sf" in
        "$SRC"*) echo "     ⚠️ 서명 키가 X31 위에 있다 — X31 을 정리하면 릴리스 서명이 깨진다" ;;
      esac
    fi
  fi

  # 워크트리 목록(본체에서만 의미가 있다)
  if [ "$kind" = "본체" ]; then
    local wts
    wts="$(git -C "$p" worktree list 2>/dev/null | tail -n +2)"
    if [ -n "$wts" ]; then
      echo "  워크트리  : $(echo "$wts" | wc -l | tr -d ' ') 개 딸려 있다 — 옮기면 repair 필요"
      echo "$wts" | sed 's/^/              /'
    fi
  fi

  [ "$risky" -eq 1 ] && echo "  ⇒ 판정    : 🚨 원격에서 복구 안 되는 것이 있다. 반드시 함께 옮긴다" \
                     || echo "  ⇒ 판정    : ✅ 원격과 일치 — 다시 클론해도 되지만, 옮기는 편이 빠르다"
}

do_survey() {
  need_macos
  hdr "① 조사 — 아무것도 바꾸지 않는다"
  echo "원본: $SRC"
  echo "대상: $DST"
  echo "보고서: $REPORT"

  if [ ! -d "$SRC" ]; then
    red "원본 볼륨이 없다: $SRC   (외장 하드가 붙어 있나?)"
    exit 2
  fi

  hdr "볼륨 상태"
  for v in "$SRC" "$DST"; do
    if [ -d "$v" ]; then
      echo "── $v"
      diskutil info "$v" 2>/dev/null \
        | grep -E "Volume Name|File System Personality|Device Location|Mount Point|Volume Free Space|Volume Total Space|Case-sensitive" \
        | sed 's/^ */   /'
    else
      ylw "── $v : 없음(마운트 안 됨)"
    fi
  done

  hdr "용량"
  local need avail
  need="$(kb_of "$SRC")"
  echo "   옮길 양     : $(human_kb "$need")"
  if [ -d "$DST" ]; then
    avail="$(df -k "$DST" | awk 'NR==2{print $4}')"
    echo "   Work 여유   : $(human_kb "$avail")"
    if [ "${avail:-0}" -lt "${need:-0}" ]; then
      red "   🚨 여유 공간이 부족하다. build/·Pods/·node_modules 를 빼면 줄어든다"
    else
      grn "   ✅ 충분하다"
    fi
  fi

  hdr "최상위 항목"
  local n
  for n in $(ls -A "$SRC" 2>/dev/null); do
    skip_top "$n" && continue
    in_scope "$n" || continue
    printf '   %-40s %s\n' "$n" "$(human_kb "$(kb_of "$SRC/$n")")"
  done

  hdr "git 저장소 — GitHub / GitLab 대조"
  load_repos
  local p name
  while read -r p; do
    [ -z "$p" ] && continue
    name="${p#$SRC/}"
    in_scope "${name%%/*}" || continue
    echo ""
    echo "▪ $name"
    survey_repo "$p" "$name"
  done <<< "$REPO_LIST"

  hdr "git 밖에 있는 자료 — 원격이 없으니 **여기에만 있다**"
  echo "   (저장소 안이거나, 저장소를 담고 있을 뿐인 부모 폴더는 뺀다)"
  local shown=0
  while read -r p; do
    [ -z "$p" ] && continue
    name="$(basename "$p")"
    skip_top "$name" && continue
    in_scope "${p#$SRC/}" || in_scope "${p#$SRC/}" || true
    under_repo "$p" && continue                       # 저장소 안이다
    # 하위에 저장소를 담고 있을 뿐인 부모 폴더는 그 자체가 자료가 아니다
    if find "$p" -mindepth 1 -maxdepth 1 -type f 2>/dev/null | head -1 | grep -q .; then
      printf '   🔒 %-42s %s\n' "${p#$SRC/}" "$(human_kb "$(kb_of "$p")")"
      shown=1
    fi
  done < <(find "$SRC" -mindepth 1 -maxdepth 3 -type d 2>/dev/null | sort)
  [ "$shown" -eq 0 ] && echo "   없음 — git 밖에 파일을 직접 담은 폴더가 없다"

  hdr "다음 단계"
  cat <<'EOS'
   위 목록에서 🚨 와 🔒 가 붙은 것을 먼저 눈으로 확인한다.
   특히 「원격 없음」·「미커밋」·「stash」·「비추적」은 **원격에서 다시 받을 수 없다.**

   확인이 끝났으면:
     tool/migrate_to_work_volume.sh copy --yes
EOS
}

# ─────────────────────────────────────────────────────────────────────────────
# ② 복사

do_copy() {
  need_macos
  hdr "② 복사 — X31 은 지우지 않는다"

  [ -d "$SRC" ] || { red "원본이 없다: $SRC"; exit 2; }
  if [ ! -d "$DST" ]; then
    red "대상 볼륨이 없다: $DST"
    red "디스크 유틸리티에서 Work 볼륨이 마운트돼 있는지 확인한다."
    exit 2
  fi
  [ -w "$DST" ] || { red "대상에 쓸 수 없다: $DST"; exit 2; }

  local need avail
  need="$(kb_of "$SRC")"; avail="$(df -k "$DST" | awk 'NR==2{print $4}')"
  echo "   옮길 양 $(human_kb "$need") / 여유 $(human_kb "$avail")"
  if [ "${avail:-0}" -lt "${need:-0}" ]; then
    red "   여유 공간 부족 — 멈춘다."
    exit 1
  fi

  # 🚨 건너뛴 것은 **마지막에 모아서** 보여준다. 긴 로그 중간의 노란 줄 한 줄은
  #    읽히지 않는다 — 2026-09-04 에 그래서 「복사됐다」로 읽고 다음 단계로 갔다.
  local SKIPPED=()
  local items=()
  local n
  for n in $(ls -A "$SRC" 2>/dev/null); do
    skip_top "$n" && continue
    in_scope "$n" || continue
    items+=("$n")
  done
  [ "${#items[@]}" -eq 0 ] && { red "옮길 것이 없다."; exit 1; }

  echo ""
  echo "   다음을 $DST 아래로 복사한다:"
  for n in "${items[@]}"; do printf '     %-38s %s\n' "$n" "$(human_kb "$(kb_of "$SRC/$n")")"; done

  if [ "$ASSUME_YES" -ne 1 ]; then
    echo ""
    ylw "   실행하려면 --yes 를 붙인다. (원본은 그대로 남는다)"
    exit 0
  fi

  # ditto 를 쓰는 이유: 권한·ACL·확장속성·한글 파일명 정규화를 그대로 옮긴다.
  # cp -R 은 확장속성을, rsync 는(구버전 macOS 기본) ACL 을 흘린다.
  # 명함데이터의 700 권한이 풀리면 제3자 개인정보가 노출된다(CLAUDE.md 4장).
  for n in "${items[@]}"; do
    echo ""
    echo "── $n"
    if [ -e "$DST/$n" ]; then
      ylw "   이미 있다 — 덮어쓰지 않고 건너뛴다."
      SKIPPED+=("$n")
      continue
    fi
    if ditto --noqtn "$SRC/$n" "$DST/$n"; then
      grn "   복사 완료 $(human_kb "$(kb_of "$DST/$n")")"
    else
      red "   🚨 복사 실패 — 여기서 멈춘다. 원본은 그대로다."
      exit 1
    fi
  done

  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    hdr "🚨 건너뛴 항목 ${#SKIPPED[@]} 개 — 복사되지 않았다"
    for n in "${SKIPPED[@]}"; do
      printf '   ⚠️ %-38s (대상에 이미 있음)\n' "$n"
    done
    cat <<'EOS'

   ⚠️ **「이미 있다」는 「같다」가 아니다.** 대상 쪽이 옛 클론이거나 다른 내용일 수
      있다. 실제로 2026-09-04 에 이것을 놓쳐 **워크트리 5개와 push 안 된 브랜치
      12개가 없는 복사본**을 「복사됐다」로 읽고 다음 단계로 갔다.

   확인: 원본과 대상의 HEAD 를 나란히 본다
     git -C <원본>/<이름> rev-parse HEAD
     git -C <대상>/<이름> rev-parse HEAD

   다시 옮기려면 — **지우지 말고 옆으로 밀어 둔다**
     mv <대상>/<이름> <대상>/<이름>.이전_$(date +%Y-%m-%d)
     tool/migrate_to_work_volume.sh copy --yes --only=<이름>
EOS
  fi

  hdr "다음 단계"
  cat <<'EOS'
   복사만 끝났다. 아직 **쓸 수 있는 상태가 아니다** — 절대경로가 박힌 것들이 남아 있다.
     tool/migrate_to_work_volume.sh repair
EOS
  [ "${#SKIPPED[@]}" -gt 0 ] && return 1
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# ③ 고치기 — 옮겨서 깨진 절대경로

do_repair() {
  need_macos
  hdr "③ 옮겨서 깨진 것 고치기"
  [ -d "$DST" ] || { red "대상이 없다: $DST"; exit 2; }

  hdr "3-1. git worktree 경로 — 파일을 직접 고친다"
  cat <<EOS
   .git 파일과 .git/worktrees/*/gitdir 에 **절대경로**가 박혀 있다. 둘 다 고쳐야 한다.

   🚨 여기서 'git worktree repair <새 경로>' 를 쓰면 안 된다.
      git 은 넘긴 경로의 .git 을 읽어 **거기 적힌 옛 본체**를 찾아가 고친다. 그래서
      「옛 본체 ↔ 새 워크트리」로 짝이 맞춰지고, **원본 X31 쪽 파일이 바뀐다.**
      2026-09-03 시험에서 실제로 그렇게 됐다 — 원본 두 파일이 새 볼륨을 가리키게
      바뀌고, 정작 복사본은 그대로 깨져 있었다(즉 **정확히 반대로** 됐다).
      ⇒ 그러므로 문자열은 우리가 고치고, git 은 **확인에만** 쓴다.
EOS

  # 🚨 안전망: 이 단계가 끝난 뒤 **원본이 그대로인지 실제로 잰다.**
  #    "X31 은 손대지 않는다" 를 말로만 두지 않는다 — 위 사고가 그렇게 났다.
  local snap_before snap_after
  snap_before="$(snapshot_src_git)"

  local f before
  local fixed=0
  # ① 새 워크트리의 .git 파일 (gitdir: <옛 본체>/.git/worktrees/<이름>)
  while read -r f; do
    [ -z "$f" ] && continue
    grep -q -- "$SRC" "$f" 2>/dev/null || continue
    rewrite_path_in "$f" && { echo "   고침: ${f#$DST/}"; fixed=1; }
  done < <(find "$DST" -maxdepth 8 -name .git -type f 2>/dev/null | LC_ALL=C sort)

  # ② 새 본체의 .git/worktrees/<이름>/gitdir (<옛 워크트리>/.git)
  while read -r f; do
    [ -z "$f" ] && continue
    grep -q -- "$SRC" "$f" 2>/dev/null || continue
    rewrite_path_in "$f" && { echo "   고침: ${f#$DST/}"; fixed=1; }
  done < <(find "$DST" -maxdepth 8 -path '*/.git/worktrees/*/gitdir' -type f 2>/dev/null | LC_ALL=C sort)

  [ "$fixed" -eq 0 ] && echo "   고칠 것이 없었다(워크트리가 없거나 이미 새 경로다)."

  hdr "3-1b. git 이 보는 결과 — 새 볼륨 안에서만 확인한다"
  local p
  while read -r p; do
    [ -z "$p" ] && continue
    [ -d "$p/.git" ] || continue          # 본체에서만
    echo ""
    echo "── ${p#$DST/}"
    # 인자를 주지 않는다 — 주면 git 이 옛 본체를 찾아간다(위 사고).
    git -C "$p" worktree repair 2>&1 | sed 's/^/   repair: /'
    git -C "$p" worktree list 2>/dev/null | sed 's/^/   /'
    # 아직도 옛 볼륨을 가리키는 등록이 남았는지 — 여기서 조용히 넘기면 나중에 터진다
    if git -C "$p" worktree list 2>/dev/null | grep -q -- "$SRC"; then
      red "   🚨 아직 $SRC 를 가리키는 워크트리가 있다 — 복사되지 않은 워크트리일 수 있다."
      red "      그 워크트리를 함께 복사한 뒤 repair 를 다시 돌린다."
    fi
    git -C "$p" worktree prune -v 2>&1 | sed 's/^/   prune: /' || true
  done < <(find "$DST" -maxdepth 6 -name .git -type d 2>/dev/null | while read -r g; do dirname "$g"; done | LC_ALL=C sort)

  hdr "3-1c. 원본이 그대로인지 — 재서 확인한다"
  snap_after="$(snapshot_src_git)"
  if [ "$snap_before" = "$snap_after" ]; then
    grn "   ✅ 원본($SRC) 쪽 git 연결 파일은 하나도 바뀌지 않았다."
  else
    red "   🚨 원본이 바뀌었다. 아래가 달라진 파일이다 — 즉시 확인한다."
    diff <(echo "$snap_before") <(echo "$snap_after") | sed 's/^/   /'
  fi

  hdr "3-2. Flutter 캐시 — .dart_tool 의 절대경로"
  echo "   package_config.json 이 옛 경로를 가리킨다. 지우고 다시 받는다."
  while read -r p; do
    [ -z "$p" ] && continue
    [ -e "$p/pubspec.yaml" ] || continue
    echo ""
    echo "── ${p#$DST/}"
    rm -rf "$p/.dart_tool" "$p/.flutter-plugins-dependencies"
    if command -v flutter >/dev/null 2>&1; then
      (cd "$p" && flutter pub get 2>&1 | tail -3 | sed 's/^/   /')
    else
      ylw "   flutter 가 PATH 에 없다 — 나중에 'flutter pub get' 을 직접 돌린다."
    fi
  done < <(find "$DST" -maxdepth 6 -name pubspec.yaml -not -path '*/build/*' 2>/dev/null | while read -r f; do dirname "$f"; done | sort)

  hdr "3-3. iOS Pods — 절대경로가 박힌 xcconfig"
  echo "   Pods/ 와 Podfile.lock 은 경로에 묶여 있다. 실기기 iOS 빌드 전에 다시 깐다."
  while read -r p; do
    [ -z "$p" ] && continue
    echo "   ${p#$DST/}  →  (cd ios && pod install)  ← iOS 빌드할 때 직접 돌린다"
  done < <(find "$DST" -maxdepth 7 -name Podfile 2>/dev/null | while read -r f; do dirname "$f"; done | sort)

  hdr "3-4. 개인정보 폴더 권한 — 700 이어야 한다"
  local d
  while read -r d; do
    [ -z "$d" ] && continue
    chmod 700 "$d" && echo "   700 으로 맞춤: ${d#$DST/}  (현재 $(stat -f '%Lp' "$d"))"
  done < <(find "$DST" -maxdepth 4 -type d -name '명함데이터' 2>/dev/null)

  hdr "3-5. ~/Downloads/커넥션센스 심볼릭 링크"
  local link="$HOME/Downloads/커넥션센스"
  mkdir -p "$HOME/Downloads" 2>/dev/null || true
  local newassets
  newassets="$(find "$DST" -maxdepth 3 -type d -name 'connection-sense-assets' 2>/dev/null | head -1)"
  if [ -n "$newassets" ]; then
    if [ -L "$link" ]; then
      echo "   지금: $link → $(readlink "$link")"
      rm "$link" && ln -s "$newassets" "$link" \
        && grn "   바꿈: $link → $newassets"
    elif [ ! -e "$link" ]; then
      ln -s "$newassets" "$link" && grn "   새로 만듦: $link → $newassets"
    else
      ylw "   $link 가 링크가 아니라 실제 폴더다 — 손대지 않는다."
    fi
  else
    ylw "   connection-sense-assets 를 $DST 아래에서 못 찾았다 — 링크는 그대로 둔다."
  fi

  hdr "3-6. 저장소 안에 남은 옛 절대경로"
  echo "   문서·에이전트 설정에 $SRC 가 적혀 있으면 다음 세션이 옛 경로로 간다."
  grep -rln "$SRC" "$DST" --include='*.md' --include='*.sh' --include='*.py' \
       --include='*.json' --include='*.yaml' 2>/dev/null \
    | grep -v '/build/' | grep -v '/\.git/' | sed 's/^/   /' | head -40
  echo "   ⇒ 위 파일들은 사람이 읽고 판단해서 고친다(과거 기록은 그대로 두는 편이 낫다)."

  hdr "다음 단계"
  echo "     tool/migrate_to_work_volume.sh verify"
}

# ─────────────────────────────────────────────────────────────────────────────
# ④ 대조

do_verify() {
  need_macos
  hdr "④ 원본과 대조 — 개수만 보지 않는다"
  [ -d "$SRC" ] || { red "원본이 없다: $SRC — 대조할 수 없다."; exit 2; }
  [ -d "$DST" ] || { red "대상이 없다: $DST"; exit 2; }

  local bad=0 byte_diff=0 n sc dc sb db
  echo "   세는 기준: .dart_tool·build·Pods·node_modules·.gradle·.DS_Store 는 뺀다"
  echo "             — repair 가 지우거나 다시 만들어지는 것들이다"
  printf '\n%-30s %12s %12s %14s %14s  %s\n' "항목" "원본(개)" "복사(개)" "원본(byte)" "복사(byte)" "판정"
  for n in $(ls -A "$SRC" 2>/dev/null); do
    skip_top "$n" && continue
    in_scope "$n" || continue
    if [ ! -e "$DST/$n" ]; then
      printf '%-30s %12s %12s %14s %14s  %s\n' "$n" "-" "-" "-" "-" "🚨 복사 안 됨"
      bad=1; continue
    fi
    sc="$(rel_count "$SRC/$n")"; dc="$(rel_count "$DST/$n")"
    sb="$(rel_bytes "$SRC/$n")";   db="$(rel_bytes "$DST/$n")"
    # 🚨 바이트 합이 다른 것은 **정상일 수 있다.** repair 가 워크트리 파일 안의
    #    경로 문자열을 바꾸기 때문이다(/Volumes/X31/Claude → /Volumes/Work, 길이가 다르다).
    #    2026-09-03 시험에서 이것으로 「2 바이트 다르다」가 떠 실패로 끝났다 —
    #    유실은 0건이었다. 그래서 **판정은 개수와 유실 목록으로 하고, 바이트는 참고**다.
    # 🚨 개수 차이는 **방향을 봐야 한다.** 2026-09-04 실물 이전에서 이걸 안 갈라
    #    「🚨 개수가 다르다」가 7건 떴는데 **유실은 0건**이었다 — 차이가 전부
    #    「복사본에 더 있는 것」이었고, repair 가 돌린 flutter pub get 이 만든
    #    ephemeral·GeneratedPluginRegistrant·.plugin_symlinks·.swift_pm.lock 과
    #    사용자가 Work 에서 git fetch 해 생긴 객체였다.
    #    ⇒ **유실은 「원본에만 있는 것」뿐이다.** 대상에 더 있는 것은 유실이 아니다.
    if [ "$sc" -gt "$dc" ]; then
      printf '%-30s %12s %12s %14s %14s  %s\n' "$n" "$sc" "$dc" "$sb" "$db" "🚨 원본이 더 많다"
      bad=1
    elif [ "$sc" -lt "$dc" ]; then
      printf '%-30s %12s %12s %14s %14s  %s\n' "$n" "$sc" "$dc" "$sb" "$db" "⚠️ 대상에 더 있다"
      byte_diff=1
    elif [ "$sb" != "$db" ]; then
      printf '%-30s %12s %12s %14s %14s  %s\n' "$n" "$sc" "$dc" "$sb" "$db" "⚠️ 바이트만 다름"
      byte_diff=1
    else
      printf '%-30s %12s %12s %14s %14s  %s\n' "$n" "$sc" "$dc" "$sb" "$db" "✅"
    fi
  done

  if [ "$byte_diff" -eq 1 ] && [ "$bad" -eq 0 ]; then
    cat <<'EOS'

   ⚠️ 위 ⚠️ 표시는 유실이 아니다. 옮기면 **반드시** 생기는 차이다:
      · 바이트 — repair 가 워크트리 경로 문자열을 바꿔 글자 수가 달라진다
      · 대상에 더 있는 것 — repair 가 돌린 flutter pub get 이 다시 만든 것들
        (ios·macos·linux 의 ephemeral/·.plugin_symlinks/·.swift_pm.lock,
         GeneratedPluginRegistrant, Generated.xcconfig, local.properties,
         .flutter-plugins-dependencies), 그리고 새 볼륨에서 fetch 한 git 객체
   ⇒ **판정은 「원본에만 있는 파일」로 한다.** 그것이 0건이면 통과다.
EOS
  fi

  # ⚠️ 개수와 바이트가 같아도 「무엇이」 다른지는 안 나온다.
  #    repair 단계에서 .dart_tool 을 지웠으므로 차이가 나는 것은 정상이다.
  #    그래서 실제로 빠진 파일 목록을 따로 뽑는다.
  #
  # 🚨 여기서 rsync 를 쓰지 않는다. rsync 가 없는 기계에서 이 단계가 **조용히
  #    「유실 0건」** 을 내면 그것이 가장 나쁜 결과다 — 틀린 답이 아니라 **잴 것이
  #    없었던 것**인데 통과로 읽힌다(CLAUDE.md 「세는 도구가 못 보는 것」).
  #    그래서 find + comm 으로만 잰다. 둘 다 어디에나 있다.
  hdr "원본에만 있는 파일 — 이것이 유실이다"
  echo "   (.dart_tool·build·Pods·node_modules·.gradle·.DS_Store 는 다시 만들어지므로 뺀다)"
  local lost=0 extra=0 cnt
  local tmpl tmpr
  tmpl="$(mktemp)"; tmpr="$(mktemp)"
  for n in $(ls -A "$SRC" 2>/dev/null); do
    skip_top "$n" && continue
    in_scope "$n" || continue
    [ -e "$DST/$n" ] || continue
    list_rel "$SRC/$n" > "$tmpl"
    list_rel "$DST/$n" > "$tmpr"

    cnt="$(comm -23 "$tmpl" "$tmpr" | wc -l | tr -d ' ')"
    if [ "${cnt:-0}" -gt 0 ]; then
      red "   🚨 $n — 원본에만 있는 것 $cnt 건:"
      # ⭐ 「몇 건 어긋났다」로 끝내지 않는다. 그 줄을 그대로 보여 준다(CLAUDE.md).
      comm -23 "$tmpl" "$tmpr" | head -40 | sed "s|^\./|   $n/|"
      [ "$cnt" -gt 40 ] && echo "   … 이하 생략(전체는 $REPORT)"
      lost=1
    fi

    cnt="$(comm -13 "$tmpl" "$tmpr" | wc -l | tr -d ' ')"
    if [ "${cnt:-0}" -gt 0 ]; then
      ylw "   ⚠️ $n — 대상에만 있는 것 $cnt 건(빈 폴더가 아니었을 수 있다):"
      comm -13 "$tmpl" "$tmpr" | head -20 | sed "s|^\./|   $n/|"
      extra=1
    fi
  done
  rm -f "$tmpl" "$tmpr"
  if [ "$lost" -eq 0 ]; then
    grn "   ✅ 원본에만 있는 파일 0건"
  else
    bad=1
  fi
  if [ "$extra" -eq 1 ]; then
    echo "   ⇒ 대상에만 있는 것은 유실이 아니다. 다만 **덮어쓰기가 일어났는지** 확인한다."
  fi
  # ⚠️ 한글 파일명은 macOS 에서 NFD 로 저장된다. ditto 는 그대로 옮기지만,
  #    Finder·다른 도구로 옮긴 것을 검증하면 **같은 이름이 다르게 보일 수 있다.**
  #    그때는 유실이 아니라 이름 정규화 차이다 — 파일을 직접 열어 확인한다.

  hdr "판정"
  if [ "$bad" -eq 0 ]; then
    grn "   ✅ 통과. 다음은 GitHub 동기화다:  tool/migrate_to_work_volume.sh sync"
    grn "   그리고 X31 정리는 사람이 직접 확인한 뒤에 한다."
    echo "      🚨 이 스크립트는 X31 을 지우지 않는다. 지우기 전에 새 경로에서"
    echo "         flutter test / 실기기 빌드까지 한 번 돌려 본다."
  else
    red "   🚨 어긋남이 있다. 위 목록을 먼저 해결한다. X31 은 절대 지우지 않는다."
    exit 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# ⑤ GitHub 동기화 — **밖으로 나가는 동작이다.** 기본은 계획만 보여준다.

do_sync() {
  need_macos
  hdr "⑤ GitHub 동기화 — 새 볼륨에서"
  [ -d "$DST" ] || { red "대상이 없다: $DST"; exit 2; }

  cat <<'EOS'
   🚨 push 는 저장소 밖(원격)으로 나가는 동작이다. 그래서 기본은 **계획만** 보여준다.
      실제로 올리려면 --yes 를 붙인다. 그리고 이 단계는 **절대 force 하지 않는다.**
   ⚠️ 미커밋·stash 는 push 되지 않는다. 그것들은 옮긴 파일로만 남는다.
EOS

  local target_remote=""
  [ -n "$SYNC_REMOTE" ] && target_remote="$SYNC_REMOTE"

  # 🚨 「검사한 저장소 0개」와 「올릴 것이 0개」는 다르다. 2026-09-03 시험에서
  #    GitHub 원격이 없어 전부 건너뛴 것이 「✅ 올릴 것이 없다」로 끝났다 —
  #    통과한 것이 아니라 **잴 것이 없었던 것**이다(CLAUDE.md).
  local p name rname rurl kind ghremote br up ahead behind
  local planned=0 pushed=0 failed=0 checked=0 skipped=0
  while read -r p; do
    [ -z "$p" ] && continue
    [ -d "$p/.git" ] || continue                 # 본체에서만 — 워크트리는 refs 를 공유한다
    [ "$(git -C "$p" rev-parse --is-bare-repository 2>/dev/null)" = "true" ] && continue
    name="${p#$DST/}"
    in_scope "${name%%/*}" || continue
    echo ""
    echo "▪ $name"

    # 어느 원격으로 올릴지 — 기본은 GitHub 으로 분류된 것
    ghremote=""
    while read -r rname rurl _; do
      [ -z "${rname:-}" ] && continue
      if [ -n "$target_remote" ]; then
        [ "$rname" = "$target_remote" ] && ghremote="$rname"
      else
        [ "$(remote_kind "$rurl")" = "GitHub" ] && [ -z "$ghremote" ] && ghremote="$rname"
      fi
    done < <(git -C "$p" remote -v 2>/dev/null | awk '$3=="(fetch)"')

    if [ -z "$ghremote" ]; then
      skipped=$((skipped+1))
      if [ -n "$target_remote" ]; then
        ylw "   원격 '$target_remote' 이 없다 — 건너뛴다."
      else
        ylw "   GitHub 원격이 없다 — 건너뛴다. (GitLab 만 있거나 원격이 없는 저장소다)"
        echo "      GitLab 쪽으로 올리려면: --remote=<원격이름> 으로 지정한다."
      fi
      continue
    fi
    checked=$((checked+1))
    echo "   원격      : $ghremote → $(git -C "$p" remote get-url "$ghremote" 2>/dev/null)"

    # 🚨 fetch 없이 비교하면 **마지막으로 받아 둔 상태**와 비교하게 된다.
    #    그 값은 남이 그 사이 올린 것을 못 본다(CLAUDE.md 「본 순간의 상태」).
    if git -C "$p" fetch --quiet "$ghremote" 2>/dev/null; then
      echo "   fetch     : 방금 갱신함"
    else
      red "   fetch     : 🚨 실패(네트워크·인증) — 아래 비교는 낡은 값이다. 먼저 해결한다."
      failed=1
      checked=$((checked-1))
      continue
    fi

    local dirty
    dirty="$(git -C "$p" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    [ "${dirty:-0}" -gt 0 ] && ylw "   ⚠️ 미커밋 $dirty 건 — push 되지 않는다(파일로만 옮겨졌다)"
    local st
    st="$(git -C "$p" stash list 2>/dev/null | wc -l | tr -d ' ')"
    [ "${st:-0}" -gt 0 ] && ylw "   ⚠️ stash $st 건 — push 되지 않는다"

    while read -r br; do
      [ -z "$br" ] && continue
      up="$(git -C "$p" rev-parse --abbrev-ref --symbolic-full-name "${br}@{u}" 2>/dev/null)"
      if [ -z "$up" ]; then
        echo "   ▸ $br — 업스트림 없음  ⇒ git push -u $ghremote $br"
        planned=1
        if [ "$ASSUME_YES" -eq 1 ]; then
          if git -C "$p" push -u "$ghremote" "$br" 2>&1 | sed 's/^/       /'; then
            grn "       올렸다: $br"; pushed=1
          else
            red "       🚨 실패: $br"; failed=1
          fi
        fi
        continue
      fi
      ahead="$(git -C "$p" rev-list --count "${up}..${br}" 2>/dev/null || echo 0)"
      behind="$(git -C "$p" rev-list --count "${br}..${up}" 2>/dev/null || echo 0)"
      if [ "${ahead:-0}" -eq 0 ] && [ "${behind:-0}" -eq 0 ]; then
        echo "   ▸ $br — $up 과 같다  ✅"
        continue
      fi
      echo "   ▸ $br — $up 대비 앞섬 $ahead · 뒤짐 $behind"
      if [ "${behind:-0}" -gt 0 ]; then
        # 🚨 갈라진 것을 push 로 밀어붙이면 남의 커밋이 사라진다. 사람이 판단한다.
        red "       🚨 원격이 앞서 있다 — 이 단계는 손대지 않는다."
        red "          merge 인지 rebase 인지는 그 저장소의 규약대로 사람이 정한다."
        failed=1
        continue
      fi
      planned=1
      echo "       ⇒ git push $ghremote $br"
      if [ "$ASSUME_YES" -eq 1 ]; then
        if git -C "$p" push "$ghremote" "$br" 2>&1 | sed 's/^/       /'; then
          grn "       올렸다: $br"; pushed=1
        else
          red "       🚨 실패: $br"; failed=1
        fi
      fi
    done < <(git -C "$p" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null)
  done < <(find "$DST" -maxdepth 6 -name .git -type d 2>/dev/null | while read -r g; do dirname "$g"; done | LC_ALL=C sort)

  hdr "판정"
  echo "   검사한 저장소 $checked 개 · 건너뛴 저장소 $skipped 개"
  if [ "$failed" -eq 1 ]; then
    red "   🚨 손대지 못한 것이 있다. 위의 🚨 를 먼저 해결한다."
    return 1
  fi
  if [ "$checked" -eq 0 ]; then
    ylw "   ⚠️ 한 곳도 검사하지 못했다 — 「올릴 것이 없다」가 아니다."
    ylw "      GitHub 원격이 붙은 저장소가 없다. --remote=<이름> 으로 원격을 지정하거나,"
    ylw "      survey 결과에서 각 저장소의 원격이 무엇인지 먼저 확인한다."
    return 1
  fi
  if [ "$planned" -eq 0 ]; then
    grn "   ✅ 검사한 $checked 개 모두 원격과 같다 — 올릴 것이 없다."
  elif [ "$ASSUME_YES" -eq 1 ] && [ "$pushed" -eq 1 ]; then
    grn "   ✅ 올렸다. GitHub 에서 브랜치가 보이는지 눈으로 확인한다."
  else
    ylw "   위 계획대로 올리려면 --yes 를 붙인다."
  fi
  return 0
}

# 🚨 tee 로 보고서를 남기면 **파이프가 실패를 삼킨다**(CLAUDE.md 4-2 와 같은 뿌리).
#    그리고 뒤에 오는 echo 두 줄이 상태를 다시 0 으로 덮는다. 2026-09-03 시험에서
#    verify 가 「🚨 어긋남이 있다」를 찍고도 **종료코드 0** 으로 끝났다 — 자동화에
#    걸면 실패가 통과로 읽힌다. 그래서 단계의 상태를 잡아 두고 마지막에 그것으로 끝낸다.
rc=0
case "$MODE" in
  survey) do_survey  2>&1 | tee "$REPORT"; rc=${PIPESTATUS[0]} ;;
  copy)   do_copy    2>&1 | tee "$REPORT"; rc=${PIPESTATUS[0]} ;;
  repair) do_repair  2>&1 | tee "$REPORT"; rc=${PIPESTATUS[0]} ;;
  verify) do_verify  2>&1 | tee "$REPORT"; rc=${PIPESTATUS[0]} ;;
  sync)   do_sync    2>&1 | tee "$REPORT"; rc=${PIPESTATUS[0]} ;;
  *) cat >&2 <<'EOS'
사용법: tool/migrate_to_work_volume.sh <단계> [옵션]

  survey   조사만 한다(읽기 전용). 무엇이 원격에 없는지 목록으로 낸다
  copy     복사한다(X31 은 그대로). --yes 없으면 계획만 보여준다
  repair   옮겨서 깨진 절대경로를 고친다(worktree·.dart_tool·권한·링크)
  verify   원본과 대조한다
  sync     새 볼륨에서 GitHub 과 맞춘다(계획만; --yes 로 실제 push)

옵션
  --yes            copy 를 실제로 실행
  --fetch          survey 에서 원격을 먼저 받아 비교(네트워크·인증 필요)
  --only=A,B       최상위 항목을 골라서
  --remote=NAME    sync 에서 올릴 원격을 직접 지정(기본은 GitHub 으로 분류된 원격)
  --out=<경로>     보고서 저장 위치

환경변수
  CS_SRC (기본 /Volumes/X31/Claude)   CS_DST (기본 /Volumes/Work)
EOS
     exit 2 ;;
esac

echo ""
echo "보고서: $REPORT"
exit "$rc"

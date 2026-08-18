#!/usr/bin/env python3
"""저장소 **밖** 산출물 폴더(`connection-sense-assets/`)의 자리를 한 곳에서 정한다.

CLAUDE.md 4장: 코드가 아닌 산출물(논의자료·피드백 정리·점검 보고서 등)은
저장소가 아니라 **형제 폴더** `connection-sense-assets/` 아래에 만든다.

- 기본값은 저장소(워크트리 포함)의 부모에 있는 `connection-sense-assets/`다.
  워크트리 넷 중 어디서 돌려도 같은 자리를 가리킨다.
- 다른 자리에 두었으면 `CS_ASSETS_DIR` 환경변수로 알려준다.

⚠️ **폴더가 없으면 만들지 않고 즉시 멈춘다.** 이 모듈이 생긴 이유가
"조용히 엉뚱한 자리에 떨어지는 것"이기 때문이다 — 옛 코드는 산출물을
`~/Downloads/`에 썼고, 자료를 옮긴 뒤에도 **에러 없이** 옛 자리에 계속
떨어졌다. 없는 폴더를 만들어 주면 같은 실수가 조용히 반복된다.
"""
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(os.path.dirname(REPO_ROOT), 'connection-sense-assets')


def assets_path(*parts):
    """`connection-sense-assets/` 아래 경로를 돌려준다. 자리가 없으면 멈춘다."""
    base = os.path.expanduser(os.environ.get('CS_ASSETS_DIR') or DEFAULT_DIR)
    if not os.path.isdir(base):
        sys.exit(
            f'⚠️ 산출물 폴더를 못 찾았다: {base}\n'
            '   저장소 밖 자료 폴더(connection-sense-assets)가 그 자리에 없다.\n'
            '   다른 자리에 있으면 알려준다:\n'
            '     CS_ASSETS_DIR=/경로/connection-sense-assets python3 <스크립트>'
        )
    out = os.path.join(base, *parts)
    if not os.path.isdir(os.path.dirname(out)):
        sys.exit(f'⚠️ 하위 폴더가 없다: {os.path.dirname(out)}')
    return out

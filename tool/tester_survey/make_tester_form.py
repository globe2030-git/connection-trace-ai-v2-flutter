#!/usr/bin/env python3
"""테스터 설문을 구글 폼으로 만드는 Apps Script를 뽑는다.

쓰는 법:  python3 tool/tester_survey/make_tester_form.py
자세한 것은 같은 폴더의 README.md.

⚠️ 문항은 tester_survey_spec.py 한 곳에서 온다. 여기서 문구를 고치지 말 것 —
워드(make_tester_doc.py)와 어긋난다.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tester_survey_spec as S

OUT = os.path.expanduser('~/Downloads/커넥션센스_설문_구글폼_만들기.gs')


def js(x):
    return json.dumps(x, ensure_ascii=False)


L = []
A = L.append

A("/**")
A(" * 커넥션센스 — 테스터 확인·질문지를 구글 설문으로 만드는 스크립트")
A(" *")
A(" * ⚠️ 이 파일은 tool/tester_survey/make_tester_form.py 가 만든 것이다.")
A(" *    문구를 여기서 고치면 다음에 다시 뽑을 때 사라진다.")
A(" *")
A(" * 쓰는 법")
A(" *   1. script.google.com → \"새 프로젝트\"")
A(" *   2. 이 파일 내용을 통째로 붙여넣기")
A(" *   3. 위쪽 함수 목록에서 makeForm 을 고르고 \"실행\"")
A(" *   4. 처음 한 번은 권한 확인 창이 뜬다 (내 구글 계정에 설문·시트를 만드는 권한)")
A(" *   5. 실행이 끝나면 \"실행 로그\"에 설문 주소와 응답 시트 주소가 찍힌다")
A(" *")
A(" * 구성은 빌드6 피드백 문서의 형식을 따랐다 — 기기 환경을 맨 위에, 그다음은")
A(" * 우리가 고친 순서가 아니라 **테스터가 앱을 여는 순서**로.")
A(" */")
A("")
A("const APP_VERSION = '____________';   // 예: '1.0.0+8 (a1b2c3d)'")
A("")
A("function makeForm() {")
A(f"  const form = FormApp.create({js(S.TITLE + ' (' + S.SUBTITLE + ')')});")
A(f"  form.setDescription({js(S.INTRO + chr(10) * 2 + S.INTRO_WARN)});")
A("  form.setProgressBar(true);")
A("")
A(f"  const YN = {js(S.YN)};")
A(f"  const RATE = {js(S.RATE)};")
A("")
A("  // ── 테스트 환경 (빌드6 문서 형식)")
for label, _kind, hint in S.HEAD:
    req = ".setRequired(true)" if label == '성함' else ""
    hh = f".setHelpText({js(hint)})" if hint else ""
    A(f"  form.addTextItem().setTitle({js(label)}){hh}{req};")
A(f"  form.addSectionHeaderItem().setTitle({js(S.PREP_TITLE)}).setHelpText({js(S.PREP)});")
A("")

A("  // ══════════════ 1부 — 화면 순서")
A("  form.addPageBreakItem().setTitle('1부. 화면별 확인 — 앱을 여는 순서대로')")
A("    .setHelpText('적힌 대로 안 되면 그것이 바로 제보 대상입니다. "
  "⭐ 표시는 이번에 새로 넣거나 고친 것입니다.');")

for title, note, rows, free in S.SCREENS:
    A("")
    if title.startswith('4.'):
        A(f"  form.addSectionHeaderItem().setTitle({js(title)}).setHelpText({js(note)});")
        for q, choices, help_ in S.AI_Q:
            hh = f".setHelpText({js(help_)})" if help_ else ""
            A(f"  form.addMultipleChoiceItem().setTitle({js(q)}){hh}"
              f".setChoiceValues({js(choices)});")
        A(f"  form.addParagraphTextItem().setTitle({js(S.AI_FREE[0])})"
          f".setHelpText({js(S.AI_FREE[1])});")
        continue
    A(f"  form.addGridItem().setTitle({js(title)})")
    A(f"    .setRows({js([r + (' — ' + h if h else '') for r, h in rows])})")
    if note:
        A("    .setColumns(YN)")
        A(f"    .setHelpText({js(note)});")
    else:
        A("    .setColumns(YN);")
    if free and free[0]:
        hh = f".setHelpText({js(free[1])})" if len(free) > 1 and free[1] else ""
        A(f"  form.addParagraphTextItem().setTitle({js(free[0])}){hh};")
    if title.startswith('1.'):
        A(f"  form.addSectionHeaderItem().setTitle({js(S.ACC_TITLE)})"
          f".setHelpText({js(S.ACC_NOTE)});")

A("")
A("  // ══════════════ 2부 — 만족도")
A(f"  form.addPageBreakItem().setTitle({js('2부. ' + S.SURVEY_TITLE)})"
  f".setHelpText({js(S.SURVEY_NOTE)});")


def grid(title, items):
    A(f"  form.addGridItem().setTitle({js(title)})")
    A(f"    .setRows({js([f'{a} {b} → {c}' for a, b, c in items])})")
    A("    .setColumns(RATE);")


grid('오류 (E) — 앞부분', S.E_ITEMS[:7])
grid('오류 (E) — 뒷부분', S.E_ITEMS[7:])
grid('기능 개선 (F) — 앞부분', S.F_ITEMS[:8])
grid('기능 개선 (F) — 뒷부분', S.F_ITEMS[8:])
A("  form.addParagraphTextItem()")
A("    .setTitle('△(그대로)나 ✗(더 나빠짐)를 고르신 항목이 있으면 적어 주세요')")
A("    .setHelpText('어느 것인지와 어떤 점이 그런지');")
A(f"  form.addMultipleChoiceItem().setTitle({js(S.OVERALL_Q[0])})"
  f".setChoiceValues({js(S.OVERALL_Q[1])});")
A(f"  form.addParagraphTextItem().setTitle({js(S.OVERALL_FREE)});")

A("")
A("  // ══════════════ 3부 — 값")
A(f"  form.addPageBreakItem().setTitle({js('3부. ' + S.PRICE_TITLE)})"
  f".setHelpText({js(S.PRICE_NOTE)});")
for q, kind, help_, choices in S.PRICE:
    hh = f".setHelpText({js(help_)})" if help_ else ""
    if kind == 'choice':
        A(f"  form.addMultipleChoiceItem().setTitle({js(q)}){hh}"
          f".setChoiceValues({js(choices)});")
    elif kind == 'text':
        A(f"  form.addTextItem().setTitle({js(q)}){hh};")
    else:
        A(f"  form.addParagraphTextItem().setTitle({js(q)}){hh};")

A("")
A("  // ══════════════ 4부 — 새로 발견한 것")
A(f"  form.addPageBreakItem().setTitle({js('4부. ' + S.NEW_TITLE)})"
  f".setHelpText({js(S.NEW_NOTE)});")
A("  for (var i = 1; i <= 3; i++) {")
A("    form.addParagraphTextItem().setTitle('오류 ' + i)")
A("      .setHelpText(i === 1 ? '어느 화면 · 무엇을 했을 때 · 무엇이 잘못됐나 · 얼마나 자주' : '');")
A("  }")
A("  form.addParagraphTextItem().setTitle('있으면 쓰겠다 싶은 기능')")
A("    .setHelpText('어떤 기능인지와, 어떤 상황에서 필요한지');")
A("  form.addParagraphTextItem().setTitle('없어도 될 것 같은 기능')")
A("    .setHelpText('왜 그렇게 느끼셨는지');")
A(f"  form.addMultipleChoiceItem().setTitle({js(S.LAST_Q[0])})"
  f".setChoiceValues({js(S.LAST_Q[1])}).setRequired(true);")
A("  form.addParagraphTextItem().setTitle('그렇게 느끼신 이유를 자유롭게 적어 주세요');")

A("")
A("  form.setConfirmationMessage('고맙습니다. 적어 주신 내용은 그대로 다음 개선에 반영됩니다.');")
A("")
A("  // 응답을 스프레드시트로 모은다")
A("  const ss = SpreadsheetApp.create('커넥션센스 테스터 응답 (2026-08-18)');")
A("  form.setDestination(FormApp.DestinationType.SPREADSHEET, ss.getId());")
A("")
A("  Logger.log('■ 테스터에게 보낼 주소: ' + form.getPublishedUrl());")
A("  Logger.log('■ 응답 정리 시트: ' + ss.getUrl());")
A("  Logger.log('■ 설문 편집: ' + form.getEditUrl());")
A("}")

open(OUT, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print('만들었습니다:', OUT)

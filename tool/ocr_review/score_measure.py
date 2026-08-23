#!/usr/bin/env python3
"""측정 파일(v2)을 정답지와 대조해 **이름 뽑기**를 채점한다 (추가 405·409).

## 왜 저장소에 있나

이 채점을 2026-08-22에 임시 스크립트로 했다가, 세션이 끝나면 사라지는 자리에
둔 탓에 같은 것을 다시 짜야 했다(Vision 측정기도 같은 일을 겪었다 — 추가 409).
**재는 자는 재는 대상만큼 오래 남아야 한다.**

## 쓰는 법

    python3 tool/ocr_review/score_measure.py <측정.tsv> <정답지.tsv>

측정 파일은 앱이 만든 v2(다섯 칸)다. 만드는 법은 같은 폴더 README 참고.

## ⚠️ 정답 이름은 **한글만**으로 맞춘다 (사용자 확정, 2026-08-22)

정답지에는 "홍길동 Gildong Hong"처럼 영문이 붙은 칸이 있는데, 파서는 한글만
내놓는다. 그대로 대조하면 **맞은 것을 틀렸다고 센다** — 실제로 그래서 84%를
66%로 잘못 보고한 적이 있다. 그래서 양쪽 모두 한글만 남기고 공백을 지워 견준다.

## ⚠️ 이 스크립트는 규칙을 만들지 않는다

마지막 절의 "줄 높이 vs 낱말 높이"는 **그렇게 골랐다면 어땠을지를 세어 보는
것**이지, 파서를 그렇게 바꾸는 것이 아니다. 규칙 착수는 숫자를 보고 정한다.

## ⚠️ 결과에 개인정보를 찍지 않는다

명함 주인(제3자)의 이름이다. 맞았는지 여부와 개수만 찍는다.
"""
import csv
import re
import sys
from collections import Counter

LS = chr(1)  # 줄 사이
FS = chr(2)  # 줄 안 칸 사이


def hangul_only(s):
    """한글만 남기고 공백을 지운다 — 위 ⚠️ 참고."""
    return ''.join(re.findall(r'[가-힣]', s or ''))


def digits(s):
    return re.sub(r'\D', '', s or '')


def excluded_fields(truth):
    """이 명함에서 **채점하면 안 되는 칸**들.

    ⚠️ `채점제외`는 **명함 단위가 아니라 칸 단위**다. 값이 `휴대폰`·`이메일`·
    `이름`처럼 **칸 이름**이고, 쉼표로 여러 개가 온다. 그 칸에 들어 있는 값이
    사람이 넣은 임의값(자리채움)이라 정답으로 쓸 수 없다는 뜻이다.

    ⚠️ **명함째 버리면 안 된다.** 95장 중 25장에 이 표시가 있는데 그중
    **이름이 걸린 것은 4장뿐**이다. 명함째 버리면 이름 채점 표본이 70장으로
    줄어 정확도가 통째로 흔들린다(2026-08-23에 실제로 그렇게 잘못 셌다).
    """
    raw = (truth.get('채점제외') or '').strip()
    return {x.strip() for x in raw.split(',') if x.strip()}


def load_truth(path):
    """이메일·전화번호로 명함을 찾을 수 있게 정답지를 색인한다.

    사진 파일 이름과 정답지 순번이 이어지지 않아(찍은 순서와 등록 순서가 다르다)
    **내용으로** 맞춰야 한다. 이메일이 가장 안 겹치고, 없으면 전화번호를 쓴다.

    ⚠️ 색인에서는 아무 행도 빼지 않는다. 이메일이 임의값인 명함이라도 **찾는
    데는** 쓸 수 있다 — 앱도 같은 임의값을 읽었을 것이기 때문이다. 채점에서
    빼는 것은 `excluded_fields`가 칸 단위로 따로 판단한다.
    """
    by_email, by_phone = {}, {}
    with open(path, encoding='utf-8') as f:
        for t in csv.DictReader(f, delimiter='\t'):
            e = (t.get('정답_이메일') or '').strip().lower()
            if e:
                by_email.setdefault(e, t)
            for col in ('정답_휴대폰', '정답_사무실'):
                d = digits(t.get(col))
                if len(d) >= 9:
                    by_phone.setdefault(d, t)
    return by_email, by_phone


def parse_row(row):
    c = row.rstrip('\n').split('\t')
    if len(c) < 4:
        return None
    lines, tokens = [], []
    for part in c[1].split(LS):
        f = part.split(FS)
        if len(f) == 2:
            lines.append((f[0], int(f[1])))
    if len(c) >= 5:
        for part in c[4].split(LS):
            f = part.split(FS)
            # v2는 네 칸(글자·높이·위·왼), v3는 너비가 더 붙어 다섯 칸이다.
            # 지난 측정본도 그대로 읽히게 둘 다 받는다 — 너비가 없으면 0으로
            # 채우되, **0을 실제 너비로 쓰면 안 된다**(틈 계산이 통째로 틀린다).
            if len(f) == 4:
                tokens.append((f[0], int(f[1]), int(f[2]), int(f[3]), 0))
            elif len(f) == 5:
                tokens.append(
                    (f[0], int(f[1]), int(f[2]), int(f[3]), int(f[4])))
    return dict(image=c[0], lines=lines, source=c[2], name=c[3], tokens=tokens)


def match_truth(rec, by_email, by_phone):
    blob = ' '.join(t for t, _ in rec['lines'])
    for m in re.findall(r'[\w.\-+]+@[\w.\-]+', blob):
        t = by_email.get(m.lower().strip())
        if t:
            return t
    for d in re.findall(r'\d[\d\-\s]{7,}\d', blob):
        t = by_phone.get(digits(d))
        if t:
            return t
    return None


# 이름처럼 생긴 후보만 남기는 눈금. 파서의 규칙을 옮긴 것이 아니라,
# **크기 신호를 잴 때 말이 되는 후보 안에서 재기 위한** 최소한의 체다.
# 명함에서 가장 큰 글자는 대개 회사 로고라, 아무거나 큰 것을 집으면 크기
# 신호가 실제보다 약해 보인다.
_NOT_NAME = ('주식회사', '(주)', '㈜', '대표', '이사', '부장', '차장', '과장',
             '팀장', '실장', '사원', '주임', '대리', '센터', '연구', '지점')


def name_shaped(text):
    """한글 2~5자이고 숫자·직함어·회사어가 안 섞인 것."""
    h = hangul_only(text)
    if not (2 <= len(h) <= 5) or len(h) != len(text.replace(' ', '')):
        return False
    return not any(k in text for k in _NOT_NAME)


def rows_of(tokens):
    """낱말을 행으로 묶는다 — **앱과 같은 규칙**(평균 높이의 60% 이내)."""
    if not tokens:
        return []
    tol = max(sum(t[1] for t in tokens) / len(tokens) * 0.6, 1)
    out = []
    for t in sorted(tokens, key=lambda x: (x[2], x[3])):
        if out and abs(t[2] - out[-1][0][2]) <= tol:
            out[-1].append(t)
        else:
            out.append([t])
    return out


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    measure_path, truth_path = sys.argv[1], sys.argv[2]
    by_email, by_phone = load_truth(truth_path)

    total = matched = 0
    verdict = Counter()
    by_source = Counter()
    src_right = Counter()
    line_pick = token_pick = both = neither = 0
    comparable = 0
    line_pick_n = token_pick_n = comparable_n = 0

    with open(measure_path, encoding='utf-8') as f:
        for row in f:
            rec = parse_row(row)
            if not rec:
                continue
            total += 1
            truth = match_truth(rec, by_email, by_phone)
            if truth is None:
                verdict['정답지에서 못 찾음'] += 1
                continue
            matched += 1
            if '이름' in excluded_fields(truth):
                verdict['이름이 임의값이라 채점 제외'] += 1
                continue
            want = hangul_only(truth.get('정답_이름'))
            got = hangul_only(rec['name'])
            by_source[rec['source']] += 1
            if not want:
                verdict['정답에 한글 이름이 없음'] += 1
                continue
            if got == want:
                verdict['맞음'] += 1
                src_right[rec['source']] += 1
            elif not rec['name'].strip():
                # ⚠️ **파서가 정말 아무것도 안 내놓은 것**만 빈 값이다.
                # 한글만 남긴 결과가 비었다고 빈 값으로 세면, 영문 이름을
                # 내놓은 것까지 "안 채웠다"로 잡힌다 — 그건 틀린 것이지
                # 비운 것이 아니다. 이 둘을 섞으면 "확신 못 하면 비운다"
                # 변경의 효과를 잴 수 없다(2026-08-23에 실제로 섞어 셌다).
                verdict['빈 값'] += 1
            else:
                verdict['틀림'] += 1

            # ── 여기부터는 **세어 보는 것**이지 규칙이 아니다 ──
            if not rec['tokens']:
                continue
            comparable += 1
            groups = rows_of(rec['tokens'])
            tallest_row = max(groups, key=lambda g: max(t[1] for t in g))
            row_text = hangul_only(''.join(t[0] for t in tallest_row))
            tallest_tok = max(rec['tokens'], key=lambda t: t[1])
            tok_text = hangul_only(tallest_tok[0])
            a, b = row_text == want, tok_text == want
            line_pick += a
            token_pick += b
            both += a and b
            neither += (not a) and (not b)

            # 이름처럼 생긴 후보 안에서만 다시 잰다(위 주석 참고).
            cand_rows = [g for g in groups
                         if name_shaped(''.join(t[0] for t in g))]
            cand_toks = [t for t in rec['tokens'] if name_shaped(t[0])]
            if not cand_rows and not cand_toks:
                continue
            comparable_n += 1
            if cand_rows:
                best = max(cand_rows, key=lambda g: max(t[1] for t in g))
                line_pick_n += hangul_only(''.join(t[0] for t in best)) == want
            if cand_toks:
                best = max(cand_toks, key=lambda t: t[1])
                token_pick_n += hangul_only(best[0]) == want

    print('측정 %d장 · 정답지와 맞춘 것 %d장\n' % (total, matched))
    print('[이름 채점]')
    for k in ('맞음', '틀림', '빈 값', '이름이 임의값이라 채점 제외',
              '정답에 한글 이름이 없음', '정답지에서 못 찾음'):
        if verdict[k]:
            print('  %-18s %3d건' % (k, verdict[k]))
    scored = verdict['맞음'] + verdict['틀림'] + verdict['빈 값']
    if scored:
        print('  ── 채점한 %d장 기준 정확도 %.1f%%'
              % (scored, 100 * verdict['맞음'] / scored))

    print('\n[경로별]')
    for s, n in by_source.most_common():
        print('  %-20s %3d건 중 맞음 %3d (%.0f%%)'
              % (s, n, src_right[s], 100 * src_right[s] / max(n, 1)))

    print('\n[⚠️ 세어 본 것 — 규칙이 아니다] 가장 큰 "행"과 가장 큰 "낱말"')
    print('  견줄 수 있는 명함 %d장' % comparable)
    print('  행 높이로 골랐다면   맞음 %3d (%.0f%%)'
          % (line_pick, 100 * line_pick / max(comparable, 1)))
    print('  낱말 높이로 골랐다면 맞음 %3d (%.0f%%)'
          % (token_pick, 100 * token_pick / max(comparable, 1)))
    print('  둘 다 맞음 %d · 둘 다 틀림 %d · 낱말만 맞음 %d · 행만 맞음 %d'
          % (both, neither, token_pick - both, line_pick - both))
    print('\n  [후보를 이름처럼 생긴 것으로 좁히면] %d장' % comparable_n)
    print('    행 높이로 골랐다면   맞음 %3d (%.0f%%)'
          % (line_pick_n, 100 * line_pick_n / max(comparable_n, 1)))
    print('    낱말 높이로 골랐다면 맞음 %3d (%.0f%%)'
          % (token_pick_n, 100 * token_pick_n / max(comparable_n, 1)))
    print('\n  ⚠️ 이것은 "그 하나만 보고 골랐다면"의 수치다. 실제 파서는 규칙을')
    print('     먼저 보고 확신이 없을 때만 크기를 쓴다 — 위 숫자를 파서 정확도로')
    print('     읽으면 안 된다. 크기 신호가 얼마나 실한지를 보는 눈금이다.')


if __name__ == '__main__':
    main()

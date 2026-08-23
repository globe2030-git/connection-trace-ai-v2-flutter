#!/usr/bin/env python3
"""서버·로컬 모델이 뽑은 결과를 정답지와 대조해 채점한다 (추가 415).

## 왜 앱 채점기와 따로인가

앱 측정본(`score_measure.py`)은 **OCR 원문**을 담고 있어 이메일·전화로 명함을
찾는다. 이 파일은 모델이 **이미 칸을 채운 결과**라 `순번`으로 곧장 붙는다.
자를 두 벌 만드는 것이 아니라, **같은 판정 규칙을 다른 입력에 대는 것**이다.

    python3 tool/ocr_review/score_server.py <결과.tsv> <정답지.tsv>

## ⚠️ 앱 숫자와 견줄 때 분모를 맞춰야 한다

앱 쪽 76.9%는 **기기가 실제로 스캔한 85장**(중복 6장 포함 91줄) 기준이고,
이 파일은 **정답지 91장** 전부를 갖는다. 그대로 견주면 **앱이 못 본 6장을
서버만 푼 셈**이 된다. 그래서 `--only` 로 겹치는 명함만 추릴 수 있게 뒀다.

## ⚠️ 완전 일치만으로 회사·주소를 재면 하한만 나온다

`(주)어디`와 `주식회사 어디`, `서울시 강남구 …`와 `서울 강남구 …`는 같은 값인데
글자가 다르다. 그래서 **하한(완전 일치)과 상한(관대 일치)을 둘 다** 찍는다.
하나만 찍으면 그 값이 실력으로 읽힌다.
"""
import csv
import re
import sys
import unicodedata

HANGUL = re.compile(r'[가-힣]')


def hangul_only(s):
    return ''.join(HANGUL.findall(s or ''))


def digits(s):
    return re.sub(r'\D', '', s or '')


def excluded_fields(t):
    """`채점제외`는 **칸 단위**다 — 명함째 버리면 표본이 무너진다."""
    raw = (t.get('채점제외') or '').strip()
    return {x.strip() for x in raw.split(',') if x.strip()}


_CORP = ('주식회사', '(주)', '㈜', '주)', '유한회사', '(유)', '재단법인', '사단법인',
         'co.,ltd', 'co.ltd', 'ltd', 'inc', 'corp', 'corporation', 'company')


def loose_company(s):
    """법인 표기·공백·기호를 지운다 — 표기 차이를 실력 차이로 세지 않기 위해."""
    s = unicodedata.normalize('NFKC', (s or '')).lower()
    for k in _CORP:
        s = s.replace(k, '')
    return re.sub(r'[^0-9a-z가-힣]', '', s)


_ADDR_NOISE = ('대한민국', '서울시', '서울특별시', '광역시', '특별자치시', '특별자치도')


def loose_address(s):
    """우편번호·시도 표기 흔들림·공백·기호를 지운다."""
    s = unicodedata.normalize('NFKC', (s or '')).lower()
    s = re.sub(r'\b\d{5}\b', '', s)              # 우편번호
    for k in _ADDR_NOISE:
        s = s.replace(k, '')
    return re.sub(r'[^0-9a-z가-힣]', '', s)


def primary_company(s):
    """정답지 회사 칸에서 **주 표기만** 남긴다.

    ⚠️ 정답지는 명함에 인쇄된 대로 **영문 병기까지** 담는다
    (`서울관광재단 (STO, Seoul Tourism Organization)`). 모델은 회사명 하나만
    내놓는 것이 정상이라, 그대로 견주면 **맞은 것을 틀렸다고 센다.**
    2026-08-22에 이름 칸에서 똑같이 데였다(84%를 66%로 보고).
    """
    s = (s or '')
    s = re.sub(r'[\(（].*?[\)）]', ' ', s)          # 괄호 병기 제거
    s = re.sub(r'\s+[A-Za-z][A-Za-z.,&\'\-\s]*$', '', s)  # 뒤에 붙은 영문 병기
    return s.strip()


def full_address(t):
    """정답 주소 + 상세주소.

    ⚠️ 모델은 주소를 **한 덩어리로** 내놓는데 정답지는 주소/상세주소로 갈라
    둔다. 주소 칸만 견주면 상세가 붙은 답이 전부 틀림이 된다(실측 83건).
    """
    a = (t.get('정답_주소') or '').strip()
    b = (t.get('정답_상세주소') or '').strip()
    return (a + ' ' + b).strip()


def contained(a, b):
    """한쪽이 다른 쪽을 품고 **길이도 크게 다르지 않으면** 같은 값으로 본다.

    ⚠️ 길이 조건이 없으면 짧은 값이 긴 값 아무 데나 들어가도 맞았다고 센다 —
    처음에 그렇게 만들어 회사·주소가 100%로 나왔다.
    """
    if not a or not b:
        return False
    if not (a in b or b in a):
        return False
    return min(len(a), len(b)) / max(len(a), len(b)) >= 0.6


FIELDS = [
    # (표시 이름, 정답 칸, 결과 칸, 엄격 정규화, 관대 정규화)
    ('이름', '정답_이름', '이름', hangul_only, hangul_only),
    ('휴대폰', '정답_휴대폰', '휴대폰', digits, digits),
    ('사무실', '정답_사무실', '사무실', digits, digits),
    ('이메일', '정답_이메일', '이메일',
     lambda s: (s or '').strip().lower(), lambda s: (s or '').strip().lower()),
    ('회사', '정답_회사', '회사',
     lambda s: re.sub(r'\s+', '', (s or '')).lower(), loose_company),
    ('직함', '정답_직함', '직함',
     lambda s: re.sub(r'\s+', '', (s or '')).lower(),
     lambda s: re.sub(r'[^0-9a-z가-힣]', '', (s or '').lower())),
    ('주소', '정답_주소', '주소',
     lambda s: re.sub(r'\s+', '', (s or '')).lower(), loose_address),
]

# 칸 이름 → `채점제외`에 적히는 말
EXCL_NAME = {'이름': '이름', '휴대폰': '휴대폰', '사무실': '사무실',
             '이메일': '이메일', '회사': '회사', '직함': '직함', '주소': '주소'}


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    got_path, truth_path = sys.argv[1], sys.argv[2]
    only = None
    if '--only' in sys.argv:
        p = sys.argv[sys.argv.index('--only') + 1]
        only = {l.strip() for l in open(p, encoding='utf-8') if l.strip()}

    truth = {}
    with open(truth_path, encoding='utf-8') as f:
        for t in csv.DictReader(f, delimiter='\t'):
            truth[(t.get('순번') or '').strip()] = t

    rows = list(csv.DictReader(open(got_path, encoding='utf-8'), delimiter='\t'))
    errors = [r for r in rows if (r.get('오류') or '').strip()]
    matched = 0
    stat = {}
    wrong_examples = {}

    for r in rows:
        no = (r.get('순번') or '').strip()
        t = truth.get(no)
        if t is None:
            continue
        if only is not None and no not in only:
            continue
        matched += 1
        exc = excluded_fields(t)
        for label, tcol, gcol, strict, loose in FIELDS:
            if EXCL_NAME[label] in exc:
                continue
            want_raw = (t.get(tcol) or '').strip()
            got_raw = (r.get(gcol) or '').strip()
            # 정답지 쪽 표기 관행을 맞춰 준다(위 두 함수의 ⚠️ 참고).
            want_loose_raw = want_raw
            if label == '회사':
                want_loose_raw = primary_company(want_raw)
            elif label == '주소':
                want_loose_raw = full_address(t)
            if not want_raw:
                continue
            s = stat.setdefault(label, dict(n=0, exact=0, loose=0, blank=0))
            s['n'] += 1
            if not got_raw:
                s['blank'] += 1
                continue
            if strict(got_raw) == strict(want_raw):
                s['exact'] += 1
                s['loose'] += 1
            elif (loose(got_raw) == loose(want_loose_raw)
                  or contained(loose(got_raw), loose(want_loose_raw))):
                s['loose'] += 1
            else:
                wrong_examples.setdefault(label, []).append(no)

    print('결과 %d행 · 정답지와 붙은 것 %d행 · 호출 오류 %d건'
          % (len(rows), matched, len(errors)))
    if only is not None:
        print('(--only 로 %d장만 채점)' % len(only))
    print()
    print('%-8s %5s %10s %10s %8s' % ('칸', '분모', '완전일치', '관대일치', '빈값'))
    for label, *_ in FIELDS:
        s = stat.get(label)
        if not s or not s['n']:
            continue
        print('%-8s %5d %6d(%3.0f%%) %6d(%3.0f%%) %6d'
              % (label, s['n'], s['exact'], 100 * s['exact'] / s['n'],
                 s['loose'], 100 * s['loose'] / s['n'], s['blank']))
    print()
    print('⚠️ 완전일치는 **하한**, 관대일치는 **상한**이다. 회사·주소는 표기가')
    print('   흔들려 완전일치만 보면 실력보다 낮게 나온다.')


if __name__ == '__main__':
    main()

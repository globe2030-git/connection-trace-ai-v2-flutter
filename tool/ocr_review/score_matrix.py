#!/usr/bin/env python3
"""여러 인식 방식을 **전 필드**로 나란히 채점한다 (추가 415).

## 왜 만들었나

사용자 지적: *"일부 필드만 보고 답을 찾으면 안 된다."* 그때까지 축별 비교가
**이름 하나**로만 있었다. 이름이 좋아도 다른 칸이 나쁘면 실제 손이 더 간다.

## ⚠️ 축마다 **낼 수 있는 칸이 다르다** — 0%로 세면 안 된다

모델 축(로컬·서버)은 프롬프트에서 **7칸만** 요구받았다
(이름·회사·직함·휴대폰·사무실·이메일·주소). 앱은 부서·팩스·홈페이지·
상세주소도 낸다.

**요구하지 않은 칸을 "못 냈다"로 세면 그 축을 실제보다 나쁘게 만든다.**
그래서 축마다 `fields` 를 선언하고, **선언하지 않은 칸은 표에서 `—`**로 둔다.

## 쓰는 법

    python3 tool/ocr_review/score_matrix.py <정답지.tsv> [--only 목록]

축은 아래 `AXES`에 적혀 있다. 파일이 없는 축은 조용히 건너뛴다.
"""
import csv
import os
import re
import sys
import unicodedata

A = '/Volumes/X31/Claude/connection-sense-assets/명함데이터/'
SCRATCH = os.environ.get('SCRATCH', '')

# (표시 이름, 파일, 키 칸, 낼 수 있는 칸)
MODEL_FIELDS = ['이름', '회사', '직함', '휴대폰', '사무실', '이메일', '주소']
APP_FIELDS = MODEL_FIELDS + ['부서', '팩스', '홈페이지', '상세주소']
# 12칸 완전판은 정답지가 가진 칸을 전부 요구받았다(우편번호 포함).
FULL_FIELDS = APP_FIELDS + ['우편번호']

AXES = [
    ('앱(ML Kit+규칙)', SCRATCH + 'app_all.tsv', '사진', APP_FIELDS),
    ('mistral-small3.1', A + 'server_ocr_local_2026-08-23.tsv', '순번', MODEL_FIELDS),
    ('qwen2.5vl:7b', A + 'server_ocr_local_qwen_2026-08-23.tsv', '순번', MODEL_FIELDS),
    ('Gemini(1차)', A + 'server_ocr_gemini_2026-08-23.tsv', '순번', MODEL_FIELDS),
    ('2.5서울(비우기강제)', A + 'server_ocr_vertex25_strict_2026-08-23.tsv',
     '순번', MODEL_FIELDS),
    ('2.5서울(기본)', A + 'server_ocr_vertex25_base_2026-08-23.tsv',
     '순번', MODEL_FIELDS),
    ('2.5서울(12칸완전판)', A + 'server_ocr_vertex25_full_2026-08-23.tsv',
     '순번', FULL_FIELDS),
]

TRUTH_COL = {
    '이름': '정답_이름', '회사': '정답_회사', '직함': '정답_직함',
    '부서': '정답_부서', '휴대폰': '정답_휴대폰', '사무실': '정답_사무실',
    '팩스': '정답_팩스', '이메일': '정답_이메일', '홈페이지': '정답_홈페이지',
    '주소': '정답_주소', '상세주소': '정답_상세주소',
    '우편번호': '정답_우편번호',
}
ORDER = ['이름', '회사', '직함', '부서', '휴대폰', '사무실', '팩스',
         '이메일', '홈페이지', '우편번호', '주소', '상세주소']

HANGUL = re.compile(r'[가-힣]')
_CORP = ('주식회사', '(주)', '㈜', '주)', '유한회사', '(유)', '재단법인', '사단법인',
         'co.,ltd', 'co.ltd', 'ltd', 'inc', 'corp', 'corporation', 'company')


def hangul_only(s):
    return ''.join(HANGUL.findall(s or ''))


def digits(s):
    return re.sub(r'\D', '', s or '')


def tight(s):
    return re.sub(r'\s+', '', unicodedata.normalize('NFKC', s or '')).lower()


def loose_company(s):
    s = tight(s)
    for k in _CORP:
        s = s.replace(k, '')
    return re.sub(r'[^0-9a-z가-힣]', '', s)


def loose_plain(s):
    return re.sub(r'[^0-9a-z가-힣]', '', tight(s))


def primary_company(s):
    """정답지 회사 칸의 **주 표기만** — 영문 병기를 걷어낸다."""
    s = re.sub(r'[\(（].*?[\)）]', ' ', s or '')
    s = re.sub(r'\s+[A-Za-z][A-Za-z.,&\'\-\s]*$', '', s)
    return s.strip()


# 칸별 (엄격 정규화, 관대 정규화)
NORM = {
    '이름': (hangul_only, hangul_only),
    '휴대폰': (digits, digits), '사무실': (digits, digits), '팩스': (digits, digits),
    '이메일': (lambda s: (s or '').strip().lower(),) * 2,
    '홈페이지': (lambda s: re.sub(r'^https?://|^www\.|/$', '', (s or '').strip().lower()),) * 2,
    '우편번호': (digits, digits),
}


def norms(field):
    if field in NORM:
        return NORM[field]
    if field == '회사':
        return (tight, loose_company)
    return (tight, loose_plain)


def excluded(t):
    raw = (t.get('채점제외') or '').strip()
    return {x.strip() for x in raw.split(',') if x.strip()}


def contained(a, b):
    if not a or not b or not (a in b or b in a):
        return False
    return min(len(a), len(b)) / max(len(a), len(b)) >= 0.6


def want_for(field, t):
    """정답 쪽 값 — 칸에 따라 표기 관행을 맞춘다.

    ⚠️ 주소는 모델이 **한 덩어리로** 내는데 정답지는 주소/상세를 갈라 둔다.
    관대 쪽에서는 합쳐 견준다.
    """
    strict = (t.get(TRUTH_COL[field]) or '').strip()
    if field == '회사':
        return strict, primary_company(strict)
    if field == '주소':
        both = (strict + ' ' + (t.get('정답_상세주소') or '')).strip()
        return strict, both
    return strict, strict


def load_axis(path, key):
    if not os.path.exists(path):
        return None
    out = {}
    with open(path, encoding='utf-8') as f:
        for r in csv.DictReader(f, delimiter='\t'):
            out.setdefault((r.get(key) or '').strip(), []).append(r)
    return out


def main():
    truth_path = sys.argv[1]
    only = None
    if '--only' in sys.argv:
        only = {l.strip() for l in
                open(sys.argv[sys.argv.index('--only') + 1], encoding='utf-8')
                if l.strip()}

    truth = {}
    photo_to_no = {}
    with open(truth_path, encoding='utf-8') as f:
        for t in csv.DictReader(f, delimiter='\t'):
            truth[(t.get('순번') or '').strip()] = t

    # 앱 축은 사진 이름이 열쇠라 정답지와 내용으로 붙여야 한다.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import score_measure as SM
    by_email, by_phone = SM.load_truth(truth_path)

    table = {}
    notes = {}
    for label, path, key, fields in AXES:
        rows = load_axis(path, key)
        if rows is None:
            continue
        col = {}
        blank = wrong = 0
        for field in fields:
            n = ex = lo = bl = 0
            for k, rs in rows.items():
                r = rs[0]
                if key == '순번':
                    t = truth.get(k)
                else:  # 앱: 줄 원문으로 찾는다
                    payload = r.get('줄', '')
                    rec = {'lines': [(p.split(chr(2))[0], 0)
                                     for p in payload.split(chr(1)) if chr(2) in p]}
                    t = SM.match_truth(rec, by_email, by_phone)
                if t is None:
                    continue
                no = (t.get('순번') or '').strip()
                if only is not None and no not in only:
                    continue
                if field in excluded(t):
                    continue
                ws, wl = want_for(field, t)
                if not ws:
                    continue
                g = (r.get(field) or '').strip()
                n += 1
                s_norm, l_norm = norms(field)
                if not g:
                    bl += 1
                    continue
                if s_norm(g) == s_norm(ws):
                    ex += 1
                    lo += 1
                elif l_norm(g) == l_norm(wl) or contained(l_norm(g), l_norm(wl)):
                    lo += 1
            col[field] = (n, ex, lo, bl)
            blank += bl
            wrong += n - lo - bl
        table[label] = col
        notes[label] = (blank, wrong)

    labels = [l for l, *_ in AXES if l in table]
    print('필드 × 축 — 완전일치%% (관대일치%%) · 분모\n')
    w = max(len(x) for x in labels) + 2
    head = '%-10s' % '칸' + ''.join('%-*s' % (w + 8, l) for l in labels)
    print(head)
    print('-' * len(head))
    for field in ORDER:
        line = '%-10s' % field
        for l in labels:
            c = table[l].get(field)
            if c is None:
                line += '%-*s' % (w + 8, '—')
                continue
            n, ex, lo, bl = c
            if n == 0:
                line += '%-*s' % (w + 8, '(표본없음)')
                continue
            cell = ('%d%%' % round(100 * ex / n)
                    + ('' if lo == ex else '(%d%%)' % round(100 * lo / n))
                    + ' %d' % n)
            line += '%-*s' % (w + 8, cell)
        print(line)
    print()
    print('— : 그 축이 **요구받지 않은 칸**이다(0%가 아니다)')
    print()
    print('⚠️ 주소의 **완전일치는 축끼리 견줄 수 없다.** 앱은 정답지처럼 주소와')
    print('   상세주소를 갈라 내고, 모델은 한 덩어리로 낸다 — 같은 실력이어도')
    print('   앱이 높게 나온다. 주소는 **관대 쪽**으로 견주어야 한다.')
    print()
    for l in labels:
        bl, wr = notes[l]
        tot = bl + wr
        share = 100 * bl / tot if tot else 0
        print('  %-18s 못 맞힌 %3d칸 중 빈값 %3d (%2.0f%%) · 틀린 값 %3d'
              % (l, tot, bl, share, wr))


if __name__ == '__main__':
    main()

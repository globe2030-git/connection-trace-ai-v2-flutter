#!/usr/bin/env python3
"""여러 인식 축을 **섞었을 때** 어디까지 가는지 계산한다 (추가 418).

새로 재지 않는다 — 이미 있는 결과 TSV들로 셋을 계산한다.

1. **역할 분담**: 서버가 7칸 + 앱이 나머지 4칸. 채택 시 실제 모습에 가깝다.
2. **일치 검증**: 앱과 서버가 같은 값을 낸 칸의 정답률 vs 다른 값을 낸 칸.
   *"둘이 같으면 자동 확정, 다르면 확인 화면에서 강조"*가 성립하는지 본다.
3. **필드별 최적(상한)**: 칸마다 가장 잘하는 축을 골랐을 때.

⚠️ **3은 운영 가능한 조합이 아니다.** 어느 축이 잘하는지는 **정답지를 봐야**
아는 것이고, 실제로는 그 정보가 없다. **상한을 보는 눈금**일 뿐이다.
"""
import csv
import os
import re
import sys
import unicodedata

A = '/Volumes/X31/Claude/connection-sense-assets/명함데이터/'
SCRATCH = os.environ.get('SCRATCH', '')

MODEL_FIELDS = ['이름', '회사', '직함', '휴대폰', '사무실', '이메일', '주소']
APP_ONLY = ['부서', '팩스', '홈페이지', '상세주소']
ALL_FIELDS = MODEL_FIELDS + APP_ONLY

TRUTH_COL = {'이름': '정답_이름', '회사': '정답_회사', '직함': '정답_직함',
             '부서': '정답_부서', '휴대폰': '정답_휴대폰', '사무실': '정답_사무실',
             '팩스': '정답_팩스', '이메일': '정답_이메일', '홈페이지': '정답_홈페이지',
             '주소': '정답_주소', '상세주소': '정답_상세주소'}

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
    s = re.sub(r'[\(（].*?[\)）]', ' ', s or '')
    return re.sub(r'\s+[A-Za-z][A-Za-z.,&\'\-\s]*$', '', s).strip()


NORM = {'이름': (hangul_only, hangul_only),
        '휴대폰': (digits, digits), '사무실': (digits, digits), '팩스': (digits, digits),
        '이메일': (lambda s: (s or '').strip().lower(),) * 2,
        '홈페이지': (lambda s: re.sub(r'^https?://|^www\.|/$', '',
                                  (s or '').strip().lower()),) * 2}


def norms(f):
    if f in NORM:
        return NORM[f]
    return (tight, loose_company) if f == '회사' else (tight, loose_plain)


def excluded(t):
    raw = (t.get('채점제외') or '').strip()
    return {x.strip() for x in raw.split(',') if x.strip()}


def contained(a, b):
    if not a or not b or not (a in b or b in a):
        return False
    return min(len(a), len(b)) / max(len(a), len(b)) >= 0.6


def want_for(field, t):
    strict = (t.get(TRUTH_COL[field]) or '').strip()
    if field == '회사':
        return strict, primary_company(strict)
    if field == '주소':
        return strict, (strict + ' ' + (t.get('정답_상세주소') or '')).strip()
    return strict, strict


def ok(field, got, t, lenient=True):
    """맞았나 — 관대 기준까지 인정한다(표기 관행 차이를 실력으로 세지 않는다)."""
    ws, wl = want_for(field, t)
    if not ws:
        return None                      # 정답이 없는 칸 — 채점 대상 아님
    if not (got or '').strip():
        return False
    s_norm, l_norm = norms(field)
    if s_norm(got) == s_norm(ws):
        return True
    if not lenient:
        return False
    return l_norm(got) == l_norm(wl) or contained(l_norm(got), l_norm(wl))


def main():
    truth_path = sys.argv[1]
    truth = {(t.get('순번') or '').strip(): t for t in
             csv.DictReader(open(truth_path, encoding='utf-8'), delimiter='\t')}

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import score_measure as SM
    by_email, by_phone = SM.load_truth(truth_path)

    # 앱 축: 사진 이름이 열쇠라 줄 원문으로 정답지와 붙인다.
    app = {}
    with open(SCRATCH + 'app_all.tsv', encoding='utf-8') as f:
        for r in csv.DictReader(f, delimiter='\t'):
            rec = {'lines': [(p.split(chr(2))[0], 0)
                             for p in r.get('줄', '').split(chr(1)) if chr(2) in p]}
            t = SM.match_truth(rec, by_email, by_phone)
            if t is None:
                continue
            app.setdefault((t.get('순번') or '').strip(), r)

    srv = {r['순번']: r for r in csv.DictReader(
        open(A + 'server_ocr_vertex25_base_2026-08-23.tsv', encoding='utf-8'),
        delimiter='\t')}
    others = {
        'mistral': A + 'server_ocr_local_2026-08-23.tsv',
        'qwen7b': A + 'server_ocr_local_qwen_2026-08-23.tsv',
        'Gemini1차': A + 'server_ocr_gemini_2026-08-23.tsv',
        '2.5강화': A + 'server_ocr_vertex25_strict_2026-08-23.tsv',
    }
    axes = {'앱': app, '2.5서울(기본)': srv}
    for k, p in others.items():
        if os.path.exists(p):
            axes[k] = {r['순번']: r for r in
                       csv.DictReader(open(p, encoding='utf-8'), delimiter='\t')}

    common = sorted(set(app) & set(srv), key=lambda x: int(x))

    # ── 1. 역할 분담 ──────────────────────────────────────────────
    print('■ 1. 역할 분담 — 서버가 7칸 + 앱이 나머지 4칸  (%d장)\n' % len(common))
    print('%-8s %-10s %s' % ('칸', '맡는 쪽', '정답률'))
    tot_n = tot_ok = 0
    for f in ALL_FIELDS:
        who = '서버' if f in MODEL_FIELDS else '앱'
        src = srv if who == '서버' else app
        n = good = 0
        for no in common:
            t = truth[no]
            if f in excluded(t):
                continue
            v = ok(f, (src[no].get(f) or ''), t)
            if v is None:
                continue
            n += 1
            good += v
        tot_n += n
        tot_ok += good
        print('%-8s %-10s %3d%% (%d/%d)' % (f, who, round(100*good/max(n,1)), good, n))
    print('%-8s %-10s **%3d%%** (%d/%d)'
          % ('전체', '', round(100*tot_ok/max(tot_n,1)), tot_ok, tot_n))

    # ── 2. 일치 검증 ──────────────────────────────────────────────
    print('\n■ 2. 일치 검증 — 앱과 서버가 같은 값을 냈을 때\n')
    print('%-8s %8s %12s %12s %10s' %
          ('칸', '일치율', '일치 시 정답', '불일치 시 앱', '불일치 시 서버'))
    ag_n = ag_ok = 0
    for f in MODEL_FIELDS:
        same = same_ok = diff = diff_app = diff_srv = 0
        s_norm, _ = norms(f)
        for no in common:
            t = truth[no]
            if f in excluded(t):
                continue
            a, b = (app[no].get(f) or ''), (srv[no].get(f) or '')
            va, vb = ok(f, a, t), ok(f, b, t)
            if va is None:
                continue
            if s_norm(a) == s_norm(b):
                same += 1
                same_ok += va
            else:
                diff += 1
                diff_app += va
                diff_srv += vb
        ag_n += same
        ag_ok += same_ok
        print('%-8s %7d%% %10d%% %11d%% %10d%%'
              % (f, round(100*same/max(same+diff,1)),
                 round(100*same_ok/max(same,1)),
                 round(100*diff_app/max(diff,1)),
                 round(100*diff_srv/max(diff,1))))
    print('\n  일치한 칸 전체 정답률: **%d%%** (%d/%d)'
          % (round(100*ag_ok/max(ag_n,1)), ag_ok, ag_n))

    # ── 3. 필드별 최적(상한) ──────────────────────────────────────
    print('\n■ 3. 칸마다 가장 잘하는 축을 골랐다면 (⚠️ 상한 — 운영 불가)\n')
    print('%-8s %-16s %s' % ('칸', '가장 잘한 축', '정답률'))
    up_n = up_ok = 0
    for f in ALL_FIELDS:
        best = None
        for label, src in axes.items():
            if f in APP_ONLY and label != '앱':
                continue
            n = good = 0
            for no in common:
                t = truth[no]
                if f in excluded(t):
                    continue
                r = src.get(no)
                if r is None:
                    continue
                v = ok(f, (r.get(f) or ''), t)
                if v is None:
                    continue
                n += 1
                good += v
            if n and (best is None or good/n > best[1]):
                best = (label, good/n, good, n)
        if best:
            up_n += best[3]
            up_ok += best[2]
            print('%-8s %-16s %3d%% (%d/%d)'
                  % (f, best[0], round(100*best[1]), best[2], best[3]))
    print('%-8s %-16s **%3d%%** (%d/%d)'
          % ('전체', '', round(100*up_ok/max(up_n,1)), up_ok, up_n))
    print('\n⚠️ 3은 **정답지를 보고 고른 것**이라 실제로는 못 쓴다. 상한 눈금이다.')


if __name__ == '__main__':
    main()

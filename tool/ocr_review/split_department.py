# 정답지를 새 규칙으로 재정리한다 — 정답_직함에서 부서를 떼어 정답_부서로.
#
# 2026-08-19 사용자 확정: 부서는 직함 칸에 넣지 않고 별도 필드로 뺀다.
#
# ⚠️ 값은 화면에 찍지 않는다(제3자 개인정보). 바뀐 장 수와 모양만 센다.
import io, re, sys, shutil, datetime

SRC = sys.argv[1]
DRY = "--write" not in sys.argv

# 파서와 같은 목록을 쓴다(ocr_scanner_service.dart의 _departmentSuffixes).
# 긴 것부터 — '팀'/'실'은 짧아 우연히 겹칠 수 있다.
SUFFIXES = [
    "사업본부", "기획실", "관리부", "지원부", "지원실", "사업부",
    "부서", "본부", "센터", "팀", "실", "국", "처",
]

# 파서의 _titleKeywords 중 실제 정답지에 나오는 것들.
TITLE_WORDS = [
    "대표", "이사", "사장", "부사장", "전무", "상무", "본부장", "실장", "국장",
    "부장", "차장", "과장", "팀장", "파트장", "그룹장", "센터장", "소장",
    "대리", "주임", "사원", "매니저", "Manager", "Director", "CEO", "CTO",
    "COO", "CFO", "President", "Head", "Lead", "변리사", "감리원", "전문위원",
    "연구원", "연구소장", "수석", "책임", "선임", "위원", "기사", "기술사",
]

STRIP = re.compile(r"^[|:/,.·]+|[|:/,.·]+$")
WS = re.compile(r"[\s　]+")


def split_dept(title):
    """직함 문자열에서 부서 토큰을 떼어낸다. (직함, 부서)를 돌려준다."""
    tokens = [t for t in WS.split(title) if t]
    if len(tokens) < 2:
        return title, ""
    # 접미사 토큰에서 **앞으로 이어 붙인다** — 부서 이름의 앞머리가 직함에
    # 남지 않게(`ICT 사업본부 상무` → 부서 `ICT 사업본부`, 직함 `상무`).
    # 앞 토큰이 직함 낱말이면 멈춘다(`상무 ICT사업본부`에서 상무를 안 뺏는다).
    is_dept = [False] * len(tokens)
    for i, tok in enumerate(tokens):
        bare = STRIP.sub("", tok)
        if not bare or not any(bare.endswith(s) for s in SUFFIXES):
            continue
        is_dept[i] = True
        j = i - 1
        while j >= 0 and not is_dept[j]:
            prev = STRIP.sub("", tokens[j])
            if not prev or any(k in prev for k in TITLE_WORDS):
                break
            is_dept[j] = True
            j -= 1
    dept = [STRIP.sub("", t) for t, d in zip(tokens, is_dept) if d]
    rest = [t for t, d in zip(tokens, is_dept) if not d]
    if dept and rest:
        return STRIP.sub("", " ".join(rest)).strip(), " ".join(dept)
    return title, ""


with io.open(SRC, encoding="utf-8") as f:
    head = f.readline().rstrip("\n").split("\t")
    rows = [l.rstrip("\n").split("\t") for l in f]

if "정답_부서" in head:
    print("이미 정답_부서 칸이 있다 — 중단")
    sys.exit(1)

ti = head.index("정답_직함")
new_head = head[: ti + 1] + ["정답_부서"] + head[ti + 1 :]

changed = 0
out = []
for r in rows:
    r = r + [""] * (len(head) - len(r))
    title, dept = split_dept(r[ti])
    if dept:
        changed += 1
    out.append(r[: ti] + [title, dept] + r[ti + 1 :])

print(f"정답지 {len(rows)}장 중 **{changed}장**에서 부서를 떼어냈다")
print(f"칸: {len(head)}개 → {len(new_head)}개 ('정답_부서' 추가)")

if DRY:
    print("\n(연습 실행 — 파일은 안 건드렸다. --write 를 붙이면 실제로 쓴다)")
else:
    stamp = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")
    bak = SRC.replace(".tsv", f".backup-부서분리전-{stamp}.tsv")
    shutil.copy2(SRC, bak)
    with io.open(SRC, "w", encoding="utf-8") as f:
        f.write("\t".join(new_head) + "\n")
        for r in out:
            f.write("\t".join(r) + "\n")
    print(f"\n원본 백업: {bak.split('/')[-1]}")
    print("정답지 갱신 완료")

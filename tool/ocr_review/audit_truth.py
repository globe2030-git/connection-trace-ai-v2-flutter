# 정답지 자체가 의심스러운 자리를 찾는다.
#
# ⚠️ 왜 필요한가 (2026-08-19, 추가 324)
#
# 채점기와 분해기는 **정답지를 믿는다.** 정답이 틀리면 두 숫자 다 틀리는데,
# 겉으로는 "파서가 틀렸다"로 보인다. 실제로 회사 오류 28건 중 최소 3건이
# **정답지 쪽 문제**였다(잘린 회사명 2건, 회사 칸에 직함이 들어간 것 1건).
#
# 이 스크립트는 **고치지 않는다.** 사람이 볼 목록을 만들 뿐이다 — 진짜 값은
# 명함 실물에 있고, 그건 검수 도구로 봐야 한다.
#
# ⚠️ 개인정보: 이름·전화·이메일 값은 찍지 않는다. 회사·직함처럼 법인/직위
# 정보만 보여 주고, 나머지는 "무엇이 이상한지"만 말한다.
import io, re, sys

TRUTH = sys.argv[1]
SCAN = sys.argv[2] if len(sys.argv) > 2 else None

WS = re.compile(r"\s+")
BAR = re.compile(r"[|·｜]")


def norm(s):
    return WS.sub(" ", BAR.sub(" ", s or "")).strip()


def squash(s):
    return norm(s).replace(" ", "")


def load(path, key="파일명"):
    rows = {}
    with io.open(path, encoding="utf-8") as f:
        head = f.readline().rstrip("\n").split("\t")
        for line in f:
            c = line.rstrip("\n").split("\t")
            c += [""] * (len(head) - len(c))
            r = dict(zip(head, c))
            if r.get(key):
                rows[r[key]] = r
    return rows


truth = load(TRUTH)
scan = load(SCAN) if SCAN else {}

# 직함 낱말 — 회사 칸에 이것만 들어 있으면 칸을 잘못 쓴 것이다.
TITLE_ONLY = {
    "대표", "이사", "사장", "부장", "차장", "과장", "팀장", "대리", "주임",
    "사원", "실장", "본부장", "소장", "수석", "책임", "선임", "매니저",
}

checked = [k for k, v in truth.items() if v.get("확인함", "").strip() == "Y"]
findings = []

for fid in sorted(checked):
    t = truth[fid]
    raw = scan.get(fid, {}).get("원문", "")
    rawS = squash(raw)

    for field in ("회사", "직함", "부서"):
        v = norm(t.get("정답_" + field, ""))
        if not v:
            continue

        # ① 회사 칸에 직함만 들어 있다
        if field == "회사" and v in TITLE_ONLY:
            findings.append((fid, field, v, "회사 칸에 직함이 들어갔다"))
            continue

        # ② 원문의 **한 낱말**이 정답으로 시작하는데 더 길다 = 잘렸다
        #
        # ⚠️ 첫 판은 공백을 지운 덩어리에서 "뒤에 뭐가 이어지나"를 봤는데,
        # 그러면 **다음 줄이 늘 걸려** 56건 중 대부분이 잡음이었다. 낱말
        # 단위로 봐야 진짜 잘림이다(`한국사회보장정` ⊂ `한국사회보장정보원`).
        if field in ("회사", "부서") and len(v) >= 2:
            longer = [
                w for w in re.split(r"[\s⏐|·]+", raw)
                if len(w) > len(v) and w.startswith(v)
            ]
            if longer:
                findings.append(
                    (fid, field, v, f"원문에 더 긴 낱말이 있다: '{longer[0]}' — 잘렸을 수 있다")
                )
                continue

        # ③ 원문 어디에도 없다 = 정답이 원문과 무관
        if rawS and squash(v) not in rawS and field in ("회사", "직함", "부서"):
            parts = [p for p in v.split() if p]
            if parts and not any(squash(p) in rawS for p in parts):
                findings.append((fid, field, v, "원문 어디에도 조각조차 없다"))

print(f"검수 완료 {len(checked)}장 중 의심 {len(findings)}건\n")
cur = None
for fid, field, v, why in findings:
    if fid != cur:
        print(f"\n{fid}")
        cur = fid
    show = v if field in ("회사", "직함", "부서") else "(값 생략 — 개인정보)"
    print(f"   [{field}] {show}")
    print(f"        → {why}")

print("\n⚠️ 이 목록은 **고칠 후보**일 뿐이다. 진짜 값은 명함 실물에 있다 —")
print("   검수 도구(tool/ocr_review/index.html)로 원본과 대조해 고칠 것.")

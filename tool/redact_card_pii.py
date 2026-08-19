# 문서에 남은 **명함 주인(제3자)** 연락처를 가린다.
#
# ⚠️ 건드리면 안 되는 것 — 자사 정보다. 성격이 다르다.
#   - docs/legal/**            공개된 법적 고지
#   - creamhouse 도메인 주소   자사 계정
#   - 사용자 본인 계정
#
# 값은 **서로 다르게** 바꾼다. "card_05와 card_66은 다른 번호"라는 뜻이
# 기록에 실려 있어서, 전부 같은 값으로 만들면 그 뜻이 사라진다.
import io, os, re, sys

WRITE = "--write" in sys.argv
ROOT = "docs"
SKIP_DIRS = {"docs/legal"}
# ⚠️ **이미 가짜인 값은 건드리지 않는다.** 첫 판이 `hong@naver.com`·
# `user@naver.com`(예시라고 적혀 있다)·`010-1111-2222`(QA 테스트값)까지
# 바꿔 버렸다 — 안전해지지도 않으면서 예시만 읽기 나빠졌다.
KEEP = re.compile(
    r"creamhouse|globe2030|@example|@b\.com|1588-3112"
    # 뻔한 예시 아이디
    r"|\b(?:hong|gildong|user|test|sample|example|abc|foo|name|admin)@"
    # 같은 숫자 넷 반복(1111·2222·0000) 또는 1234/5678 — 사람이 지어낸 값이다
    r"|(\d)\1{3}"
    r"|1234|5678"
)

MOBILE = re.compile(r"\b01[016789][-. ]?\d{3,4}[-. ]?\d{4}\b")
LAND   = re.compile(r"\b0(?:2|[3-6]\d|70)[-. ]?\d{3,4}[-. ]?\d{4}\b")
EMAIL  = re.compile(r"\b[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+\.(?:co\.kr|or\.kr|com|net|kr)\b")

mob, land, mail = {}, {}, {}

def sub_mobile(m):
    v = m.group(0)
    if KEEP.search(v): return v
    mob.setdefault(v, f"010-0000-{len(mob)+1:04d}")
    return mob[v]

def sub_land(m):
    v = m.group(0)
    if KEEP.search(v): return v
    land.setdefault(v, f"02-0000-{len(land)+1:04d}")
    return land[v]

def sub_mail(m):
    v = m.group(0)
    if KEEP.search(v): return v
    dom = v.split("@")[1]
    mail.setdefault(v, f"card{len(mail)+1:02d}@{dom}")
    return mail[v]

changed = []
for dp, _, fns in os.walk(ROOT):
    if any(dp == s or dp.startswith(s + "/") for s in SKIP_DIRS): continue
    for fn in fns:
        if not fn.endswith((".md", ".html", ".txt")): continue
        p = os.path.join(dp, fn)
        s = io.open(p, encoding="utf-8").read()
        n = EMAIL.sub(sub_mail, MOBILE.sub(sub_mobile, s))
        n = LAND.sub(sub_land, n)
        if n != s:
            changed.append((p, sum(1 for a, b in zip(s.split("\n"), n.split("\n")) if a != b)))
            if WRITE: io.open(p, "w", encoding="utf-8").write(n)

print(f"휴대폰 {len(mob)}개 · 유선 {len(land)}개 · 이메일 {len(mail)}개를 가린다")
print(f"파일 {len(changed)}개\n")
for p, c in sorted(changed, key=lambda x: -x[1]):
    print(f"  {c:3d}줄  {p}")
if not WRITE:
    print("\n(연습 실행 — 파일은 안 건드렸다. --write 로 실제 반영)")

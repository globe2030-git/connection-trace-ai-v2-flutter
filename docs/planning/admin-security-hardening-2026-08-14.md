# 관리자 보안 즉시급 4건 — 작업기록 (2026-08-14)

- 담당: 관리자(admin) 개발 세션
- 근거: [`admin-security-vulnerability-assessment-2026-08-13.md`](./admin-security-vulnerability-assessment-2026-08-13.md)(취약점 12건),
  [`admin-code-privacy-audit-2026-08-13.md`](./admin-code-privacy-audit-2026-08-13.md)(코드·개인정보 점검)
- 브랜치: `feat/admin-security-hardening` → **PR #149로 main 병합됨**(2026-08-14 11:53)
- 상태: **구현·자동검증·병합 완료 / 실서버 배포는 미완**(아래 6절 (b) 목록)

---

## 1. 배경

2026-08-13 관리자 전용 감사 2건에서 취약점 12건(높음 3·중간 8·낮음 1)이
나왔다. 감사일 이후 관리자 코드가 하나도 고쳐지지 않은 상태였다(커밋 이력으로
확인). 이 중 **출시/운영 차단급 "즉시급 4건"**을 먼저 수정했다. 나머지
중간 8건·낮음 1건은 미착수로 남는다.

작업은 이 저장소 규약대로 `origin/main` 기준 격리 `git worktree`
(`connection-trace-ai-v2-flutter-admin`)에서만 진행해 공유 트리(명함인식·기능
개선·지갑 세션)를 건드리지 않았다.

## 2. 수정 4건 — 증상 → 원인 → 해결

### 1) 법적 문서 편집기가 실제 앱에 반영되지 않음 (code-privacy P0-1)

- **증상**: 관리자 콘솔이 "여기서 고치면 앱 재배포 없이 바로 반영"이라 안내.
- **원인**: 콘솔은 Firestore `legalDocs/{slug}`를 읽고 쓰지만, 앱은 그걸 전혀
  안 읽고 `connection-sense.web.app/{slug}` 정적 Hosting HTML을 연다
  (`legal_document_view.dart`). 즉 콘솔 편집이 사용자·스토어 심사에 **닿지
  않는데 닿는 것처럼** 안내 → 방침과 실제 고지가 어긋나는 법적 리스크.
- **해결**: `admin.js`의 법적문서 편집(저장/삭제) 경로 제거·읽기전용화. 배너를
  "이 편집은 앱/웹에 반영되지 않으며, 실제 문안은 `docs/legal/*.html`을 고친 뒤
  `firebase deploy --only hosting:legal`로 배포한다"로 교체. `README.md` 정정.
  Firestore `legalDocs` 규칙은 후속(진짜 게시 파이프라인) 재사용 위해 남김.

### 2) 관리자 해제 후 Callable 권한 잔존 (ADMIN-VULN-001 / P0-2)

- **증상**: README대로 `firestore.rules`에서만 관리자를 빼도 `getUserUsage`·
  `grantBonusCredits`가 계속 통과.
- **원인**: 관리자 이메일이 `rules`(isAdmin)와 `functions`(ADMIN_EMAILS)에 문자
  그대로 두 벌. 어긋나도 아무도 알려주지 않음.
- **해결(인터림)**: `functions/src/adminEmails.ts`를 단일 소스로 두고 `index.ts`가
  import. Rules는 외부 파일 import가 불가능해 리터럴이 불가피 → `tool/
  check_admin_sync.py`가 소스 배열들을 파싱·비교해 **불일치 시 실패**(N-소스
  제네릭 구조). CI(`.github/workflows/ci.yml`)에 반영. README를 "여러 소스를
  함께 고치고 동기화검사 통과 후 동시 배포, 탈취 의심 시 refresh token 폐기"로
  교체.
- **PR #144 반영 후 확장**: 명함 세션의 #144가 앱쪽에도 관리자 목록
  (`auth_repository.dart`의 `_adminEmails`, 관리자 메뉴 게이팅용)을 신설해
  이메일 목록이 **3곳(앱·rules·functions)**이 됐다. rebase 후 동기화 검사에
  이 3번째 소스를 추가(커밋 `5aee163`). 앱 목록은 UX 게이팅이라 서버와
  벌어져도 보안 자체를 뚫진 않지만, "메뉴는 보이는데 동작은 거부"되는 혼선을
  막기 위해 동기화 대상에 포함.

### 3) 무료 크레딧 무제한·중복 지급 (ADMIN-VULN-002 / P1-4)

- **증상**: `grantBonusCredits`가 임의 `amount` 허용, 상한·멱등·행위자 감사 없음.
- **원인**: 숫자 검사만 있고 결과 잔액 상한/operationId/감사 원장 부재. 중복
  클릭·재시도가 다시 반영.
- **해결**: 금액 검증을 순수 함수로 분리(`Number.isSafeInteger`, `amount != 0`,
  1회 지급 상한 ±100, 결과 잔액 상한 `MAX_BONUS_BALANCE=100000`).
  operationId 기반 멱등 처리 + 같은 트랜잭션에 `creditGrantAudits/{operationId}`
  (actor·reason·before·after·시각) 기록. Rules에서 `creditGrantAudits`는
  `allow write: if false`로 잠금(클라이언트 위조 방지). Cloud Log엔 `reason`
  원문 미기록(제3자 개인정보 로그 금지 규약). `admin.js` 지급 UI에 사유 입력·
  버튼 잠금·operationId 생성 추가.
- **결과 잔액 상한을 100000으로 크게 잡은 이유**: 이 잔액이 향후 IAP 충전
  누적 지갑과 공유될 수 있어, 낮은 상한(예: 1000)은 정당한 대량 충전을 막는
  버그가 된다. 그래서 낮은 상한 대신 **비상식값 방어용 넉넉한 상한**으로 뒀다.
  이는 기술적 안전장치이고 사업적 무료횟수 정책과는 무관하다.

### 4) 강제 업데이트가 임의 외부 URL 허용 (ADMIN-VULN-003 / P1-5)

- **증상**: 관리자가 `config/appUpdate`에 임의 scheme/host URL·임의 minBuild
  저장 가능, 앱은 비취소 강제 게이트로 그 URL을 외부 실행.
- **원인**: 서버·앱 어디에도 스토어 URL 검증이 없음. 세션 탈취 시 전체 사용자
  피싱/soft-brick 가능.
- **해결**: Rules에 `isValidAppUpdateConfig` — `iosUrl`은 `https://apps.apple.com`,
  `androidUrl`은 `https://play.google.com`만, `min<=latest`, message 길이 상한.
  다른 문서 참조(`get()`) 없이 `request.resource.data`만 봐 로컬 규칙엔진으로
  완전 재현 가능. 앱 측(`app_update_service.dart`)도 host+https 재검증, 아니면
  `null` 반환(강제 화면은 뜨되 버튼이 아무 것도 안 여는 안전한 실패로 낮춤).

## 3. 변경 파일

- `docs/admin/admin.js`, `docs/admin/README.md`
- `functions/src/index.ts`, `functions/src/adminEmails.ts`(신규),
  `functions/src/creditGrant.ts`(신규), `functions/src/creditGrant.test.ts`(신규),
  `functions/package.json`
- `firestore.rules`
- `lib/core/services/app_update_service.dart`, `test/app_update_service_test.dart`
- `test/firestore_rules/verify_rules.py`
- `tool/check_admin_sync.py`(신규), `tool/README.md`
- `.github/workflows/ci.yml`

## 4. 커밋

- `bfc074f` — 즉시급 4건(법적문서·권한잔존·크레딧·업데이트URL). rules·functions·
  admin.js가 4건에 걸쳐 공유되고 이 환경은 대화형 hunk 분할(`git add -p`)을 못
  써서 파일 단위 분리가 불가능 → 한 커밋으로 묶되 메시지 본문에 항목별 증상·
  원인·해결을 상세히 남김.
- `5aee163` — #2 3번째 소스(앱 `auth_repository.dart`) 동기화 검사 추가
  (PR #144 rebase 후).

## 5. 검증 — 세션 내 자동(독립 재실행 통과)

최종 rebase 트리(= 갱신 main + 내 변경)에서 직접 재실행해 통과 확인:

| 검증 | 결과 |
|---|---|
| `tool/check_admin_sync.py`(+ `--selftest`) | 통과(3소스 일치, 의도적 불일치 감지 재현) |
| `test/firestore_rules/verify_rules.py` | 22/22(신규 #4 케이스 6건 포함) |
| `functions` `npm test` | 25/25(금액검증 경계값 포함) |
| `flutter analyze` | 신규 error/warning 0(info 19 기존 잔재) |
| `flutter test` | 333/333(rebase로 #144·#145 테스트 포함) |

## 6. 남은 것

### (a) 이번에 의도적으로 미룬 후속 과제

- **진짜 단일 원본**(`config/admins` Firestore 문서 + Rules `get()`): 운영
  Firestore에 문서가 실제로 있어야 검증 가능하고 배포 순서(문서 선행 없이 규칙
  배포 시 전 관리자 락아웃)가 꼬여, 이번엔 "공유 상수 + 드리프트 감지"
  인터림으로 대체. 진짜 단일화는 별도 항목.
- 관리자 **중간 8건·낮음 1건**(billing XSS·문의 답변 위조·문의 DoS·탈퇴 후
  잔존·내부 보고서 공개·OCR 오염·감사 부재·CSP·세션 잔존): 미착수.

### (b) 배포가 있어야 재현되는 실서버 확인 — 배포 슬롯 조율 대상

정적 코드 수정·자동 테스트 통과만으로 "완료" 처리하지 않는다는 감사 원칙에
따라, 아래는 실배포 후 확인이 필요하다(이 저장소의 "코드는 맞는데 실물이
틀린" 반복 결함 방지).

1. **#2** 실제 "관리자 해제 → Firestore·`getUserUsage`·`grantBonusCredits`
   모두 거부"(rules+functions 배포 필요).
2. **#3** 트랜잭션 멱등성 실물(같은 operationId 2회 → 1회 반영) +
   `creditGrantAudits` 기록(배포 필요).
3. **#4** `config/appUpdate`에 비허용 URL 저장 시 서버 거부 실물(rules 배포
   필요). 단 `verify_rules.py`로 로컬 완전 재현되어 코드 신뢰도는 높음.
4. **#1** 콘솔 법적문서 화면 읽기전용·문구 육안(`hosting:admin` 배포 후 브라우저).

> 배포·PR병합·정책 변경은 관리자 세션 자율 범위 밖이다. PR #149 병합은 PM이
> 수행했고(사용자가 직접 위임 확정), 실배포는 F-07 서버 변경과 묶어 배포 승인
> 1건으로 사용자에게 올릴 예정이다.

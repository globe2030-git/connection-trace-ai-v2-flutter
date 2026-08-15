# 세션 기록 — 2026-08-15 · 지갑 엔진 완성 + 병합 보류 확정

앞선 [세션 기록](session-log-2026-08-14-marketing-wallet.md)에 이어, 지갑/과금
엔진을 끝까지 만들고 **최신 main에 맞춘(rebase) 뒤 브랜치에 보존**한 기록.
사용자 확정으로 **main 병합은 하지 않는다**([[wallet-branch-parked]]).

## 한 일

### 1. 엔진 남은 단위 완성 (브랜치 `feat/ai-credit-wallet`)
- **U3** grantBonusCredits → grantSupportCredits 순수 개명 (관리자 하드닝 그대로,
  reason은 이미 #149로 필수라 중복 안 함).
- **U5** 재가입×무료체험 무한 지급 방어 — `deviceLedger/{기기해시}`. 원본(iOS
  identifierForVendor / Android 기기 식별자)을 **서버 전용 salt로 HMAC-SHA256**,
  해시만 저장. 탈퇴해도 이 문서는 유지(가드 유효). ⚠️ 이 "탈퇴 후 잔존"은 법무
  검토에 올림(PM #166) — 가명 성격, 보존기간 판단 대기.
- **U7 뼈대만** IAP 구조 (실결제·상품ID 없이 이중 잠금).
- **파일럿 계측** 활성화·코호트·멘트 전송·👍/👎 (개인정보 없이 숫자·플래그만).

### 2. 최신 main에 맞춤(rebase) + 재검증
- main이 30커밋 앞서(관리자 보안 배포분) 6개 파일이 겹쳤다. **관리자 하드닝을
  전부 지키며** 해소. 기계 병합이 빠뜨린 괄호 하나(`isValidAdminAuditEntry`)도
  발견해 고침 — 안 고쳤으면 배포 때 터졌을 것.
- 재검증 전부 통과: **functions 97/97 · rules 75/75 · flutter 358/358 · analyze 0**.

### 3. ⚠️ reset 모드 "잠듦" 버그 발견·수정 (배포 안전에 중요)
- 무료체험 지급 함수(`bootstrapAccount`)가 **플래그와 상관없이 로그인마다
  지급**하고 있었다. 화면 변화는 없었지만 ① 기기당 무료체험 예산이 미리 소진,
  ② "이미 지급됨"이 먼저 찍혀 나중에 지갑 켜도 무료체험이 영영 안 나감.
- **수정**: 지급을 `model==='wallet'`일 때만 실행. 이제 `reset`이면 서버에
  아무것도 안 쓴다(진짜 잠듦). "잠든 채 배포"가 실제로 성립하게 됨.
- 덤: 탈퇴 시 안 지워지던 `pilotEvents`도 파기하도록 고침(deviceLedger는 계속 보존).

### 4. 세션 간 조율
- 관리자팀: grantSupportCredits 개명 OK, 관리자 이메일 드리프트 0 확인.
- PM: onUserDeletedCleanup은 #164가 functions 미변경이라 충돌 없음. 순서 정리.
- 기기 해시 사실관계를 법무 검토용으로 전달.

## 확정된 결정

- **지갑 코드는 main 병합 안 함**(2026-08-15 사용자 재확정). CLAUDE.md 6절 현행
  지침 유지. 처음엔 "병합 진행"이었다가, 병합해두면 다른 배포에 딸려나가 테스터
  백엔드를 건드릴 위험 때문에 보류로 확정. (reset 잠듦 수정으로 위험은 줄었으나
  결정은 보류.)
- **배포·플래그 켜기·스토어 등록 = 사용자 최종 결정**([[billing-gate-before-store-release]]).

## 문서 처리
- 마케팅·과금 스펙 12건은 정리 세션이 **PR #171**(문서만, 코드 0줄, 병합 대기)로
  main에 올림. `docs/planning` 기록 이관은 **#168**.
- 이 세션 배포 문서 2건(ios-asc-403-action·wallet-tester-deploy-runbook)은 지갑
  브랜치에 보존.

## 지금 상태 / 남은 것 (전부 사용자 몫)
- 지갑 엔진: **완성·검증·브랜치 보존** (`feat/ai-credit-wallet`).
- 출시 0단계: iOS 403(Apple 계정), Android 서명(key.properties 비밀값), 스토어 등록.
- 리텐션 파일럿: 출시 후 실행(계측은 브랜치에 준비됨).
- U6(리퍼럴 redemption)·실배포·플래그 전환: 미착수, 사용자 결정 대기.

*근거: planner 보고(rebase·재검증·reset 수정), [[wallet-branch-parked]],
CLAUDE.md 6절, PM/관리자/정리 세션 조율.*

# iOS App Store Connect 업로드 403 — 해결 액션 (사용자 실행용)

이건 **코드 문제가 아니라 계정 권한 문제**라 에이전트가 못 고친다. App Store
Connect 웹사이트에서 **계정 소유자(Account Holder)**가 직접 해야 한다.

## 증상 vs 원인 (구분)

- **증상**: 빌드 업로드 시 `FORBIDDEN_ERROR.ROLE_NOT_VALID` (403). 앱 레코드
  생성·조회는 **되는데** `CREATE BUILD` API만 거부됨.
- **원인**: **Developer Portal 권한 ≠ App Store Connect 권한** — 별개 시스템이다.
  `apps@creamhouse.net`은 Developer Portal에선 Admin으로 보이지만, **App Store
  Connect의 "사용자 및 접근"에서는 빌드 업로드 권한이 있는 역할이 아닐 수 있다**
  (또는 목록에 아예 없을 수 있다). 이 구분이 핵심이다.

## 액션 (Account Holder가 실행)

1. https://appstoreconnect.apple.com → **사용자 및 접근(Users and Access)**.
2. 목록에서 **`apps@creamhouse.net`** 확인:
   - **목록에 없으면** → "+"로 초대. 역할은 **App Manager**(빌드 업로드 가능) 또는
     **Admin**. 초대 메일 수락까지 완료.
   - **있는데 역할이 낮으면**(예: Developer/Marketing만) → 역할을 **App Manager
     이상**으로 변경.
3. (초대인 경우) 해당 이메일에서 초대 수락 → Xcode에서 로그아웃/재로그인으로
   갱신된 권한 반영.
4. Xcode 또는 `xcrun altool`/Transporter로 **빌드 업로드 재시도**.

## 확인 포인트

- **Account Holder가 누구인지** 먼저 확인(초대·역할 변경은 Account Holder 또는
  Admin만 가능). CreamHouse Co. 팀의 Account Holder 계정으로 로그인해야 한다.
- 역할 변경 후에도 403이면, 그 앱에 대한 **앱별 권한(App별 역할 제한)**이 걸려
  있는지 확인 — "사용자 및 접근 → 해당 사용자 → 앱 접근"에서 대상 앱이 포함돼야 함.

## 참고

- Xcode 서명 팀: `77L7BH2M2W`(CreamHouse Co.) — 서명 자체는 정상(HANDOFF 0-1).
- 이건 **출시 0단계의 선행 블로커**다. 이게 풀려야 TestFlight/심사 제출이 가능.
- 에이전트가 할 수 있는 건 여기까지(문서화). 실제 초대·역할 변경은 계정
  자격증명이 필요해 사용자 몫이다.

*근거: HANDOFF.md 0-1 "미해결 — App Store Connect 빌드 업로드 403" 항목.*

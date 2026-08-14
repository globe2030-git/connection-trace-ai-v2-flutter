/**
 * 관리자 이메일 — 단일 원본(2026-08-14, ADMIN-VULN-001 인터림 조치).
 *
 * 이 배열이 관리자 판별의 유일한 원본이어야 하지만, `firestore.rules`는
 * 외부 파일을 import할 수 없어(리터럴 배열만 가능) 완전한 단일 원본으로
 * 만들 수 없다. 그래서 `firestore.rules`의 `isAdmin()` 배열과 이 파일의
 * 내용이 **항상 정확히 같아야 한다**는 것을 `tool/check_admin_sync.py`로
 * 자동 검사한다.
 *
 * 관리자를 추가/제거할 때: 이 배열과 firestore.rules의 isAdmin() 배열을
 * **둘 다** 고치고 `python3 tool/check_admin_sync.py`를 통과시킨 뒤
 * `firebase deploy --only firestore:rules,functions`로 동시에 배포한다.
 * 절차 전체는 docs/admin/README.md "관리자 판별 방식" 참고.
 *
 * ⚠️ 이 방식은 임시 조치다. 진짜 단일 원본(`config/admins` Firestore 문서 +
 * Rules `get()`) 전환이 후속 과제로 남아 있다 — 이번 세션은 운영 Firestore에
 * 그 문서를 실제로 만들어 검증할 수 없어 재현 불가능했다
 * (docs/planning/admin-security-vulnerability-assessment-2026-08-13.md).
 */
export const ADMIN_EMAILS = [
  "connectionsense@creamhouse.net",
  "globe@creamhouse.net",
];

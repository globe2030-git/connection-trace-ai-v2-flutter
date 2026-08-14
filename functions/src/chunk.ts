/**
 * 배열을 지정 크기로 나눈다(2026-08-15, ADMIN-VULN-007에서 분리).
 *
 * Firestore batch 쓰기는 한 번에 최대 500건까지만 허용하므로, 탈퇴 시
 * 사용자 소유 문서(문의·답변 등)를 대량으로 지울 때 400건 단위로 나눠 여러
 * 번의 batch로 커밋한다(onUserDeletedCleanup 참고). Firestore Admin SDK
 * 호출(쿼리·batch) 자체는 에뮬레이터 없이는 테스트할 수 없으므로, 그 호출과
 * 무관한 이 순수 함수만 별도 파일로 분리해 `node --test`로 검증한다
 * (creditGrant.ts와 같은 분리 원칙).
 */
export function chunkArray<T>(arr: T[], size: number): T[][] {
  if (size <= 0) {
    throw new Error("size must be positive");
  }
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

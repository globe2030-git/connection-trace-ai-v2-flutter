/// 명함 사진 **서버 백업 장수 한도** 계산(2026-08-16).
///
/// ## 왜 한도가 있나
///
/// **충전형은 "AI를 쓸 때" 받는데, 사진 저장은 "안 써도 계속 나가는" 비용이다.**
/// 무료 이용자가 AI를 한 번도 쓰지 않아도 매달 저장 요금이 나가고, **회수
/// 경로가 없다.** 한도는 매출 장치가 아니라 **천장 장치**다 — "최악이어도
/// 여기까지"를 말할 수 있게 한다.
///
/// 근거·계산: `docs/planning/card-photo-storage-cost-spec-2026-08-16.md`
///
/// ## ⚠️ 한도는 상수가 아니다 — 사용자마다 다르다
///
/// [kFreeCardPhotoQuota]는 **기본값일 뿐**이고, 진짜 값은 서버의
/// `users/{uid}.cardPhotoQuota`다.
///
/// - **컴파일 상수로 박으면 올릴 때마다 앱을 새로 배포**해야 한다. 한도는
///   *"낮게 시작해 필요하면 올린다"*는 전제 위에 정해졌으므로 올릴 일이 온다
/// - ⚠️ 그 필드는 **`firestore.rules`의 `clientWritableUserFields()`에 넣지
///   않는다.** 넣으면 **이용자가 자기 한도를 늘려** 한도가 무의미해진다
///   (AI 잔여 회차와 같은 원칙)
///
/// ## 제한하는 것은 **서버 백업**뿐이다
///
/// 명함 등록·기기 저장·검색·AI는 **전부 무제한**이다. 한도를 넘어도
/// **명함은 정상 저장되고 사진도 기기에는 남는다.** 서버 업로드만 멈춘다.
///
/// ⚠️ **이미 올라간 것은 건드리지 않는다.** 밀어내기(오래된 것부터 삭제)를
/// 하지 않는 이유는 UX가 아니라 **법무**다 — 개인정보처리방침이 적은 사진
/// 파기 사유는 **"명함 삭제 시"와 "회원 탈퇴 시" 둘뿐**이고, *"한도를 넘어
/// 회사가 지운다"*는 근거가 없다.
library;

/// 무료 이용자 기본 한도(2026-08-16 사용자 확정).
///
/// 월 3장이면 약 5.6년이다. 100장(2.8년)을 버린 이유는 **핵심 타겟
/// (보험설계사·자동차 영업)이 1년 안에 닿기 때문**이었다.
const int kFreeCardPhotoQuota = 200;

/// 충전 이용자 상한(2026-08-16 사용자 확정).
///
/// 무제한으로 두면 **극단적 이용자 한 명이 비용을 끌어올린다.** 실제로 닿을
/// 사람은 거의 없지만 **상한이 있어야 최악을 계산할 수 있다.**
const int kChargedCardPhotoQuota = 2000;

/// 미리 알리는 지점. 한도의 **80%**.
///
/// ⚠️ **걸린 뒤에 알면 늦다.** 사진 백업은 보험이라, 한도에 걸린 것을 **기기를
/// 바꾼 뒤에 알게 되면** 그때는 충전이 아니라 이탈이다.
const double kCardPhotoQuotaWarnRatio = 0.8;

/// 서버 값이 없거나 이상하면 기본값을 쓴다.
///
/// 0이나 음수는 **"백업을 끈다"는 뜻이 아니라 잘못 들어간 값**으로 본다 —
/// 그런 값 때문에 백업이 조용히 멈추면 사용자는 이유를 알 수 없다.
int resolveQuota(int? serverValue) {
  if (serverValue == null || serverValue <= 0) return kFreeCardPhotoQuota;
  return serverValue;
}

/// 이 장수에서 **더 올릴 수 있나**.
bool canUpload(int syncedCount, int quota) => syncedCount < quota;

/// 미리 알려야 하는 구간인가(80% 이상, 아직 한도 안).
///
/// 한도에 닿은 뒤에는 [canUpload]가 false가 되므로 여기서는 false다 —
/// **"곧 찹니다"와 "찼습니다"는 다른 안내**다.
bool isNearQuota(int syncedCount, int quota) {
  if (!canUpload(syncedCount, quota)) return false;
  return syncedCount >= warnThreshold(quota);
}

/// 미리 알리기 시작하는 장수. 기본 한도 200장이면 **160장**.
int warnThreshold(int quota) => (quota * kCardPhotoQuotaWarnRatio).floor();

/// 남은 장수. 이미 넘었으면 0.
int remainingSlots(int syncedCount, int quota) {
  final left = quota - syncedCount;
  return left < 0 ? 0 : left;
}

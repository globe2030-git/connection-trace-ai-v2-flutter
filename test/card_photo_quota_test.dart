// 명함 사진 서버 백업 한도 검사(2026-08-16).
//
// 무엇을 지키려는 검사인가:
// ① **한도는 상수가 아니다** — 서버 값이 우선이고, 상수는 기본값일 뿐이다.
//    올릴 때마다 앱을 재배포하지 않기 위한 구조다.
// ② **"곧 찹니다"와 "찼습니다"는 다른 안내다** — 섞이면 사용자가 이미 늦은
//    뒤에 알게 된다.
// ③ 이상한 서버 값이 **백업을 조용히 멈추게 하지 않는다.**
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/card_photo_quota.dart';

void main() {
  group('확정값 — 바뀌면 비용 계산이 어긋난다', () {
    test('⭐ 단일 한도 2,000 · 경고선 80% (2026-08-26 무료/충전 구분 폐지)', () {
      // 이 값들은 비용 스펙(card-photo-storage-cost-spec-2026-08-16.md)의
      // 계산 전제다. 바꾸려면 그 문서의 원가도 함께 고쳐야 한다.
      // 🚨 무료·충전 구분이 없다. 옛 두 상수(무료 200 / 충전 2,000)는
      //    충전형 과금과 앞뒤가 안 맞아 2026-08-26에 하나로 합쳤다.
      //    자세한 경위는 card_photo_quota.dart 주석에 있다.
      expect(kCardPhotoQuota, 2000);
      expect(kCardPhotoQuotaWarnRatio, 0.8);
    });
  });

  group('resolveQuota — 서버 값이 우선, 상수는 기본값', () {
    test('서버 값이 있으면 그것을 쓴다 — 올릴 때 앱 재배포가 필요 없다', () {
      expect(resolveQuota(500), 500);
      expect(resolveQuota(2000), 2000);
    });

    test('없으면 기본값', () {
      expect(resolveQuota(null), kCardPhotoQuota);
    });

    test('0·음수는 "백업 끄기"가 아니라 잘못된 값으로 본다', () {
      // 그런 값 때문에 백업이 조용히 멈추면 사용자는 이유를 알 수 없다.
      expect(resolveQuota(0), kCardPhotoQuota);
      expect(resolveQuota(-10), kCardPhotoQuota);
    });
  });

  group('canUpload', () {
    test('한도 미만이면 올린다', () {
      expect(canUpload(0, 200), isTrue);
      expect(canUpload(199, 200), isTrue);
    });

    test('한도에 닿으면 멈춘다', () {
      expect(canUpload(200, 200), isFalse);
      expect(canUpload(201, 200), isFalse);
    });
  });

  group('경고선 — "곧 찹니다"와 "찼습니다"는 다르다', () {
    test('2,000장 한도의 경고선은 1,600장', () {
      expect(warnThreshold(200), 160);
      expect(warnThreshold(2000), 1600);
    });

    test('160장부터 미리 알린다', () {
      expect(isNearQuota(159, 200), isFalse);
      expect(isNearQuota(160, 200), isTrue);
      expect(isNearQuota(199, 200), isTrue);
    });

    test('⚠️ 이미 찼으면 "곧 찹니다"가 아니다 — 다른 안내를 해야 한다', () {
      expect(isNearQuota(200, 200), isFalse);
      expect(canUpload(200, 200), isFalse);
    });
  });

  group('remainingSlots', () {
    test('남은 장수를 센다', () {
      expect(remainingSlots(0, 200), 200);
      expect(remainingSlots(160, 200), 40);
    });

    test('이미 넘었으면 0 — 음수를 보여주지 않는다', () {
      expect(remainingSlots(200, 200), 0);
      expect(remainingSlots(250, 200), 0);
    });
  });
}

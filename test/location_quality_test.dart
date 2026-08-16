// 내 위치 품질 판단 검사(E-12, 2026-08-16).
//
// 무엇을 지키려는 검사인가:
// ① **기준은 절대값이 아니라 반경 대비다.** 반경 10km에서 300m 오차는 알리지
//    않고, 반경 500m에서는 알린다. 이 규칙이 깨지면 안내가 소음이 된다.
// ② **모르는 것과 나쁜 것은 다르다.** 오차를 모르면(null) 알리지 않는다 —
//    "모르니까 일단 경고"는 가짜 정보다.
// ③ 오래된 위치가 오차보다 무겁다 — 둘 다면 오래된 쪽을 말한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/location_quality.dart';

void main() {
  group('isCoarseForRadius — 반경에 견준다', () {
    test('반경 500m에서 300m 오차는 알린다', () {
      expect(isCoarseForRadius(300, 500), isTrue);
    });

    test('반경 10km에서 300m 오차는 알리지 않는다', () {
      expect(isCoarseForRadius(300, 10000), isFalse);
    });

    test('정확히 절반이면 알리지 않는다 — 경계는 넘어야 한다', () {
      expect(isCoarseForRadius(250, 500), isFalse);
      expect(isCoarseForRadius(251, 500), isTrue);
    });

    test('오차를 모르면 알리지 않는다 — 모르는 것과 나쁜 것은 다르다', () {
      expect(isCoarseForRadius(null, 500), isFalse);
    });

    test('오차가 0 이하인 이상한 값은 무시한다', () {
      expect(isCoarseForRadius(0, 500), isFalse);
      expect(isCoarseForRadius(-10, 500), isFalse);
    });

    test('반경이 무제한이면 알리지 않는다 — 견줄 기준이 없다', () {
      expect(isCoarseForRadius(5000, double.infinity), isFalse);
    });
  });

  group('isStaleFix — 오래된 위치', () {
    test('3분을 넘으면 오래된 것', () {
      expect(isStaleFix(const Duration(minutes: 4)), isTrue);
    });

    test('3분 이하는 아니다', () {
      expect(isStaleFix(const Duration(minutes: 3)), isFalse);
      expect(isStaleFix(Duration.zero), isFalse);
    });

    test('나이를 모르면(방금 잰 것) 아니다', () {
      expect(isStaleFix(null), isFalse);
    });

    test('기기 시계가 흔들려 음수가 와도 던지지 않는다', () {
      expect(isStaleFix(const Duration(minutes: -5)), isFalse);
    });
  });

  group('locationQualityNotice — 화면에 띄울 한 줄', () {
    test('알릴 것이 없으면 null — 억지로 채우지 않는다', () {
      expect(
        locationQualityNotice(accuracyMeters: 20, radiusMeters: 1000),
        isNull,
      );
    });

    test('오래된 위치는 분 단위로 말한다', () {
      final msg = locationQualityNotice(
        accuracyMeters: 10,
        age: const Duration(minutes: 7),
        radiusMeters: 1000,
      );
      expect(msg, contains('7분 전'));
    });

    test('오차는 미터로 말한다 — 숫자가 있어야 판단할 수 있다', () {
      final msg = locationQualityNotice(
        accuracyMeters: 380,
        radiusMeters: 500,
      );
      expect(msg, contains('380m'));
    });

    test('⚠️ 둘 다면 오래된 쪽을 말한다 — 아예 다른 곳일 수 있어 더 무겁다', () {
      final msg = locationQualityNotice(
        accuracyMeters: 400,
        age: const Duration(minutes: 8),
        radiusMeters: 500,
      );
      expect(msg, contains('8분 전'));
      expect(msg, isNot(contains('400m')));
    });
  });

  group('상수 — 바꾸면 안내 빈도가 통째로 달라진다', () {
    test('오차 기준은 반경의 절반, 오래됨은 3분', () {
      expect(kCoarseAccuracyRatio, 0.5);
      expect(kStaleFixAge, const Duration(minutes: 3));
    });
  });
}

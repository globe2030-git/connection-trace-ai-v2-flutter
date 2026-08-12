import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/services/location_service.dart';

/// E-10 회귀 테스트(테스터 피드백, 2026-08-12).
///
/// 증상은 "지도에서 위치를 갱신하면 대부분 '현재 위치를 확인하지 못했어요'가
/// 뜨고 간헐적으로만 성공"이었다. 원인은 새 측위 제한 시간이 6초로 너무 짧아
/// 실내·콜드 스타트에서 흔히 시간 초과가 났고, 그때 쓸 수 있는 **마지막으로
/// 알려진 위치를 전혀 쓰지 않고** 곧바로 실패로 처리한 것이었다.
///
/// 여기서는 폴백의 안전장치(너무 오래된 위치는 쓰지 않는다)를 고정한다 —
/// 무제한으로 받아들이면 한참 전 동네를 현재 위치로 삼아 거리 계산이 틀린다
/// (E-06 정확도 문제와 직결).
void main() {
  final now = DateTime(2026, 8, 12, 12, 0, 0);

  group('마지막으로 알려진 위치를 쓸 수 있는가', () {
    test('방금 측정된 위치는 쓴다', () {
      expect(
        LocationService.isLastKnownUsable(
          now.subtract(const Duration(seconds: 5)),
          now,
        ),
        isTrue,
      );
    });

    test('상한(10분) 직전까지는 쓴다', () {
      expect(
        LocationService.isLastKnownUsable(
          now.subtract(LocationService.maxLastKnownAge),
          now,
        ),
        isTrue,
      );
    });

    test('⭐ 상한을 넘긴 오래된 위치는 쓰지 않는다', () {
      expect(
        LocationService.isLastKnownUsable(
          now.subtract(LocationService.maxLastKnownAge +
              const Duration(seconds: 1)),
          now,
        ),
        isFalse,
        reason: '오래된 위치를 현재 위치로 삼으면 거리 계산이 틀린다',
      );
    });

    test('기기 시계가 흔들려 미래 시각이 찍히면 쓰지 않는다', () {
      expect(
        LocationService.isLastKnownUsable(
          now.add(const Duration(minutes: 1)),
          now,
        ),
        isFalse,
      );
    });
  });

  test('새 측위 제한 시간은 6초보다 넉넉하다(E-10 재발 방지)', () {
    expect(
      LocationService.fixTimeout,
      greaterThan(const Duration(seconds: 6)),
      reason: '6초는 실내·콜드 스타트에서 대부분 시간 초과였다',
    );
  });
}

import 'package:connection_trace_ai_flutter/presentation/features/radar/utils/nearby_map_label_collision.dart';
import 'package:flutter_test/flutter_test.dart';

/// 지도 위 회사명 라벨 충돌 판정(추가 452)을 고정한다.
///
/// 실기기 결함: 서로 다른 주소의 묶음 마커가 화면상 가까우면 대표 회사명
/// 라벨(추가 445)이 겹쳐 가운데 것만 읽혔다. 여기서는 **어떤 라벨이 남고
/// 어떤 라벨이 숨는지**, 그리고 **겹친 마커를 눌렀을 때 같은 클러스터로
/// 묶이는지**를 검사한다(화면 렌더링 자체는 위젯 테스트/실기기 몫).
void main() {
  group('computeLabelClusters — 겹치지 않으면 전부 보인다', () {
    test('멀리 떨어진 후보 둘은 각자 자기 클러스터', () {
      final candidates = [
        const LabelCandidate(
          id: 'a',
          x: 0,
          y: 0,
          labelWidth: 40,
          priority: 1,
          order: 0,
        ),
        const LabelCandidate(
          id: 'b',
          x: 1000,
          y: 0,
          labelWidth: 40,
          priority: 1,
          order: 1,
        ),
      ];

      final clusters = computeLabelClusters(candidates);

      expect(clusters, hasLength(2));
      expect(clusters.every((c) => !c.isCollision), isTrue);
      expect(clusters.map((c) => c.visibleId), containsAll(['a', 'b']));
    });

    test('빈 목록은 빈 결과', () {
      expect(computeLabelClusters(const []), isEmpty);
    });
  });

  group('computeLabelClusters — 우선순위: 인원 많은 쪽이 남는다', () {
    test('⭐ 겹치면 인원(priority)이 큰 쪽 라벨만 남는다', () {
      final candidates = [
        const LabelCandidate(
          id: '작은묶음',
          x: 100,
          y: 100,
          labelWidth: 60,
          priority: 2,
          order: 0,
        ),
        const LabelCandidate(
          id: '큰묶음',
          x: 110, // 60+60/2=60 이내 → 겹침
          y: 100,
          labelWidth: 60,
          priority: 5,
          order: 1,
        ),
      ];

      final clusters = computeLabelClusters(candidates);

      expect(clusters, hasLength(1));
      expect(clusters.single.isCollision, isTrue);
      expect(clusters.single.visibleId, '큰묶음');
      expect(clusters.single.memberIds, containsAll(['작은묶음', '큰묶음']));
    });

    test('인원이 같으면 order(=거리)가 앞선 쪽이 남는다', () {
      final candidates = [
        const LabelCandidate(
          id: '멀리',
          x: 100,
          y: 100,
          labelWidth: 60,
          priority: 3,
          order: 5,
        ),
        const LabelCandidate(
          id: '가까이',
          x: 110,
          y: 100,
          labelWidth: 60,
          priority: 3,
          order: 1,
        ),
      ];

      final clusters = computeLabelClusters(candidates);

      expect(clusters.single.visibleId, '가까이');
    });
  });

  group('computeLabelClusters — 사슬(A-B-C)도 하나의 클러스터로 묶인다', () {
    test('⭐ A-B, B-C만 겹치고 A-C는 안 겹쳐도 셋이 한 클러스터', () {
      // 폭 60짜리 라벨이 30 간격으로 나란히 있으면: A-B는 30 < 60 겹침,
      // B-C도 겹침, A-C는 60 < 60이 아니므로(경계) 안 겹친다 — 그래도
      // 손가락으로 "그 근처 전부"를 눌렀을 때는 A까지 같이 보여야 한다
      // (사용자 지시, 추가 452).
      final candidates = [
        const LabelCandidate(
          id: 'A',
          x: 0,
          y: 0,
          labelWidth: 60,
          priority: 2,
          order: 0,
        ),
        const LabelCandidate(
          id: 'B',
          x: 30,
          y: 0,
          labelWidth: 60,
          priority: 4,
          order: 1,
        ),
        const LabelCandidate(
          id: 'C',
          x: 60,
          y: 0,
          labelWidth: 60,
          priority: 3,
          order: 2,
        ),
      ];

      final clusters = computeLabelClusters(candidates);

      expect(clusters, hasLength(1));
      final cluster = clusters.single;
      expect(cluster.isCollision, isTrue);
      expect(cluster.memberIds, containsAll(['A', 'B', 'C']));
      // 인원이 가장 많은 B가 라벨을 보여준다.
      expect(cluster.visibleId, 'B');
    });
  });

  group('computeLabelClusters — 세로(y) 차이가 크면 안 겹친다', () {
    test('x는 겹치는 범위여도 y가 라벨 높이보다 멀면 각자 보인다', () {
      final candidates = [
        const LabelCandidate(
          id: '위',
          x: 100,
          y: 0,
          labelWidth: 60,
          priority: 2,
          order: 0,
        ),
        const LabelCandidate(
          id: '아래',
          x: 100,
          y: 200, // kLabelHeight(22)보다 훨씬 멀다
          labelWidth: 60,
          priority: 5,
          order: 1,
        ),
      ];

      final clusters = computeLabelClusters(candidates);

      expect(clusters, hasLength(2));
      expect(clusters.every((c) => !c.isCollision), isTrue);
    });
  });

  group('computeLabelClusters — 세 그룹이 겹치는 실측 재현(VE…/크림하우스/…NY)', () {
    test('⭐ 셋이 한 자리에 겹치면 하나만 남고 나머지 둘은 숨는다', () {
      final candidates = [
        const LabelCandidate(
          id: 'VE',
          x: 200,
          y: 300,
          labelWidth: 60,
          priority: 2,
          order: 0,
        ),
        const LabelCandidate(
          id: '크림하우스',
          x: 205,
          y: 302,
          labelWidth: 148,
          priority: 3,
          order: 1,
        ),
        const LabelCandidate(
          id: 'NY',
          x: 210,
          y: 298,
          labelWidth: 60,
          priority: 1,
          order: 2,
        ),
      ];

      final clusters = computeLabelClusters(candidates);

      expect(clusters, hasLength(1));
      expect(clusters.single.memberIds, hasLength(3));
      expect(clusters.single.visibleId, '크림하우스');
    });
  });
}

/// 지도 위 **회사명 라벨끼리 겹치는 문제**(추가 452)를 푸는 순수 로직.
///
/// ## 왜 필요했나
///
/// 추가 445에서 같은 주소 묶음 마커에 대표 회사명 라벨(`groupCompanyLabel`)을
/// 붙였는데, 그 라벨이 낱개 숫자 마커보다 **가로로 훨씬 넓다**(최대 148)는
/// 것을 계산에 안 넣었다. 같은 주소끼리는 이미 [groupContactsByAddress]로
/// 묶이지만, **주소가 다른데 화면상 가까운** 마커끼리는 묶이지 않으므로 그
/// 라벨들이 화면에서 그대로 겹쳤다 — 실기기에서 `VE…`/`크림하우스(주)`/`…NY`
/// 세 라벨이 한 자리에 포개져 가운데 것만 읽혔다(2026-08-24 사용자 제보).
///
/// ## 판정 방식 — 화면 좌표 기준, 폭은 미리 잰 값을 재사용
///
/// 지도를 옮기거나 확대할 때마다 이 계산이 다시 돈다(마커의 화면 좌표가
/// 바뀌므로). 하지만 **글자 폭을 다시 재지는 않는다** — 글자 폭은 카메라와
/// 무관한 값(글자·글꼴이 바뀌지 않는 한 그대로)이라, 호출부
/// (`nearby_map_view.dart`)가 마커 목록을 만들 때(=인맥 데이터가 바뀔 때)
/// **한 번만** [measureGroupLabelWidth]로 재서 [LabelCandidate.labelWidth]로
/// 넘긴다. 여기 [computeLabelClusters]는 그 값과 **현재 화면 좌표**만 가지고
/// 겹침을 비교한다 — 비교는 뺄셈·부등호뿐이라 지도를 움직일 때마다 다시
/// 돌아도 비용이 낮다(마커 수는 많아야 수십 개 단위).
///
/// ## 우선순위 — 무엇을 남기고 무엇을 숨기나
///
/// "지도를 보는 사용자가 먼저 알고 싶은 것"을 기준으로 정했다.
/// 1. **묶음 인원이 많은 쪽을 남긴다.** 인원이 많을수록 그 자리를 놓쳤을 때
///    잃는 정보가 크다 — 한 명을 놓치는 것과 열 명을 놓치는 것은 다르다.
/// 2. 인원이 같으면 **[LabelCandidate.order]가 앞선 쪽**을 남긴다. 호출부는
///    이미 거리순으로 정렬된 목록([RadarViewModel.filteredContacts] 기준
///    `computeMapMarkerGroups`)의 인덱스를 그대로 order로 넘기므로, 이는 곧
///    "기준 위치에 더 가까운 쪽"이다 — 사용자가 지금 챙길 사람은 가까운
///    쪽이다. 그래서 거리를 별도 필드로 다시 받지 않는다(이미 order 안에
///    있다).
/// 3. 그래도 같으면(이론상만 — 순서까지 같은 두 후보는 생길 수 없다) 정렬이
///    안정적이므로 먼저 온 쪽이 그대로 이긴다.
///
/// ## 겹친 마커를 눌렀을 때 — 클러스터
///
/// 라벨을 숨긴 마커도 "정상 동작"해야 한다는 요구(사용자 지시, 추가 452)에
/// 따라, 서로 겹치는 마커들을 [LabelCluster]로 묶어 돌려준다. 클러스터
/// 안의 **아무 마커나 눌러도 같은 결과**를 보여줘야 한다 — 화면에서
/// 겹쳐 있으면 손가락으로 어느 것을 정확히 짚었는지 사용자도 구분할 수
/// 없기 때문이다(2026-08-24 사용자 지시: "겹친 것들을 하나로 묶어 받는
/// 편"). 그래서 판정은 그리디(우선순위 높은 것부터 이미 보여주기로 한
/// 라벨과만 비교)가 아니라 **합집합-찾기(Union-Find)로 연결 요소를 구한다**
/// — A-B가 겹치고 B-C가 겹치지만 A-C는 안 겹치는 사슬도 하나의 클러스터로
/// 묶여야, "C를 눌렀는데 A가 안 보인다"가 생기지 않는다.
library;

/// 라벨 충돌 판정에 넣을 마커 하나. 화면 좌표(dp) 기준이다.
class LabelCandidate {
  const LabelCandidate({
    required this.id,
    required this.x,
    required this.y,
    required this.labelWidth,
    required this.priority,
    required this.order,
  });

  /// 이 마커의 고유 식별자 — 호출부는 대표 인맥의 id를 쓴다(같은 인맥은
  /// 한 그룹에만 속하므로 그룹마다 유일하다).
  final String id;

  /// 마커의 화면 x 좌표(라벨은 마커 위 중앙에 정렬되므로 마커 x와 같다).
  final double x;

  /// 라벨 밴드의 화면 y 좌표. 카메라가 바뀔 때마다 다시 잰다.
  final double y;

  /// [measureGroupLabelWidth]로 미리 잰 라벨 폭(dp). 카메라와 무관해 한 번만
  /// 재고 재사용한다.
  final double labelWidth;

  /// 인원수 — 클수록 남는다(우선순위 규칙 1).
  final int priority;

  /// 목록(거리) 순서 — 작을수록(=가까울수록) 남는다(우선순위 규칙 2).
  final int order;
}

/// 라벨 하나의 화면상 세로 크기(dp) — `_GroupPin`의 알약(라벨) 높이(세로
/// 패딩 3+3, 글꼴 10.5의 줄 높이 약 13~14 ≈ 19~20)에 여유를 더한 값이다.
///
/// ⚠️ **잰 값이 아니라 위젯 스타일에서 고른 값이다.** `_GroupPin`의 패딩·
/// 글꼴 크기가 바뀌면 이 값도 함께 봐야 한다.
const double kLabelHeight = 22;

/// 겹쳐서 하나로 묶인 마커 무리.
class LabelCluster {
  const LabelCluster({required this.memberIds, required this.visibleId});

  /// 이 클러스터에 속한 마커 id 전부(자기 자신 포함, 1개면 안 겹친 것).
  final List<String> memberIds;

  /// 라벨을 실제로 보여줄 마커 id — 우선순위가 가장 높은 것.
  final String visibleId;

  /// 2개 이상이 겹쳐 하나로 묶였는지. `false`면 원래부터 안 겹친 낱개
  /// 마커라 클러스터 시트가 아니라 예전 그대로의 단일 시트를 보여줘야 한다.
  bool get isCollision => memberIds.length > 1;
}

/// [candidates]를 화면 겹침 기준으로 클러스터로 묶는다.
///
/// 각 클러스터 안에서는 우선순위가 가장 높은 후보만 라벨을 보여주고
/// ([LabelCluster.visibleId]), 나머지는 라벨을 숨긴다(마커 자체는 그대로
/// 그려진다 — 숨기는 것은 라벨 글자뿐이다).
List<LabelCluster> computeLabelClusters(List<LabelCandidate> candidates) {
  final n = candidates.length;
  if (n == 0) return const [];

  // 합집합-찾기(Union-Find) — 겹치는 쌍을 모두 이어 연결 요소를 만든다.
  // 그리디하게 "이미 보여주기로 한 라벨"과만 비교하면 A-B-C 사슬에서 C가
  // A와는 안 겹쳐 따로 떨어져 나갈 수 있다 — 그러면 "C를 눌렀는데 클러스터에
  // A가 없다"가 생긴다. 전체 쌍을 다 보는 편이 안전하고, 마커 수가 많아야
  // 수십 개라 O(n²)이어도 비용이 크지 않다.
  final parent = List<int>.generate(n, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[ra] = rb;
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (_labelsOverlap(candidates[i], candidates[j])) union(i, j);
    }
  }

  final membersByRoot = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    membersByRoot.putIfAbsent(find(i), () => []).add(i);
  }

  final clusters = <LabelCluster>[];
  for (final indices in membersByRoot.values) {
    // 우선순위 규칙: 인원 많은 쪽 → 순서(거리) 앞선 쪽.
    indices.sort((a, b) {
      final byPriority = candidates[b].priority.compareTo(
        candidates[a].priority,
      );
      if (byPriority != 0) return byPriority;
      return candidates[a].order.compareTo(candidates[b].order);
    });
    clusters.add(
      LabelCluster(
        memberIds: [for (final i in indices) candidates[i].id],
        visibleId: candidates[indices.first].id,
      ),
    );
  }
  return clusters;
}

/// 두 라벨의 사각형(중심 x,y · 폭 labelWidth · 높이 [kLabelHeight])이
/// 겹치는지. 표준 AABB(축 정렬 사각형) 충돌 판정 — 두 중심 간 거리가 각
/// 절반 폭/높이의 합보다 작으면 겹친다.
bool _labelsOverlap(LabelCandidate a, LabelCandidate b) {
  final dx = (a.x - b.x).abs();
  final dy = (a.y - b.y).abs();
  final maxDx = (a.labelWidth + b.labelWidth) / 2;
  return dx < maxDx && dy < kLabelHeight;
}

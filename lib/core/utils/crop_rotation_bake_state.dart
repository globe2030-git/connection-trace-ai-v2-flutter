/// [회전]을 연타할 때의 누적·배경 굽기 상태 전이(P2-③ 2차, "굽기 ~2초"
/// 실기기 피드백 후속).
///
/// ## 왜 위젯 밖으로 뺐나
///
/// "연타하면 회전 수만 누적하고, 굽기 큐를 따로 쌓지 않는다 — 진행 중이던
/// 굽기가 끝나면 그 순간의 누적분을 한 번에 다시 굽는다"는 규칙은 화면·
/// 실제 파일 굽기(`bakeImageRotation`, 무겁고 비동기) 없이도 검증할 수 있는
/// **상태 전이**다. 이 화면은 회전×자르기 좌표계를 섞어 실기기에서 두 번
/// 헤맨 전례가 있다(추가 273·397) — 판정 로직만이라도 화면 없이 먼저
/// 고정해 둔다.
///
/// 실제 비동기 굽기·파일 교체는 `ManualCropView`가 이 상태를 참고해 스스로
/// 수행한다. 이 클래스는 "지금 무엇을 해야 하나"만 답한다.
library;

/// 회전 누적·굽기 진행 상태. **불변**(모든 메서드가 새 인스턴스를 돌려준다).
class CropRotationBakeState {
  const CropRotationBakeState({this.pendingTurns = 0, this.bakingTarget});

  /// 아직 파일에 구워지지 않은 누적 회전 — 시계 방향 90도 단위(0~3).
  ///
  /// 3은 "반시계 90도 한 번"과 시각적으로 같다(270도 = −90도) — 화면은
  /// 이 값을 직접 굽지 않고 `bakeImageRotation`에 `pendingTurns*90`을 한
  /// 번에 넘긴다. 90을 세 번 나눠 굽지 않는다.
  final int pendingTurns;

  /// 지금 배경에서 굽는 중인 목표 값. 굽는 중이 아니면 null.
  ///
  /// ⚠️ **[pendingTurns]와 다를 수 있다** — 굽기가 도는 동안 사용자가 더
  /// 눌렀으면 [pendingTurns]가 이 값을 앞질러 간다. 그 굽기가 끝나면
  /// [bakeCompleted]가 "낡았다"고 판정해 결과를 버린다.
  final int? bakingTarget;

  bool get isBaking => bakingTarget != null;

  /// [자르기 확정]으로 넘길 수 있는 상태인가 — 밀린 회전도 없고 굽는 중도
  /// 아니다. 이 값이 false인 채로 저장하면 화면에 보이는 방향과 실제 파일
  /// 방향이 어긋난다(이 작업의 인수 기준 1번).
  bool get isSettled => pendingTurns == 0 && bakingTarget == null;

  /// 시계 방향 한 번 누적. 굽기 시작 여부는 건드리지 않는다 — 시작 판단은
  /// [startBakeIfNeeded]가 따로 한다.
  CropRotationBakeState rotatedCw() => CropRotationBakeState(
    pendingTurns: (pendingTurns + 1) % 4,
    bakingTarget: bakingTarget,
  );

  /// 반시계 방향 한 번 누적(= 시계 3번과 같은 값).
  CropRotationBakeState rotatedCcw() => CropRotationBakeState(
    pendingTurns: (pendingTurns + 3) % 4,
    bakingTarget: bakingTarget,
  );

  /// 지금 굽는 중이 아니고 밀린 회전이 있으면, 그 값을 목표로 굽기를
  /// "시작한다"(상태만 — 실제 비동기 굽기는 호출하는 쪽이 한다).
  ///
  /// 이미 굽는 중이면 그대로 돌려준다 — **한 번에 하나만 굽는다.** 클릭마다
  /// 굽기 요청을 쌓지 않기 위한 관문이다.
  CropRotationBakeState startBakeIfNeeded() {
    if (isBaking || pendingTurns == 0) return this;
    return CropRotationBakeState(
      pendingTurns: pendingTurns,
      bakingTarget: pendingTurns,
    );
  }

  /// 굽기가 끝났을 때 다음 상태.
  ///
  /// - **목표가 여전히 최신**([pendingTurns]가 [bakingTarget]과 같으면):
  ///   그만큼 뺀다 — 보통 0이 된다(정착).
  /// - **목표가 낡았음**(굽는 동안 더 눌려 [pendingTurns]가 달라졌으면):
  ///   [pendingTurns]는 그대로 두고 굽기 표시만 지운다 — 다음
  ///   [startBakeIfNeeded]가 최신 값으로 다시 굽는다.
  ///
  /// [bakingTarget]이 null이면(부르는 쪽 실수로 굽지도 않았는데 불렀으면)
  /// 아무 것도 하지 않는다.
  CropRotationBakeState bakeCompleted() {
    final target = bakingTarget;
    if (target == null) return this;
    if (pendingTurns == target) {
      return CropRotationBakeState(pendingTurns: 0, bakingTarget: null);
    }
    return CropRotationBakeState(pendingTurns: pendingTurns, bakingTarget: null);
  }
}

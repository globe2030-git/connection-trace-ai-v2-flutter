/// 앞면 촬영 직후 시트의 **읽은 필드 칩**(P2-④ 이어찍기, 2026-08-22 확정)
/// 상태 계산.
///
/// ## 왜 위젯 밖으로 뺐나
///
/// "어느 칸이 채워졌는지"는 이미 `_askNextScanStep`이 계산해 둔
/// `missing`(빈 칸 라벨 목록) 하나로 정해진다 — 위젯 없이도 검증할 수
/// 있는 순수 규칙이라 이 저장소의 다른 계산들과 같은 자리에 둔다.
library;

/// 칩 하나의 상태. [filled]가 true면 accentSoft 톤, false면 warningSoft 톤
/// (실제 색 매핑은 화면 쪽에서 한다 — 이 파일은 위젯을 모른다).
class ScanFieldChipState {
  const ScanFieldChipState({required this.label, required this.filled});

  final String label;
  final bool filled;
}

/// [allLabels] 순서를 그대로 유지하며, [missingLabels]에 있는 라벨만
/// `filled: false`로 표시한다.
List<ScanFieldChipState> buildScanFieldChipStates({
  required List<String> allLabels,
  required List<String> missingLabels,
}) {
  return [
    for (final label in allLabels)
      ScanFieldChipState(label: label, filled: !missingLabels.contains(label)),
  ];
}

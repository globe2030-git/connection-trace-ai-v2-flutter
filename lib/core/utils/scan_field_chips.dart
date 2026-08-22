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

// ── 이어찍기 안내 문구(P2-④ 동승 결함, 추가 397) ─────────────────────────

/// "뒷면에 있는 경우가 많은" 필드. 이름·회사명·휴대폰은 대체로 앞면에
/// 있으므로 대상에서 뺀다.
const kBackSideProneLabels = ['주소', '이메일'];

/// 이어찍기 안내 문구를 정한다. **못 찾은 항목만** 나열하고, 전부 찾았으면
/// `null`을 돌려준다(부르는 쪽이 문구를 생략하거나 중립 문구로 바꾼다).
///
/// ⚠️ 왜 필요한가: 이메일·주소를 이미 찾았는데도 "주소·이메일이 뒷면에
/// 있는 경우가 많아요"가 **고정 문구로** 떴다(실기기 관찰, 추가 397 동승
/// 결함). 이미 찾은 항목까지 "뒷면에 있다"고 말하는 것은 부정확하고,
/// 사용자에게 불필요한 재촬영을 권하는 꼴이 된다.
String? backSideHintFor(List<String> missing) {
  final hasAddress = missing.contains('주소');
  final hasEmail = missing.contains('이메일');
  if (hasAddress && hasEmail) return '주소·이메일이 뒷면에 있는 경우가 많아요';
  if (hasAddress) return '주소가 뒷면에 있는 경우가 많아요';
  if (hasEmail) return '이메일이 뒷면에 있는 경우가 많아요';
  return null;
}

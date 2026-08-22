/// 갤러리 자르기(398)의 **단계 라벨** 계산 — "앞면 자르기 1/2" 등.
///
/// ## 왜 위젯 밖으로 뺐나
///
/// P2-②(2장 선택)와 결합되면서 앞·뒷면을 순서대로 자르게 됐다. 라벨 문구를
/// 화면 코드 안에서만 조립하면, 인덱스 하나가 밀려도 위젯 테스트 없이는
/// 못 잡는다 — 이 저장소의 다른 순수 계산(`gallery_pick_order.dart`,
/// `crop_mode_corners.dart`)과 같은 이유로 뺐다.
library;

/// [index]번째(0-기반, 0=앞면·1=뒷면) 사진의 자르기 단계 라벨.
///
/// [totalCount]가 2 미만이면(1장만 골랐으면) **null** — 앞/뒷면 순서 개념
/// 자체가 없는 기존 단일 선택 경로와 화면을 그대로 공유하기 위함이다.
String? galleryCropStepLabel({required int index, required int totalCount}) {
  if (totalCount < 2) return null;
  final side = index == 0 ? '앞면' : '뒷면';
  return '$side 자르기 ${index + 1}/$totalCount';
}

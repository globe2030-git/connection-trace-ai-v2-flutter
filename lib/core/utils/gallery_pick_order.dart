/// 갤러리에서 **앞·뒷면 2장을 한 번에** 고를 때(P2-②)의 순서 계산.
///
/// ## 왜 위젯 밖으로 뺐나
///
/// `image_picker`의 `pickMultiImage`가 돌려주는 순서가 "사용자가 탭한
/// 순서"라는 보장은 플랫폼 문서 어디에도 없다(`ocr_scanner_service.dart`의
/// [pickUpToTwoImagesFromGallery] 문서 참고 — 플러그인 소스 실측). 그래서
/// 화면은 **항상 "순서 바꾸기" 버튼을 함께 두고**, 그 버튼이 하는 일은
/// 이 파일의 순수 함수 하나뿐이다 — 위젯 없이 규칙만 검사하기 위해
/// 뺐다(`card_quad_geometry.dart`·`scan_rotation.dart`와 같은 이유).
library;

/// 목록의 **앞 두 원소**를 맞바꾼다. 원소가 2개 미만이면 그대로 돌려준다.
///
/// ⚠️ **1장뿐일 때는 손대지 않는다** — 앞/뒷면 개념 자체가 없는 상태라
/// "바꿀 것"이 없다. 이 조건이 없으면 갤러리 다중 선택이 아닌 **기존
/// 단일 선택 경로**(원소 1개)에서도 실수로 이 함수가 불릴 때 위험하다.
List<T> swapFrontBackOrder<T>(List<T> items) {
  if (items.length != 2) return items;
  return [items[1], items[0]];
}

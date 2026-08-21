/// 갤러리 선택 화면([FilePickerModalView])의 **문구 계산**(P2-②).
///
/// ## 왜 위젯 밖으로 뺐나
///
/// "1장만 고르면 기존 화면과 완전히 같다"는 요구(회귀 0)를 화면 코드
/// 안에서만 지키면, 다음 사람이 조건문 하나를 고치다가 조용히 깨뜨려도
/// 위젯 테스트 없이는 못 잡는다. 여기서는 **글자 하나까지 고정**해 둔다.
library;

/// 화면 제목. **0장·1장일 때는 기존 문구와 완전히 같다** — `sideLabel`만
/// 그대로 넣는다. 2장을 고른 경우에만 바뀐다.
String galleryPickerHeaderTitle({
  required String sideLabel,
  required int pickedCount,
}) {
  return pickedCount == 2 ? '명함 이미지 선택 (2장)' : '$sideLabel 이미지 선택';
}

/// 실행 버튼 문구. **0장·1장일 때는 기존 문구와 완전히 같다.**
String galleryPickerPrimaryButtonLabel({
  required bool isProcessing,
  required int pickedCount,
}) {
  if (isProcessing) return '선택한 이미지 OCR 스캔 중...';
  return pickedCount == 2 ? '2장 불러와 인식하기' : '선택한 파일 명함 OCR 스캔 실행';
}

/// 보관용 명함 사진을 줄이는 계산(2026-08-16).
///
/// ## 왜 줄이나
///
/// 서버에 올리는 것은 **암호화된 저장본**이고, 실측 평균이 **1.67MB**다
/// (실기기 16장 전수, 손익/원가 세션). 축소도 압축도 하지 않고
/// `encodeJpg(quality: 100)`에 원본 해상도 그대로 굽기 때문이다.
///
/// 그 값은 **OCR 인식률을 위한 것**인데, **보관본은 인식이 끝난 뒤의
/// 복원용**이라 같은 품질일 이유가 없다. 10,000명이 1,000장씩 들면 16.7TB,
/// 월 58만원이고 **누적된다**. 충전형은 AI를 쓸 때 받는데 저장은 안 써도
/// 계속 나가는 비용이라, 무료 이용자가 늘수록 회수 경로 없이 쌓인다.
///
/// 근거·계산: `docs/planning/card-photo-storage-cost-spec-2026-08-16.md`
///
/// ## ⚠️ 인식 경로에는 절대 넣지 않는다
///
/// 촬영 → 크롭 → 회전 → **OCR** → (화면 닫힘) → 저장 순서다. 축소를 크롭
/// 단계에 넣으면 **그 결과물이 곧 OCR 입력**이라 인식률이 떨어진다.
/// 들어갈 자리는 **`ContactImageService.saveEncryptedCardImage`의 암호화
/// 직전** 하나뿐이다. 갤러리 선택의 `imageQuality: 100`도 그대로 둔다.
///
/// ## 값의 근거
///
/// 명함 긴 변 90mm가 1,600px이면 **약 390dpi**로, 문서 스캔 표준 300dpi를
/// 넘는다. 표본 103장 재인코딩 실측 평균 **236KB**(약 82% 절감).
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 보관본 긴 변 최대 픽셀.
const int kCardPhotoMaxLongSide = 1600;

/// 보관본 JPEG 품질.
const int kCardPhotoJpegQuality = 80;

/// [width]×[height] 이미지를 줄여야 하는가.
///
/// 긴 변이 이미 [kCardPhotoMaxLongSide] 이하면 **건드리지 않는다** — 작은
/// 사진을 다시 구우면 화질만 깎이고 크기는 오히려 늘 수 있다.
bool needsDownscale(int width, int height) =>
    width > kCardPhotoMaxLongSide || height > kCardPhotoMaxLongSide;

/// 가로세로 비를 유지한 채 긴 변을 [kCardPhotoMaxLongSide]에 맞춘 크기.
///
/// 줄일 필요가 없으면 원래 크기를 그대로 돌려준다. 짧은 변이 0으로
/// 반내림되지 않도록 최소 1을 보장한다 — 폭 3000×높이 1 같은 극단값에서
/// `copyResize`가 던지는 것을 막는다.
({int width, int height}) downscaledSize(int width, int height) {
  if (!needsDownscale(width, height)) return (width: width, height: height);
  if (width >= height) {
    final h = (height * kCardPhotoMaxLongSide / width).round();
    return (width: kCardPhotoMaxLongSide, height: h < 1 ? 1 : h);
  }
  final w = (width * kCardPhotoMaxLongSide / height).round();
  return (width: w < 1 ? 1 : w, height: kCardPhotoMaxLongSide);
}

/// 보관용으로 줄인 JPEG 바이트. 줄일 수 없으면 **원본을 그대로** 돌려준다.
///
/// 원본을 그대로 돌려주는 경우:
/// - 디코딩 실패(지원하지 않는 형식·깨진 파일) — 저장 자체를 막는 것보다
///   원본이라도 남기는 편이 낫다
/// - 이미 충분히 작음
/// - **다시 구웠더니 오히려 커짐** — 작은 PNG를 JPEG으로 바꾸면 일어난다
///
/// ⚠️ 던지지 않는다. 축소 실패로 **명함 저장 자체가 막히면 안 된다** —
/// 사용자가 잃는 것(명함)이 얻는 것(용량)보다 크다.
/// 줄였는지까지 함께 알려 준다. 관측용이다 — 자세한 이유는
/// [CardPhotoSizeBand] 참고.
({Uint8List bytes, bool downscaled}) downscaleForArchiveWithInfo(
  Uint8List original,
) {
  final out = downscaleForArchive(original);
  return (bytes: out, downscaled: !identical(out, original));
}

Uint8List downscaleForArchive(Uint8List original) {
  try {
    final decoded = img.decodeImage(original);
    if (decoded == null) return original;
    if (!needsDownscale(decoded.width, decoded.height)) return original;

    final size = downscaledSize(decoded.width, decoded.height);
    final resized = img.copyResize(
      decoded,
      width: size.width,
      height: size.height,
      interpolation: img.Interpolation.average,
    );
    final out = img.encodeJpg(resized, quality: kCardPhotoJpegQuality);
    return out.length < original.length ? out : original;
  } catch (_) {
    return original;
  }
}

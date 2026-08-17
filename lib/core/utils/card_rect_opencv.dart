import 'dart:typed_data';

import 'package:dartcv4/dartcv.dart' as cv;

/// 안드로이드에서 명함 사각형을 찾는다 — OpenCV.
///
/// ## 아이폰과 무엇이 같고 무엇이 다른가
///
/// **같은 것**: 받는 것(밝기 평면)도, 돌려주는 것(정규화 좌표 + 진단값)도
/// 아이폰과 똑같다. 그래서 `card_quad_geometry.dart`의 판정·좌표 변환·크롭이
/// **두 플랫폼에서 글자 그대로 같은 코드**로 돈다(검사 98건 공용).
///
/// **다른 것**: 아이폰은 OS가 `VNDetectRectanglesRequest`로 검출만 내주지만,
/// 안드로이드에는 대응 기능이 없다 — ML Kit의 문서 스캐너는 **화면까지 주는
/// 것**뿐이라 못 쓴다(그게 A안에서 아팠던 지점이다). 그래서 직접 찾는다.
///
/// ## ⚠️ 왜 Kotlin이 아니라 Dart인가 (2026-08-17 사용자 결정)
///
/// 처음에는 **기성 OpenCV를 Kotlin으로** 감쌌다. 되긴 됐는데 **용량이 문제**였다.
///
/// | | arm64 네이티브 |
/// |---|---|
/// | 기성 OpenCV(전 모듈, `libopencv_java4.so` 하나가 24.7MB) | **+26.1 MB** |
/// | `dartcv4`(필요한 모듈만 골라 컴파일) | **+10.5 MB** |
///
/// 기성품은 안 쓰는 기능까지 다 들어 있는데 **파일이 하나라 골라 뺄 수 없다.**
///
/// ⚠️ `dartcv4`가 처음에 실패했던 이유는 **패키지가 아니라 경로**였다 —
/// 저장소가 있던 볼륨 이름 `X31(VM)`의 **괄호**를 OpenCV 빌드 스크립트가
/// 따옴표 없이 셸에 넘겨 깨졌다. **저장소를 괄호 없는 경로로 옮겨** 풀었다.
///
/// ## 무엇을 하나
///
/// ```
/// 밝기 평면 → 블러 → 캐니 경계 → 윤곽선 → 네 점으로 근사 → 볼록한 것만
/// ```
///
/// **판단은 여기서 하지 않는다.** 후보만 내놓고 명함인지 고르는 것은 Dart의
/// `judgeCardShape`가 한다 — 두 플랫폼이 **같은 규칙**을 쓰게 하기 위함이다.
///
/// ## ⚠️ 매 프레임 도는 일이다
///
/// 부르는 쪽이 **긴 변 1024로 줄인** 평면을 넘긴다(아이폰 실측: 원본 그대로면
/// 밝기 평면만 12MB, 초당 8장이면 100MB/초). 줄여도 정규화 좌표를 돌려주므로
/// 결과는 같다. 그리고 이 함수는 **별도 isolate에서** 돌아야 한다 —
/// `card_rect_worker.dart` 참고.

/// 캐니 경계 검출의 아래·위 문턱값.
///
/// ⚠️ **아직 실측이 아니다.** 이 작업에서 최소 크기·가로세로비를 짐작으로
/// 정했다가 **두 번 틀렸다**(15% → 실측 6.7%, 1.3~1.7 → 실측 1.83).
/// 실기기에서 명함이 안 잡히면 **여기부터 의심하되, 고치기 전에 재라.**
const double kCannyLow = 60;
const double kCannyHigh = 180;

/// 윤곽선을 네 점으로 근사할 때 쓰는 허용 오차(둘레 대비 비율).
///
/// 작으면 곡선을 그대로 따라가 점이 많아지고, 크면 명함이 삼각형으로 뭉갠다.
const double kApproxEpsilonRatio = 0.02;

/// 후보로 볼 최소 넓이(전체 대비).
///
/// 여기서는 **아주 느슨하게만** 거른다 — 진짜 판정은 `judgeCardShape`가 한다.
/// 아이폰 쪽 Vision 설정과 같은 태도다.
const double kMinContourAreaFraction = 0.01;

/// 한 프레임에서 넘길 후보 개수 상한.
const int kMaxObservations = 12;

/// 검출 결과 — 좌표와 진단값.
///
/// ⚠️ **아이폰 네이티브가 돌려주는 것과 같은 모양**으로 맞춘다. 부르는 쪽이
/// 플랫폼을 몰라야 **화면의 진단 줄이 두 플랫폼에서 같게** 나온다. 갈리기
/// 시작하면 그 차이 자체가 다음 함정이 된다.
class OpenCvRectResult {
  const OpenCvRectResult({
    required this.quads,
    required this.observations,
    required this.meanLuma,
    required this.imageOk,
  });

  /// 사각형 하나당 여덟 개(x,y × 4)가 이어 붙은 **0~1 정규화** 좌표.
  final List<double> quads;

  /// 걸러내기 전 원본 후보 개수. -1이면 실패.
  final int observations;

  /// 넘어온 평면의 평균 밝기(0~255). ⚠️ 이미지가 깨졌는지 가르는 값이다.
  final int meanLuma;

  /// 이미지를 만들 수 있었나. false면 **결함**이지 "못 찾음"이 아니다.
  final bool imageOk;

  /// 채널 응답과 같은 모양의 맵. 부르는 쪽이 플랫폼별로 갈라지지 않게 한다.
  Map<Object?, Object?> toChannelMap() => <Object?, Object?>{
    'quads': quads,
    'observations': observations,
    'meanLuma': meanLuma,
    'imageOk': imageOk,
  };
}

/// 한 프레임에서 사각형 후보를 찾는다.
///
/// [luma]는 **행 패딩이 없는** 밝기 평면이어야 한다([width] × [height]).
/// 부르는 쪽(`downsampleLuma`)이 그렇게 맞춰 준다.
///
/// ⚠️ 던지지 않는다. 실패하면 빈 결과 — 부르는 쪽이 기존 고정 가이드 상자로
/// 되돌아간다.
OpenCvRectResult detectCardQuadsWithOpenCv(
  Uint8List luma, {
  required int width,
  required int height,
}) {
  final mean = meanLumaOf(luma, width: width, height: height);

  if (width < 8 || height < 8 || luma.length < width * height) {
    // ⚠️ 여기로 빠지면 OpenCV는 **한 번도 불리지 않는다.** 그냥 빈 결과를 주면
    // "못 찾았다"와 구분이 안 된다.
    return OpenCvRectResult(
      quads: const [],
      observations: 0,
      meanLuma: mean,
      imageOk: false,
    );
  }

  cv.Mat? gray;
  cv.Mat? blurred;
  cv.Mat? edges;
  try {
    gray = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, luma);

    // 잡음을 눌러 준다 — 안 누르면 종이 결·책상 무늬가 전부 경계가 된다.
    blurred = cv.gaussianBlur(gray, (5, 5), 0);
    edges = cv.canny(blurred, kCannyLow, kCannyHigh);

    final (contours, _) = cv.findContours(
      edges,
      cv.RETR_LIST,
      cv.CHAIN_APPROX_SIMPLE,
    );

    final totalArea = width.toDouble() * height.toDouble();
    final quads = <double>[];
    var observations = 0;

    for (final contour in contours) {
      if (observations >= kMaxObservations) break;

      final area = cv.contourArea(contour).abs();
      if (area < totalArea * kMinContourAreaFraction) continue;

      final perimeter = cv.arcLength(contour, true);
      if (perimeter <= 0) continue;

      final approx = cv.approxPolyDP(
        contour,
        kApproxEpsilonRatio * perimeter,
        true,
      );
      if (approx.length != 4) continue;
      // 오목한 것은 명함이 아니다 — 그림자·글자 덩어리가 이렇게 잡힌다.
      if (!cv.isContourConvex(approx)) continue;

      observations++;
      for (final point in approx) {
        quads.add(point.x / width);
        quads.add(point.y / height);
      }
    }

    return OpenCvRectResult(
      quads: quads,
      observations: observations,
      meanLuma: mean,
      imageOk: true,
    );
  } catch (_) {
    // 실패해도 촬영 자체는 막지 않는다.
    return OpenCvRectResult(
      quads: const [],
      observations: -1,
      meanLuma: mean,
      imageOk: true,
    );
  } finally {
    gray?.dispose();
    blurred?.dispose();
    edges?.dispose();
  }
}

/// 넘어온 평면의 평균 밝기(0~255). 잴 수 없으면 -1.
///
/// ⚠️ 아이폰 쪽 Swift와 **같은 이유로** 잰다 — 이미지가 깨져서 못 찾는 것인지,
/// 멀쩡한데 못 찾는 것인지를 **화면에서** 가르기 위해서다. 로그를 볼 수 없는
/// 기기가 있다는 것을 실측으로 확인했다(iOS 26).
///
/// 매 프레임 도는 일이라 격자로 성기게 본다.
int meanLumaOf(Uint8List luma, {required int width, required int height}) {
  if (width <= 0 || height <= 0 || luma.isEmpty) return -1;
  var total = 0;
  var count = 0;
  final stepY = height ~/ 32 < 1 ? 1 : height ~/ 32;
  final stepX = width ~/ 32 < 1 ? 1 : width ~/ 32;
  for (var y = 0; y < height; y += stepY) {
    final row = y * width;
    for (var x = 0; x < width; x += stepX) {
      final index = row + x;
      if (index < luma.length) {
        total += luma[index];
        count++;
      }
    }
  }
  return count == 0 ? -1 : total ~/ count;
}

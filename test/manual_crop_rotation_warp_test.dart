import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:connection_trace_ai_flutter/core/utils/card_quad_warp.dart';
import 'package:connection_trace_ai_flutter/core/utils/image_rotation_bake.dart';

/// P2-③ 회전 크롭(추가 397) 회귀 방지.
///
/// ## 무엇을 지키나
///
/// 손으로 자르기(`ManualCropView`)에서 [회전]을 쓴 뒤 "이대로 자르기"를
/// 누르면, 화면에서는 테두리가 명함에 딱 맞는데 저장물은 안 맞는 결함이
/// 실기기에서 나왔다(폴드, 빌드 513893b). 대조 실측: 회전 1회를 쓴 저장물은
/// 명함이 이미지 폭의 36.8%, 안 쓴 저장물은 83.9%였다.
///
/// 코드 추적으로 이 경로에서 **두 가지**를 확인했다.
///
/// 1. `warpCardToFile`이 결과가 세로로 길면 무조건 [uprightCard]로 눕힌다
///    (`card_quad_warp.dart`). 이 규칙은 **자동 촬영 경로**(가이드/검출
///    크롭 — "결과물은 항상 눕혀 있다"는 촬영 규칙 전제)를 위한 것인데,
///    손으로 자르기에도 그대로 걸려 있었다. 손으로 자르기는 사용자가
///    [회전] 버튼과 귀퉁이로 **방향을 이미 확정한 뒤** 넘어오므로, 여기서
///    또 뒤집으면 그 선택을 화면에는 안 보이게 조용히 취소한다.
/// 2. 손으로 자르기는 "화면 크기 = 사진 크기"를 넘겨 화면 매핑
///    (`visibleImageRect`)을 항등식으로 만드는 우회를 썼다. 그 우회는
///    **부르는 쪽이 잰 사진 크기(Flutter 디코더)**와 **`warpCardToFile`이
///    자기 소스를 다시 재는 크기(image 패키지 디코더)**가 정확히 같다는
///    전제 위에 있다 — 그 전제가 깨지면(원인이 무엇이든) 화면 매핑 계산이
///    "보이는 영역"을 실제와 다르게 잘라 대칭으로 여백이 남거나 카드가
///    잘리는 결함이 생긴다. `cornersAreImageRelative: true`로 이 화면
///    매핑 자체를 없애면, 두 디코더가 합의해야 하는 자리도 함께 없어진다.
///
/// 아래 테스트는 **이 두 지점을 되돌리면 실패한다.**
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('manual_crop_warp_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// 배경(회녹색) 위에 명함(베이지) 사각형을 그린 합성 사진을 만든다.
  /// 명함은 가장자리에 딱 붙지 않는다 — 실제 촬영본처럼 사방에 배경
  /// 여백이 보이게 한다(가장자리까지 꽉 채운 표본은 "너무 타이트한
  /// 크롭"과 "제대로 된 크롭"을 구분하지 못한다).
  Future<String> writeCardPhoto({
    required int width,
    required int height,
    double marginFrac = 0.10,
  }) async {
    final photo = img.Image(width: width, height: height);
    img.fill(photo, color: img.ColorRgb8(90, 100, 90));
    final left = (width * marginFrac).round();
    final top = (height * marginFrac).round();
    img.fillRect(
      photo,
      x1: left,
      y1: top,
      x2: width - left,
      y2: height - top,
      color: img.ColorRgb8(210, 190, 150),
    );
    final path = '${dir.path}/photo_${width}x$height.jpg';
    await File(path).writeAsBytes(img.encodeJpg(photo, quality: 100));
    return path;
  }

  /// 가운데 가로줄·세로줄에서 베이지(명함) 픽셀이 차지하는 비율.
  ({double wFrac, double hFrac}) beigeFraction(img.Image out) {
    bool isCard(img.Pixel p) => p.r > 180 && (p.r - p.b) > 6;

    final y = out.height ~/ 2;
    var minX = -1, maxX = -1;
    for (var x = 0; x < out.width; x++) {
      if (isCard(out.getPixel(x, y))) {
        minX = minX == -1 ? x : minX;
        maxX = x;
      }
    }
    final x = out.width ~/ 2;
    var minY = -1, maxY = -1;
    for (var yy = 0; yy < out.height; yy++) {
      if (isCard(out.getPixel(x, yy))) {
        minY = minY == -1 ? yy : minY;
        maxY = yy;
      }
    }
    return (
      wFrac: minX == -1 ? 0 : (maxX - minX) / out.width,
      hFrac: minY == -1 ? 0 : (maxY - minY) / out.height,
    );
  }

  const autoCorners = [0.02, 0.02, 0.98, 0.02, 0.98, 0.98, 0.02, 0.98];

  /// [ManualCropView]가 실제로 하는 것과 같은 순서 — 회전 → `_imageSize`
  /// 다시 읽기 → 기본(자동) 귀퉁이로 "이대로 자르기".
  Future<img.Image> rotateThenCrop(
    String sourcePath,
    int degrees, {
    double? screenWidthOverride,
    double? screenHeightOverride,
  }) async {
    final baked = await bakeImageRotation(XFile(sourcePath), degrees);
    final bakedDecoded = img.decodeImage(File(baked.path).readAsBytesSync())!;
    final outPath = '${dir.path}/out_${degrees}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final result = warpCardToFile(
      CardWarpRequest(
        sourcePath: baked.path,
        visibleCornersFlat: autoCorners,
        screenWidth: screenWidthOverride ?? bakedDecoded.width.toDouble(),
        screenHeight: screenHeightOverride ?? bakedDecoded.height.toDouble(),
        outputPath: outPath,
        margin: 0,
        cornersAreImageRelative: true,
        autoUpright: false,
      ),
    );
    expect(result, isNotNull, reason: 'warp가 실패하면 안 된다(회전 $degrees도)');
    return img.decodeImage(File(outPath).readAsBytesSync())!;
  }

  group('회전량별 좌표계 일치(0·90·180·270도)', () {
    for (final degrees in [0, 90, 180, 270]) {
      test('회전 $degrees도 뒤 기본(자동) 귀퉁이로 자르면 명함이 대부분을 채운다', () async {
        final photoPath = await writeCardPhoto(width: 1600, height: 1000);
        final out = await rotateThenCrop(photoPath, degrees);
        final frac = beigeFraction(out);

        // ⚠️ 재확인 기준(추가 397): 80% 이상이면 정상, 50% 미만이면 결함.
        // 이 합성 사진은 명함 여백을 10%씩 둬서 만점(100%)이 안 나오도록
        // 일부러 만들었다 — 기대값은 그 여백을 감안한 실측 기준선(약
        // 83%)에서 잡는다. **회전량에 따라 값이 달라지면 좌표계가 섞인
        // 것**이므로, 여기서 중요한 것은 절대값보다 **네 회전량이 서로
        // 갈리지 않는 것**이다.
        expect(
          frac.wFrac,
          greaterThanOrEqualTo(0.75),
          reason: '회전 $degrees도: 명함 폭이 이미지 폭의 75% 이상이어야 한다 (실측 $frac)',
        );
        expect(
          frac.hFrac,
          greaterThanOrEqualTo(0.75),
          reason: '회전 $degrees도: 명함 높이가 이미지 높이의 75% 이상이어야 한다 (실측 $frac)',
        );
      });
    }
  });

  test(
    '회전 버튼이 정한 방향을 워프가 되돌리지 않는다(autoUpright=false, 추가 397)',
    () async {
      // 가로(landscape) 사진을 90도 돌리면 세로가 된다. autoUpright를 껐으면
      // 결과물도 세로여야 한다 — uprightCard가 다시 개입해 가로로
      // 뒤집으면(옛 결함) 이 테스트가 실패한다.
      final photoPath = await writeCardPhoto(width: 1600, height: 1000);
      final out = await rotateThenCrop(photoPath, 90);
      expect(
        out.height,
        greaterThan(out.width),
        reason:
            '사용자가 90도 돌려 세운 결과는 세로로 저장돼야 한다. '
            '가로(${out.width}x${out.height})로 나왔다면 uprightCard가 '
            '사용자의 회전 선택을 되돌린 것이다.',
      );
    },
  );

  test(
    '회전 + 기울어진 명함을 함께 써도 좌표계가 맞는다(추가 397, 미측정 조합)',
    () async {
      // 살짝 기울어진 명함을 먼저 검출-크롭(warpCardToFile, autoUpright:true
      // — 자동 촬영 경로와 동일)한 뒤, ManualCropView에서 회전 1회를 더
      // 얹는 조합. 실기기에서 아직 재지 못한 조합이라고 backlog에 남아
      // 있었다(2026-08-22, 추가 397) — 순수 로직으로라도 덮어 둔다.
      final rawPhoto = await writeCardPhoto(width: 3024, height: 4032, marginFrac: 0.20);
      final raw = img.decodeImage(File(rawPhoto).readAsBytesSync())!;

      // 촬영본 자체를 3도 기울여 다시 쓴다(사람이 완전히 반듯하게 들지
      // 못하는 상황 흉내).
      final tilted = img.copyRotate(raw, angle: 3);
      final tiltedPath = '${dir.path}/tilted.jpg';
      await File(tiltedPath).writeAsBytes(img.encodeJpg(tilted, quality: 100));

      // 1단계: 자동 촬영 경로와 동일하게 근접 전체 사각형으로 한 번 크롭
      // (실제로는 검출된 사각형을 쓰지만, 여기서는 근접 전체를 써서 같은
      // 함수 경로를 태운다).
      final stage1Out = '${dir.path}/stage1.jpg';
      final r1 = warpCardToFile(
        CardWarpRequest(
          sourcePath: tiltedPath,
          visibleCornersFlat: const [0.05, 0.05, 0.95, 0.05, 0.95, 0.95, 0.05, 0.95],
          screenWidth: tilted.width.toDouble(),
          screenHeight: tilted.height.toDouble(),
          outputPath: stage1Out,
          margin: 0.04,
        ),
      );
      expect(r1, isNotNull);

      // 2단계: ManualCropView에서 회전 1회 + "이대로 자르기".
      final out = await rotateThenCrop(stage1Out, 90);
      final frac = beigeFraction(out);
      expect(
        frac.wFrac,
        greaterThanOrEqualTo(0.55),
        reason: '기울기+회전 조합: 명함 폭이 이미지 폭의 55% 이상이어야 한다 (실측 $frac)',
      );
      expect(
        frac.hFrac,
        greaterThanOrEqualTo(0.55),
        reason: '기울기+회전 조합: 명함 높이가 이미지 높이의 55% 이상이어야 한다 (실측 $frac)',
      );
    },
  );

  test(
    'cornersAreImageRelative=true면 (잘못된) screenWidth/Height와 무관하게 같은 결과가 나온다',
    () async {
      // 이 저장소가 실제로 겪은 위험 — 부르는 쪽이 화면 크기를 잘못 재서
      // 넘기면(디코더 불일치 등, 원인 무관) 화면 매핑 계산이 "보이는
      // 영역"을 실제와 다르게 잡는다. cornersAreImageRelative가 그 계산을
      // 아예 건너뛰므로, 엉뚱한 screenWidth/Height를 넘겨도 결과가 같아야
      // 한다.
      final photoPath = await writeCardPhoto(width: 1000, height: 1600);
      final decoded = img.decodeImage(File(photoPath).readAsBytesSync())!;

      final correctOut = '${dir.path}/correct.jpg';
      final rCorrect = warpCardToFile(
        CardWarpRequest(
          sourcePath: photoPath,
          visibleCornersFlat: autoCorners,
          screenWidth: decoded.width.toDouble(),
          screenHeight: decoded.height.toDouble(),
          outputPath: correctOut,
          margin: 0,
          cornersAreImageRelative: true,
          autoUpright: false,
        ),
      );

      final wrongOut = '${dir.path}/wrong.jpg';
      final rWrong = warpCardToFile(
        CardWarpRequest(
          sourcePath: photoPath,
          visibleCornersFlat: autoCorners,
          // 일부러 완전히 틀린 화면 크기를 넘긴다.
          screenWidth: 9999,
          screenHeight: 42,
          outputPath: wrongOut,
          margin: 0,
          cornersAreImageRelative: true,
          autoUpright: false,
        ),
      );

      expect(rCorrect, isNotNull);
      expect(rWrong, isNotNull);
      expect(rWrong!.width, rCorrect!.width);
      expect(rWrong.height, rCorrect.height);

      final correctFrac = beigeFraction(
        img.decodeImage(File(correctOut).readAsBytesSync())!,
      );
      final wrongFrac = beigeFraction(
        img.decodeImage(File(wrongOut).readAsBytesSync())!,
      );
      expect(wrongFrac.wFrac, closeTo(correctFrac.wFrac, 0.01));
      expect(wrongFrac.hFrac, closeTo(correctFrac.hFrac, 0.01));
    },
  );
}

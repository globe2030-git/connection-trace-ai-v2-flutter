// 갤러리 자르기 화면(결함 399)의 배너 상태 판정을 검증한다.
//
// 왜 중요한가: 398이 [자동 인식] 배너를 열어 뒀는데 실제 검출은 한 번도
// 돌지 않아, "찾지 못했는데 찾았다고 말하는" 화면이 났다(실측: 명함이
// 상자의 69%·55%만 차지). 이 판정을 위젯 State 안에만 두면 사람이 화면을
// 눌러 봐야만 그 경로가 남아 있는지 알 수 있다 — 여기서 화면 없이 잡는다.
import 'package:connection_trace_ai_flutter/core/utils/crop_mode_corners.dart';
import 'package:connection_trace_ai_flutter/core/utils/gallery_crop_banner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('galleryCropBannerKind — 갤러리 경로(autoDetectEnabled: true)', () {
    test('검출 중이면 detecting — 모드가 무엇이든 우선한다', () {
      for (final mode in CropAdjustMode.values) {
        expect(
          galleryCropBannerKind(
            autoDetectEnabled: true,
            detecting: true,
            hasDetectedCorners: false,
            mode: mode,
          ),
          GalleryCropBannerKind.detecting,
        );
      }
    });

    test('검출을 끝냈는데 못 찾았으면 notFound — [자동 인식] 탭이어도 마찬가지', () {
      expect(
        galleryCropBannerKind(
          autoDetectEnabled: true,
          detecting: false,
          hasDetectedCorners: false,
          mode: CropAdjustMode.auto,
        ),
        GalleryCropBannerKind.notFound,
        reason:
            '사용자가 검출 실패 뒤에도 [자동 인식] 탭을 다시 누를 수 있다 — '
            '그때도 "찾았다"고 말하면 안 된다(결함 399가 고치려는 유형).',
      );
      expect(
        galleryCropBannerKind(
          autoDetectEnabled: true,
          detecting: false,
          hasDetectedCorners: false,
          mode: CropAdjustMode.manual,
        ),
        GalleryCropBannerKind.notFound,
      );
    });

    test('실제로 찾았고 [자동 인식] 탭이면 autoFound', () {
      expect(
        galleryCropBannerKind(
          autoDetectEnabled: true,
          detecting: false,
          hasDetectedCorners: true,
          mode: CropAdjustMode.auto,
        ),
        GalleryCropBannerKind.autoFound,
      );
    });

    test('찾았어도 사용자가 [직접 조정]을 골랐으면 manualHint', () {
      expect(
        galleryCropBannerKind(
          autoDetectEnabled: true,
          detecting: false,
          hasDetectedCorners: true,
          mode: CropAdjustMode.manual,
        ),
        GalleryCropBannerKind.manualHint,
      );
    });
  });

  group('galleryCropBannerKind — 촬영 경로(autoDetectEnabled: false)', () {
    test('⚠️ 회귀 방지: detecting·notFound로는 절대 가지 않는다', () {
      // 촬영 경로는 이 화면에 오기 전 이미 실시간 검출을 거쳤다 — 여기서
      // 다시 "검출 중"·"못 찾음"을 말하면 뜻이 안 통한다.
      for (final detecting in [true, false]) {
        for (final hasDetected in [true, false]) {
          for (final mode in CropAdjustMode.values) {
            final kind = galleryCropBannerKind(
              autoDetectEnabled: false,
              detecting: detecting,
              hasDetectedCorners: hasDetected,
              mode: mode,
            );
            expect(
              kind,
              anyOf(
                GalleryCropBannerKind.autoFound,
                GalleryCropBannerKind.manualHint,
              ),
            );
          }
        }
      }
    });

    test('모드만 본다 — auto면 autoFound, manual이면 manualHint', () {
      expect(
        galleryCropBannerKind(
          autoDetectEnabled: false,
          detecting: false,
          hasDetectedCorners: false,
          mode: CropAdjustMode.auto,
        ),
        GalleryCropBannerKind.autoFound,
      );
      expect(
        galleryCropBannerKind(
          autoDetectEnabled: false,
          detecting: false,
          hasDetectedCorners: false,
          mode: CropAdjustMode.manual,
        ),
        GalleryCropBannerKind.manualHint,
      );
    });
  });

  group('galleryCropBannerText', () {
    test('notFound와 autoFound는 절대 같은 문구를 쓰지 않는다', () {
      expect(
        galleryCropBannerText(GalleryCropBannerKind.notFound),
        isNot(galleryCropBannerText(GalleryCropBannerKind.autoFound)),
      );
    });

    test('찾지 못했을 때는 "찾았다"는 낱말이 들어가지 않는다', () {
      final text = galleryCropBannerText(GalleryCropBannerKind.notFound);
      expect(text.contains('찾았'), isFalse);
      expect(text, contains('찾지 못했'));
    });

    test('실제로 찾았을 때만 "찾았다"고 말한다', () {
      expect(
        galleryCropBannerText(GalleryCropBannerKind.autoFound),
        contains('찾았어요'),
      );
    });
  });
}

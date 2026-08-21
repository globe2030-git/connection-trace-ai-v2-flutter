// 갤러리 선택 화면([FilePickerModalView])의 문구 계산을 검증한다.
//
// P2-②의 요구: "1장(또는 0장)만 고르면 기존 화면과 완전히 같다"(회귀 0).
// 이 파일은 그 문구가 **글자 하나까지** 예전과 같은지를 고정한다.
import 'package:connection_trace_ai_flutter/core/utils/gallery_picker_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('galleryPickerHeaderTitle — 회귀 0(1장 이하는 기존과 동일)', () {
    test('0장 — 기존 문구 그대로', () {
      expect(
        galleryPickerHeaderTitle(sideLabel: '앞면', pickedCount: 0),
        '앞면 이미지 선택',
      );
    });

    test('1장 — 기존 문구 그대로', () {
      expect(
        galleryPickerHeaderTitle(sideLabel: '뒷면', pickedCount: 1),
        '뒷면 이미지 선택',
      );
    });

    test('2장일 때만 문구가 바뀐다', () {
      expect(
        galleryPickerHeaderTitle(sideLabel: '앞면', pickedCount: 2),
        '명함 이미지 선택 (2장)',
      );
    });
  });

  group('galleryPickerPrimaryButtonLabel — 회귀 0(1장 이하는 기존과 동일)', () {
    test('0장 — 기존 문구 그대로', () {
      expect(
        galleryPickerPrimaryButtonLabel(isProcessing: false, pickedCount: 0),
        '선택한 파일 명함 OCR 스캔 실행',
      );
    });

    test('1장 — 기존 문구 그대로', () {
      expect(
        galleryPickerPrimaryButtonLabel(isProcessing: false, pickedCount: 1),
        '선택한 파일 명함 OCR 스캔 실행',
      );
    });

    test('2장일 때만 문구가 바뀐다', () {
      expect(
        galleryPickerPrimaryButtonLabel(isProcessing: false, pickedCount: 2),
        '2장 불러와 인식하기',
      );
    });

    test('인식 중에는 장수와 무관하게 진행 문구다', () {
      expect(
        galleryPickerPrimaryButtonLabel(isProcessing: true, pickedCount: 2),
        '선택한 이미지 OCR 스캔 중...',
      );
    });
  });
}

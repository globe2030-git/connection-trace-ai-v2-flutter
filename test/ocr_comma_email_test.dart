/// **마침표를 쉼표로 읽은 이메일을 되살린다**(2026-08-29, globe2030님 제보).
///
/// ## 무엇이 문제였나
///
/// 이메일 정규식은 `…@도메인.최상위`처럼 **마침표**를 요구한다. 인식기가
/// **`.` 을 `,` 로 읽으면** 정규식에 **아예 안 걸리고**, 이메일 칸이 **빈 채로**
/// 저장된다.
///
/// 🚨 「잘못 잘린」 것이 아니라 **「없는 것으로 취급」**된 것이라 **화면에 아무
/// 흔적이 안 남는다** — 이용자는 인식기가 그 줄을 못 봤다고 생각한다.
///
/// ✅ **실물**: 같은 명함을 **아이폰·폴드 양쪽**에 넣었는데 **둘 다** 못 읽어
/// 수기로 넣으셨다. **기기 차이가 아니라 인식기 공통**이다.
///
/// 📌 그 명함 배치: `Mobile 010-…  E-mail  hong@…` — **한 줄에 나란히** 있다.
library;

import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('되살린다', () {
    test('⭐ 도메인의 쉼표를 마침표로', () {
      expect(
        OcrScannerService.repairCommaEmail('hong@company,co,kr'),
        'hong@company.co.kr',
      );
    });

    test('로컬파트의 쉼표도', () {
      expect(
        OcrScannerService.repairCommaEmail('hong,gil@x,com'),
        'hong.gil@x.com',
      );
    });

    test('쉼표와 마침표가 섞여 있어도', () {
      expect(
        OcrScannerService.repairCommaEmail('a.b@company,co.kr'),
        'a.b@company.co.kr',
      );
    });
  });

  group('🚨 건드리면 안 되는 것', () {
    test('이미 멀쩡한 이메일은 그대로 둔다(null)', () {
      expect(OcrScannerService.repairCommaEmail('hong@company.co.kr'), isNull);
    });

    test('끝에 붙은 쉼표는 문장부호다 — 마침표로 바꾸지 않는다', () {
      // 'a@b.com,' → 바꾸면 'a@b.com.' 이 되어 되레 깨진다. 잘라 낸 뒤 보면
      // 이미 멀쩡하므로 손댈 것이 없다(null).
      expect(OcrScannerService.repairCommaEmail('a@b.com,'), isNull);
    });

    test('@ 가 없으면 이메일이 아니다', () {
      expect(OcrScannerService.repairCommaEmail('서울시 강남구,역삼동'), isNull);
    });

    test('🚨 되살려도 이메일이 안 되면 포기한다 — 짐작해서 채우지 않는다', () {
      expect(OcrScannerService.repairCommaEmail('hong@company,'), isNull);
      expect(OcrScannerService.repairCommaEmail('@,,'), isNull);
    });
  });

  group('실제 명함 배치 — Mobile 과 E-mail 이 한 줄에 나란히', () {
    test('⭐ 그 줄에서 이메일을 되살린다', () {
      final line = 'Mobile 010-1234-5678  E-mail  hong@company,co,kr';
      final token = line
          .split(RegExp(r'\s+'))
          .firstWhere((t) => t.contains('@'));
      expect(OcrScannerService.repairCommaEmail(token), 'hong@company.co.kr');
    });

    test('라벨이 붙어 있어도 — 라벨 걷어내기는 기존 규칙이 처리한다', () {
      expect(
        OcrScannerService.repairCommaEmail('hong@company,co,kr'),
        'hong@company.co.kr',
      );
    });

    test('🚨 전화번호를 이메일로 착각하지 않는다', () {
      expect(OcrScannerService.repairCommaEmail('010-1234-5678'), isNull);
    });
  });

  group('부르는 곳이 있나 — 규칙만 맞고 안 부르면 소용이 없다', () {
    test('정규식이 실패했을 때 폴백으로 쓰인다', () {
      final src = File(
        'lib/core/services/ocr_scanner_service.dart',
      ).readAsStringSync();
      expect(src.contains('repairCommaEmail(token)'), isTrue);
      expect(src.contains("line.contains('@')"), isTrue);
    });
  });
}

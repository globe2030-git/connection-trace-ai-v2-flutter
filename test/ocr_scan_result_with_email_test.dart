// 라틴 2차 패스가 결과에 이메일을 갈아 끼우는 것(추가 336).
//
// ⚠️ 2차 패스 **자체**는 여기서 못 본다 — ML Kit은 실기기에서만 돌고, 재생
// 하네스는 저장된 글자만 다시 먹인다. 그래서 이 테스트가 지키는 것은
// **"이메일 말고는 아무것도 안 바뀐다"**이다. 효과는 기기에서 일괄 스캔을
// 돌려 재야 한다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

OcrScanResult _sample({String email = ''}) => OcrScanResult(
  rawText: '원문 줄',
  rawLines: const ['홍길동', '(주)어디어디'],
  rawLineBoxes: [lineBoxOf('홍길동', height: 30)],
  name: '홍길동',
  company: '(주)어디어디',
  title: '부장',
  department: '영업팀',
  phone: '010-0000-0001',
  officePhone: '02-0000-0002',
  fax: '02-0000-0003',
  email: email,
  website: 'https://example.com',
  address: '서울시 어디구 어디로 1',
  addressDetail: '2층',
  postalCode: '01234',
  tags: const ['태그'],
  avatarUrl: '/a/b.png',
  imagePath: '/c/d.png',
);

void main() {
  group('withEmail', () {
    test('이메일이 바뀐다', () {
      expect(_sample().withEmail('a@b.com').email, 'a@b.com');
    });

    test('⚠️ 나머지 칸은 하나도 안 바뀐다', () {
      final before = _sample(email: '옛값');
      final after = before.withEmail('새값@b.com');

      expect(after.rawText, before.rawText);
      expect(after.rawLines, before.rawLines);
      expect(after.rawLineBoxes, before.rawLineBoxes);
      expect(after.name, before.name);
      expect(after.company, before.company);
      expect(after.title, before.title);
      expect(after.department, before.department);
      expect(after.phone, before.phone);
      expect(after.officePhone, before.officePhone);
      expect(after.fax, before.fax);
      expect(after.website, before.website);
      expect(after.address, before.address);
      expect(after.addressDetail, before.addressDetail);
      expect(after.postalCode, before.postalCode);
      expect(after.tags, before.tags);
      expect(after.avatarUrl, before.avatarUrl);
      expect(after.imagePath, before.imagePath);
      expect(after.parseShape, before.parseShape);
    });

    test('원래 값은 그대로 있다(사본을 만든다)', () {
      final before = _sample(email: '옛값');
      before.withEmail('새값@b.com');
      expect(before.email, '옛값');
    });
  });
}

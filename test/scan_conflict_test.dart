// "같은 명함의 뒷면인가, 다른 명함인가" 판정 규칙 검증.
//
// 2026-08-14: 예전에는 이름 하나만 비교해서, 앞면에서 이름을 못 읽으면 감지가
// 아예 안 됐다. "확신하지 못하면 비운다"(추가 183)로 바꾸면서 이름이 빈 경우가
// 103장 기준 9장 → 24장으로 늘어 이 구멍이 더 자주 열리게 됐다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/utils/scan_conflict.dart';

bool check({
  String existingName = '',
  String scannedName = '',
  String existingPhone = '',
  String scannedPhone = '',
  String existingEmail = '',
  String scannedEmail = '',
}) => ScanConflict.looksLikeDifferentCard(
  existingName: existingName,
  scannedName: scannedName,
  existingPhone: existingPhone,
  scannedPhone: scannedPhone,
  existingEmail: existingEmail,
  scannedEmail: scannedEmail,
);

void main() {
  group('다른 명함으로 본다', () {
    test('이름이 서로 다르면', () {
      expect(check(existingName: '남궁현', scannedName: '홍길동'), isTrue);
    });

    test('이름이 비어 있어도 휴대폰이 다르면 — 예전에는 못 잡던 경우', () {
      expect(
        check(existingPhone: '010-1111-2222', scannedPhone: '010-3333-4444'),
        isTrue,
      );
    });

    test('이름이 비어 있어도 이메일이 다르면', () {
      expect(
        check(existingEmail: 'a@hanbit.co.kr', scannedEmail: 'b@other.com'),
        isTrue,
      );
    });
  });

  group('같은 명함으로 본다 — 오탐 방지', () {
    test('앞면에 없던 값이 뒷면에서 나온 경우(한쪽이 빔)', () {
      expect(check(existingName: '남궁현', scannedName: ''), isFalse);
      expect(check(scannedPhone: '010-1111-2222'), isFalse);
      expect(check(existingEmail: 'a@hanbit.co.kr', scannedEmail: ''), isFalse);
    });

    test('아무 값도 없는 첫 스캔', () {
      expect(check(), isFalse);
    });

    test('이름의 음절 사이 공백만 다른 경우', () {
      expect(check(existingName: '최 태 웅', scannedName: '최태웅'), isFalse);
    });

    test('전화번호 구분자만 다른 경우', () {
      expect(
        check(existingPhone: '010-1111-2222', scannedPhone: '010.1111.2222'),
        isFalse,
      );
      expect(
        check(existingPhone: '01011112222', scannedPhone: 'M 010 1111 2222'),
        isFalse,
      );
    });

    test('이메일 대소문자만 다른 경우', () {
      expect(
        check(
          existingEmail: 'A@Hanbit.CO.KR',
          scannedEmail: 'a@hanbit.co.kr',
        ),
        isFalse,
      );
    });

    test('회사명은 판단에 쓰지 않는다 — 한글/영문 병기 오탐 방지', () {
      // 같은 명함이라도 앞면은 "크림하우스(주)", 뒷면은 "CREAMHOUSE"인 경우가
      // 흔하다. 회사명을 비교했다면 다른 명함으로 잘못 잡았을 것이다.
      // (회사명 인자 자체가 없으므로 이름·전화·이메일이 안 부딪히면 같은 명함)
      expect(check(existingName: '이희규', scannedName: ''), isFalse);
    });
  });

  // --- F-01 칸 단위 충돌 -------------------------------------------------
  //
  // "이 스캔 전체가 다른 사람 것인가"(위 group)와 "이 칸 하나를 어느 값으로
  // 둘 것인가"는 다른 물음이다. 뒷면을 이어 찍었을 때 이미 채워진 칸에 들어온
  // 값이 조용히 버려지던 것을 사용자에게 꺼내 보이기 위한 판정이다.
  group('칸 단위 충돌(F-01)', () {
    bool conflict(String a, String b, ScanValueKind kind) =>
        ScanConflict.valuesConflict(existing: a, scanned: b, kind: kind);

    test('한쪽이 비어 있으면 충돌이 아니다 — 빈 칸 채우기는 고를 일이 없다', () {
      expect(conflict('', '02-555-0000', ScanValueKind.phone), isFalse);
      expect(conflict('010-1234-5678', '', ScanValueKind.phone), isFalse);
    });

    test('앞면 휴대폰 / 뒷면 대표번호 — 이게 F-01이 꺼내려는 값이다', () {
      expect(
        conflict('010-1234-5678', '02-555-0000', ScanValueKind.phone),
        isTrue,
      );
    });

    test('전화번호 구분자만 다르면 충돌이 아니다', () {
      expect(
        conflict('010-1234-5678', '010.1234.5678', ScanValueKind.phone),
        isFalse,
      );
    });

    test('이름은 음절 사이 공백을 무시한다', () {
      expect(conflict('최 태 웅', '최태웅', ScanValueKind.name), isFalse);
      expect(conflict('최태웅', '남궁현', ScanValueKind.name), isTrue);
    });

    test('이메일은 대소문자를 무시한다', () {
      expect(
        conflict('A@Hanbit.CO.KR', 'a@hanbit.co.kr', ScanValueKind.email),
        isFalse,
      );
      expect(
        conflict('a@hanbit.co.kr', 'a@raum.co.kr', ScanValueKind.email),
        isTrue,
      );
    });

    test('자유 문장은 연속 공백·앞뒤 공백만 다르면 충돌이 아니다', () {
      expect(
        conflict(' 서울시  강남구 ', '서울시 강남구', ScanValueKind.text),
        isFalse,
      );
    });

    test('⚠️ 회사명 한글/영문 표기는 **칸 단위로는 충돌로 본다**', () {
      // 다른 명함인지 판정할 때는 회사명을 일부러 안 본다(위 group). 하지만
      // 칸 단위로는 이야기가 다르다 — 둘 다 쓸모 있는 값이고 어느 쪽을 남길지는
      // 사용자가 정할 일이다. 두 규칙이 반대인 것이 의도다.
      expect(conflict('크림하우스(주)', 'CREAMHOUSE', ScanValueKind.text), isTrue);
    });
  });
}

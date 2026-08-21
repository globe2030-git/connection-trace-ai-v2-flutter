import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/utils/masked_email.dart';

void main() {
  group('로그인 이메일 가리기', () {
    test('아이디 앞 두 글자만 남기고 도메인은 남긴다', () {
      expect(maskEmail('globe@creamhouse.net'), 'gl****@creamhouse.net');
    });

    test('⚠️ 별표 개수가 실제 길이를 드러내지 않는다', () {
      // 길이에 맞춰 별표를 찍으면 아이디가 몇 자인지가 드러난다 —
      // 가리는 시늉만 하는 셈이다. 길이가 달라도 별표는 같아야 한다.
      final a = maskEmail('ab@x.com');
      final b = maskEmail('abcdefghijklmnop@x.com');
      expect(a, 'ab****@x.com');
      expect(b, 'ab****@x.com');
      expect(a, b);
    });

    test('⚠️ 도메인은 가리지 않는다 — 계정을 가리는 실마리다', () {
      // 회사 계정인지 개인 계정인지가 "어느 계정으로 로그인했나"의 단서다.
      expect(maskEmail('hong@gmail.com'), endsWith('@gmail.com'));
      expect(maskEmail('hong@creamhouse.net'), endsWith('@creamhouse.net'));
    });

    test('아이디가 한 글자여도 그 한 글자는 남긴다', () {
      // 전부 가리면 계정을 가릴 단서가 사라진다.
      expect(maskEmail('a@x.com'), 'a****@x.com');
    });

    test('⚠️ @ 가 없으면 이메일이 아니므로 더 강하게 가린다', () {
      // 애플 릴레이나 제공자가 이상한 값을 줄 때. 모르는 값을 그대로
      // 펼쳐 두는 것보다 가리는 쪽이 안전하다.
      expect(maskEmail('notanemail'), 'no****');
    });

    test('@ 가 맨 앞이면 도메인을 가려낼 수 없다 — 통째로 가린다', () {
      expect(maskEmail('@x.com'), '@x****');
    });

    test('⚠️ @ 가 여러 개면 마지막 것을 도메인 경계로 본다', () {
      // "a@b"@example.com 같은 형태가 규격상 가능하다. 앞 두 글자를 남기는
      // 규칙을 그대로 적용하므로 남는 두 글자에 @ 가 들어갈 수 있다.
      // 📌 보기 좋지는 않지만 **정확하다** — 있는 글자를 그대로 남긴다.
      expect(maskEmail('a@b@example.com'), 'a@****@example.com');
    });

    test('빈 값·공백은 그대로 둔다', () {
      expect(maskEmail(''), '');
      expect(maskEmail('   '), '');
    });
  });
}

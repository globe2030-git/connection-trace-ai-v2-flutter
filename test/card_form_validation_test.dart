// 명함 등록/편집 폼의 필수 검증 규칙(추가 361 스펙)을 화면 없이 고정한다.
//
// 화면 위젯 테스트만으로는 F-10(재연락 문구가 규칙 테스트를 다 통과하고도
// 실기기에서만 깨졌던 사고)류를 못 잡는다 — 판정 로직 자체를 위젯 밖 순수
// 함수로 뽑아 여기서 직접 검증한다.
import 'package:connection_trace_ai_flutter/core/utils/card_form_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('기본 빌드에서는 정리 모드가 꺼져 있다', () {
    test('--dart-define 없이 실행되는 이 테스트 환경도 마찬가지', () {
      expect(relaxRequiredForCleanup, isFalse);
    });
  });

  group('이름·회사명 — 항상 필수(신규), 편집은 원래 비었던 칸만 완화', () {
    test('신규 등록: 비어 있으면 막는다', () {
      expect(
        validateRequiredTextField(
          value: '',
          emptyMessage: '이름을 입력해 주세요.',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        '이름을 입력해 주세요.',
      );
    });

    test('신규 등록: 값이 있으면 통과', () {
      expect(
        validateRequiredTextField(
          value: '홍길동',
          emptyMessage: '이름을 입력해 주세요.',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        isNull,
      );
    });

    test('편집: 열 때 이미 비어 있던 칸은 빈 채로 저장 허용', () {
      expect(
        validateRequiredTextField(
          value: '',
          emptyMessage: '회사명을 입력해 주세요.',
          isEditing: true,
          wasInitiallyEmpty: true,
        ),
        isNull,
      );
    });

    test('편집: 열 때 값이 있었는데 지금 지웠으면 여전히 막는다', () {
      expect(
        validateRequiredTextField(
          value: '  ',
          emptyMessage: '회사명을 입력해 주세요.',
          isEditing: true,
          wasInitiallyEmpty: false,
        ),
        '회사명을 입력해 주세요.',
      );
    });

    test('정리 모드면 편집 여부와 무관하게 비어 있어도 통과', () {
      expect(
        validateRequiredTextField(
          value: '',
          emptyMessage: '이름을 입력해 주세요.',
          isEditing: false,
          wasInitiallyEmpty: false,
          relaxAll: true,
        ),
        isNull,
      );
    });
  });

  group('이메일 — 2026-08-26부터 단독 필수가 아니다. 형식만 본다', () {
    test('비어 있으면 통과 — 예전에는 여기서 막았고, 그게 가짜 이메일의 원인이었다', () {
      expect(validateEmailField(''), isNull);
      expect(validateEmailField(null), isNull);
      expect(validateEmailField('   '), isNull);
    });

    test('값이 있는데 형식이 틀리면 형식 오류', () {
      expect(
        validateEmailField('not-an-email'),
        '올바른 이메일 형식을 입력해 주세요.',
      );
    });

    test('형식이 맞으면 통과', () {
      expect(validateEmailField('name@company.com'), isNull);
    });
  });

  group('연락 수단 — 휴대폰·사무실 전화·이메일 중 하나만 있으면 통과', () {
    String? reach({
      String? mobile,
      String? office,
      String? email,
      bool isEditing = false,
      bool wasInitiallyEmpty = false,
      bool relaxAll = false,
    }) => validateContactReachField(
      mobileValue: mobile,
      officeValue: office,
      emailValue: email,
      isEditing: isEditing,
      wasInitiallyEmpty: wasInitiallyEmpty,
      relaxAll: relaxAll,
    );

    const groupError = '휴대폰 · 사무실 전화 · 이메일 중 하나는 입력해 주세요.';

    test('휴대폰만 있으면 통과(형식 맞음)', () {
      expect(reach(mobile: '010-1234-5678'), isNull);
    });

    test('사무실 전화만 있으면 휴대폰 칸도 통과', () {
      expect(reach(mobile: '', office: '02-123-4567'), isNull);
    });

    // 🚨 이번 변경의 핵심. 이메일뿐인 명함에 가짜 휴대폰을 요구하던 자리다.
    test('이메일만 있어도 휴대폰 칸이 통과한다', () {
      expect(reach(mobile: '', office: '', email: 'a@b.com'), isNull);
    });

    test('셋 다 없으면(신규) 휴대폰 칸에 묶음 오류', () {
      expect(reach(mobile: '', office: '', email: ''), groupError);
      expect(reach(), groupError);
    });

    test('공백만 든 값은 없는 것으로 친다', () {
      expect(reach(mobile: ' ', office: '  ', email: '   '), groupError);
    });

    // 형식이 틀린 이메일도 "연락 수단이 하나 있다"로 친다. 그러지 않으면
    // 이메일 오타 하나에 휴대폰 칸까지 빨개진다 — 형식은 이메일 칸이 본다.
    test('형식이 틀린 이메일도 묶음 조건은 채운다(형식은 이메일 칸이 본다)', () {
      expect(reach(mobile: '', office: '', email: 'broken'), isNull);
      expect(validateEmailField('broken'), '올바른 이메일 형식을 입력해 주세요.');
    });

    test('휴대폰 값이 있으면 다른 칸과 무관하게 형식을 본다', () {
      expect(
        reach(mobile: '01012345678', office: '02-123-4567', email: 'a@b.com'),
        '올바른 전화번호 형식(예: 010-1234-5678)으로 입력해 주세요.',
      );
    });

    test('사무실 전화 형식은 그 칸이 따로 본다', () {
      expect(
        validateOfficePhoneField('021234567'),
        '올바른 전화번호 형식(예: 02-123-4567)으로 입력해 주세요.',
      );
      expect(validateOfficePhoneField(''), isNull);
    });

    test('편집: 열 때 셋 다 비어 있었으면 그대로 저장 허용', () {
      expect(
        reach(mobile: '', office: '', email: '',
            isEditing: true, wasInitiallyEmpty: true),
        isNull,
      );
    });

    test('편집: 열 때 하나라도 있었는데 지금 셋 다 지우면 여전히 막는다', () {
      expect(
        reach(mobile: '', office: '', email: '',
            isEditing: true, wasInitiallyEmpty: false),
        groupError,
      );
    });

    test('신규 등록은 편집 완화 규칙을 타지 않는다 — 강제', () {
      expect(
        reach(mobile: '', office: '', email: '',
            isEditing: false, wasInitiallyEmpty: true),
        groupError,
      );
    });

    test('정리 모드면 편집 여부와 무관하게 셋 다 없어도 통과', () {
      expect(
        reach(mobile: '', office: '', email: '', relaxAll: true),
        isNull,
      );
    });

    test('정리 모드에서도 값이 있으면 형식은 그대로 본다', () {
      expect(
        reach(mobile: '01012345678', relaxAll: true),
        '올바른 전화번호 형식(예: 010-1234-5678)으로 입력해 주세요.',
      );
    });
  });
}

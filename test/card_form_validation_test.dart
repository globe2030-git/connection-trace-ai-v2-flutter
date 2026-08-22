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

  group('이메일 — 필수 규칙은 위와 같고, 값이 있을 때만 형식을 본다', () {
    test('비어 있으면(신규) 막는다', () {
      expect(
        validateEmailField(
          value: '',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        '이메일을 입력해 주세요.',
      );
    });

    test('값이 있는데 형식이 틀리면 형식 오류', () {
      expect(
        validateEmailField(
          value: 'not-an-email',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        '올바른 이메일 형식을 입력해 주세요.',
      );
    });

    test('형식이 맞으면 통과', () {
      expect(
        validateEmailField(
          value: 'name@company.com',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        isNull,
      );
    });

    test('편집: 열 때 비었던 칸은 형식 검사 없이 통과', () {
      expect(
        validateEmailField(value: '', isEditing: true, wasInitiallyEmpty: true),
        isNull,
      );
    });

    test('정리 모드: 비어 있어도 통과, 값이 있으면 형식은 여전히 본다', () {
      expect(
        validateEmailField(
          value: '',
          isEditing: false,
          wasInitiallyEmpty: false,
          relaxAll: true,
        ),
        isNull,
      );
      expect(
        validateEmailField(
          value: 'broken',
          isEditing: false,
          wasInitiallyEmpty: false,
          relaxAll: true,
        ),
        '올바른 이메일 형식을 입력해 주세요.',
      );
    });
  });

  group('전화 — 휴대폰 또는 사무실 전화 중 하나만 있으면 통과(either-or)', () {
    test('휴대폰만 있으면 통과(형식 맞음)', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '010-1234-5678',
          officeValue: '',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        isNull,
      );
      expect(validateOfficePhoneField(''), isNull);
    });

    test('사무실 전화만 있으면 휴대폰 칸도 통과', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '',
          officeValue: '02-123-4567',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        isNull,
      );
      expect(validateOfficePhoneField('02-123-4567'), isNull);
    });

    test('둘 다 없으면(신규) 휴대폰 칸에 either-or 오류', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '',
          officeValue: '',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        '휴대폰 또는 사무실 전화 중 하나를 입력해 주세요.',
      );
      // 사무실 전화 칸 자체는 오류를 보여주지 않는다 — 스펙: 오류는
      // 휴대폰 칸에만 뜬다.
      expect(validateOfficePhoneField(''), isNull);
    });

    test('둘 다 있으면 통과', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '010-1234-5678',
          officeValue: '02-123-4567',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        isNull,
      );
      expect(validateOfficePhoneField('02-123-4567'), isNull);
    });

    test('형식 오류는 값이 있을 때만 — 휴대폰 형식이 틀리면 막는다', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '010-2345', // 자릿수 부족
          officeValue: '',
          isEditing: false,
          wasInitiallyEmpty: false,
        ),
        '올바른 전화번호 형식(예: 010-1234-5678)으로 입력해 주세요.',
      );
    });

    test('형식 오류는 값이 있을 때만 — 사무실 전화 형식이 틀리면 막는다', () {
      expect(
        validateOfficePhoneField('02-abcd'),
        '올바른 전화번호 형식(예: 02-123-4567)으로 입력해 주세요.',
      );
    });

    test('편집: 열 때 휴대폰·사무실 둘 다 비어 있었으면 그대로 저장 허용', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '',
          officeValue: '',
          isEditing: true,
          wasInitiallyEmpty: true,
        ),
        isNull,
      );
    });

    test('편집: 열 때 휴대폰만 있었는데 지금 둘 다 지우면 여전히 막는다', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '',
          officeValue: '',
          isEditing: true,
          wasInitiallyEmpty: false,
        ),
        '휴대폰 또는 사무실 전화 중 하나를 입력해 주세요.',
      );
    });

    test('신규 등록은 편집 완화 규칙을 타지 않는다 — 강제', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '',
          officeValue: '',
          isEditing: false,
          wasInitiallyEmpty: true, // isEditing이 false면 의미 없음
        ),
        '휴대폰 또는 사무실 전화 중 하나를 입력해 주세요.',
      );
    });

    test('정리 모드면 편집 여부와 무관하게 둘 다 없어도 통과', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '',
          officeValue: '',
          isEditing: false,
          wasInitiallyEmpty: false,
          relaxAll: true,
        ),
        isNull,
      );
    });

    test('정리 모드에서도 값이 있으면 형식은 그대로 본다', () {
      expect(
        validateMobilePhoneField(
          mobileValue: '010-99',
          officeValue: '',
          isEditing: false,
          wasInitiallyEmpty: false,
          relaxAll: true,
        ),
        '올바른 전화번호 형식(예: 010-1234-5678)으로 입력해 주세요.',
      );
    });
  });
}

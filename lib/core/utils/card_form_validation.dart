/// 명함 등록/편집 폼의 필수 칸 검증 규칙.
///
/// 화면(`add_card_modal_view.dart`)의 `TextFormField.validator`는 이 파일의
/// 함수를 그대로 호출한다 — 판정 로직을 위젯 밖 순수 함수로 뽑아 둔 이유는
/// "화면이 말하는 것과 로직이 다른" 유형(F-10, 재연락 문구가 실기기에서만
/// 깨졌던 사고)을 피하기 위해서다. 화면을 띄우지 않고도 자동 테스트로 이
/// 규칙 자체를 검증할 수 있다.
///
/// ## 배경(2026-08-21 사용자 확정 스펙)
///
/// 명함에 없는 값을 폼이 강제로 요구해서 테스터가 가짜 값(010-2345-6789,
/// error@ 등)을 채워 넣은 것이 자리채움 24건의 근본 원인이었다. 또 요즘
/// 명함은 휴대폰만 있거나 사무실 전화만 있는 경우가 흔한데, 휴대폰이 단독
/// 필수였던 예전 규칙은 사무실 전화뿐인 명함에도 가짜 휴대폰을 요구했다.
///
/// ## 세 가지 상황
///
/// 1. **신규 등록**: 이름·회사명·이메일은 항상 필수. 전화는 휴대폰 또는
///    사무실 전화 중 하나만 있으면 통과.
/// 2. **편집(정리 상태 보존)**: 폼을 열던 시점에 이미 비어 있던 필수 칸은
///    빈 채로 저장을 허용한다. 데이터 정제로 비운 필드를 편집할 때마다 다시
///    채우라고 막으면 가짜 값이 재생산된다. 값을 넣으면 형식 검사는 그대로
///    적용된다.
/// 3. **정리 모드**(`--dart-define=RELAX_REQUIRED_FOR_CLEANUP=true`, 기본
///    꺼짐): 모든 "비어 있음" 검증을 해제한다. 형식 검사는 값이 있으면
///    그대로 유지한다. 대량 데이터 정리 작업에서 잠깐 켜는 용도로,
///    기본 빌드에서는 항상 꺼져 있다.
library;

/// 정리 모드가 켜져 있는지. `--dart-define=RELAX_REQUIRED_FOR_CLEANUP=true`로
/// 빌드했을 때만 true — 기본(정의 안 함/false)에서는 항상 false다.
const bool relaxRequiredForCleanup = bool.fromEnvironment(
  'RELAX_REQUIRED_FOR_CLEANUP',
);

/// 한국 전화번호 형식(하이픈 포함) 정규식. 지역번호 2~3자리, 국번 3~4자리,
/// 번호 4자리 — `KoreanPhoneNumberFormatter`가 만들어내는 모든 형태(02-XXX-XXXX,
/// 02-XXXX-XXXX, 010-XXXX-XXXX 등)를 하나로 커버한다. 휴대폰·사무실·직통·팩스
/// 전부 이 정규식 하나로 일관되게 검사한다.
final RegExp koreanPhoneRegExp = RegExp(r'^\d{2,3}-\d{3,4}-\d{4}$');

/// 이 필드의 "비어 있음" 오류를 건너뛸지 판단한다.
///
/// - 정리 모드면 무조건 건너뛴다.
/// - 편집 중이고 이 칸이 폼을 열 때 이미 비어 있었다면 건너뛴다(정리 상태
///   보존).
/// - 그 외(신규 등록, 또는 편집인데 원래 값이 있었던 칸을 지운 경우)는
///   건너뛰지 않는다 — 강제한다.
bool shouldSkipEmptyRequiredCheck({
  required bool isEditing,
  required bool wasInitiallyEmpty,
  bool relaxAll = relaxRequiredForCleanup,
}) {
  if (relaxAll) return true;
  return isEditing && wasInitiallyEmpty;
}

/// 이름·회사명처럼 형식 검사 없이 "값이 있는지"만 보는 필수 칸의 공통 검증.
String? validateRequiredTextField({
  required String? value,
  required String emptyMessage,
  required bool isEditing,
  required bool wasInitiallyEmpty,
  bool relaxAll = relaxRequiredForCleanup,
}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return shouldSkipEmptyRequiredCheck(
          isEditing: isEditing,
          wasInitiallyEmpty: wasInitiallyEmpty,
          relaxAll: relaxAll,
        )
        ? null
        : emptyMessage;
  }
  return null;
}

/// 이메일 칸 검증 — 필수 여부는 [validateRequiredTextField]와 같은 규칙,
/// 값이 있을 때만 형식(`@`와 `.` 포함)을 본다.
String? validateEmailField({
  required String? value,
  required bool isEditing,
  required bool wasInitiallyEmpty,
  bool relaxAll = relaxRequiredForCleanup,
}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return shouldSkipEmptyRequiredCheck(
          isEditing: isEditing,
          wasInitiallyEmpty: wasInitiallyEmpty,
          relaxAll: relaxAll,
        )
        ? null
        : '이메일을 입력해 주세요.';
  }
  if (!trimmed.contains('@') || !trimmed.contains('.')) {
    return '올바른 이메일 형식을 입력해 주세요.';
  }
  return null;
}

/// 휴대폰 칸 검증(either-or 규칙의 오류 문구는 이 칸에서만 뜬다).
///
/// - 사무실 전화([officeValue])가 있으면 휴대폰은 비어도 통과.
/// - 둘 다 비어 있으면 [wasInitiallyEmpty](편집 시 "둘 다 원래 비어
///   있었는지")·[relaxAll]에 따라 건너뛰거나, "휴대폰 또는 사무실 전화 중
///   하나를 입력해 주세요."를 반환한다.
/// - 휴대폰 값이 있으면 사무실 전화 유무와 무관하게 형식을 검사한다.
String? validateMobilePhoneField({
  required String? mobileValue,
  required String? officeValue,
  required bool isEditing,
  required bool wasInitiallyEmpty,
  bool relaxAll = relaxRequiredForCleanup,
}) {
  final mobile = mobileValue?.trim() ?? '';
  final office = officeValue?.trim() ?? '';
  if (mobile.isEmpty) {
    if (office.isNotEmpty) return null;
    return shouldSkipEmptyRequiredCheck(
          isEditing: isEditing,
          wasInitiallyEmpty: wasInitiallyEmpty,
          relaxAll: relaxAll,
        )
        ? null
        : '휴대폰 또는 사무실 전화 중 하나를 입력해 주세요.';
  }
  if (!koreanPhoneRegExp.hasMatch(mobile)) {
    return '올바른 전화번호 형식(예: 010-1234-5678)으로 입력해 주세요.';
  }
  return null;
}

/// 사무실 전화 칸 검증 — either-or의 "비어 있음" 오류는 휴대폰 칸에서만
/// 보여준다(스펙). 이 칸은 값이 있을 때 형식만 본다.
String? validateOfficePhoneField(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  if (!koreanPhoneRegExp.hasMatch(trimmed)) {
    return '올바른 전화번호 형식(예: 02-123-4567)으로 입력해 주세요.';
  }
  return null;
}

/// "전화를 걸 때 무엇을 할 것인가" 판정.
///
/// 2026-08-26에 `presentation/common/call_picker_sheet.dart`의 시트 함수
/// 안에서 **한 줄도 고치지 않고** 떼어냈다(추가 505).
///
/// ## 왜 뗐나
///
/// 이건 화면이 아니라 **규칙**인데 화면 코드 안에 있어서 자동 테스트가
/// 없었다. `card_form_validation.dart`를 왜 위젯 밖으로 뺐는지와 같은
/// 이유다 — 화면을 띄우지 않고도 규칙 자체를 확인할 수 있어야 한다.
///
/// 🚨 특히 이 판정에는 **한 번 터진 자국**이 있다. 예전에는 휴대폰 번호가
/// 반드시 있다고 보고 "사무실 번호가 있으면 시트, 없으면 휴대폰으로 바로
/// 걸기"로만 나눴다. 그래서 **사무실 번호만 있는 인맥은 전화를 걸 수
/// 없었다** — 빈 번호로 `tel:`을 열어 아무 일도 일어나지 않았다.
/// 2026-08-10에 두 번호를 대칭으로 다루도록 고쳤는데, **테스트가 없으니 그
/// 수정이 지금도 지켜지는지 아무도 모르는 상태**였다. 옮기는 김에 박는다.
///
/// ## 규칙 (2026-08-10 동작 그대로)
///
/// ```
/// 둘 다 없음      아무것도 안 한다        none
/// 휴대폰만        바로 건다                single(휴대폰)
/// 사무실만        바로 건다                single(사무실)
/// 둘 다 있음      어느 쪽인지 고르게 한다   choose
/// ```
///
/// ⚠️ 공백만 든 값은 **없는 것으로 친다.** 빈 번호로 `tel:`을 여는 것이
/// 위 사고의 증상이었다.
///
/// 📌 이메일은 여기 안 들어온다. 2026-08-26에 폼의 "연락 수단"이 셋(휴대폰·
/// 사무실 전화·이메일)으로 넓어졌지만(추가 499 계열), **전화 걸기는 여전히
/// 전화번호만 본다.** 이메일로는 전화를 걸 수 없다.
library;

/// 무엇을 할지.
enum CallTargetKind {
  /// 걸 번호가 없다 — 아무것도 하지 않는다.
  none,

  /// 번호가 하나뿐이다 — 고르게 하지 않고 바로 건다.
  single,

  /// 둘 다 있다 — 어느 쪽으로 걸지 고르게 한다.
  choose,
}

/// [resolveCallTarget]의 결과.
class CallTarget {
  const CallTarget._(this.kind, this.number);

  final CallTargetKind kind;

  /// [CallTargetKind.single]일 때 걸 번호(앞뒤 공백 제거됨). 그 외에는 null.
  final String? number;

  static const CallTarget none = CallTarget._(CallTargetKind.none, null);
  static const CallTarget choose = CallTarget._(CallTargetKind.choose, null);

  factory CallTarget.single(String number) =>
      CallTarget._(CallTargetKind.single, number);

  @override
  bool operator ==(Object other) =>
      other is CallTarget && other.kind == kind && other.number == number;

  @override
  int get hashCode => Object.hash(kind, number);

  @override
  String toString() => 'CallTarget(${kind.name}, $number)';
}

/// 휴대폰·사무실 전화를 보고 무엇을 할지 정한다.
///
/// 두 번호를 **대칭으로** 다룬다 — 어느 쪽이든 하나만 있으면 바로 건다.
CallTarget resolveCallTarget({String? mobile, String? officePhone}) {
  final m = mobile?.trim() ?? '';
  final o = officePhone?.trim() ?? '';
  if (m.isEmpty && o.isEmpty) return CallTarget.none;
  if (o.isEmpty) return CallTarget.single(m);
  if (m.isEmpty) return CallTarget.single(o);
  return CallTarget.choose;
}

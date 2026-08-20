/// 명함 카메라 화면의 촬영 모드(추가 — 테스터 B 요청).
///
/// 기존 설계(안정성 감지 기반 **자동 촬영**)는 그대로 기본값으로 둔다 —
/// "촬영 버튼을 직접 눌러야 찍히게 해 달라"는 요청에 맞춰 **수동을 공존
/// 옵션으로 추가**하는 것이지, 자동 촬영 자체를 없애는 것이 아니다(사용자
/// 확정 사항).
enum CameraCaptureMode {
  /// 명함이 가이드 안에서 멈추면 자동으로 찍는다(기존 동작, 기본값).
  auto,

  /// 사용자가 셔터 버튼을 눌러야만 찍는다.
  manual,
}

extension CameraCaptureModeToggle on CameraCaptureMode {
  /// 다음 모드로 전환한다(자동↔수동 두 값뿐이라 토글이면 충분하다).
  CameraCaptureMode get toggled =>
      this == CameraCaptureMode.auto
          ? CameraCaptureMode.manual
          : CameraCaptureMode.auto;

  bool get isManual => this == CameraCaptureMode.manual;
  bool get isAuto => this == CameraCaptureMode.auto;
}

/// 지금 이 순간(흔들림 없이 멈춘 상태)에 **자동 촬영을 실제로 트리거해도
/// 되는가**.
///
/// ⚠️ 이 하나의 분기가 A(자동/수동 전환) 기능의 핵심이다 — 나머지는 전부
/// 기존 안정성 감지 로직(대비·톤·테두리 검출)을 그대로 두고, **수동
/// 모드에서만 마지막 트리거를 끈다.** 안정성 판정 자체(화면에 "고정됨"
/// 표시)는 두 모드 모두에서 계속 계산해도 무방하다 — 수동 모드에서는
/// "명함이 잘 놓였는지"를 보여주는 안내로만 쓰이고, 실제 촬영은 이
/// 함수가 false를 돌려주는 한 일어나지 않는다.
bool shouldTriggerAutoCapture({
  required CameraCaptureMode mode,
  required bool stabilityConditionMet,
}) => mode.isAuto && stabilityConditionMet;

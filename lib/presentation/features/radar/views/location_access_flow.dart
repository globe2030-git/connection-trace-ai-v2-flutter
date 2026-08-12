import 'package:flutter/material.dart';
import '../view_models/radar_view_model.dart';
import 'location_consent_sheet.dart';

/// 이 흐름이 지금 진행 중인지. **연속 탭 방어용**(테스터 피드백, 2026-08-12).
///
/// 지도 카드·위치 버튼을 빠르게 여러 번 누르면 매 탭마다 동의 시트가 새로
/// 열리거나 OS 설정이 거듭 호출돼, 화면이 시트로 겹겹이 덮여 "앱이 멈췄다"고
/// 느껴졌다(사용자가 강제종료함). GPS 요청 자체는 `_resolveLocationAccess`가
/// 이미 단일화하고 있었지만 **시트·설정 열기 같은 UI 경로는 무방비**였다.
/// 화면 단위가 아니라 흐름 단위로 막아야 해서 파일 스코프에 둔다 — 레이더와
/// 설정 화면이 같은 흐름을 공유하므로 어느 쪽에서 눌러도 하나만 열린다.
bool _actionInProgress = false;

/// 테스트 전용 초기화. 이 가드는 흐름 단위(파일 스코프)라 위젯을 새로 띄워도
/// 남아 있다 — 앞 테스트가 시트를 연 채 끝나면 다음 테스트까지 잠긴다.
/// 실사용에서는 시트가 닫히거나 예외가 나면 `finally`가 풀어 주므로 필요 없다.
@visibleForTesting
void resetLocationAccessActionGuard() {
  _actionInProgress = false;
}

/// 레이더와 설정에서 동일하게 사용하는 위치 접근 복구 흐름.
///
/// UI는 상태에 맞는 행동 하나만 요청하고, OS 권한·기기 설정·앱 자체 동의의
/// 순서는 이 함수에서 일관되게 유지한다.
///
/// 이미 진행 중이면 **아무 일도 하지 않는다**(연속 탭 방어).
Future<void> handleLocationAccessAction(
  BuildContext context,
  RadarViewModel viewModel, {
  bool openSettingsWhenReady = false,
}) async {
  if (_actionInProgress) return;
  _actionInProgress = true;
  try {
    await _handleLocationAccessAction(
      context,
      viewModel,
      openSettingsWhenReady: openSettingsWhenReady,
    );
  } finally {
    // 예외가 나도 반드시 풀어 준다 — 안 그러면 이후 탭이 영영 먹지 않는다.
    _actionInProgress = false;
  }
}

Future<void> _handleLocationAccessAction(
  BuildContext context,
  RadarViewModel viewModel, {
  required bool openSettingsWhenReady,
}) async {
  switch (viewModel.locationAccessState) {
    case LocationAccessState.loading:
    case LocationAccessState.locating:
      return;
    case LocationAccessState.consentRequired:
    case LocationAccessState.consentDeclined:
      final accepted = await showLocationConsentSheet(context);
      if (accepted == true) {
        await viewModel.acceptLocationConsent();
      } else if (accepted == false) {
        await viewModel.declineLocationConsent();
      }
    case LocationAccessState.permissionDenied:
      await viewModel.requestLocationPermission();
    case LocationAccessState.permissionDeniedForever:
    case LocationAccessState.serviceDisabled:
      await viewModel.openRelevantLocationSettings();
    case LocationAccessState.ready:
      if (openSettingsWhenReady) {
        await viewModel.openRelevantLocationSettings();
      } else {
        await viewModel.refreshLocation();
      }
    case LocationAccessState.unavailable:
      await viewModel.refreshLocation();
  }
}

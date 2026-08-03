import 'package:flutter/material.dart';
import '../view_models/radar_view_model.dart';
import 'location_consent_sheet.dart';

/// 레이더와 설정에서 동일하게 사용하는 위치 접근 복구 흐름.
///
/// UI는 상태에 맞는 행동 하나만 요청하고, OS 권한·기기 설정·앱 자체 동의의
/// 순서는 이 함수에서 일관되게 유지한다.
Future<void> handleLocationAccessAction(
  BuildContext context,
  RadarViewModel viewModel, {
  bool openSettingsWhenReady = false,
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

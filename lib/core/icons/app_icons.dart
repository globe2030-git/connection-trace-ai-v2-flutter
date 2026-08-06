import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 2026-08-05 Claude Design 아이콘 시스템 핸드오프의 38종 커스텀 SVG 아이콘.
///
/// 각 아이콘은 24×24 격자, 선 굵기 1.25px로 assets/icons/{id}.svg에 저장돼
/// 있다. 강조 요소는 브랜드 블루(#2563EB)로 SVG 파일 안에 고정돼 있고, 기본
/// 색만 `currentColor`로 남겨뒀다 — [AppIcon]이 [SvgTheme.currentColor]로
/// 그 부분만 치환하므로 다크 배경에서도 강조색은 그대로 유지된다.
enum AppIconId {
  // 주요 항목 (탭바)
  nearbyPeople('nearby-people'),
  aiBriefing('ai-briefing'),
  cardWallet('card-wallet'),
  settings('settings'),

  // 기능 아이콘 (메뉴 · 설정)
  talkPoints('talk-points'),
  recentContact('recent-contact'),
  memo('memo'),
  callCheck('call-check'),
  emailLink('email-link'),
  logout('logout'),
  accountDelete('account-delete'),
  cancelService('cancel-service'),
  radarDetect('radar-detect'),
  detectRadius('detect-radius'),
  locationInfo('location-info'),
  consentRevoke('consent-revoke'),
  cardData('card-data'),
  aiChip('ai-chip'),
  aiDataInfo('ai-data-info'),

  // 기능성 아이콘 (액션 · 도구)
  scanCard('scan-card'),
  addCard('add-card'),
  editCard('edit-card'),
  share('share'),
  saveDownload('save-download'),
  call('call'),
  message('message'),
  mailSend('mail-send'),
  chatSend('chat-send'),

  // 상태 / 기타
  pinActive('pin-active'),
  pinInactive('pin-inactive'),
  connecting('connecting'),
  aiProcessing('ai-processing'),
  sync('sync'),
  notification('notification'),
  favorite('favorite'),
  more('more'),
  back('back'),

  // 브랜드
  appIconMark('app-icon'),

  // 2026-08-06 추가 — 공식 38종 핸드오프에 없어 같은 그리드(24×24·1.25px·
  // currentColor+#2563EB 강조) 규칙으로 직접 제작한 보충 아이콘.
  qrScan('qr-scan'),
  galleryUpload('gallery-upload');

  const AppIconId(this.assetId);

  final String assetId;

  String get assetPath => 'assets/icons/$assetId.svg';
}

/// [Icon]을 대체하는 커스텀 SVG 아이콘 위젯. `color`를 넘기지 않으면
/// 주변 [IconTheme]의 색을 따른다 — 기존 `Icon(Icons.xxx)` 호출부와 동일한
/// 방식으로 바꿔 끼울 수 있다.
class AppIcon extends StatelessWidget {
  const AppIcon(this.id, {super.key, this.size = 24, this.color});

  final AppIconId id;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return SvgPicture.asset(
      id.assetPath,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: resolvedColor),
    );
  }
}

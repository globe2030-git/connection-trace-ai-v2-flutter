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
  nearbyPeople('nb_people'),
  aiBriefing('ai_brief'),
  cardWallet('wl_wallet'),
  settings('st_gear'),

  // 기능 아이콘 (메뉴 · 설정)
  talkPoints('ai_talkpts'),
  recentContact('co_recent'),
  memo('co_memo'),
  callCheck('co_callchk'),
  emailLink('co_maillink'),
  logout('st_logout'),
  accountDelete('st_acctdel'),
  cancelService('st_cancel'),
  radarDetect('nb_radar'),
  detectRadius('nb_radius'),
  locationInfo('st_locinfo'),
  consentRevoke('st_revoke'),
  cardData('st_carddata'),
  aiChip('ai_chip'),
  aiDataInfo('ai_datainfo'),

  // 기능성 아이콘 (액션 · 도구)
  scanCard('sc_scan'),
  addCard('wl_add'),
  editCard('wl_edit'),
  share('cm_share'),
  saveDownload('cm_save'),
  call('co_call'),
  message('co_msg'),
  mailSend('co_mailsend'),
  chatSend('co_chatsend'),

  // 상태 / 기타
  pinActive('nb_pin_on'),
  pinInactive('nb_pin_off'),
  connecting('cm_connect'),
  aiProcessing('ai_proc'),
  sync('cm_sync'),
  notification('cm_notify'),
  favorite('wl_fav'),
  more('cm_more'),
  back('cm_back'),

  // 브랜드
  appIconMark('br_mark'),

  // 2026-08-06 추가 — 공식 38종 핸드오프에 없어 같은 그리드(24×24·1.25px·
  // currentColor+#2563EB 강조) 규칙으로 직접 제작한 보충 아이콘.
  qrScan('pf_qr'),
  galleryUpload('sc_gallery');

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

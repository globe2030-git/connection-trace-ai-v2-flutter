import 'package:flutter/material.dart';

/// AppColors - 앱 전역 디자인 컬러 토큰
///
/// 2026-08 확정 리디자인: 밝은 화이트 배경 + 브랜드 블루 + 둥근 카드 체계.
/// (2026-08-09, P2-8) 예전엔 다크 테마 시절 이름(bgDarkSlate/cardDark 등)을
/// 값만 라이트로 바꿔 유지했는데, 이름과 실제 값(흰색 계열)이 반대라 오해를
/// 낳아 의미 기반 이름으로 정리했다: bgBase(페이지 배경) / bgElevated(떠 있는
/// 표면) / cardSurface(카드) / borderSubtle(옅은 경계).
///
/// 2026-08-05: Claude Design 아이콘 시스템 핸드오프에 맞춰 액센트를
/// 퍼플(#6C5CE7)에서 브랜드 블루(#2563EB)로 교체.
///
/// 향후 디자인이나 색상이 변경될 때 이 파일의 토큰만 수정하면 앱 전체에 즉시 반영됩니다.
class AppColors {
  // 배경/서피스
  static const Color bgBase = Color(0xFFF7F8FA);
  static const Color bgElevated = Color(0xFFFFFFFF);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color borderSubtle = Color(0xFFE8EBF0);
  static const Color borderFunctional = Color(0xFFDDE2EA);
  // 카드에 얹는 옅은 그림자. 여러 카드가 각자 다른 값을 하드코딩하지 않도록
  // 한 곳에 모은다(P1-11). ARGB의 앞 2자리(0A)가 불투명도(≈4%)다.
  static const Color cardShadow = Color(0x0A111827);

  // 텍스트 — 같은 뉴트럴 스케일 안에서 명도 단계만 다름
  static const Color textPrimary = Color(0xFF171A21);
  static const Color textSecondary = Color(0xFF5F6673);
  static const Color textMuted = Color(0xFF7B8391);

  // 브랜드 액센트 — 아이콘 시스템 핸드오프의 브랜드 블루,
  // 선택 배경은 아주 옅은 스카이블루
  static const Color accent = Color(0xFF2563EB);
  static const Color accentText = Color(0xFF1D4ED8);
  static const Color accentSoft = Color(0xFFE8F0FE);
  // accentSoft를 accent 쪽으로 10% 블렌드한 톤 — 원형 아이콘 배경처럼 좀 더
  // 존재감이 필요한 자리에 쓴다(2026-08-06, 헤더 아이콘 배경 피드백).
  static const Color accentSoftStrong = Color(0xFFD5E2FC);

  // 상태색 — 장식이 아니라 의미가 있는 최소한의 예외(에러/삭제)
  static const Color destructive = Color(0xFFEF4444);

  // 소통 채널 범례색 — 통화/문자/이메일/카카오톡을 목록에서 한눈에 구분하기 위한
  // 카테고리 색상. 브랜드 액센트(2색 원칙)와는 별개의 기능적 예외다(차트 범례와 동일한 성격).
  static const Color channelCall = Color(0xFF38BDF8);
  static const Color channelSms = Color(0xFF84CC16);
  static const Color channelEmail = Color(0xFFF59E0B);
  static const Color channelKakao = Color(0xFFFEE500); // 카카오 공식 브랜드 옐로우

  // 검색 캡슐 바 — 카드 표면과 동일 톤으로 통일(기존엔 흰색 단독 라이트 아일랜드였음)
  static const Color capsuleInputBg = Color(0xFFFFFFFF);
  static const Color capsuleInputText = Color(0xFF171A21);
}

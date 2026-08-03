import 'package:flutter/material.dart';

/// AppColors - 앱 전역 디자인 컬러 토큰
///
/// 2026-08 확정 리디자인: 밝은 화이트 배경 + 브랜드 블루 + 둥근 카드 체계.
/// 기존 이름(bgDark/cardDark)은 광범위한 화면 호환성을 위해 유지하지만 실제
/// 값은 라이트 테마의 의미 토큰으로 바뀌었다.
///
/// 향후 디자인이나 색상이 변경될 때 이 파일의 토큰만 수정하면 앱 전체에 즉시 반영됩니다.
class AppColors {
  // 배경/서피스
  static const Color bgDarkSlate = Color(0xFFF7F8FA);
  static const Color bgDarkObsidian = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFFFFFFFF);
  static const Color borderDark = Color(0xFFE8EBF0);
  static const Color borderFunctional = Color(0xFFDDE2EA);

  // 텍스트 — 같은 뉴트럴 스케일 안에서 명도 단계만 다름
  static const Color textPrimary = Color(0xFF171A21);
  static const Color textSecondary = Color(0xFF5F6673);
  static const Color textMuted = Color(0xFF7B8391);

  // 브랜드 액센트 — 신뢰감 있는 블루, 선택 배경은 아주 옅은 블루
  static const Color accent = Color(0xFF2F6EDB);
  static const Color accentText = Color(0xFF245FC2);
  static const Color accentSoft = Color(0xFFEAF2FF);

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

import 'package:flutter/material.dart';

/// AppColors - 앱 전역 디자인 컬러 토큰
/// 향후 디자인이나 색상이 변경될 때 이 파일의 토큰만 수정하면 앱 전체에 즉시 반영됩니다.
class AppColors {
  // 프리미엄 다크 슬레이트 & 메탈릭 그래디언트 배경
  static const Color bgDarkSlate = Color(0xFF0F172A);
  static const Color bgDarkObsidian = Color(0xFF0B0F17);
  
  // 카드 및 서피스 컨테이너 (유리질감 글래스모피즘)
  static const Color cardDark = Color(0xFF1E293B);
  static const Color cardDarkSubtle = Color(0xFF172133);
  static const Color borderDark = Color(0xFF334155);

  // 고대비 타이포그래피 텍스트
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // 포인트 강조 스태티스틱 및 상태 액센트
  static const Color accentLime = Color(0xFF84CC16);   // 369km 프로그레스 뱃지 톤
  static const Color accentSky = Color(0xFF38BDF8);    // 레이더 및 GPS 라이브 링
  static const Color accentAmber = Color(0xFFF59E0B);  // 근접 알림 강조
  static const Color accentRed = Color(0xFFEF4444);    // 통화 종결 / 경고

  // 검색 캡슐 바 (고대비 화이트 피치)
  static const Color capsuleInputBg = Color(0xFFFFFFFF);
  static const Color capsuleInputText = Color(0xFF0F172A);

  // 스태그넘 메탈릭 그래디언트
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF111827),
      Color(0xFF0F172A),
      Color(0xFF070A11),
    ],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1E293B),
      Color(0xFF111827),
    ],
  );

  static const LinearGradient primaryBtnGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF38BDF8),
      Color(0xFF0284C7),
    ],
  );
}

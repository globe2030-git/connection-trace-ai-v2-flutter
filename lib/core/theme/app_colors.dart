import 'package:flutter/material.dart';

/// AppColors - 앱 전역 디자인 컬러 토큰
///
/// 2026-08 리디자인: 다크 뉴트럴 1벌 + 브랜드 액센트(#004EA2) 1색으로 정리했다.
/// 이전 버전의 4색 액센트(lime/sky/amber/red)와 배경/카드 그라디언트, 유리질감
/// 그림자는 전부 제거 — flat, 얇은 1px 보더 중심 스타일로 전환.
/// UI/UX 접근성 검토(WCAG 대비 실측) 근거로 액센트를 용도별 2단으로 나눔:
/// 면적이 큰 곳(버튼 fill)엔 `accent`를, 텍스트/아이콘처럼 얇게 얹히는 곳엔
/// 밝게 파생시킨 `accentText`를 쓴다 — 둘 다 같은 브랜드 블루 계열이라
/// "액센트는 논리적으로 1색"이라는 원칙은 유지된다.
///
/// 향후 디자인이나 색상이 변경될 때 이 파일의 토큰만 수정하면 앱 전체에 즉시 반영됩니다.
class AppColors {
  // 배경/서피스 — 단일 다크 뉴트럴 스케일
  static const Color bgDarkSlate = Color(0xFF0B0E14); // 페이지 배경
  static const Color bgDarkObsidian = Color(0xFF0B0E14); // 하단 탭바 등, 배경과 동일 톤(추가 깊이감 없앰)
  static const Color cardDark = Color(0xFF1C212B); // 카드 표면 — 배경보다 밝게 해 경계를 확실히 구분(접근성 검토 반영)
  static const Color borderDark = Color(0xFF262B33); // 장식용 구분선(1px)
  static const Color borderFunctional = Color(0xFF2A2F3A); // 입력 필드 등 기능적 경계(1px)

  // 텍스트 — 같은 뉴트럴 스케일 안에서 명도 단계만 다름
  static const Color textPrimary = Color(0xFFF5F6F7);
  static const Color textSecondary = Color(0xFF8A909B);
  static const Color textMuted = Color(0xFF6B7280);

  // 브랜드 액센트 — #004EA2 하나, 용도별 2단 톤
  static const Color accent = Color(0xFF004EA2); // 버튼 fill·선택 배경(흰 텍스트와 대비 8:1)
  static const Color accentText = Color(0xFF5A90C8); // 아이콘·텍스트·얇은 보더 단독 강조(다크 배경 대비 4.5:1+)

  // 상태색 — 장식이 아니라 의미가 있는 최소한의 예외(에러/삭제)
  static const Color destructive = Color(0xFFEF4444);

  // 소통 채널 범례색 — 통화/문자/이메일/카카오톡을 목록에서 한눈에 구분하기 위한
  // 카테고리 색상. 브랜드 액센트(2색 원칙)와는 별개의 기능적 예외다(차트 범례와 동일한 성격).
  static const Color channelCall = Color(0xFF38BDF8);
  static const Color channelSms = Color(0xFF84CC16);
  static const Color channelEmail = Color(0xFFF59E0B);
  static const Color channelKakao = Color(0xFFFEE500); // 카카오 공식 브랜드 옐로우

  // 검색 캡슐 바 — 카드 표면과 동일 톤으로 통일(기존엔 흰색 단독 라이트 아일랜드였음)
  static const Color capsuleInputBg = Color(0xFF1C212B);
  static const Color capsuleInputText = Color(0xFFF5F6F7);
}

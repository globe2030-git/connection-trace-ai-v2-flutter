import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bgDarkSlate,
      // 2026-08-06: 앱 전체 폰트를 Pretendard로 통일(assets/fonts/, pubspec
      // fonts: 섹션 참고). fontFamily를 최상위에 두면 아래 textTheme의
      // 개별 스타일에도 상속된다.
      fontFamily: 'Pretendard',
      colorScheme: const ColorScheme.light(
        primary: AppColors.accent,
        surface: AppColors.cardDark,
        onSurface: AppColors.textPrimary,
        error: AppColors.destructive,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgDarkSlate,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      textTheme: ThemeData.light().textTheme.copyWith(
        displayLarge: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -1.0,
        ),
        titleLarge: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: AppColors.bgDarkObsidian,
        indicatorColor: AppColors.accentSoft,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.accentText : AppColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? AppColors.accentText : AppColors.textSecondary,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardDark,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
      dividerColor: AppColors.borderDark,
    );
  }
}

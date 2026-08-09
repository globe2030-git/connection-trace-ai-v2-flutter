import 'package:flutter/material.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';

class ActionCircleButton extends StatelessWidget {
  /// 신규 아이콘 시스템(2026-08-05 핸드오프)에 매칭되는 항목이 있으면
  /// [appIcon]을 우선 사용한다. 매칭이 없는 호출부는 계속 [icon](Material)을
  /// 쓴다 — 두 중 하나는 반드시 지정해야 한다.
  final IconData? icon;
  final AppIconId? appIcon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  const ActionCircleButton({
    super.key,
    this.icon,
    this.appIcon,
    required this.label,
    this.onTap,
    this.isActive = false,
  }) : assert(
         icon != null || appIcon != null,
         'icon 또는 appIcon 중 하나는 지정해야 합니다',
       );

  @override
  Widget build(BuildContext context) {
    final iconColor = onTap == null
        ? AppColors.textMuted
        : isActive
        ? AppColors.accentText
        : AppColors.textPrimary;
    final iconWidget = appIcon != null
        ? AppIcon(appIcon!, size: 26, color: iconColor)
        : Icon(icon, color: iconColor, size: 26);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: onTap == null
                ? AppColors.bgBase
                : isActive
                ? AppColors.accentSoft
                : AppColors.cardSurface,
            shape: CircleBorder(
              side: BorderSide(
                color: onTap == null
                    ? AppColors.borderSubtle
                    : isActive
                    ? AppColors.accent
                    : AppColors.borderSubtle,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(width: 56, height: 56, child: iconWidget),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: onTap == null
                  ? AppColors.textMuted
                  : isActive
                  ? AppColors.accentText
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

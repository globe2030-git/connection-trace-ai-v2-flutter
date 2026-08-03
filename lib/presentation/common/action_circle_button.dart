import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class ActionCircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isActive;

  const ActionCircleButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: onTap == null
                ? AppColors.bgDarkSlate
                : isActive
                ? AppColors.accentSoft
                : AppColors.cardDark,
            shape: CircleBorder(
              side: BorderSide(
                color: onTap == null
                    ? AppColors.borderDark
                    : isActive
                    ? AppColors.accent
                    : AppColors.borderDark,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  icon,
                  color: onTap == null
                      ? AppColors.textMuted
                      : isActive
                      ? AppColors.accentText
                      : AppColors.textPrimary,
                  size: 26,
                ),
              ),
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

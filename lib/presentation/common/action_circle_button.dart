import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class ActionCircleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const ActionCircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? AppColors.accentSky.withOpacity(0.2)
                  : AppColors.cardDark.withOpacity(0.9),
              border: Border.all(
                color: isActive ? AppColors.accentSky : AppColors.borderDark,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isActive
                      ? AppColors.accentSky.withOpacity(0.3)
                      : Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Icon(
              icon,
              color: isActive ? AppColors.accentSky : AppColors.textPrimary,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          )
        ],
      ),
    );
  }
}

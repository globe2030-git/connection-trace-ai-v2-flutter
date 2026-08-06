import 'dart:io';

import 'package:flutter/material.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';

/// 인맥 아바타 — 사용자가 실제로 촬영/선택한 사진 파일이 있으면 그 사진을,
/// 없으면 이름 첫 글자로 된 원형 이니셜을 보여준다.
///
/// [photoPath]는 로컬 파일 경로다(원격 URL이 아님 — image_picker로 고른
/// 사진을 앱 문서 디렉터리에 복사해 영구 보관하는 방식). 예전에는 실제
/// 사진이 아닌 Unsplash 스톡 사진 4장을 프리셋으로 돌려 보여주는 가짜
/// 구현이었는데, 실제 인맥의 사진처럼 보이는 게 문제라 진짜 사진 선택
/// 기능으로 교체했다.
class ContactAvatar extends StatelessWidget {
  final String? photoPath;
  final String name;
  final double radius;
  // 이름 이니셜 대신 커넥션센스 브랜드 아이콘을 기본값으로 쓸지 여부.
  // "내 명함"처럼 앱을 대표하는 자리에서만 true로 쓴다 — 다른 사람의
  // 명함에 브랜드 아이콘을 쓰면 그 사람을 나타내는 게 아니게 되어 버리므로
  // 일반 인맥 아바타는 계속 이니셜을 쓴다.
  final bool useBrandFallback;

  const ContactAvatar({
    super.key,
    required this.photoPath,
    required this.name,
    this.radius = 24,
    this.useBrandFallback = false,
  });

  @override
  Widget build(BuildContext context) {
    final path = photoPath;
    final hasPhoto =
        path != null && path.trim().isNotEmpty && File(path).existsSync();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.accentSoft,
      backgroundImage: hasPhoto ? FileImage(File(path)) : null,
      child: hasPhoto
          ? null
          : (useBrandFallback && name.trim().isEmpty)
          ? AppIcon(
              AppIconId.appIconMark,
              size: radius * 1.1,
              color: AppColors.accentText,
            )
          : Text(
              name.trim().isEmpty ? '?' : name.trim().substring(0, 1),
              style: TextStyle(
                fontSize: radius * 0.62,
                fontWeight: FontWeight.bold,
                color: AppColors.accentText,
              ),
            ),
    );
  }
}

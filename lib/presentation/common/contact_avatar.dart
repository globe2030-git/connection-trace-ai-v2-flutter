import 'dart:io';

import 'package:flutter/material.dart';
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

  const ContactAvatar({
    super.key,
    required this.photoPath,
    required this.name,
    this.radius = 24,
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

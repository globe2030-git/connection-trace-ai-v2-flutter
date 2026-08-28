import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../core/icons/app_icons.dart';
import '../../core/services/contact_image_service.dart';
import '../../core/theme/app_colors.dart';

/// 인맥 아바타 — 우선순위: ① (선택 시) 암호화된 명함 이미지 → ② 사용자가 고른
/// 프로필 사진([photoPath]) → ③ 이름 첫 글자 이니셜.
///
/// [photoPath]는 로컬 파일 경로다(원격 URL이 아님 — image_picker로 고른
/// 사진을 앱 문서 디렉터리에 복사해 영구 보관하는 방식). 예전에는 실제
/// 사진이 아닌 Unsplash 스톡 사진 4장을 프리셋으로 돌려 보여주는 가짜
/// 구현이었는데, 실제 인맥의 사진처럼 보이는 게 문제라 진짜 사진 선택
/// 기능으로 교체했다.
///
/// [cardImagePath]+[uid]가 모두 주어지면(=사용자가 "명함을 대표 이미지로"
/// 선택) 그 **암호화된 명함 이미지**를 복호화해 아바타로 쓴다(추가 133).
/// 복호화 전/실패 시에는 위 ②③으로 자연스럽게 폴백한다.
class ContactAvatar extends StatefulWidget {
  final String? photoPath;
  final String name;
  final double radius;
  // 이름 이니셜 대신 커넥션센스 브랜드 아이콘을 기본값으로 쓸지 여부.
  // "내 명함"처럼 앱을 대표하는 자리에서만 true로 쓴다 — 다른 사람의
  // 명함에 브랜드 아이콘을 쓰면 그 사람을 나타내는 게 아니게 되어 버리므로
  // 일반 인맥 아바타는 계속 이니셜을 쓴다.
  final bool useBrandFallback;
  // 암호화된 명함 이미지를 아바타로 쓸 때만 둘 다 넣는다(호출자가 useCardAsAvatar를
  // 판단해 전달). 둘 중 하나라도 없으면 명함 이미지는 시도하지 않는다.
  final String? cardImagePath;
  final String? uid;

  /// 명함 id — 있으면 **저장된 경로보다 이것으로 만든 정본 경로를 먼저**
  /// 본다(2026-08-28, 추가 559). 저장된 경로는 저장하던 순간의 절대경로라
  /// iOS에서는 앱을 다시 깔면 틀린 값이 된다(추가 554).
  final String? contactId;

  const ContactAvatar({
    super.key,
    required this.photoPath,
    required this.name,
    this.radius = 24,
    this.useBrandFallback = false,
    this.cardImagePath,
    this.uid,
    this.contactId,
  });

  @override
  State<ContactAvatar> createState() => _ContactAvatarState();
}

class _ContactAvatarState extends State<ContactAvatar> {
  // 복호화 결과를 State에 들고 있어 위젯이 리빌드돼도 매번 다시 복호화하지
  // 않는다(경로/uid가 바뀔 때만 다시 로드).
  Future<Uint8List?>? _cardBytes;

  @override
  void initState() {
    super.initState();
    _maybeLoadCard();
  }

  @override
  void didUpdateWidget(covariant ContactAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardImagePath != widget.cardImagePath ||
        oldWidget.uid != widget.uid ||
        oldWidget.contactId != widget.contactId) {
      _maybeLoadCard();
    }
  }

  void _maybeLoadCard() {
    final path = widget.cardImagePath;
    final uid = widget.uid;
    _cardBytes = (path != null && uid != null)
        ? ContactImageService().loadDecryptedCardImage(
            uid: uid,
            path: path,
            contactId: widget.contactId,
          )
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final future = _cardBytes;
    if (future == null) return _fallbackAvatar();

    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return _fallbackAvatar();
        return CircleAvatar(
          radius: widget.radius,
          backgroundColor: AppColors.accentSoft,
          backgroundImage: MemoryImage(bytes),
        );
      },
    );
  }

  /// 명함 이미지가 없거나 아직/실패했을 때: 프로필 사진 → 이니셜.
  Widget _fallbackAvatar() {
    final path = widget.photoPath;
    final hasPhoto =
        path != null && path.trim().isNotEmpty && File(path).existsSync();
    final name = widget.name;
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: AppColors.accentSoft,
      backgroundImage: hasPhoto ? FileImage(File(path)) : null,
      child: hasPhoto
          ? null
          : (widget.useBrandFallback && name.trim().isEmpty)
          ? AppIcon(
              AppIconId.appIconMark,
              size: widget.radius * 1.1,
              color: AppColors.accentText,
            )
          : Text(
              name.trim().isEmpty ? '?' : name.trim().substring(0, 1),
              style: TextStyle(
                fontSize: widget.radius * 0.62,
                fontWeight: FontWeight.bold,
                color: AppColors.accentText,
              ),
            ),
    );
  }
}

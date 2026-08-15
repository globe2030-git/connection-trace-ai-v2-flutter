import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 같은 주소에 여러 명이 있을 때 그 위에 붙는 머리글(F-15).
///
/// 사용자가 알고 싶은 것은 *"이 건물에 3명 있다"*이다. 아래 줄들이 한 덩어리
/// 임을 보이려고 배경을 옅게 깔고, 주소는 한 줄로 자른다 — 도로명 주소는
/// 길어서 두 줄로 넘어가면 목록의 리듬이 깨진다.
class SameAddressGroupHeader extends StatelessWidget {
  const SameAddressGroupHeader({
    super.key,
    required this.address,
    required this.count,
  });

  final String address;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: '$address에 $count명',
      // 아래 Text들을 스크린리더에서 제외한다. 없으면 "테헤란로 123에 2명"을
      // 읽은 뒤 "테헤란로 123", "2명"을 **다시** 읽는다(위젯 테스트에서 발견).
      // 눈으로 보는 사람에게는 한 줄이지만 듣는 사람에게는 세 번이 된다.
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.apartment_outlined,
              size: 15,
              color: AppColors.accentText,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count명',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.accentText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

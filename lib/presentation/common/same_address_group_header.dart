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

/// 같은 주소 묶음(F-15)에 **속한 카드들을 감싸는 블록**.
///
/// ## 왜 필요한가 — 머리글만으로는 묶음이 "닫히지" 않는다
///
/// 처음에는 [SameAddressGroupHeader]만 붙이고 카드를 그 아래에 그대로
/// 이어 붙였다. 그랬더니 **묶음이 어디서 끝나는지 화면에서 알 수 없었다.**
/// 머리글 아래로 낱개 카드가 계속 이어지면, 보는 사람은 그것까지 묶음에
/// 속한다고 읽는다. 실기기 확인에서 *"2명"* 머리글 밑에 **5장이 이어져
/// 보였다**(2026-08-18, 추가 313).
///
/// 안팎을 가르는 단서가 하나 있기는 했다 — 묶음 안에서는 주소 줄을 그리지
/// 않는다(`showAddress: !group.isGrouped`). 그러나 **그 규칙을 아는 사람만
/// 읽을 수 있는 단서**다. 화면은 규칙을 모르는 사람에게도 말해야 한다.
///
/// ## 무엇으로 닫나 — 들여쓰기 + 왼쪽 세로선
///
/// 카드로 한 번 더 감싸는 방법도 있었지만, 이 목록은 이미 카드 리듬이라
/// **카드 안에 카드**가 생겨 겹쳐 보인다. 끝에 구분선만 넣는 방법은 "여기서
/// 끝"을 약하게만 말한다. **들여쓰기는 "이건 저 머리글에 속한다"를 한눈에
/// 말하고**, 세로선이 그 범위를 눈으로 잇는다.
///
/// 세로선을 카드마다 따로 그리지 않고 **블록 하나로 감싸는 이유**: 카드에는
/// 아래 여백(8)이 있어서, 카드마다 그리면 선이 토막토막 끊긴다.
class SameAddressGroupBody extends StatelessWidget {
  const SameAddressGroupBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 왼쪽만 띄운다. 오른쪽까지 좁히면 묶음 안 카드만 폭이 달라져
      // 목록 전체가 들쭉날쭉해 보인다.
      padding: const EdgeInsets.only(left: 10),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.accentSoftStrong, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

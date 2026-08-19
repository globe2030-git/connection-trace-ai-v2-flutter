import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/phone_call_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/contact_avatar.dart';
import 'add_card_modal_view.dart';

/// 명함 **상세 보기** — 읽는 화면이다(2026-08-19 사용자 확정, 추가 330).
///
/// ## 왜 만들었나
///
/// 예전에는 목록에서 명함을 누르면 **곧장 편집 폼**이 떴다. 그런데 명함을 여는
/// 이유는 대개 *"연락하려고"*다 — 읽으려는 사람에게 **입력 화면을 준 셈**이고,
/// 값을 실수로 건드릴 위험도 있었다.
///
/// 사용자 지적: *"명함 리스트에서 좀 더 세부적인 자료(연락처 중심, 전화번호·
/// 이메일 등)를 보려고 하는데 편집으로 바로 뜨니까 불편하다."*
///
/// ```
/// 전   목록 탭 → 편집 폼(전체 칸, 입력 가능)
/// 후   목록 탭 → 이 화면(읽기 전용) → [편집] → 편집 폼
/// ```
///
/// ## 무엇을 담나 — **여섯 개만** (2026-08-19 개정, 추가 332)
///
/// ```
/// 이름 · 직함 · 부서 · 회사      머리글 한 덩어리
/// 휴대폰 · 사무실 전화            연락처
/// ```
///
/// ⚠️ **처음엔 전 칸(이메일·주소·팩스·메모)을 다 그렸다가 뺐다.** 실기기에서
/// *"자료가 많으면 이름이 위로 너무 붙어 있다"*는 제보가 왔다 — 줄이 길어지자
/// 머리글이 화면 꼭대기로 밀려 답답했다. 여백만 넓히는 길도 있었으나, 사용자가
/// **담는 것 자체를 줄이는 쪽**을 골랐다: *"…만 통일해서 보여주고 편집을
/// 클릭하면 전체를 보여주는 것으로."*
///
/// 그래서 이 화면은 **스크롤이 거의 나지 않는다** — 길이가 명함마다 들쭉날쭉
/// 하지 않고, 여는 목적(연락)에 필요한 것만 있다. 나머지는 [편집]에 있다.
///
/// ⚠️ **빈 칸은 그리지 않는다.** 이 저장소는 화면을 채우려고 없는 값을 만들지
/// 않는다(CLAUDE.md 4절). 값이 없으면 그 줄 자체가 없다.
class ContactDetailView extends StatelessWidget {
  const ContactDetailView({super.key, required this.contact});

  final ContactModel contact;

  /// 목록에서 이 화면을 연다. 편집과 같은 방식(바텀시트)으로 띄워, 목록에서
  /// 화면이 튀어 오르는 결이 예전과 같게 한다.
  static Future<void> show(BuildContext context, ContactModel contact) {
    final topInset = MediaQuery.of(context).padding.top;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height - topInset - 12,
      ),
      builder: (_) => ContactDetailView(contact: contact),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthRepository>().firebaseUid;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 손잡이만 둔다. **닫기·편집은 아래 고정 줄**에 있다.
            //
            // ⚠️ 여기 X를 뒀다가 뺐다(2026-08-19 실기기 제보, 추가 331).
            // 보이기는 하는데 **눌리지 않았다** — 바텀시트 맨 위는 끌어 내리는
            // 제스처가 먹는 자리라 버튼과 다툰다. 사용자 제안대로 **아래로
            // 옮겼다**: 손이 닿는 자리이기도 하고, [편집] 옆이라 짝이 맞는다.
            // ⚠️ 손잡이 아래 여백을 넉넉히 둔다(2026-08-19 실기기 제보, 추가 332).
            // 자료가 많은 명함에서 **이름이 위에 너무 붙어** 답답해 보였다.
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 16),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(context, uid),
                    const SizedBox(height: 18),
                    _actions(context),
                    const SizedBox(height: 8),
                    ..._contactRows(context),
                  ],
                ),
              ),
            ),
            // ⚠️ **아래 고정 줄** — 내용이 아무리 길어도 늘 손이 닿는다.
            //
            // 예전에는 [편집]도 스크롤 안에 있어서 **끝까지 내려야** 나왔다.
            // 닫기가 없던 때 사용자가 [편집]으로 빠져나온 것도 그래서다.
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderSubtle)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        side: const BorderSide(color: AppColors.borderSubtle),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('닫기'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        AddCardModalView.show(context, contact: contact);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('편집'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String? uid) {
    // 이름 아래 한 줄에 직함·부서·회사를 잇는다. 없는 것은 빼고 이으므로
    // `대리 ·  · 회사`처럼 빈 자리가 남지 않는다.
    final line = [
      contact.title.trim(),
      contact.department?.trim() ?? '',
      contact.company.trim(),
    ].where((v) => v.isNotEmpty).join(' · ');

    return Row(
      children: [
        ContactAvatar(
          photoPath: contact.avatarUrl,
          name: contact.name,
          radius: 30,
          cardImagePath: contact.useCardAsAvatar ? contact.cardImagePath : null,
          uid: contact.useCardAsAvatar ? uid : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contact.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              if (line.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  line,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 연락 동작 — **이미 있는 경로를 그대로 부른다.**
  ///
  /// ⚠️ 새로 만들지 않는다. 전화는 목록 타일이 쓰는 것과 **같은 통로**라,
  /// 번호가 여럿일 때 고르게 하는 처리와 소통 이력 기록이 함께 따라온다.
  Widget _actions(BuildContext context) {
    final hasPhone =
        contact.phone.trim().isNotEmpty ||
        (contact.officePhone?.trim().isNotEmpty ?? false);
    if (!hasPhone) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => PhoneCallService.showCallPicker(context, contact),
        icon: const Icon(Icons.call, size: 18),
        label: const Text('전화'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  /// ⚠️ **여기 두 줄이 전부다.** 나머지 칸(직통·팩스·이메일·홈페이지·주소·
  /// 메모)은 [편집]에서 본다 — 2026-08-19 사용자 확정(추가 332).
  List<Widget> _contactRows(BuildContext context) => _section('연락처', [
    _row('휴대폰', contact.phone),
    _row('사무실', contact.officePhone),
  ]);

  /// 값이 하나도 없으면 **제목까지 통째로 뺀다.**
  List<Widget> _section(String title, List<Widget?> rows) {
    final kept = rows.whereType<Widget>().toList();
    if (kept.isEmpty) return const [];
    return [
      const SizedBox(height: 18),
      Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.accentText,
        ),
      ),
      const SizedBox(height: 8),
      ...kept,
    ];
  }

  /// 값이 비면 `null`을 돌려 **줄 자체를 없앤다**(빈 줄을 그리지 않는다).
  Widget? _row(String label, String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            SizedBox(
              width: 62,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

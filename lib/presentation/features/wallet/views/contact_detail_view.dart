import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/phone_call_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/contact_avatar.dart';
import 'add_card_modal_view.dart';

/// 명함 **상세 보기** — 읽는 화면이다(2026-08-19 사용자 확정, 추가 329).
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
/// ## 무엇을 담나 — **연락처 중심**
///
/// 목록 타일에 이미 있는 것(사진·이름·직함·회사)을 그대로 반복하지 않는다.
/// 이 화면의 값은 **목록에서 볼 수 없던 것**이다 — 전화·이메일·주소.
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
            // ⚠️ **닫기 줄은 스크롤 밖에 둔다**(2026-08-19 실기기 제보, 추가 330).
            //
            // 처음에는 손잡이를 스크롤 영역 **안에** 뒀다. 그랬더니 **자료가 많은
            // 명함에서 위로 밀려 사라져**, 닫을 방법이 없었다. 시트가 화면을
            // 거의 다 덮어서 **바깥을 눌러 닫을 자리도 없다.**
            //
            // 📌 사용자는 [편집]으로 들어가 거기 있는 X로 빠져나오고 있었다 —
            // **읽으려고 연 화면을 닫으려고 입력 화면을 거치는** 꼴이었다.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
              child: Row(
                children: [
                  const Spacer(),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        color: AppColors.textMuted,
                        tooltip: '닫기',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(context, uid),
                    const SizedBox(height: 18),
                    _actions(context),
                    const SizedBox(height: 8),
                    ..._contactRows(context),
                    ..._placeRows(context),
                    ..._memoRows(context),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          AddCardModalView.show(context, contact: contact);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('편집'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accentText,
                          side: const BorderSide(color: AppColors.borderSubtle),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
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

  List<Widget> _contactRows(BuildContext context) => _section('연락처', [
    _row('휴대폰', contact.phone),
    _row('사무실', contact.officePhone),
    _row('직통', contact.directPhone),
    _row('팩스', contact.fax),
    _row('이메일', contact.email),
    _row('홈페이지', contact.website),
  ]);

  List<Widget> _placeRows(BuildContext context) => _section('주소', [
    _row('주소', contact.address),
    _row('상세', contact.addressDetail),
    _row('우편번호', contact.postalCode),
  ]);

  List<Widget> _memoRows(BuildContext context) =>
      _section('메모', [_row('', contact.memo)]);

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

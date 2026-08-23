import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/contact_image_service.dart';
import '../../../../core/services/phone_call_service.dart';
import '../../../../core/utils/card_history_note.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../common/card_image_viewer.dart';
import '../../../common/contact_avatar.dart';
import '../view_models/groups_view_model.dart';
import 'add_card_modal_view.dart';
import 'group_assign_sheet.dart';

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
/// ## 무엇을 담나 — **일곱 개만** (2026-08-19 개정, 추가 332)
///
/// ```
/// 이름 · 직함 · 부서 · 회사      머리글 한 덩어리
/// 휴대폰 · 사무실 전화 · 이메일   연락처
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
///
/// ## 연락 동작은 줄마다 아이콘으로 (2026-08-21 사용자 확정, UI 개선 브리프 ⑤)
///
/// 예전엔 화면 위쪽에 큰 파란 "전화" 띠 버튼이 하나 있었다. "화면을 차지하고
/// 부담스럽다"는 제보로 없앴다 — **이 버튼은 전화만 걸었다.** AI 브리핑 같은
/// 다른 진입로는 애초에 이 화면에 없었다(그건 명함 목록 행에 이미 별도
/// 아이콘으로 있다 — `wallet_view.dart`의 `_CompactAction`/`onBriefing`).
/// 대신 값이 있는 연락처 줄마다 그 값으로 할 수 있는 동작(전화·문자·메일)을
/// 오른쪽에 원형 아이콘으로 붙였다 — [contactRowActionKinds]가 무엇을
/// 붙일지 정한다.
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
                    ..._contactRows(context),
                    ..._groupRows(context),
                    ..._historyRows(context),
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
                  // ⚠️ [편집]도 [닫기]와 **같은 무채색 외곽선 스타일**로
                  // 통일했다(2026-08-21, 브리프 ⑤) — 예전엔 파란 강조
                  // 버튼이라 위쪽 "전화" 띠와 함께 파란 덩어리가 두 개
                  // 겹쳐 보였다. 연락 동작은 이제 줄마다 아이콘이 맡으므로
                  // 아래 줄은 이동(닫기·편집) 목적만 남았다 — 둘 다 같은
                  // 무게로 둔다.
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        AddCardModalView.show(context, contact: contact);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('편집'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        side: const BorderSide(color: AppColors.borderSubtle),
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

    // 이 화면의 유일한 이미지 영역 — 명함을 대표 이미지로 쓰기로 했을 때만
    // 아바타가 실제 명함 사진을 보여준다(그 외엔 프로필 사진/이니셜). 그
    // 경우에만 눌러서 크게 볼 수 있게 한다(추가 426) — 이니셜·프로필 사진을
    // 눌러 "명함 뷰어"를 여는 것은 뜻이 안 맞는다.
    final showsCardImage =
        contact.useCardAsAvatar && contact.cardImagePath != null && uid != null;

    return Row(
      children: [
        showsCardImage
            ? _ZoomableCardAvatar(contact: contact, uid: uid)
            : ContactAvatar(
                photoPath: contact.avatarUrl,
                name: contact.name,
                radius: 30,
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

  /// ⚠️ **여기 세 줄이 전부다.** 나머지 칸(직통·팩스·홈페이지·주소·메모)은
  /// [편집]에서 본다 — 2026-08-19 사용자 확정(추가 332).
  ///
  /// 📌 이메일은 **뺐다가 도로 넣었다.** 처음 여섯 칸으로 줄일 때 빠졌는데,
  /// 이 화면을 여는 목적이 원래 *"연락처 중심 — 전화번호·이메일 등"*이었다.
  /// 전화만 남기면 그 목적의 절반이 [편집] 뒤로 숨는다.
  List<Widget> _contactRows(BuildContext context) => _section('연락처', [
    _row(
      '휴대폰',
      contact.phone,
      actions: _actionIconsFor(
        context,
        rowKind: ContactRowKind.mobile,
        value: contact.phone,
      ),
    ),
    _row(
      '사무실',
      contact.officePhone,
      actions: _actionIconsFor(
        context,
        rowKind: ContactRowKind.office,
        value: contact.officePhone,
      ),
    ),
    _row(
      '이메일',
      contact.email,
      actions: _actionIconsFor(
        context,
        rowKind: ContactRowKind.email,
        value: contact.email,
      ),
    ),
  ]);

  /// **그룹** 섹션(추가 427) — 항상 보인다(값이 없어도 진입 버튼 자체가
  /// 동작이라 다른 빈 칸들과 달리 숨기지 않는다).
  ///
  /// ⚠️ [contact] 필드를 직접 쓰지 않고 [_GroupsSection]이 ContactsRepository
  /// 에서 **매 빌드마다 다시 조회**한다 — 이 화면은 StatelessWidget이라
  /// [contact]는 열릴 때의 스냅샷이고, 시트에서 그룹을 바꾼 뒤에도 이 화면이
  /// 다시 그려지려면 최신 값을 봐야 한다.
  List<Widget> _groupRows(BuildContext context) => [
    const SizedBox(height: 18),
    const Text(
      '그룹',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AppColors.accentText,
      ),
    ),
    const SizedBox(height: 8),
    _GroupsSection(contactId: contact.id),
  ];

  /// [contactRowActionKinds]가 정한 종류대로 아이콘 위젯을 만든다.
  ///
  /// 실행은 전부 **이미 있는 launch 경로를 그대로 부른다** — 새 권한·새
  /// 플러그인 없음(2026-08-21 브리프 ⑤ 지시).
  /// - 전화: [PhoneCallService.makeCall] — 목록 행([wallet_view.dart]의
  ///   `onCall`)이 번호가 하나뿐일 때 쓰는 것과 같은 통로다. 여기서는 줄이
  ///   이미 어느 번호인지 정해 주므로, 둘 중 골라야 하는
  ///   [PhoneCallService.showCallPicker] 시트는 쓰지 않는다 — 휴대폰 줄의
  ///   전화 아이콘을 눌렀는데 "휴대폰이냐 사무실이냐" 되묻는 시트가 뜨면
  ///   오히려 헷갈린다.
  /// - 문자·메일: 새로 둔 [PhoneCallService.sendSms]/[PhoneCallService.sendEmail]
  ///   — 브리핑 화면(`briefing_overlay_view.dart`)이 쓰는 것과 같은
  ///   `sms:`/`mailto:` 스킴이다. 다만 여기는 미리 채울 대화 포인트가 없어
  ///   본문 없이 앱만 연다.
  List<Widget> _actionIconsFor(
    BuildContext context, {
    required ContactRowKind rowKind,
    required String? value,
  }) {
    final v = value?.trim() ?? '';
    final kinds = contactRowActionKinds(rowKind: rowKind, value: v);
    final icons = <Widget>[];
    for (final kind in kinds) {
      if (icons.isNotEmpty) icons.add(const SizedBox(width: 4));
      icons.add(switch (kind) {
        ContactActionKind.call => ContactActionIcon(
          icon: Icons.call,
          label: '${contact.name}에게 전화',
          onTap: () => PhoneCallService.makeCall(v),
        ),
        ContactActionKind.sms => ContactActionIcon(
          icon: Icons.sms_outlined,
          label: '문자 보내기',
          onTap: () => _sendSms(context, v),
        ),
        ContactActionKind.email => ContactActionIcon(
          icon: Icons.mail_outline,
          label: '이메일 보내기',
          onTap: () => _sendEmail(context, v),
        ),
      });
    }
    return icons;
  }

  Future<void> _sendSms(BuildContext context, String phoneNumber) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await PhoneCallService.sendSms(phoneNumber);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('문자 앱을 열지 못했어요.'),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  Future<void> _sendEmail(BuildContext context, String email) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await PhoneCallService.sendEmail(email);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('메일 앱을 열지 못했어요.'),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  /// **이전 명함** — 명함이 바뀐 사람의 예전 값들.
  ///
  /// 접혀 있다가 누르면 펼쳐진다. 이력이 없으면 이 묶음 자체가 없다.
  ///
  /// ⚠️ **칸으로 나누어 보여주지 않는다.** 기록이 메모에 한 줄 문자열로 쌓여
  /// 있고, 빈 칸은 통째로 빠져서 **조각 개수가 명함마다 다르다** — 어느 조각이
  /// 어느 칸인지 되살릴 방법이 없다. 추측해 붙이면 **틀린 이력이 그럴듯하게**
  /// 남는다. 그래서 적힌 그대로 보여 준다([CardHistoryNote] 참고).
  List<Widget> _historyRows(BuildContext context) {
    final notes = CardHistoryNote.parse(contact.memo);
    if (notes.isEmpty) return const [];
    return [
      const SizedBox(height: 18),
      Text(
        '이전 명함 ${notes.length}건',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.accentText,
        ),
      ),
      const SizedBox(height: 8),
      ...notes.map((n) => _historyTile(context, n)),
    ];
  }

  /// 이력 한 건. 접힌 채로 나오고 누르면 펼쳐진다.
  ///
  /// `dividerColor`를 지우는 것은 [ExpansionTile]이 펼칠 때 위아래로 긋는
  /// 기본 선을 없애기 위함이다 — 테두리를 이미 그리고 있어서 겹친다.
  Widget _historyTile(BuildContext context, CardHistoryNote note) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderSubtle),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(
              note.date,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            children: [
              SelectableText(
                note.content,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
  /// [actions]도 값이 없을 땐 함께 사라진다 — 애초에 이 메서드 자체가
  /// `null`을 돌리기 때문에 별도 분기가 필요 없다.
  Widget? _row(String label, String? value, {List<Widget> actions = const []}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
          if (actions.isNotEmpty) ...[const SizedBox(width: 8), ...actions],
        ],
      ),
    );
  }
}

/// 연락처 줄이 붙일 수 있는 동작 종류.
enum ContactActionKind { call, sms, email }

/// 어느 연락처 줄인지 — 종류마다 붙는 아이콘이 다르다
/// (2026-08-21 브리프 ⑤: 휴대폰=전화+문자, 사무실=전화, 이메일=메일).
enum ContactRowKind { mobile, office, email }

/// 이 줄에 어떤 동작 아이콘을 붙일지 정한다 — **순수 함수**라 위젯을 그리지
/// 않고도 테스트할 수 있다.
///
/// 값이 없는 줄은 빈 목록을 돌려준다(빈 상태 그대로 보여준다는 원칙,
/// CLAUDE.md 4절 — 가짜 데이터를 만들지 않는다. 값이 없으면 누를 수 있는
/// 동작도 없다).
List<ContactActionKind> contactRowActionKinds({
  required ContactRowKind rowKind,
  required String? value,
}) {
  if ((value ?? '').trim().isEmpty) return const [];
  switch (rowKind) {
    case ContactRowKind.mobile:
      return const [ContactActionKind.call, ContactActionKind.sms];
    case ContactRowKind.office:
      return const [ContactActionKind.call];
    case ContactRowKind.email:
      return const [ContactActionKind.email];
  }
}

/// 연락처 줄 오른쪽에 붙는 동작 아이콘 — 시각 크기 40dp(accentSoft 원형
/// 배경, accentText 아이콘), 터치 영역은 44dp 이상(2026-08-21 브리프 ⑤).
///
/// [IconButton]을 그대로 쓴다 — `tooltip`이 접근성 라벨로도 쓰인다는
/// 프레임워크 기본 동작을 그대로 활용한다(별도 `Semantics` 래핑 불필요).
/// 시각 크기(40)와 터치 영역(44)을 다르게 두는 것은, 아이콘을 눈에 띄게
/// 키우지 않으면서도 손가락으로 누르기엔 충분한 여백을 주기 위함이다.
class ContactActionIcon extends StatelessWidget {
  const ContactActionIcon({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.accentSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: AppColors.accentText),
      ),
    );
  }
}

/// 상세 화면의 "그룹" 줄(추가 427) — 현재 지정된 그룹 칩 + 편집 버튼.
///
/// [ContactsRepository]에서 [contactId]로 매번 다시 찾는다 — 명함이 이미
/// 삭제됐으면(드물지만 방어적으로) 조용히 아무것도 그리지 않는다.
class _GroupsSection extends StatelessWidget {
  const _GroupsSection({required this.contactId});

  final String contactId;

  @override
  Widget build(BuildContext context) {
    final contactsRepo = context.watch<ContactsRepository>();
    final groupsVm = context.watch<GroupsViewModel>();
    final matches = contactsRepo.contacts.where((c) => c.id == contactId);
    if (matches.isEmpty) return const SizedBox.shrink();
    final current = matches.first;
    final myGroupNames = groupsVm.groups
        .where((g) => current.groupIds.contains(g.id))
        .map((g) => g.name)
        .toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: myGroupNames.isEmpty
              ? const Text(
                  '지정된 그룹 없음',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in myGroupNames)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accentText,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        TextButton.icon(
          onPressed: () async {
            final result = await GroupAssignSheet.show(
              context,
              initialSelectedGroupIds: current.groupIds.toSet(),
            );
            if (result == null || !context.mounted) return;
            groupsVm.setContactGroups(current.id, result);
          },
          icon: const Icon(Icons.folder_outlined, size: 16),
          label: const Text('편집'),
        ),
      ],
    );
  }
}

/// 상세 화면의 아바타가 **명함 사진**일 때만 쓰는 래퍼(추가 426) — 누르면
/// [showCardImageViewer]로 크게 연다.
///
/// 화면 자체는 여전히 [ContactAvatar]가 그린다(복호화 캐시 재사용 — 여기서
/// 다시 읽어도 [ContactImageService]가 메모리에 캐시해 둔 값을 그대로 돌려줄
/// 뿐, 새 평문 파일을 만들지 않는다). 이 위젯은 그 위에 "누를 수 있다"는
/// 표시(작은 돋보기 배지)와 탭 핸들러만 얹는다.
class _ZoomableCardAvatar extends StatelessWidget {
  const _ZoomableCardAvatar({required this.contact, required this.uid});

  final ContactModel contact;
  final String uid;

  Future<void> _open(BuildContext context) async {
    final bytes = await ContactImageService().loadDecryptedCardImage(
      uid: uid,
      path: contact.cardImagePath!,
    );
    if (bytes == null || !context.mounted) return;
    await showCardImageViewer(
      context,
      faces: [CardFaceImage(image: MemoryImage(bytes), label: '명함 사진')],
      title: '${contact.name} 님의 명함',
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: Semantics(
        button: true,
        label: '명함 사진 크게 보기',
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            ContactAvatar(
              photoPath: contact.avatarUrl,
              name: contact.name,
              radius: 30,
              cardImagePath: contact.cardImagePath,
              uid: uid,
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.zoom_in, size: 12, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

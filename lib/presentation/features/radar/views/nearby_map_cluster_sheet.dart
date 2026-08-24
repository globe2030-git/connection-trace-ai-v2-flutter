import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/glass_card.dart';
import '../../wallet/views/contact_detail_view.dart';
import '../utils/nearby_map_clusters.dart';
import 'nearby_map_group_sheet.dart';

/// 실제 지도(`nearby_map_view.dart`)에서 **서로 다른 주소의 묶음 마커끼리
/// 화면상 겹쳤을 때** 뜨는 바텀시트(추가 452, 사용자 지시: "누르면 회사를
/// 선택할 수 있게 해주면 편할듯" → "그 회사 사람들만 볼 수 있도록").
///
/// ## 왜 기존 묶음 시트([showNearbyMapGroupSheet])로는 안 되나
///
/// 기존 시트는 **같은 주소**(F-15 규칙) 묶음 하나를 보여주는 구조라 주소
/// 하나만 받는다. 그런데 라벨이 겹치는 건 **서로 다른 주소**의 마커가
/// 화면에서 가까울 때다(추가 445가 라벨 폭을 계산에 안 넣어 생긴 결함,
/// 추가 452) — 주소가 다른 여러 묶음을 한 시트에 모아야 하니 그대로는
/// 못 쓴다. 그래서 **회사로 먼저 고르고, 고른 회사의 사람만 보여주는 두
/// 단계**를 이 파일에 새로 짰다. 다만 **사람 한 명을 보여주는 행 위젯은
/// 새로 만들지 않고** 기존 시트의 [GroupSheetContactRow]를 그대로 가져다
/// 쓴다 — 같은 인맥이 시트마다 다르게 보이면 안 된다는 원칙 때문이다.
///
/// ## 두 단계 — 회사가 필터가 된다
///
/// ```
/// 1단계  겹친 마커를 누른다  →  그 자리의 회사 목록(회사명 + 인원수)
/// 2단계  회사를 고른다      →  그 회사 사람들만 보인다
/// ```
///
/// **회사가 하나뿐이면 1단계를 건너뛰고 바로 2단계**를 보여준다 — 고를
/// 것이 하나뿐인 선택 화면은 누르는 수고만 늘리는 군더더기다(이 저장소의
/// 화면 복잡도 원칙, `docs/planning/product-principles.md`).
///
/// 회사 정보가 없는 인맥은 [kNoCompanyLabel]("회사 정보 없음") 자리로
/// 모은다 — 이 앱의 다른 화면(`wallet_view.dart`·`radar_view.dart`)이 이미
/// 쓰는 문구와 같다. 가짜 회사명을 지어내지 않는다.
Future<void> showNearbyMapClusterSheet(
  BuildContext pageContext, {
  required List<ContactModel> contacts,
  required GeoPosition origin,
}) {
  final buckets = bucketContactsByCompany(contacts);
  return showModalBottomSheet<void>(
    context: pageContext,
    backgroundColor: AppColors.cardSurface,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(pageContext).size.height * 0.75,
    ),
    builder: (sheetContext) => _ClusterSheetBody(
      buckets: buckets,
      origin: origin,
      onOpenContact: (contact) {
        // 이 시트만 닫는다 — 지도 화면은 그대로 둔다. 기존 묶음 시트
        // (`nearby_map_group_sheet.dart`)와 같은 구분이다.
        Navigator.of(sheetContext).pop();
        ContactDetailView.show(pageContext, contact);
      },
    ),
  );
}

class _ClusterSheetBody extends StatefulWidget {
  const _ClusterSheetBody({
    required this.buckets,
    required this.origin,
    required this.onOpenContact,
  });

  final List<CompanyBucket> buckets;
  final GeoPosition origin;
  final ValueChanged<ContactModel> onOpenContact;

  @override
  State<_ClusterSheetBody> createState() => _ClusterSheetBodyState();
}

class _ClusterSheetBodyState extends State<_ClusterSheetBody> {
  /// 지금 골라 둔 회사. `null`이면 1단계(회사 목록)를 보고 있다는 뜻.
  CompanyBucket? _selected;

  @override
  void initState() {
    super.initState();
    // 회사가 하나뿐이면 처음부터 그 회사가 골라진 것으로 시작한다 — 고를
    // 필요가 없는 화면에는 선택 UI를 보여주지 않는다.
    if (widget.buckets.length == 1) _selected = widget.buckets.first;
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthRepository>().firebaseUid;
    final selected = _selected;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: selected == null
              ? _companyListStep()
              : _peopleStep(selected, uid),
        ),
      ),
    );
  }

  List<Widget> _companyListStep() {
    final total = widget.buckets.fold<int>(
      0,
      (sum, b) => sum + b.contacts.length,
    );
    return [
      _ClusterHeader(
        icon: Icons.apartment_outlined,
        title: '겹쳐 보이는 회사 ${widget.buckets.length}곳',
        count: total,
      ),
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: widget.buckets.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final bucket = widget.buckets[index];
            return _CompanyRow(
              bucket: bucket,
              onTap: () => setState(() => _selected = bucket),
            );
          },
        ),
      ),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline,
              size: 13,
              color: AppColors.textMuted,
            ),
          ),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              '지도에서 화면상 겹쳐 보이는 마커를 모았습니다. 회사를 고르면'
              ' 그 회사 인맥만 보여드려요',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _peopleStep(CompanyBucket bucket, String? uid) {
    final rows = buildContactRows(bucket.contacts, widget.origin);
    return [
      Row(
        children: [
          // 고를 회사가 여럿이었을 때만 되돌아갈 곳이 있다. 하나뿐이라
          // 1단계 자체를 건너뛴 경우에는 돌아갈 회사 목록이 없으므로
          // 화살표를 보여주지 않는다.
          if (widget.buckets.length > 1)
            IconButton(
              tooltip: '회사 목록으로',
              onPressed: () => setState(() => _selected = null),
              icon: const Icon(Icons.arrow_back, size: 20),
              color: AppColors.textSecondary,
            ),
          Expanded(
            child: _ClusterHeader(
              icon: Icons.business_outlined,
              title: bucket.label,
              count: bucket.contacts.length,
            ),
          ),
        ],
      ),
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            // 기존 묶음 시트(F-15)와 **같은 행 위젯**. 이름·직함·회사·거리
            // 배지·눌렀을 때의 동작까지 전부 같다 — 새로 그리지 않는다.
            return GroupSheetContactRow(
              row: row,
              uid: uid,
              onTap: () => widget.onOpenContact(row.contact),
            );
          },
        ),
      ),
    ];
  }
}

/// 1단계·2단계 머리글. [SameAddressGroupHeader](F-15)와 같은 시각 스타일
/// (배경·둥근 모서리·글자 크기)을 따르되, 그 위젯은 "주소"를 전제로 한
/// 문구(`$address에 $count명`)라 여기서는 못 그대로 쓴다 — 이 시트는 주소
/// 하나가 아니라 **화면상 겹친 여러 주소**를 다루기 때문이다. 그래서 모양은
/// 맞추고 내용만 이 화면에 맞게 새로 짰다.
class _ClusterHeader extends StatelessWidget {
  const _ClusterHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: '$title, $count명',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6, top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.accentText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
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

/// 1단계 회사 목록의 행 하나.
class _CompanyRow extends StatelessWidget {
  const _CompanyRow({required this.bucket, required this.onTap});

  final CompanyBucket bucket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: onTap,
      child: Row(
        children: [
          const Icon(
            Icons.apartment_outlined,
            size: 18,
            color: AppColors.accentText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              bucket.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${bucket.contacts.length}명',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.accentText,
              ),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/address_grouping.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../common/contact_avatar.dart';
import '../../../common/glass_card.dart';
import '../../../common/same_address_group_header.dart';
import '../../wallet/views/contact_detail_view.dart';
import '../utils/nearby_map_clusters.dart';

/// 실제 지도(`nearby_map_view.dart`)에서 같은 주소 묶음 마커를 탭했을 때 뜨는
/// 바텀시트(P2-①, 2026-08-22 사용자 확정 — "묶음 탭 = 바텀시트").
///
/// [pageContext]는 지도 화면(`NearbyMapView`)의 build context다. 항목을 눌러
/// 명함 상세로 이동할 때 이 시트 자체는 닫아야 하지만 **지도 화면까지 닫으면
/// 안 되므로**, 시트를 닫는 데는 `builder`가 주는 지역 context(같은 Navigator
/// 스택의 맨 위=이 시트)를 쓰고, 상세 화면을 여는 데는 [pageContext](지도
/// 화면 자체 — 시트를 닫아도 그대로 살아 있다)를 쓴다. 지도의 낱개 핀 미니
/// 카드(`_showContactSheet`)가 전화 걸기에서 쓰는 것과 같은 구분이다.
Future<void> showNearbyMapGroupSheet(
  BuildContext pageContext, {
  required AddressGroup group,
  required GeoPosition origin,
}) {
  final rows = buildGroupSheetRows(group: group, origin: origin);
  return showModalBottomSheet<void>(
    context: pageContext,
    backgroundColor: AppColors.cardSurface,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(pageContext).size.height * 0.75,
    ),
    builder: (sheetContext) => _GroupSheetBody(
      group: group,
      rows: rows,
      onOpenContact: (contact) {
        // 이 시트만 닫는다 — 지도 화면은 그대로 둔다.
        Navigator.of(sheetContext).pop();
        // 명함 상세는 그 자체가 바텀시트라, 지도 화면(다른 라우트) 위에
        // 그대로 얹힌다. 목록 화면의 [ContactDetailView.show] 진입로와 같다.
        ContactDetailView.show(pageContext, contact);
      },
    ),
  );
}

class _GroupSheetBody extends StatelessWidget {
  const _GroupSheetBody({
    required this.group,
    required this.rows,
    required this.onOpenContact,
  });

  final AddressGroup group;
  final List<GroupSheetRow> rows;
  final ValueChanged<ContactModel> onOpenContact;

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthRepository>().firebaseUid;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 목록 화면(F-15)과 같은 머리글 컴포넌트 — 위치 아이콘 + 도로명 +
            // "N명" 배지. 새로 만들지 않고 그대로 재사용해, 같은 묶음 개념이
            // 두 화면에서 다르게 보이지 않게 한다.
            SameAddressGroupHeader(
              address: group.address,
              count: group.contacts.length,
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return GroupSheetContactRow(
                    row: row,
                    uid: uid,
                    onTap: () => onOpenContact(row.contact),
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
                    '묶음 기준은 목록 화면(같은 도로명 주소)과 동일합니다',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 같은 주소 묶음(F-15)·겹친 마커 클러스터(추가 452) 시트가 함께 쓰는 인맥
/// 행 하나. **한 곳에서만 정의해 재사용한다** — 시트마다 따로 그리면 같은
/// 인맥이 시트에 따라 다르게 보일 수 있다(사용자 지시, 추가 452).
class GroupSheetContactRow extends StatelessWidget {
  const GroupSheetContactRow({
    super.key,
    required this.row,
    required this.uid,
    required this.onTap,
  });

  final GroupSheetRow row;
  final String? uid;
  final VoidCallback onTap;

  static String _distanceLabel(double meters) {
    if (!meters.isFinite) return '';
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    final contact = row.contact;
    final distanceLabel = _distanceLabel(row.distanceMeters);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      onTap: onTap,
      child: Row(
        children: [
          ContactAvatar(
            photoPath: contact.avatarUrl,
            name: contact.name,
            radius: 20,
            cardImagePath: contact.useCardAsAvatar
                ? contact.cardImagePath
                : null,
            uid: contact.useCardAsAvatar ? uid : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  contact.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (row.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    row.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (distanceLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                distanceLabel,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentText,
                ),
              ),
            ),
          ],
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

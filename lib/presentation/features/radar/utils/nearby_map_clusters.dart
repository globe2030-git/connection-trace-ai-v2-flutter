/// 실제 지도 화면(`views/nearby_map_view.dart`)에서 **같은 건물에 여러 핀이
/// 겹치는 문제**(P2-①, 2026-08-22 확정)를 푸는 순수 로직.
///
/// ## 묶음 판정은 새로 만들지 않는다
///
/// 사용자 확정(추가 395): "묶음 판정 = 목록(F-15)과 같은 도로명 일치 기준".
/// 그래서 여기서는 [groupContactsByAddress]를 **그대로 재사용**한다 — 같은
/// 인맥 데이터를 두고 목록 화면과 지도 화면이 서로 다른 규칙으로 묶으면,
/// 목록에서는 "3명"인데 지도에서는 낱개 2개+묶음 1개로 보이는 모순이 생긴다.
/// (`nearby_map_layout.dart`의 주변 홈 지도 **카드**도 같은 이유로 같은 함수를
/// 쓴다 — 이 파일은 그것과 별개로 **실제 지도(flutter_map) 마커**용이다.)
library;

import '../../../../core/utils/address_grouping.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';

/// 실제 지도 위 마커 하나 — 낱개 인맥이거나 같은 주소 묶음(F-15).
class MapMarkerGroup {
  const MapMarkerGroup({required this.group, required this.point});

  /// 이 마커가 대표하는 인맥 묶음. [AddressGroup.isGrouped]가 false면 낱개다.
  final AddressGroup group;

  /// 마커를 찍을 좌표 — 묶음 안 **첫 인맥의 좌표**를 대표점으로 쓴다. 같은
  /// 주소라도 지오코딩이 각자 이뤄졌다면 좌표가 미세하게 다를 수 있는데,
  /// 마커는 하나만 찍어야 하므로 임의로 대표 하나를 고른다(목록 F-15가
  /// "처음 나온 자리"를 기준으로 삼는 것과 같은 결).
  final GeoPosition point;

  bool get isGrouped => group.isGrouped;
  int get count => group.contacts.length;

  /// 대표 인맥 — 낱개면 본인, 묶음이면 첫 번째 사람(개별 핀 스타일을 그대로
  /// 쓸 때 이름 이니셜 등에 쓴다).
  ContactModel get representative => group.contacts.first;
}

/// [contactsWithGeo]를 같은 도로명 주소끼리 묶어 지도 마커 목록으로 바꾼다.
///
/// ⚠️ 호출부가 좌표(`geo`)가 있는 인맥만 걸러서 넘겨야 한다 — 좌표가 없으면
/// 대표점을 정할 수 없다.
List<MapMarkerGroup> computeMapMarkerGroups(
  List<ContactModel> contactsWithGeo,
) {
  return groupContactsByAddress(contactsWithGeo)
      .map(
        (group) =>
            MapMarkerGroup(group: group, point: group.contacts.first.geo!),
      )
      .toList();
}

/// 묶음 마커를 탭했을 때 뜨는 바텀시트의 목록 행 하나 — 화면(위젯) 없이도
/// 검사할 수 있도록 순수 데이터로 뽑아 둔다.
class GroupSheetRow {
  const GroupSheetRow({
    required this.contact,
    required this.distanceMeters,
    required this.subtitle,
  });

  final ContactModel contact;

  /// 거리 기준점([origin], F-13이 있으면 그 지점·없으면 내 위치)에서 잰 거리.
  final double distanceMeters;

  /// "직함 · 회사" — `nearby_map_view.dart`의 낱개 핀 미니 카드와 같은 조합
  /// 규칙(`[title, company].where(비어있지않음).join(' · ')`)이다.
  final String subtitle;
}

/// 같은 주소 묶음 [group]의 인맥들을 바텀시트에 뿌릴 행 목록으로 바꾼다.
///
/// 순서는 [group.contacts]가 넘어온 순서(=거리순, F-15와 동일)를 그대로
/// 따른다 — 같은 주소면 좌표도 대개 같아 거리도 같으므로 다시 정렬할 이유가
/// 없다.
List<GroupSheetRow> buildGroupSheetRows({
  required AddressGroup group,
  required GeoPosition origin,
}) {
  return [
    for (final contact in group.contacts)
      GroupSheetRow(
        contact: contact,
        distanceMeters: GeoUtils.getDistanceMeters(origin, contact.geo),
        subtitle: [
          contact.title,
          contact.company,
        ].where((s) => s.trim().isNotEmpty).join(' · '),
      ),
  ];
}

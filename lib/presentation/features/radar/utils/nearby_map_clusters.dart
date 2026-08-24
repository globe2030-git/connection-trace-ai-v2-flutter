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

/// 묶음 마커에 붙일 대표 회사명 라벨을 만든다(추가 445).
///
/// ## 왜 필요한가
///
/// 예전에는 묶음 마커가 "같은 주소 N명"이라는 숫자만 보여줘서, 눌러 보기
/// 전에는 어느 건물인지 알 수 없었다. 경쟁 앱(리멤버)은 "크림하우스 외 9"처럼
/// 대표 회사명을 미리 보여준다 — 이 함수가 그 대표 이름을 정한다.
///
/// ## 대표를 정하는 규칙
///
/// **가장 많은 명함이 속한 회사**를 대표로 삼는다. 회사명별로 등장 횟수를 세고,
/// 가장 큰 것을 고른다. **동률이면 먼저 나온(=[group.contacts] 순서상 앞선)
/// 회사가 이긴다** — 그 회사가 곧 "첫 명함의 회사"이기도 하므로, 지시된 두
/// 규칙("가장 많은 회사" 또는 "첫 명함의 회사")이 이 하나의 구현으로 동시에
/// 만족된다.
///
/// 대표 회사에 속하지 않는 나머지 인원이 있으면 `"$대표 외 $나머지수"`로,
/// 전원이 같은 회사면 나머지 없이 회사명만 돌려준다.
///
/// ## 빈 값 처리
///
/// 묶음 안 전원의 회사명이 비어 있으면(가짜 이름을 지어내지 않는다는 이 저장소
/// 원칙에 따라) **`null`을 돌려준다** — 호출부는 이때 예전처럼 "같은 주소 N명"
/// 문구로 대신한다. 회사명이 없는 인맥은 집계에서 건너뛰므로, 일부만 비어 있는
/// 묶음에서는 회사명이 있는 사람들끼리만 비교한다.
String? groupCompanyLabel(AddressGroup group) {
  final counts = <String, int>{};
  final firstSeenOrder = <String>[];
  for (final contact in group.contacts) {
    final company = contact.company.trim();
    if (company.isEmpty) continue;
    if (!counts.containsKey(company)) firstSeenOrder.add(company);
    counts[company] = (counts[company] ?? 0) + 1;
  }
  if (firstSeenOrder.isEmpty) return null;

  var best = firstSeenOrder.first;
  var bestCount = counts[best]!;
  for (final company in firstSeenOrder) {
    final count = counts[company]!;
    if (count > bestCount) {
      best = company;
      bestCount = count;
    }
  }

  final others = group.contacts.length - bestCount;
  return others > 0 ? '$best 외 $others' : best;
}

/// 같은 주소 묶음 [group]의 인맥들을 바텀시트에 뿌릴 행 목록으로 바꾼다.
///
/// 순서는 [group.contacts]가 넘어온 순서(=거리순, F-15와 동일)를 그대로
/// 따른다 — 같은 주소면 좌표도 대개 같아 거리도 같으므로 다시 정렬할 이유가
/// 없다.
List<GroupSheetRow> buildGroupSheetRows({
  required AddressGroup group,
  required GeoPosition origin,
}) => buildContactRows(group.contacts, origin);

/// [contacts]를 [origin] 기준 바텀시트 행으로 바꾼다. [buildGroupSheetRows]가
/// 쓰는 것과 같은 규칙이다 — 겹친 마커 클러스터 시트(추가 452,
/// `nearby_map_cluster_sheet.dart`)는 하나의 주소 묶음이 아니라 **여러 묶음을
/// 합친** 인맥 목록을 받으므로, [AddressGroup] 하나를 요구하는
/// [buildGroupSheetRows]로는 못 쓴다. 그래서 인맥 목록을 직접 받는 이 함수로
/// 뽑아 두고, 두 함수가 같은 결과를 내도록 [buildGroupSheetRows]가 이 함수를
/// 감싸는 형태로 정리했다 — 규칙이 갈라지면 같은 인맥이 시트마다 다르게
/// 보인다.
List<GroupSheetRow> buildContactRows(
  List<ContactModel> contacts,
  GeoPosition origin,
) {
  return [
    for (final contact in contacts)
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

/// 회사별로 묶은 인맥 무리 하나 — 겹친 마커 클러스터 시트의 1단계(회사
/// 목록)에 쓴다(추가 452, 사용자 지시: "그 회사 사람들만 볼 수 있도록").
class CompanyBucket {
  const CompanyBucket({required this.label, required this.contacts});

  /// 회사명, 또는 회사 정보가 없는 사람들을 모은 자리라면
  /// [kNoCompanyLabel] — 이 앱의 다른 화면(`wallet_view.dart`,
  /// `radar_view.dart`)이 이미 쓰는 문구와 같다. 가짜 회사명을 지어내지
  /// 않는다는 원칙에 따른다.
  final String label;

  final List<ContactModel> contacts;
}

/// 회사 정보가 없는 인맥을 모으는 자리의 이름. `wallet_view.dart`·
/// `radar_view.dart`가 이미 같은 문구를 쓰고 있어 그대로 맞췄다 — 같은 개념이
/// 화면마다 다른 말로 불리면 안 된다.
const String kNoCompanyLabel = '회사 정보 없음';

/// [contacts]를 회사별로 나눈다.
///
/// - 인원이 많은 회사가 앞선다 — [groupCompanyLabel]의 대표 규칙과 같은
///   근거다("그 자리에 사람이 많이 몰린 회사가 더 중요한 정보").
/// - [kNoCompanyLabel] 자리는 **인원수와 무관하게 항상 맨 뒤**로 보낸다 —
///   실제 회사가 아니라 "모르는 자리"이므로, 회사 목록에서 실제 회사들보다
///   먼저 나오면 실제 회사인 것처럼 오인될 수 있다.
List<CompanyBucket> bucketContactsByCompany(List<ContactModel> contacts) {
  final order = <String>[];
  final byCompany = <String, List<ContactModel>>{};
  for (final contact in contacts) {
    final company = contact.company.trim();
    final key = company.isEmpty ? kNoCompanyLabel : company;
    if (!byCompany.containsKey(key)) order.add(key);
    (byCompany[key] ??= []).add(contact);
  }

  final buckets = [
    for (final key in order)
      CompanyBucket(label: key, contacts: byCompany[key]!),
  ];
  // `List.sort`는 안정 정렬을 보장하지 않는다 — 인원수가 같은 회사끼리도
  // 결과가 실행마다 흔들리지 않도록 먼저 나온 순서(원래 [order])를
  // 동률 처리 기준으로 명시한다.
  final firstSeenIndex = {for (var i = 0; i < order.length; i++) order[i]: i};
  buckets.sort((a, b) {
    if (a.label == kNoCompanyLabel) return 1;
    if (b.label == kNoCompanyLabel) return -1;
    final byCount = b.contacts.length.compareTo(a.contacts.length);
    if (byCount != 0) return byCount;
    return firstSeenIndex[a.label]!.compareTo(firstSeenIndex[b.label]!);
  });
  return buckets;
}

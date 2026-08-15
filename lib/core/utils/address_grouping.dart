/// 같은 주소에 있는 인맥을 묶는다(F-15).
///
/// ## 왜 필요한가
///
/// 한 건물에 여러 명이 있으면 "가까운 인맥" 목록에 같은 거리가 여러 줄
/// 나열된다. 사용자가 실제로 알고 싶은 것은 *"이 건물에 3명 있다"*인데,
/// 지금은 그걸 스스로 세어야 한다.
///
/// ## 무엇을 같은 주소로 보나 — 도로명까지만
///
/// **상세주소(층·호)는 무시한다.** 같은 건물의 3층과 7층은 사용자에게 "같은
/// 곳"이고, 한 번에 들르는 대상이기 때문이다. 반대로 상세주소까지 따지면
/// 층이 다르다는 이유로 안 묶여, 이 기능이 있으나 마나 해진다.
///
/// 주소가 **비어 있는 명함은 묶지 않는다.** 주소를 모르는 사람들끼리
/// "같은 곳"이라고 묶으면 없는 사실을 만들어 내는 것이다(F-02 이후 주소 없는
/// 명함도 등록되므로 실제로 생기는 경우다).
///
/// ## 순서를 바꾸지 않는다
///
/// 묶음은 **처음 나온 자리**에 놓는다. 호출부가 거리순으로 정렬해 넘기면 그
/// 순서가 유지된다 — 같은 주소면 좌표도 같아 거리도 같으므로, 묶어도 거리순이
/// 깨지지 않는다.
library;

import '../../data/models/contact_model.dart';

/// 같은 주소에 있는 인맥 묶음. [contacts]가 1명이면 묶음이 아니라 낱개다.
class AddressGroup {
  const AddressGroup({required this.address, required this.contacts});

  /// 묶음의 기준이 된 주소(도로명까지). 낱개이거나 주소가 없으면 빈 문자열.
  final String address;

  /// 이 묶음에 속한 인맥. 넘어온 순서를 유지한다.
  final List<ContactModel> contacts;

  /// 2명 이상일 때만 "묶음"으로 보여 준다. 1명짜리 묶음 머리글은 정보가 없다.
  bool get isGrouped => contacts.length > 1;
}

/// 주소 비교용 정규화 — 앞뒤 공백을 떼고, 사이의 연속 공백을 하나로 줄인다.
///
/// OCR로 읽은 주소는 `'서울시  강남구 테헤란로 123'`처럼 공백이 불규칙하다.
/// 그대로 비교하면 눈으로는 같은 주소가 안 묶인다.
String _normalize(String? address) =>
    (address ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

/// [contacts]를 주소별로 묶는다. 순서는 각 주소가 **처음 나온 자리**를 따른다.
List<AddressGroup> groupContactsByAddress(List<ContactModel> contacts) {
  final groups = <AddressGroup>[];
  // 주소 → groups에서의 위치. 같은 주소를 다시 만나면 그 자리에 이어 붙인다.
  final indexByAddress = <String, int>{};

  for (final contact in contacts) {
    final key = _normalize(contact.address);
    if (key.isEmpty) {
      // 주소를 모르는 사람은 언제나 낱개다 — 서로 묶지 않는다.
      groups.add(AddressGroup(address: '', contacts: [contact]));
      continue;
    }
    final existing = indexByAddress[key];
    if (existing == null) {
      indexByAddress[key] = groups.length;
      groups.add(AddressGroup(address: key, contacts: [contact]));
    } else {
      groups[existing].contacts.add(contact);
    }
  }
  return groups;
}

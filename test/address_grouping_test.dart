import 'package:connection_trace_ai_flutter/core/utils/address_grouping.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 같은 주소 묶음(F-15)의 규칙을 고정한다.
///
/// 묶는 규칙이 틀려도 화면은 멀쩡히 뜬다 — 안 묶이거나(기능이 없는 것처럼
/// 보임), 엉뚱한 사람이 같은 곳에 있다고 나온다(없는 사실을 만듦). 둘 다
/// 눈으로 훑어서는 알기 어렵다.
ContactModel _c(String id, {String? address, String? detail}) => ContactModel(
  id: id,
  name: id,
  company: '',
  title: '',
  phone: '',
  email: '',
  tags: const [],
  talkingPoints: const [],
  address: address,
  addressDetail: detail,
);

List<String> _ids(AddressGroup g) => g.contacts.map((c) => c.id).toList();

void main() {
  group('같은 주소 묶기', () {
    test('⭐ 주소가 같으면 한 묶음이 된다', () {
      final groups = groupContactsByAddress([
        _c('a', address: '서울특별시 강남구 테헤란로 123'),
        _c('b', address: '서울특별시 강남구 테헤란로 123'),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.isGrouped, isTrue);
      expect(_ids(groups.single), ['a', 'b']);
    });

    test('⭐ 상세주소(층·호)가 달라도 같은 건물이면 묶는다', () {
      final groups = groupContactsByAddress([
        _c('3층사람', address: '테헤란로 123', detail: '3층'),
        _c('7층사람', address: '테헤란로 123', detail: '7층 701호'),
      ]);
      expect(
        groups.single.isGrouped,
        isTrue,
        reason: '사용자에게 같은 건물은 "같은 곳"이다 — 층이 다르다고 안 묶으면 '
            '이 기능이 있으나 마나 해진다',
      );
    });

    test('공백이 불규칙해도 같은 주소로 본다', () {
      final groups = groupContactsByAddress([
        _c('a', address: '서울시  강남구   테헤란로 123'),
        _c('b', address: ' 서울시 강남구 테헤란로 123 '),
      ]);
      expect(
        groups.single.isGrouped,
        isTrue,
        reason: 'OCR로 읽은 주소는 공백이 불규칙하다',
      );
    });

    test('⭐ 주소가 없는 사람끼리는 묶지 않는다', () {
      final groups = groupContactsByAddress([
        _c('a'),
        _c('b', address: ''),
        _c('c', address: '   '),
      ]);
      expect(
        groups, hasLength(3),
        reason: '주소를 모르는 사람들을 "같은 곳"이라고 묶으면 없는 사실을 만든다',
      );
      expect(groups.every((g) => !g.isGrouped), isTrue);
    });

    test('주소가 다르면 각각 낱개로 남는다', () {
      final groups = groupContactsByAddress([
        _c('a', address: '테헤란로 123'),
        _c('b', address: '테헤란로 456'),
      ]);
      expect(groups, hasLength(2));
      expect(groups.every((g) => !g.isGrouped), isTrue);
    });

    test('⭐ 묶음은 그 주소가 처음 나온 자리에 놓인다', () {
      // 거리순으로 정렬해 넘긴 순서가 유지되어야 한다.
      final groups = groupContactsByAddress([
        _c('가까움', address: 'A로 1'),
        _c('중간', address: 'B로 2'),
        _c('멀지만같은건물', address: 'A로 1'),
      ]);
      expect(groups.map((g) => g.address).toList(), ['A로 1', 'B로 2']);
      expect(_ids(groups.first), ['가까움', '멀지만같은건물']);
    });

    test('빈 목록은 빈 결과', () {
      expect(groupContactsByAddress([]), isEmpty);
    });

    test('한 명뿐이면 묶음이 아니다', () {
      final groups = groupContactsByAddress([_c('a', address: '테헤란로 123')]);
      expect(
        groups.single.isGrouped,
        isFalse,
        reason: '1명짜리 묶음 머리글은 아무 정보도 주지 않는다',
      );
    });
  });
}

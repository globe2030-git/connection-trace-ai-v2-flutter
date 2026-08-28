/// 🚨 **등록할 때도 같은 주소는 다시 안 물어본다** (globe2030님 지적, 2026-08-28).
///
/// > *"회사별 좌표는 한번만 확인되면 저장되서 명함의 회사 주소로 계속
/// >  검색할 이유가 없지않나?"*
///
/// ## ⚠️ 처음에 옆길을 고쳤다 — 경위를 남긴다
///
/// 이 지적을 받고 **좌표 채우기(백필)** 쪽에 재사용을 넣었다. 그런데 등록은
/// 저장하면서 좌표가 바로 붙어 **백필 경로에 아예 가지 않는다.** 그래서
/// globe2030님이 아이폰 126장을 등록하는 동안 **같은 주소를 그 수만큼 계속
/// 물어보고 있었다** — 고친 것이 그 옆길이었다.
///
/// 📌 **「계속 검색」이 일어나는 곳은 등록 경로였다.** 지적의 원문이 이미
/// 그것을 가리키고 있었는데, `pendingContacts` 를 보고 *"좌표 없는 명함을
/// 채우는 곳"* 이라고 읽은 뒤 **그 함수가 정말 그 「검색」인지 확인하지
/// 않았다.**
///
/// ⭐ 백필 쪽이 쓸모없지는 않다 — 복원·다기기 동기화 뒤에는 실제로 돈다
/// (폴드 실측 11장 중 6장). **범위가 좁았을 뿐이다. 두 경로 다 필요하다.**
library;

import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/geo_backfill_service.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ContactModel card({
  required String id,
  String? address,
  GeoPosition? geo,
}) => ContactModel(
  id: id,
  name: '테스트$id',
  company: '회사',
  title: '직함',
  phone: '010-0000-0000',
  email: 'a@b.c',
  address: address,
  geo: geo,
  tags: const [],
  talkingPoints: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const addr = '서울특별시 강남구 테헤란로 1';
  const geo = GeoPosition(lat: 37.5, lng: 127.0);

  group('🚨 저장 직전에 같은 주소를 찾는다', () {
    test('⭐ 같은 주소를 가진 명함이 있으면 그 좌표를 준다', () {
      final repo = ContactsRepository();
      repo.addContact(card(id: 'old', address: addr, geo: geo));

      expect(
        repo.geoForSameAddress(addr),
        geo,
        reason: '이것이 없으면 등록할 때마다 같은 주소를 다시 물어본다',
      );
    });

    test('🚨 주소가 조금이라도 다르면 안 준다', () {
      final repo = ContactsRepository();
      repo.addContact(card(id: 'old', address: addr, geo: geo));

      expect(
        repo.geoForSameAddress('서울 강남구 테헤란로 1'), // 사람 눈엔 같다
        isNull,
        reason: '정규화하지 않는다 — 잘못 묶으면 엉뚱한 좌표가 붙는다. '
            '틀린 좌표가 붙을 유일한 경로라 아예 만들지 않았다',
      );
    });

    test('⭐ 앞뒤 공백은 다듬어 견준다', () {
      final repo = ContactsRepository();
      repo.addContact(card(id: 'old', address: addr, geo: geo));
      expect(repo.geoForSameAddress('  $addr  '), geo);
    });

    test('좌표가 없는 명함의 주소는 안 준다', () {
      final repo = ContactsRepository();
      repo.addContact(card(id: 'old', address: addr));
      expect(
        repo.geoForSameAddress(addr),
        isNull,
        reason: '빈 좌표를 빌려 주면 "좌표를 얻었다"고 잘못 판정한다',
      );
    });

    test('빈 주소로는 아무것도 안 준다', () {
      final repo = ContactsRepository();
      repo.addContact(card(id: 'old', address: addr, geo: geo));
      expect(repo.geoForSameAddress(''), isNull);
      expect(repo.geoForSameAddress('   '), isNull);
    });
  });

  group('🚨 계측 — 재지 않으면 "좋아졌겠지"만 남는다', () {
    test('⭐ 빌려 쓴 건수를 누적으로 센다', () async {
      final repo = ContactsRepository();
      repo.addContact(card(id: 'old', address: addr, geo: geo));

      repo.geoForSameAddress(addr);
      repo.geoForSameAddress(addr);
      await Future<void>.delayed(Duration.zero);

      expect(
        await GeoBackfillService.readAddressReuseTotal(),
        2,
        reason: '이 숫자가 곧 "주소가 얼마나 겹치나"의 실측이다 — '
            '2026-08-28에 그 값을 아무도 몰랐다',
      );
    });

    test('⭐ 못 빌렸으면 안 센다', () async {
      final repo = ContactsRepository();
      repo.geoForSameAddress(addr);
      await Future<void>.delayed(Duration.zero);
      expect(await GeoBackfillService.readAddressReuseTotal(), 0);
    });

    test('🚨 누적은 회차 스냅샷과 다른 키에 쌓인다', () async {
      // _stageStatsKey 는 마지막 회차만 담고 덮어쓴다. 등록 시 재사용을 거기
      // 넣으면 다음 백필이 그 숫자를 지운다 — 그래서 따로 뒀다.
      final repo = ContactsRepository();
      repo.addContact(card(id: 'old', address: addr, geo: geo));
      repo.geoForSameAddress(addr);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('geo_reuse_total_v1'), 1);
      expect(
        prefs.getString('geo_backfill_stage_stats_v1'),
        isNull,
        reason: '회차 스냅샷을 건드리면 안 된다',
      );
    });
  });

  group('🚨 배선 — 등록 화면이 실제로 부르는가', () {
    test('⭐ 저장 직전에 geoForSameAddress 를 부른다', () {
      // 이 흐름은 카메라·OCR·지오코딩이 얽혀 위젯 테스트로 세우기 어렵다.
      // 그래서 "부르는 줄이 있는가"만 소스로 못 박는다 — 이 저장소는
      // "서비스는 정상, 부르는 쪽이 없음"으로 이미 한 번 데었다(CLAUDE.md 4절).
      final source = File(
        'lib/presentation/features/wallet/views/add_card_modal_view.dart',
      ).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

      expect(
        source.contains('geoForSameAddress(') &&
            source.contains('if (reusedGeo != null)'),
        isTrue,
        reason: '안 부르면 저장소 테스트는 전부 초록인데 등록할 때마다 '
            '계속 물어본다 — 아무도 모른다',
      );
    });

    test('🚨 통신보다 먼저 본다', () {
      final source = File(
        'lib/presentation/features/wallet/views/add_card_modal_view.dart',
      ).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

      final reuse = source.indexOf('geoForSameAddress(');
      final geocode = source.indexOf('AddressGeocodingService.validateAndConvert');
      expect(reuse, greaterThan(-1));
      expect(geocode, greaterThan(-1));
      expect(
        reuse,
        lessThan(geocode),
        reason: '뒤에 있으면 이미 물어본 뒤라 아끼는 것이 없다',
      );
    });
  });
}

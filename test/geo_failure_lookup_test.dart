import 'dart:convert';
import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/geo_failure_lookup.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 좌표를 못 얻은 명함이 **주변 화면에서 어떤 상태인지** 가르는 규칙.
///
/// ## 🚨 이 파일이 제일 먼저 막는 것 — 조용히 빈 값이 되는 것
///
/// [GeoFailureLookup] 은 `GeoBackfillService` 가 쓴 기록을 **읽기만** 한다.
/// 그런데 그쪽 상수가 private 이라 **키·해시·상한을 여기서 맞춰 두고 있다.**
/// 한쪽이 바뀌면 이 통로가 **아무 말 없이 "실패한 적 없음"을 돌려준다** —
/// 오늘 `firestore.rules` 에서 겪은 것과 같은 모양이다(추가 533).
///
/// 그래서 **원본 파일을 읽어 대조한다.**
ContactModel card({
  String id = 'c1',
  String? address = '서울특별시 강남구 테헤란로 1',
  GeoPosition? geo,
}) =>
    ContactModel(
      id: id,
      name: '홍길동',
      company: '가상상사',
      title: '영업팀장',
      phone: '010-0000-0001',
      email: 'example@example.invalid',
      address: address,
      geo: geo,
      tags: const [],
      talkingPoints: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('🚨 원본과 어긋나면 조용히 깨진다 — 대조로 고정', () {
    final source =
        File('lib/core/services/geo_backfill_service.dart').readAsStringSync();

    test('⭐ prefs 키가 GeoBackfillService 와 같다', () {
      expect(
        source,
        contains("'${GeoFailureLookup.prefsKey}'"),
        reason: '키가 어긋나면 기록을 못 찾고 **모든 명함이 "실패한 적 없음"** 이 '
            '된다. 화면에는 안내가 아예 안 뜨는데, 그것이 정상인지 고장인지 '
            '구분할 수 없다',
      );
    });

    test('⭐ 시도 상한이 같다', () {
      expect(
        source,
        contains('maxAttemptsPerContact = ${GeoFailureLookup.maxAttempts}'),
        reason: '상한이 어긋나면 아직 재시도 중인 명함에 "찾지 못했습니다"를 '
            '띄우거나, 포기한 명함에 아무 말도 안 한다',
      );
    });

    test('⭐ 주소 해시 계산이 같다', () {
      expect(
        source,
        contains("sha256.convert(utf8.encode(address)).toString().substring(0, 12)"),
        reason: '해시가 달라지면 저장된 기록과 하나도 안 맞아 **조용히 "실패한 적 '
            '없음"** 이 된다',
      );
    });
  });

  group('상태 판정 — 화면이 무슨 말을 할지가 여기서 갈린다', () {
    test('좌표가 있으면 안내하지 않는다', () {
      expect(
        geoNoticeStateOf(card(geo: const GeoPosition(lat: 37.5, lng: 127.0)), 9),
        GeoNoticeState.located,
      );
    });

    test('⭐ 아직 포기하지 않았으면 말하지 않는다', () {
      expect(
        geoNoticeStateOf(card(), 2),
        GeoNoticeState.located,
        reason: '다음 실행에서 좌표를 얻을 수 있는데 "찾지 못했습니다"라고 하면 '
            '틀린 말이 된다',
      );
      expect(geoNoticeStateOf(card(), null), GeoNoticeState.located);
    });

    test('⭐ 3회 실패 + 지역은 뽑힘 → regionOnly', () {
      expect(geoNoticeStateOf(card(), 3), GeoNoticeState.regionOnly);
    });

    test('⭐ 3회 실패 + 지역도 못 뽑음 → hidden', () {
      expect(
        geoNoticeStateOf(card(address: '3층 301호'), 3),
        GeoNoticeState.hidden,
        reason: '이것만 주변 화면에서 실제로 사라진다',
      );
    });

    test('⭐ 주소가 없으면 지오코딩 실패가 아니다', () {
      expect(geoNoticeStateOf(card(address: null), 3), GeoNoticeState.noAddress);
      expect(geoNoticeStateOf(card(address: '  '), 3), GeoNoticeState.noAddress);
    });
  });

  group('기록 읽기', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('⭐ 지금 주소로 실패한 것만 센다 — 주소가 바뀌면 기록을 버린다', () async {
      const addr = '서울특별시 강남구 테헤란로 1';
      SharedPreferences.setMockInitialValues({
        GeoFailureLookup.prefsKey: jsonEncode({
          'c1': {'h': GeoFailureLookup.hashAddress(addr), 'n': 3},
          'c2': {'h': 'ffffffffffff', 'n': 3}, // 예전 주소로 실패한 기록
        }),
      });
      final counts = await GeoFailureLookup().loadFailureCounts([
        card(id: 'c1', address: addr),
        card(id: 'c2', address: addr),
      ]);
      expect(counts['c1'], 3);
      expect(
        counts.containsKey('c2'),
        isFalse,
        reason: '주소를 고쳤으면 이전 실패는 의미가 없다 — GeoBackfillService 도 '
            '같은 규칙으로 다시 시도한다',
      );
    });

    test('기록이 없으면 빈 값', () async {
      expect(await GeoFailureLookup().loadFailureCounts([card()]), isEmpty);
    });

    test('⭐ 깨진 값이 들어 있어도 흐름을 막지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        GeoFailureLookup.prefsKey: '{ not json',
      });
      expect(await GeoFailureLookup().loadFailureCounts([card()]), isEmpty);
    });
  });

  group('🚨 개인정보 — 쓰지 않는다', () {
    test('⭐ shared_preferences 에 아무것도 안 쓴다', () async {
      SharedPreferences.setMockInitialValues({});
      final before = SharedPreferences.getInstance()
          .then((p) => p.getKeys().toSet());
      await GeoFailureLookup().loadFailureCounts([card()]);
      final after = (await SharedPreferences.getInstance()).getKeys().toSet();
      expect(
        after,
        equals(await before),
        reason: 'shared_preferences 는 암호화되지 않는다. 이 통로는 읽기 전용이고, '
            '기록을 만들고 지우는 것은 GeoBackfillService 하나뿐이어야 한다',
      );
    });

    test('⭐ 주소 원문이 아니라 해시로만 견준다', () {
      const addr = '서울특별시 강남구 테헤란로 1';
      final h = GeoFailureLookup.hashAddress(addr);
      expect(h.length, 12);
      expect(h.contains('서울'), isFalse);
      expect(RegExp(r'^[0-9a-f]{12}$').hasMatch(h), isTrue);
    });
  });
}

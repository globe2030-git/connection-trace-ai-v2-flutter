import 'dart:convert';
import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/geo_failure_lookup.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 좌표를 못 얻은 명함이 **주변 화면에서 어떤 상태인지** 가르는 규칙.
///
/// ## 🚨 이 파일이 한 번 잘못 만들어졌다 — 경위를 남긴다
///
/// 처음 판은 시도 기록을 [GeoFailureLookup] 이 **직접 해석하던 시절**의 것이라
/// 키 이름·해시 계산·시도 상한이 `GeoBackfillService` 와 같은지 **원본을 읽어
/// 대조하는 테스트 셋**을 들고 있었다.
///
/// ⚠️ **그 자물쇠는 없어도 될 것이었다.** 판정 함수(`resolveGivenUpIds`)가
/// 이미 있었고, 복제할 이유가 애초에 없었다. 복제를 지웠으니 **지킬 것도
/// 함께 사라졌다.**
///
/// 📌 그 대신 **위임이 실제로 닿는지**를 아래 「기록을 통해서 본다」로 확인한다.
/// 상수를 견주는 것이 아니라, 진짜 기록을 넣고 판정이 나오는지 보는 것이다 —
/// 키가 어긋나면 이 쪽이 먼저 깨진다.
ContactModel card({
  String id = 'c1',
  String? address = '서울특별시 강남구 테헤란로 1',
  GeoPosition? geo,
}) => ContactModel(
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

/// `GeoBackfillService` 가 기기에 적어 두는 모양 그대로 기록을 만든다.
///
/// ⚠️ 일부러 **원본과 같은 방식으로 해시를 계산**한다 — 여기서 어긋나면
/// 아래 테스트가 통째로 실패하고, 그것이 곧 통로가 끊겼다는 신호다.
void seedGivenUp(String id, String address, {int count = 3}) {
  SharedPreferences.setMockInitialValues({
    'geo_backfill_attempts_v1': jsonEncode({
      id: {
        'h': sha256
            .convert(utf8.encode(address))
            .toString()
            .substring(0, 12),
        'n': count,
      },
    }),
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('상태 판정 — 화면이 무슨 말을 할지가 여기서 갈린다', () {
    test('좌표가 있으면 안내하지 않는다', () {
      expect(
        geoNoticeStateOf(
          card(geo: const GeoPosition(lat: 37.5, lng: 127.0)),
          true,
        ),
        GeoNoticeState.located,
        reason: '좌표가 있으면 포기 기록이 남아 있어도 지금은 잘 보인다',
      );
    });

    test('⭐ 아직 포기하지 않았으면 말하지 않는다', () {
      expect(
        geoNoticeStateOf(card(), false),
        GeoNoticeState.located,
        reason: '다음 실행에서 좌표를 얻을 수 있는데 "찾지 못했습니다"라고 하면 '
            '틀린 말이 된다',
      );
    });

    test('⭐ 포기 + 지역은 뽑힘 → regionOnly', () {
      expect(
        geoNoticeStateOf(card(), true),
        GeoNoticeState.regionOnly,
        reason: '화면에서 사라지지 않았다 — 2026-08-21 실측에서 좌표 없는 30건이 '
            '전부 이 상태였다. 여기에 "확인할 수 없습니다"는 거짓이다',
      );
    });

    test('⭐ 포기 + 지역도 못 뽑음 → hidden', () {
      expect(
        geoNoticeStateOf(card(address: '3층 301호'), true),
        GeoNoticeState.hidden,
        reason: '이것만 주변 화면에서 실제로 사라진다',
      );
    });

    test('⭐ 주소가 없으면 지오코딩 실패가 아니다', () {
      expect(geoNoticeStateOf(card(address: null), true), GeoNoticeState.noAddress);
      expect(geoNoticeStateOf(card(address: '  '), true), GeoNoticeState.noAddress);
    });
  });

  group('기록을 통해서 본다 — 위임이 실제로 닿는지', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('⭐ 3회 실패한 명함이 포기로 잡힌다', () async {
      const addr = '서울특별시 강남구 테헤란로 1';
      seedGivenUp('c1', addr);
      final ids = await GeoFailureLookup().loadGivenUpIds([
        card(id: 'c1', address: addr),
      ]);
      expect(
        ids,
        contains('c1'),
        reason: '여기가 비면 통로가 끊긴 것이다 — 화면에는 안내가 아예 안 뜨는데, '
            '그것이 정상인지 고장인지 화면만 봐서는 구분할 수 없다',
      );
    });

    test('⭐ 주소를 고치면 이전 실패는 무효다', () async {
      seedGivenUp('c1', '서울특별시 강남구 테헤란로 1');
      final ids = await GeoFailureLookup().loadGivenUpIds([
        card(id: 'c1', address: '서울특별시 서초구 반포대로 2'),
      ]);
      expect(
        ids,
        isEmpty,
        reason: 'GeoBackfillService 가 주소 해시를 함께 저장하는 이유가 이것이다 — '
            '주소가 바뀌면 다시 시도 대상이 된다. 이 규칙을 여기서 다시 세지 '
            '않고 그쪽 판정을 그대로 쓴다',
      );
    });

    test('아직 3회에 못 미친 명함은 안 잡힌다', () async {
      const addr = '서울특별시 강남구 테헤란로 1';
      seedGivenUp('c1', addr, count: 2);
      expect(
        await GeoFailureLookup().loadGivenUpIds([card(id: 'c1', address: addr)]),
        isEmpty,
      );
    });

    test('기록이 없으면 빈 값', () async {
      expect(await GeoFailureLookup().loadGivenUpIds([card()]), isEmpty);
    });

    test('⭐ 깨진 값이 들어 있어도 흐름을 막지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        'geo_backfill_attempts_v1': '{ not json',
      });
      expect(await GeoFailureLookup().loadGivenUpIds([card()]), isEmpty);
    });

    test('좌표가 이미 있으면 기록이 남아 있어도 안 잡는다', () async {
      const addr = '서울특별시 강남구 테헤란로 1';
      seedGivenUp('c1', addr);
      expect(
        await GeoFailureLookup().loadGivenUpIds([
          card(id: 'c1', address: addr, geo: const GeoPosition(lat: 37.5, lng: 127.0)),
        ]),
        isEmpty,
      );
    });
  });

  group('🚨 개인정보 — 쓰지 않는다', () {
    test('⭐ shared_preferences 에 아무것도 안 쓴다', () async {
      const addr = '서울특별시 강남구 테헤란로 1';
      seedGivenUp('c1', addr);
      final before = (await SharedPreferences.getInstance()).getKeys().toSet();
      await GeoFailureLookup().loadGivenUpIds([card(id: 'c1', address: addr)]);
      final after = (await SharedPreferences.getInstance()).getKeys().toSet();
      expect(
        after,
        equals(before),
        reason: 'shared_preferences 는 암호화되지 않는다. 이 통로는 읽기 전용이고, '
            '기록을 만들고 지우는 것은 GeoBackfillService 하나뿐이어야 한다',
      );
    });

    test('⭐ 이 파일에는 저장소를 만지는 코드가 아예 없다', () {
      // 위 테스트는 "이번 호출이 안 썼다"만 본다. 나중에 누가 쓰기 경로를
      // 하나 더 만들면 그 테스트는 그대로 통과한다 — 그래서 파일 자체를 본다.
      final source = File(
        'lib/core/services/geo_failure_lookup.dart',
      ).readAsStringSync();
      expect(
        source.contains('SharedPreferences'),
        isFalse,
        reason: '기록을 만들고 지우는 것은 GeoBackfillService 하나뿐이어야 한다. '
            '두 곳이 같은 키를 만지면 어느 쪽이 마지막인지 알 수 없어진다',
      );
    });
  });
}

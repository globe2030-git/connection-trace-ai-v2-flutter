import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/data/models/billing_config_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/billing_config_repository.dart';

void main() {
  BillingConfigRepository repo(Map<String, dynamic>? raw) =>
      BillingConfigRepository(fetchRaw: () async => raw);

  test('정상 데이터 — active+credits 있는 티어만 가격 오름차순으로 반환', () async {
    final config = await repo({
      'freeCredits': 5,
      'tiers': [
        {'priceKrw': 5000, 'credits': 60, 'active': true},
        {'priceKrw': 1000, 'credits': 10, 'active': true},
        {'priceKrw': 3000, 'credits': 30, 'active': true},
      ],
    }).fetchConfig();

    expect(config, isNotNull);
    expect(config!.freeCredits, 5);
    expect(config.tiers.map((t) => t.priceKrw).toList(), [1000, 3000, 5000]);
    expect(config.tiers.map((t) => t.credits).toList(), [10, 30, 60]);
  });

  test('active:false 또는 credits:null인 티어는 제외', () async {
    final config = await repo({
      'freeCredits': 3,
      'tiers': [
        {'priceKrw': 1000, 'credits': 10, 'active': true},
        {'priceKrw': 2000, 'credits': 20, 'active': false},
        {'priceKrw': 3000, 'credits': null, 'active': true},
        {'priceKrw': 4000, 'credits': 0, 'active': true},
      ],
    }).fetchConfig();

    expect(config, isNotNull);
    expect(config!.tiers.length, 1);
    expect(config.tiers.single.priceKrw, 1000);
  });

  test('tiers 필드가 없으면 빈 리스트', () async {
    final config = await repo({'freeCredits': 3}).fetchConfig();

    expect(config, isNotNull);
    expect(config!.tiers, isEmpty);
  });

  test('tiers 필드 타입이 이상해도(Map/String 등) 죽지 않고 빈 리스트', () async {
    final configFromMap = await repo({
      'freeCredits': 3,
      'tiers': {'not': 'a list'},
    }).fetchConfig();
    expect(configFromMap!.tiers, isEmpty);

    final configFromString = await repo({
      'freeCredits': 3,
      'tiers': 'oops',
    }).fetchConfig();
    expect(configFromString!.tiers, isEmpty);
  });

  test('tiers 안의 항목이 Map이 아니면 그 항목만 무시', () async {
    final config = await repo({
      'freeCredits': 3,
      'tiers': [
        {'priceKrw': 1000, 'credits': 10, 'active': true},
        'not a map',
        42,
      ],
    }).fetchConfig();

    expect(config!.tiers.length, 1);
  });

  test('문서가 없으면(fetchRaw가 null 반환) fetchConfig도 null', () async {
    final config = await repo(null).fetchConfig();
    expect(config, isNull);
  });

  // model 필드(2026-08-14, wallet 전환 U4): fetchConfig가 티어를 걸러
  // 새 BillingConfig를 재구성하는 과정에서 model 필드를 놓치기 쉬운
  // 회귀 지점이었다 — 실제로 처음 구현에서 이 필드를 빠뜨렸다가 이
  // 테스트로 잡았다.
  test('model이 "wallet"이면 BillingModel.wallet으로 파싱된다', () async {
    final config = await repo({'freeCredits': 3, 'model': 'wallet'}).fetchConfig();
    expect(config!.model, BillingModel.wallet);
  });

  test('model 필드가 없거나 알 수 없는 값이면 BillingModel.reset으로 폴백', () async {
    final noField = await repo({'freeCredits': 3}).fetchConfig();
    expect(noField!.model, BillingModel.reset);

    final explicitReset = await repo({
      'freeCredits': 3,
      'model': 'reset',
    }).fetchConfig();
    expect(explicitReset!.model, BillingModel.reset);

    final typo = await repo({'freeCredits': 3, 'model': 'wallett'}).fetchConfig();
    expect(typo!.model, BillingModel.reset);
  });
}

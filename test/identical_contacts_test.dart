/// **완전히 같은 명함만 자동으로 정리한다**(2026-08-29, 추가 572).
///
/// ## 왜 이 조건 하나뿐인가
///
/// 2026-08-28 하루에 합치기에서 **세 번 데었다** — 사진을 버렸고(추가 552),
/// 이력을 버렸고(추가 553), 빈 값으로 덮었다. **셋 다 사람이 확인창을 보는
/// 경로였는데도** 그랬다. 🚨 **동기화는 아무도 안 보는 자리다 — 거기서
/// 자동으로 합치면 잃어도 모른다.**
///
/// 그래서 자동으로 정리하는 것은 **잃을 것이 정의상 없는 경우**뿐이다.
///
/// 📌 **이 판정은 매칭 규칙의 아래쪽에 있다** — 이름+휴대폰이든 더 넓은
/// 그물이든, 이 조건을 통과한 쌍은 어느 규칙으로 봐도 같은 사람이다.
library;

import 'package:connection_trace_ai_flutter/core/utils/identical_contacts.dart';
import 'package:connection_trace_ai_flutter/core/utils/geo_utils.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

ContactModel c({
  String id = 'a',
  String name = '홍길동',
  String company = '가상상사',
  String title = '부장',
  String phone = '010-0000-0000',
  String email = 'a@b.c',
  String? office,
  String? memo,
  String? cardImagePath,
  List<String> tags = const [],
  GeoPosition? geo,
}) => ContactModel(
  id: id,
  name: name,
  company: company,
  title: title,
  phone: phone,
  officePhone: office,
  email: email,
  tags: tags,
  talkingPoints: const [],
  memo: memo,
  cardImagePath: cardImagePath,
  geo: geo,
);

void main() {
  group('합쳐도 되는 경우', () {
    test('⭐ 두 기기가 같은 명함을 각각 등록했다 — id만 다르다', () {
      expect(isSafeToMergeAutomatically(c(id: '1'), c(id: '2')), isTrue);
    });

    test('🚨 사진이 한쪽에만 있어도 합칠 수 있다 — 기기마다 다른 로컬 값이다', () {
      expect(
        isSafeToMergeAutomatically(
          c(id: '1', cardImagePath: '/폴드/a.enc'),
          c(id: '2'),
        ),
        isTrue,
        reason: '사진으로 막으면 "두 기기에서 찍었으니 못 합친다"가 된다',
      );
    });

    test('메모가 한쪽에만 있어도 합칠 수 있다 — 살리면 된다', () {
      expect(
        isSafeToMergeAutomatically(c(id: '1', memo: '골프'), c(id: '2')),
        isTrue,
      );
    });

    test('좌표가 한쪽에만 있어도 합칠 수 있다', () {
      expect(
        isSafeToMergeAutomatically(
          c(id: '1', geo: const GeoPosition(lat: 37.5, lng: 127.0)),
          c(id: '2'),
        ),
        isTrue,
      );
    });
  });

  group('🚨 합치면 안 되는 경우 — 사람이 골라야 한다', () {
    test('사무실 전화가 한쪽만 다르다 — 오늘 null 로 덮이던 그 칸이다', () {
      expect(
        isSafeToMergeAutomatically(
          c(id: '1', office: '02-111-1111'),
          c(id: '2', office: '02-222-2222'),
        ),
        isFalse,
      );
    });

    test('직함이 다르다 — 승진인지 OCR 오독인지 코드는 못 가른다', () {
      expect(
        isSafeToMergeAutomatically(c(id: '1', title: '대리'), c(id: '2', title: '과장')),
        isFalse,
      );
    });

    test('이름이 다르다', () {
      expect(
        isSafeToMergeAutomatically(c(id: '1', name: '홍길동'), c(id: '2', name: '홍길순')),
        isFalse,
      );
    });

    test('메모가 서로 다르다 — 합치면 한쪽이 사라진다', () {
      expect(
        isSafeToMergeAutomatically(
          c(id: '1', memo: '골프'),
          c(id: '2', memo: '등산'),
        ),
        isFalse,
      );
    });

    test('태그가 서로 다르다 — 섞으면 만든 적 없는 목록이 된다', () {
      expect(
        isSafeToMergeAutomatically(
          c(id: '1', tags: const ['거래처']),
          c(id: '2', tags: const ['협력사']),
        ),
        isFalse,
      );
    });

    test('⭐ 좌표가 값으로 같으면 합칠 수 있다 — 두 기기가 각자 계산한 경우다', () {
      expect(
        isSafeToMergeAutomatically(
          c(id: '1', geo: const GeoPosition(lat: 37.5, lng: 127.0)),
          c(id: '2', geo: const GeoPosition(lat: 37.5, lng: 127.0)),
        ),
        isTrue,
      );
    });

    test('좌표가 서로 다르다', () {
      expect(
        isSafeToMergeAutomatically(
          c(id: '1', geo: const GeoPosition(lat: 37.5, lng: 127.0)),
          c(id: '2', geo: const GeoPosition(lat: 35.1, lng: 129.0)),
        ),
        isFalse,
      );
    });

    test('같은 명함이면 합칠 것이 없다', () {
      expect(isSafeToMergeAutomatically(c(id: '1'), c(id: '1')), isFalse);
    });
  });

  group('무엇을 살려야 하는지 알려 준다 — 안 보고 합치면 오늘을 되풀이한다', () {
    test('한쪽에만 있는 값의 이름을 돌려준다', () {
      final out = oneSidedFields(
        c(id: '1', cardImagePath: '/a.enc', memo: '골프'),
        c(id: '2'),
      );
      expect(out, containsAll(<String>['명함 사진', '메모']));
    });

    test('양쪽 다 있거나 양쪽 다 없으면 살릴 것이 없다', () {
      expect(oneSidedFields(c(id: '1'), c(id: '2')), isEmpty);
      expect(
        oneSidedFields(
          c(id: '1', memo: '골프'),
          c(id: '2', memo: '골프'),
        ),
        isEmpty,
      );
    });
  });
}

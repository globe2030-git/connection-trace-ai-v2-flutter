/// **가진 키를 차례로 시도해 연다** — 키링 (2026-09-04, 설계 문서 2단계).
///
/// ## 왜 이 능력이 필요한가
///
/// 한 사람이 계정을 둘 이상 갖게 되면(로그인 수단을 더하거나 번호로 잇거나)
/// 명함이 **서로 다른 키로 잠긴 채** 한 명함첩에 모인다. 한쪽을 전부 복호화해
/// 다른 키로 다시 암호화하는 길도 있지만, 그것은 **원본을 덮어쓴다** —
/// 중간에 끊기면 반쯤 암호화된 상태가 되고 되돌릴 수 없다.
///
/// ⭐ **키링은 아무것도 덮어쓰지 않는다. 읽는 방법만 늘린다.**
///
/// ## 왜 「어느 키인지」를 안 적어도 되나
///
/// 암호문 형식이 `nonce + ciphertext + MAC` 이라 키 식별자가 들어갈 자리가
/// 없다. 그런데 넣을 필요가 없다 — **AES-GCM 의 MAC 이 틀린 키를 반드시
/// 걸러 준다.** 이 파일이 그 성질을 실제로 확인한다.
library;

import 'package:connection_trace_ai_flutter/core/services/data_crypto_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

Future<SecretKey> newKey() => AesGcm.with256bits().newSecretKey();

void main() {
  test('⭐ 두 번째 키로 잠긴 것도 열린다 — 순서를 몰라도 된다', () async {
    final a = await newKey();
    final b = await newKey();
    final sealed = await DataCryptoService.encryptJson({'명함': '나중 키'}, b);

    final opened = await DataCryptoService.decryptJsonWithAny(sealed, [a, b]);

    expect(opened['명함'], '나중 키');
  });

  test('첫 키로 잠긴 것은 첫 시도에 열린다', () async {
    final a = await newKey();
    final b = await newKey();
    final sealed = await DataCryptoService.encryptJson({'명함': '첫 키'}, a);

    final opened = await DataCryptoService.decryptJsonWithAny(sealed, [a, b]);

    expect(opened['명함'], '첫 키');
  });

  test('🚨 가진 키가 전부 안 맞으면 실패한다 — 조용히 빈 값으로 넘어가지 않는다', () async {
    final mine = await newKey();
    final others = [await newKey(), await newKey()];
    final sealed = await DataCryptoService.encryptJson({'명함': '남의 키'}, mine);

    expect(
      () => DataCryptoService.decryptJsonWithAny(sealed, others),
      throwsA(isA<DataDecryptionException>()),
      reason: '못 읽었으면 못 읽었다고 해야 부르는 쪽이 「없다」와 가를 수 있다',
    );
  });

  test('🚨 키가 하나도 없으면 실패한다 — 「키가 없다」도 「못 읽는다」다', () async {
    final sealed = await DataCryptoService.encryptJson({'명함': 'x'}, await newKey());

    expect(
      () => DataCryptoService.decryptJsonWithAny(sealed, const []),
      throwsA(isA<DataDecryptionException>()),
    );
  });

  test('키가 하나뿐일 때는 예전과 똑같이 동작한다 — 이번 변경이 동작을 안 바꾼다', () async {
    final only = await newKey();
    final sealed = await DataCryptoService.encryptJson({'명함': '하나'}, only);

    final viaOne = await DataCryptoService.decryptJson(sealed, only);
    final viaRing = await DataCryptoService.decryptJsonWithAny(sealed, [only]);

    expect(viaRing, viaOne);
  });
}

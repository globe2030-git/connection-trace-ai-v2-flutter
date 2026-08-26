import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute;

/// 위변조되었거나(MAC 불일치) 잘못된 키로 복호화를 시도했을 때 던지는 예외.
///
/// 조용히 빈 데이터로 넘어가면 사용자가 "명함이 다 사라졌다"고 오해할 수
/// 있으므로, 호출자(리포지토리 계층)가 반드시 이 예외를 잡아 명시적으로
/// 처리(레거시 평문 폴백 시도 → 그래도 실패하면 빈 상태로 시작)하도록
/// 강제한다.
class DataDecryptionException implements Exception {
  final String message;
  final Object? cause;

  DataDecryptionException(this.message, [this.cause]);

  @override
  String toString() =>
      'DataDecryptionException: $message${cause != null ? ' (원인: $cause)' : ''}';
}

/// 명함/프로필 JSON을 AES-256-GCM으로 암호화·복호화한다.
///
/// 설계상 한계(정직하게 명시): 이 서비스 자체는 순수한 대칭키 암/복호화
/// 로직일 뿐이고, 키 자체가 어디에 보관되는지(로컬 기기 vs 서버)는
/// [EncryptionKeyService]가 결정한다. 현재 설계에서는 계정 복구를 위해
/// 키가 Firestore에도 함께 저장되므로, 이 암호화는 "로컬 기기 유출/분실",
/// "백업 파일 유출", "서버 DB 일부 유출" 같은 시나리오를 방어하지만,
/// Firestore 프로젝트 관리자 권한을 가진 사람으로부터의 완전한 제로-지식
/// 보호는 아니다(그 사람은 같은 문서에서 키도 함께 읽을 수 있음). 완전한
/// 키 분리는 Cloud Functions/KMS 인프라(현재 Blaze 요금제 대기 중)가
/// 갖춰진 뒤 별도로 강화할 예정.
class DataCryptoService {
  DataCryptoService._();

  static final AesGcm _algorithm = AesGcm.with256bits();

  /// [json]을 UTF-8 JSON 문자열로 직렬화한 뒤 AES-256-GCM으로 암호화한다.
  /// 반환값은 `nonce + ciphertext + MAC`을 이어붙여 base64 문자열 하나로
  /// 인코딩한 것 — 별도 필드 구조 없이 문자열 하나로 저장/전송하기 위함.
  /// ## ⚠️ 크기와 무관하게 항상 별도 isolate에서 돈다 (추가 481)
  ///
  /// 작은 데이터는 그냥 여기서 하는 게 빠르지 않을까 싶어 **경계값을 두는
  /// 안을 검토했다가 버렸다.** 재 보니 띄우는 값이 생각보다 작았다.
  ///
  /// ```
  /// 명함 한 장 크기(약 400B)를 500번 암호화   맥 실측, 2026-08-25
  ///   인라인   13ms
  ///   isolate  41ms      → 500번에 28ms, 한 번에 0.06ms
  /// ```
  ///
  /// 📌 **`data_backup_service.rebackupAllContacts`가 명함마다 한 번씩
  /// 부른다**(반복문 안). 그래서 이 경우를 재 봤는데, 28ms는 같은 함수가
  /// 이어서 하는 Firestore 일괄 쓰기(네트워크) 옆에서 눈에 띄지 않는다.
  ///
  /// **경계값을 두면 분기가 하나 늘고 그 분기를 시험해야 한다.** 아끼는 것이
  /// 28ms뿐이라 사지 않았다.
  static Future<String> encryptJson(
    Map<String, dynamic> json,
    SecretKey key,
  ) async {
    final plainBytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final keyBytes = Uint8List.fromList(await key.extractBytes());
    return compute(_encryptWorker, <Uint8List>[plainBytes, keyBytes]);
  }

  /// 별도 isolate에서 도는 실제 암호화. `compute()`가 부르므로 **톱레벨/정적
  /// 함수여야 하고 인자가 하나여야 한다.**
  ///
  /// ⚠️ [SecretKey] 객체를 그대로 넘기지 않고 **바이트로 풀어 넘긴 뒤 여기서
  /// 다시 만든다.** `SecretKey`가 isolate 경계를 넘을 수 있는지에 기대지
  /// 않기 위함이다 — 넘어가더라도 구현이 바뀌면 조용히 깨질 자리다.
  /// `Uint8List`는 확실히 넘어간다.
  static Future<String> _encryptWorker(List<Uint8List> args) async {
    final algorithm = AesGcm.with256bits();
    final key = SecretKey(args[1]);
    final nonce = algorithm.newNonce();
    final secretBox = await algorithm.encrypt(
      args[0],
      secretKey: key,
      nonce: nonce,
    );
    // nonce(12B) + ciphertext(가변) + mac(16B) 순서로 이어붙인다. 길이가
    // 고정된 nonce/mac 덕분에 복호화 시 별도 구분자 없이 잘라낼 수 있다.
    final combined = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64Encode(combined);
  }

  /// 임의의 바이트(예: 명함 이미지 JPG)를 AES-256-GCM으로 암호화한다.
  /// 반환값은 `nonce(12B) + ciphertext + MAC(16B)`을 이어붙인 바이트 —
  /// 그대로 파일로 저장하면 된다(P1-9: 명함 이미지 로컬 암호화).
  static Future<Uint8List> encryptBytes(
    List<int> plainBytes,
    SecretKey key,
  ) async {
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      plainBytes,
      secretKey: key,
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  /// [encryptBytes]로 만든 바이트를 원래 바이트로 복원한다. 인증 실패(MAC
  /// 불일치)·형식 오류면 [DataDecryptionException].
  static Future<Uint8List> decryptBytes(
    Uint8List combined,
    SecretKey key,
  ) async {
    const nonceLength = 12;
    const macLength = 16;
    if (combined.length < nonceLength + macLength) {
      throw DataDecryptionException('암호문 길이가 너무 짧음');
    }
    final nonce = combined.sublist(0, nonceLength);
    final mac = combined.sublist(combined.length - macLength);
    final cipherText = combined.sublist(nonceLength, combined.length - macLength);
    try {
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
      final plain = await _algorithm.decrypt(secretBox, secretKey: key);
      return Uint8List.fromList(plain);
    } catch (e) {
      throw DataDecryptionException('이미지 복호화 실패(위변조 또는 잘못된 키)', e);
    }
  }

  /// [encryptJson]으로 만든 base64 문자열을 원래의 JSON 맵으로 복원한다.
  ///
  /// 인증 실패(MAC 불일치 — 위변조되었거나 다른 키로 암호화된 데이터)나
  /// 형식이 잘못된 입력이면 [DataDecryptionException]을 던진다. 절대 조용히
  /// 삼키지 않는다 — 호출자가 레거시 평문 폴백 등 명확한 정책을 적용해야
  /// 하기 때문.
  static Future<Map<String, dynamic>> decryptJson(
    String encoded,
    SecretKey key,
  ) async {
    late final Uint8List combined;
    try {
      combined = base64Decode(encoded);
    } catch (e) {
      throw DataDecryptionException('base64 디코딩 실패', e);
    }

    const nonceLength = 12; // AES-GCM 표준 nonce 길이
    const macLength = 16; // AES-GCM MAC(태그) 길이
    if (combined.length < nonceLength + macLength) {
      throw DataDecryptionException('암호문 길이가 너무 짧음');
    }

    final keyBytes = Uint8List.fromList(await key.extractBytes());
    final result = await compute(
      _decryptWorker,
      <Uint8List>[combined, keyBytes],
    );

    // ⚠️ 실패를 **예외가 아니라 값으로** 돌려받는다. isolate 경계 너머로
    // 던지려면 예외 객체 자체가 넘어갈 수 있어야 하는데, cryptography가
    // 던지는 SecretBoxAuthenticationError가 그럴 수 있는지에 기댈 수 없다.
    // 넘어가더라도 패키지 구현이 바뀌면 조용히 깨질 자리다.
    final errorText = result[1] as String?;
    if (errorText != null) {
      // cryptography 패키지는 MAC 불일치 시 SecretBoxAuthenticationError를
      // 던진다 — 위변조/잘못된 키 케이스를 모두 이 하나의 예외 타입으로
      // 통일해 호출자가 구분 없이 처리할 수 있게 한다.
      throw DataDecryptionException('복호화 실패(위변조 또는 잘못된 키)', errorText);
    }

    final decoded = jsonDecode(result[0] as String);
    if (decoded is! Map<String, dynamic>) {
      throw DataDecryptionException('복호화 결과가 JSON 객체가 아님');
    }
    return decoded;
  }

  /// 별도 isolate에서 도는 실제 복호화. 성공하면 `[JSON 문자열, null]`,
  /// 실패하면 `[null, 오류 설명]`을 돌려준다.
  ///
  /// ⚠️ **던지지 않고 돌려준다.** 위 [decryptJson] 주석 참고.
  ///
  /// 📌 `jsonDecode`는 여기서 하지 않고 부르는 쪽에 남겼다 — 여기서 하면
  /// 큰 Map을 isolate 경계로 복사해야 하는데, 문자열 하나를 넘기는 편이
  /// 싸다. 무거운 것(base64 디코딩·AES)은 이미 여기로 넘어와 있다.
  static Future<List<Object?>> _decryptWorker(List<Uint8List> args) async {
    const nonceLength = 12;
    const macLength = 16;
    final combined = args[0];
    try {
      final algorithm = AesGcm.with256bits();
      final secretBox = SecretBox(
        combined.sublist(nonceLength, combined.length - macLength),
        nonce: combined.sublist(0, nonceLength),
        mac: Mac(combined.sublist(combined.length - macLength)),
      );
      final plainBytes = await algorithm.decrypt(
        secretBox,
        secretKey: SecretKey(args[1]),
      );
      return <Object?>[utf8.decode(plainBytes), null];
    } catch (e) {
      return <Object?>[null, '$e'];
    }
  }
}

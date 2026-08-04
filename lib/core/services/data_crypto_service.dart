import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

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
  static Future<String> encryptJson(
    Map<String, dynamic> json,
    SecretKey key,
  ) async {
    final plainBytes = utf8.encode(jsonEncode(json));
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      plainBytes,
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

    final nonce = combined.sublist(0, nonceLength);
    final mac = combined.sublist(combined.length - macLength);
    final cipherText = combined.sublist(
      nonceLength,
      combined.length - macLength,
    );

    try {
      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(mac),
      );
      final plainBytes = await _algorithm.decrypt(secretBox, secretKey: key);
      final decoded = jsonDecode(utf8.decode(plainBytes));
      if (decoded is! Map<String, dynamic>) {
        throw DataDecryptionException('복호화 결과가 JSON 객체가 아님');
      }
      return decoded;
    } on DataDecryptionException {
      rethrow;
    } catch (e) {
      // cryptography 패키지는 MAC 불일치 시 SecretBoxAuthenticationError를
      // 던진다 — 위변조/잘못된 키 케이스를 모두 이 하나의 예외 타입으로
      // 통일해 호출자가 구분 없이 처리할 수 있게 한다.
      throw DataDecryptionException('복호화 실패(위변조 또는 잘못된 키)', e);
    }
  }
}

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connection_trace_ai_flutter/core/services/data_crypto_service.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';

void main() {
  group('DataCryptoService', () {
    test('암호화 후 복호화하면 원본 JSON과 동일하다', () async {
      final key = await AesGcm.with256bits().newSecretKey();
      final original = {
        'name': '문정순',
        'phone': '010-1234-5678',
        'nested': {
          'a': 1,
          'b': [1, 2, 3],
        },
      };

      final encrypted = await DataCryptoService.encryptJson(original, key);
      // 결과가 알아볼 수 없는 형태(원문이 그대로 노출되지 않음)인지도 함께 확인.
      expect(encrypted, isNot(contains('문정순')));
      expect(encrypted, isNot(contains('010-1234-5678')));

      final decrypted = await DataCryptoService.decryptJson(encrypted, key);
      expect(decrypted, equals(original));
    });

    test('잘못된 키로 복호화하면 예외를 던진다', () async {
      final key = await AesGcm.with256bits().newSecretKey();
      final wrongKey = await AesGcm.with256bits().newSecretKey();
      final encrypted = await DataCryptoService.encryptJson({
        'secret': 'value',
      }, key);

      expect(
        () => DataCryptoService.decryptJson(encrypted, wrongKey),
        throwsA(isA<DataDecryptionException>()),
      );
    });

    test('위변조된(잘린) 암호문은 예외를 던진다', () async {
      final key = await AesGcm.with256bits().newSecretKey();
      final encrypted = await DataCryptoService.encryptJson({
        'secret': 'value',
      }, key);
      final tampered = encrypted.substring(0, encrypted.length - 4);

      expect(
        () => DataCryptoService.decryptJson(tampered, key),
        throwsA(isA<DataDecryptionException>()),
      );
    });

    test('⭐ 바이트(명함 이미지) 암호화 후 복호화하면 원본과 동일 (P1-9)', () async {
      final key = await AesGcm.with256bits().newSecretKey();
      // JPG 헤더 흉내 + 임의 바이트로 이미지 바이트를 대신한다.
      final original = List<int>.generate(2000, (i) => (i * 31 + 7) % 256);

      final encrypted = await DataCryptoService.encryptBytes(original, key);
      // 암호문에 원본이 그대로 들어있지 않다(앞부분이 원본과 다름).
      expect(encrypted.sublist(0, 16), isNot(equals(original.sublist(0, 16))));

      final decrypted = await DataCryptoService.decryptBytes(encrypted, key);
      expect(decrypted, equals(original));
    });

    test('바이트 복호화도 잘못된 키면 예외를 던진다', () async {
      final key = await AesGcm.with256bits().newSecretKey();
      final wrongKey = await AesGcm.with256bits().newSecretKey();
      final encrypted = await DataCryptoService.encryptBytes([1, 2, 3, 4], key);

      expect(
        () => DataCryptoService.decryptBytes(encrypted, wrongKey),
        throwsA(isA<DataDecryptionException>()),
      );
    });
  });

  group('ContactsRepository 암호화/레거시 마이그레이션', () {
    ContactModel makeContact() => const ContactModel(
      id: 'legacy-1',
      name: '문정순',
      company: '테스트상사',
      title: '대표',
      phone: '010-0000-0000',
      email: 'moon@example.com',
      tags: [],
      talkingPoints: [],
    );

    test(
      '기존 평문 저장분은 uid 없이도 그대로 읽히고, 로그인 후 자동으로 암호화되어 재저장된다',
      () async {
        final legacyJson = jsonEncode([makeContact().toJson()]);
        SharedPreferences.setMockInitialValues({
          'flutter.saved_contacts_v2': legacyJson,
        });

        final repo = ContactsRepository();
        // 생성자에서 비동기로 로드하므로 완료를 기다린다.
        await Future.delayed(const Duration(milliseconds: 50));

        expect(repo.contacts, hasLength(1));
        expect(repo.contacts.first.name, '문정순');

        // 아직 로그인 전이라 평문 그대로 남아있어야 한다.
        final prefsBefore = await SharedPreferences.getInstance();
        final rawBefore = prefsBefore.getString('saved_contacts_v2');
        expect(rawBefore, contains('문정순'));

        // 로그인(uid 부여) 시점에 자동으로 암호화되어 재저장돼야 한다.
        await repo.setCurrentUid('test-uid-1');
        await Future.delayed(const Duration(milliseconds: 50));

        final prefsAfter = await SharedPreferences.getInstance();
        final rawAfter = prefsAfter.getString('saved_contacts_v2');
        expect(rawAfter, isNotNull);
        expect(rawAfter, isNot(contains('문정순')));

        // 메모리 상의 데이터는 여전히 그대로 유지되어야 한다(사용자 입장에서
        // 데이터가 사라지면 안 됨).
        expect(repo.contacts, hasLength(1));
        expect(repo.contacts.first.name, '문정순');
      },
    );

    test('새로 추가한 명함은 로그인 상태에서 곧바로 암호화되어 저장된다', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = ContactsRepository();
      await repo.setCurrentUid('owner-uid');
      repo.addContact(makeContact());
      await Future.delayed(const Duration(milliseconds: 50));

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('saved_contacts_v2');
      expect(raw, isNotNull);
      expect(raw, isNot(contains('문정순')));
      expect(raw, isNot(contains('010-0000-0000')));
    });

    test('손상되었거나 다른 키로 암호화된 데이터는 크래시 없이 빈 목록으로 시작한다', () async {
      SharedPreferences.setMockInitialValues({
        // 유효한 JSON도, 유효한 base64도 아닌 쓰레기 문자열.
        'flutter.saved_contacts_v2': 'not-json-not-base64-garbage!!!',
      });

      final repo = ContactsRepository();
      await Future.delayed(const Duration(milliseconds: 50));
      // 로그인 전에는 키가 없어 복호화를 시도조차 하지 않고 대기 상태.
      expect(repo.contacts, isEmpty);

      await repo.setCurrentUid('some-uid');
      await Future.delayed(const Duration(milliseconds: 50));
      // 로그인 후 복호화를 시도하지만 실패 → 크래시 없이 빈 목록 유지.
      expect(repo.contacts, isEmpty);
    });
  });
}

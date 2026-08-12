import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/repositories/contacts_repository.dart';
import 'package:connection_trace_ai_flutter/presentation/features/wallet/view_models/wallet_view_model.dart';

/// 명함 지갑 검색 회귀 테스트.
///
/// 주변 탭 검색은 소문자로 바꿔 비교하는데 지갑 검색만 원문 그대로 비교해서,
/// 'SAMSUNG'으로 저장된 회사명이 'samsung'으로는 검색되지 않았다(영문 회사명에서
/// 흔한 일). 같은 앱 안에서 두 검색이 다르게 동작하던 것을 맞춘다.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ContactModel contact({
    required String id,
    required String name,
    String company = '',
    String title = '',
  }) => ContactModel(
    id: id,
    name: name,
    company: company,
    title: title,
    phone: '010-0000-0000',
    email: 'a@b.c',
    tags: const [],
    talkingPoints: const [],
  );

  /// 로그인 전(uid 없음) 평문 저장 형식으로 명함을 심어 둔다.
  void seed(List<ContactModel> contacts) {
    final entries = contacts.map((c) {
      final j = c.toJson();
      final parts = j.entries.map((e) {
        final v = e.value;
        if (v == null) return '"${e.key}":null';
        if (v is num) return '"${e.key}":$v';
        if (v is bool) return '"${e.key}":$v';
        if (v is List) return '"${e.key}":[]';
        return '"${e.key}":"${v.toString().replaceAll('"', r'\"')}"';
      });
      return '{${parts.join(',')}}';
    });
    SharedPreferences.setMockInitialValues({
      'saved_contacts_v2': '[${entries.join(',')}]',
    });
  }

  Future<WalletViewModel> viewModelWith(List<ContactModel> contacts) async {
    seed(contacts);
    final repo = ContactsRepository();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return WalletViewModel(contactsRepository: repo);
  }

  test('⭐ 대소문자가 달라도 회사명으로 검색된다', () async {
    final vm = await viewModelWith([
      contact(id: '1', name: '홍길동', company: 'SAMSUNG'),
      contact(id: '2', name: '김서연', company: '커넥션센스'),
    ]);

    vm.setSearchTerm('samsung');
    expect(vm.filteredContacts.map((c) => c.id), ['1']);

    vm.setSearchTerm('SAMSUNG');
    expect(vm.filteredContacts.map((c) => c.id), ['1']);
  });

  test('앞뒤 공백을 넣어도 찾는다', () async {
    final vm = await viewModelWith([
      contact(id: '1', name: '홍길동', company: 'Acme'),
    ]);

    vm.setSearchTerm('  acme  ');
    expect(vm.filteredContacts.map((c) => c.id), ['1']);
  });

  test('이름·직함으로도 찾고, 없는 말은 못 찾는다', () async {
    final vm = await viewModelWith([
      contact(id: '1', name: '홍길동', company: 'Acme', title: 'CTO'),
    ]);

    vm.setSearchTerm('길동');
    expect(vm.filteredContacts, hasLength(1));

    vm.setSearchTerm('cto');
    expect(vm.filteredContacts, hasLength(1));

    vm.setSearchTerm('없는회사');
    expect(vm.filteredContacts, isEmpty);
  });

  test('검색어가 비어 있으면 전체가 나온다', () async {
    final vm = await viewModelWith([
      contact(id: '1', name: '홍길동'),
      contact(id: '2', name: '김서연'),
    ]);

    vm.setSearchTerm('');
    expect(vm.filteredContacts, hasLength(2));
  });
}

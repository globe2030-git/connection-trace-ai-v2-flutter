// 명함 그룹 참조(ContactModel.groupIds, 추가 427)의 저장·복원·마이그레이션을
// 고정한다. 태그와 같은 취급이라는 법무 검토 결론(group-feature-legal-note-
// 2026-08-23.md 질문 2)대로 서버 백업(toBackupJson)에도 실려야 한다 — 안
// 그러면 다른 기기에서 그룹 지정이 사라진다.
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

ContactModel _base({List<String>? groupIds}) => ContactModel(
  id: 'c1',
  name: '홍길동',
  company: '테스트',
  title: '담당자',
  phone: '010-1234-5678',
  email: 'a@b.com',
  tags: const ['신규'],
  talkingPoints: const [],
  groupIds: groupIds ?? const [],
);

void main() {
  group('명함 그룹 참조(groupIds)', () {
    test('toJson(기기)에 들어간다', () {
      final j = _base(groupIds: ['g1', 'g2']).toJson();
      expect(j['groupIds'], ['g1', 'g2']);
    });

    test('⭐ toBackupJson(서버)에도 들어간다 — 태그와 같은 취급, 동기화 대상', () {
      final j = _base(groupIds: ['g1', 'g2']).toBackupJson();
      expect(j['groupIds'], ['g1', 'g2']);
    });

    test('fromJson이 그대로 복원한다(라운드트립)', () {
      final original = _base(groupIds: ['g1', 'g2']);
      final restored = ContactModel.fromJson(original.toJson());
      expect(restored.groupIds, ['g1', 'g2']);
    });

    test('⭐ 옛 저장분(키 자체가 없음)은 빈 목록으로 — 마이그레이션 불필요', () {
      final legacy = _base().toJson()..remove('groupIds');
      expect(legacy.containsKey('groupIds'), isFalse);
      expect(ContactModel.fromJson(legacy).groupIds, isEmpty);
    });

    test('기본값은 빈 목록이다(그룹을 지정한 적 없는 명함)', () {
      expect(const ContactModel(
        id: 'c2',
        name: '김철수',
        company: '',
        title: '',
        phone: '010-0000-0000',
        email: 'x@y.com',
        tags: [],
        talkingPoints: [],
      ).groupIds, isEmpty);
    });

    test('copyWith가 groupIds를 전달·유지한다', () {
      final c = _base(groupIds: ['g1']);
      final unchanged = c.copyWith(name: '이영희');
      expect(unchanged.groupIds, ['g1']);

      final changed = c.copyWith(groupIds: ['g2', 'g3']);
      expect(changed.groupIds, ['g2', 'g3']);
      expect(changed.name, '홍길동');
    });

    test('copyWith로 빈 목록으로도 바꿀 수 있다(그룹 전부 해제)', () {
      final c = _base(groupIds: ['g1']);
      final cleared = c.copyWith(groupIds: []);
      expect(cleared.groupIds, isEmpty);
    });
  });
}

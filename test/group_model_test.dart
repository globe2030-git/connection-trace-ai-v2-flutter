// GroupModel의 저장/복원 왕복을 고정한다(추가 427).
import 'package:connection_trace_ai_flutter/data/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupModel', () {
    test('toJson → fromJson 왕복에서 값이 그대로 살아남는다', () {
      final createdAt = DateTime.utc(2026, 8, 23, 10, 30);
      final original = GroupModel(
        id: 'g_1',
        name: '삼성전자 사람들',
        createdAt: createdAt,
      );

      final restored = GroupModel.fromJson(original.toJson());

      expect(restored.id, 'g_1');
      expect(restored.name, '삼성전자 사람들');
      expect(restored.createdAt, createdAt);
    });

    test('copyWith로 이름만 바꿀 수 있다 — id·생성일은 그대로', () {
      final createdAt = DateTime.utc(2026, 8, 23);
      final original = GroupModel(id: 'g_1', name: '옛 이름', createdAt: createdAt);

      final renamed = original.copyWith(name: '새 이름');

      expect(renamed.id, 'g_1');
      expect(renamed.name, '새 이름');
      expect(renamed.createdAt, createdAt);
    });
  });
}

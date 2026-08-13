// 내 프로필의 생일(월·일) 저장 형식 검증.
//
// 2026-08-13 추가. 생일은 "MM-DD"로 **0을 채운 두 자리**여야 한다 — 나중에
// "이번 달 생일자"를 문자열 범위(>= "10-01" && <= "10-31")로 뽑을 계획이라,
// "10-1"이 섞이면 정렬이 깨져 조회에서 조용히 빠진다. 화면을 봐서는 알 수
// 없는 종류의 결함이라 형식 자체를 코드 레벨에서 고정해 둔다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/data/models/my_profile_model.dart';

void main() {
  group('생일 저장 형식 — 0을 채운 MM-DD', () {
    test('한 자리 월·일도 두 자리로 채운다', () {
      expect(MyProfileModel.formatMonthDay(1, 5), '01-05');
    });

    test('두 자리는 그대로 둔다', () {
      expect(MyProfileModel.formatMonthDay(10, 1), '10-01');
      expect(MyProfileModel.formatMonthDay(12, 25), '12-25');
    });

    test('문자열 정렬이 날짜 순서와 같다 — 범위 조회의 전제', () {
      final days = [
        MyProfileModel.formatMonthDay(10, 9)!,
        MyProfileModel.formatMonthDay(2, 28)!,
        MyProfileModel.formatMonthDay(10, 10)!,
        MyProfileModel.formatMonthDay(1, 1)!,
      ]..sort();
      expect(days, ['01-01', '02-28', '10-09', '10-10']);
    });

    test('월만 있고 일이 없으면 저장하지 않는다', () {
      expect(MyProfileModel.formatMonthDay(10, null), isNull);
      expect(MyProfileModel.formatMonthDay(null, 5), isNull);
      expect(MyProfileModel.formatMonthDay(null, null), isNull);
    });

    test('범위를 벗어난 값은 저장하지 않는다', () {
      expect(MyProfileModel.formatMonthDay(0, 5), isNull);
      expect(MyProfileModel.formatMonthDay(13, 5), isNull);
      expect(MyProfileModel.formatMonthDay(10, 0), isNull);
      expect(MyProfileModel.formatMonthDay(10, 32), isNull);
    });
  });

  group('생일 읽기 — 저장값에서 월·일 되찾기', () {
    MyProfileModel profileWith(String? birthMonthDay) => MyProfileModel(
      name: '테스터',
      title: '',
      company: '',
      phone: '',
      email: '',
      address: '',
      birthMonthDay: birthMonthDay,
    );

    test('저장한 값을 그대로 되읽는다', () {
      final p = profileWith('03-07');
      expect(p.birthMonth, 3);
      expect(p.birthDay, 7);
    });

    test('생일이 없으면 월·일 모두 null', () {
      final p = profileWith(null);
      expect(p.birthMonth, isNull);
      expect(p.birthDay, isNull);
    });

    test('형식이 깨진 값에도 예외를 던지지 않는다', () {
      expect(profileWith('3월 7일').birthMonth, isNull);
      expect(profileWith('0307').birthDay, isNull);
    });

    test('저장·복원을 거쳐도 값이 유지된다', () {
      final restored = MyProfileModel.fromJson(profileWith('12-25').toJson());
      expect(restored.birthMonthDay, '12-25');
    });

    test('생일 필드가 없던 시절의 데이터도 읽힌다 — 마이그레이션 불필요', () {
      final legacy = MyProfileModel.fromJson({
        'name': '테스터',
        'title': '',
        'company': '',
        'phone': '',
        'email': '',
        'address': '',
      });
      expect(legacy.birthMonthDay, isNull);
      expect(legacy.name, '테스터');
    });

    test('copyWith로 생일을 지울 수 있다', () {
      final cleared = profileWith('12-25').copyWith(clearBirthday: true);
      expect(cleared.birthMonthDay, isNull);
    });
  });
}

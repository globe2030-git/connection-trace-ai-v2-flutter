import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨 **진단 화면이 개발 용어로 말하지 않는지** 지킨다(2026-08-28 사용자 요청).
///
/// 「명함 인식 진단」은 **숫자를 읽고 판단하는 화면**이다. 이름이 막히면
/// 숫자를 못 읽고, 그러면 화면 자체가 소용없어진다.
///
/// 실제로 이 화면을 처음 열어 본 사용자가 **"백필이 무슨 말이야?"** 라고
/// 물었다. backfill 은 "뒤늦게 채워 넣기"라는 영어 개발 용어라, 관리자
/// 화면이라 해도 그대로 두면 안 되는 말이었다("좌표 채우기"로 바꿨다).
///
/// ## ⚠️ 코드 쪽 이름은 여기서 막지 않는다
///
/// `GeoBackfillService`·`backfillMissingGeo` 는 그대로 둔다. 그것까지 바꾸면
/// 이 저장소의 기록·주석과 이름이 어긋나 **검색이 끊긴다.** 여기서 지키는
/// 것은 **화면에 나가는 말**뿐이라, 주석은 걷어 내고 본다.
void main() {
  /// 주석을 걷어 낸 소스. **왜 그 말을 버렸는지 주석에 남기는 것이 이 저장소의
  /// 방식**이라, 그 설명이 "그 말이 아직 있다"로 걸리면 남길 수가 없어진다.
  String codeOf(String path) => File(path)
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  /// 화면에 나가는 **문자열 리터럴만** 모은다. 코드 이름
  /// (`backfillMissingGeo` 등)까지 보면 거짓 실패가 난다 — 실제로 첫 판이
  /// 그렇게 걸렸다.
  final literals = RegExp(r"'([^'\n]*)'")
      .allMatches(
        codeOf('lib/presentation/features/settings/views/ocr_stats_view.dart'),
      )
      .map((m) => m.group(1)!)
      // import 경로는 화면에 안 나간다. 파일 이름에 backfill 이 들어 있어
      // 빼지 않으면 거짓 실패가 난다.
      .where((v) => !v.endsWith('.dart'))
      .join('\n');

  /// 화면에 그대로 나가면 뜻이 안 통하는 말들.
  const forbidden = <String, String>{
    '백필': '"좌표 채우기" — 사용자가 실제로 뜻을 물었던 말이다',
    'backfill': '한글로 쓴다',
    '지오코딩': '"주소 → 좌표 변환"',
    '폴백': '이 화면은 "OS 폴백 성공"으로 쓰고 있다. 바꿀 때 함께 본다',
  };

  group('🚨 진단 화면은 개발 용어로 말하지 않는다', () {
    for (final entry in forbidden.entries) {
      // 폴백은 아직 화면에 남아 있다 — 지금 막으면 거짓 실패가 된다.
      // 이 목록에 둔 것은 "다음에 손댈 때 함께 본다"는 표시다.
      if (entry.key == '폴백') continue;
      test('⭐ "${entry.key}" 이 화면 문구에 없다', () {
        expect(
          literals.contains(entry.key),
          isFalse,
          reason: '대신 쓸 말: ${entry.value}',
        );
      });
    }
  });
}

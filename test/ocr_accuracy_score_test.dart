// 정답지와 대조해 **필드별 정확도**를 낸다.
//
// 왜 필요한가: 그동안 잴 수 있는 것이 **채움률**뿐이었다. 값이 들어갔는지만
// 세고 맞는지는 보지 않아서, "오분류 0장"이라고 적어 둔 수치가 사실은 정확도가
// 아니었다(backlog 추가 198에서 정정). 정답지가 생겨야 정확도로 잴 수 있고,
// 이 파일이 그 정답지를 읽는 쪽이다.
//
// 정답지는 `tool/ocr_review/index.html`(검수 도구)이 만든다.
//
// ## 쓰는 법
//
// ```bash
// TSV=~/card-ocr-data/scan_result.tsv \
// TRUTH=~/card-ocr-data/ocr_truth.tsv \
// flutter test test/ocr_accuracy_score_test.dart
// ```
//
// ⚠️ 두 파일이 없으면 **조용히 건너뛴다** — CI에는 개인정보인 이 파일들이
// 없기 때문이다. 그래서 이 테스트는 "실패하지 않는 것"이 목적이 아니라
// **숫자를 뽑는 것**이 목적이다. 통과 여부가 아니라 출력을 봐야 한다.
//
// ## 무엇을 재는가
//
// | 판정 | 뜻 |
// |---|---|
// | 일치 | 추출값 = 정답 |
// | 틀림 | 둘 다 값이 있는데 다름 |
// | 미검출 | 명함에는 있는데 못 찾음 |
// | 오검출 | 명함에 없는데 값이 들어감 |
// | 둘 다 빔 | 명함에 없고 인식도 안 함 → **분모에서 제외** |
//
// "둘 다 빔"을 빼는 이유: 명함에 원래 전화가 없는 경우(card_134)까지 "맞혔다"고
// 세면 정확도가 부풀려진다. 없는 것을 못 찾은 것은 공도 과도 아니다.
import 'dart:io';

import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _fields = [
  '이름',
  '회사',
  '직함',
  // 2026-08-19(추가 321): 부서를 직함에서 뗐다. 정답지에도 '정답_부서' 칸이
  // 생겼고, 46장이 이 칸으로 갈렸다.
  '부서',
  '휴대폰',
  '사무실',
  '팩스',
  '이메일',
  '홈페이지',
  '우편번호',
  '주소',
  '상세주소',
];

/// 비교 전 정규화. 공백과 **칸막이 기호**만 정리한다 — 그 이상 손대면
/// "맞다고 쳐 주는" 범위가 슬금슬금 넓어져 정확도가 부풀려진다.
///
/// ## 왜 칸막이 기호를 무시하나 (2026-08-17, 추가 286)
///
/// 명함에 `부장 | 스포츠기획팀`처럼 **막대기로 칸을 나눠 인쇄**한 것이 흔한데,
/// **OCR이 그 막대기를 읽을 때도 있고 놓칠 때도 있다.** 그래서 같은 값이
/// 막대기 하나 때문에 틀린 것으로 세어졌다(card_20 · card_113).
///
/// ⚠️ **정답은 "명함에 뭐라고 쓰여 있나"이지 "인식이 뭘 읽을 수 있나"가
/// 아니다.** 읽을 수 있는 것만 정답으로 적으면 **정답지가 파서를 따라가게
/// 되고**, 그건 씨앗값 문제(추가 280)와 같은 자리다. 그래서 정답지를
/// 되돌리지 않고 **자를 고쳤다.**
///
/// ## ⚠️ `/`는 **일부러 안 지운다**
///
/// `/`는 칸막이가 아니라 **내용**인 경우가 많다 — `영업대표/부장`,
/// `Module/Pack개발그룹`, 홈페이지의 `https://`. 지우면 값이 달라진다.
/// 실측에서도 `/` 때문에 틀린 장은 없었다. **근거가 있는 것만 넓힌다.**
String _norm(String v) => v
    .replaceAll(RegExp(r'[|·｜]'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

Map<String, Map<String, String>> _readTsv(File file, String keyColumn) {
  final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
  if (lines.isEmpty) return {};
  final header = lines.first.split('\t');
  final out = <String, Map<String, String>>{};
  for (final line in lines.skip(1)) {
    final cells = line.split('\t');
    final row = <String, String>{};
    for (var i = 0; i < header.length; i++) {
      row[header[i]] = i < cells.length ? cells[i] : '';
    }
    final key = row[keyColumn] ?? '';
    if (key.isNotEmpty) out[key] = row;
  }
  return out;
}

void main() {
  // ⚠️ 자(채점 기준)를 넓히는 것은 위험하다. **넓힌 만큼만 넓혔는지** 여기서
  // 고정한다. 이 검사가 없으면 "맞다고 쳐 주는" 범위가 슬금슬금 넓어져
  // 정확도가 부풀려진다 — 이 저장소가 실제로 겪은 일이다(추가 198·212).
  group('비교 자 — 넓힌 만큼만 넓혔나 (추가 286)', () {
    test('칸막이 기호는 무시한다', () {
      // 명함에 인쇄된 막대기를 OCR이 읽을 때도, 놓칠 때도 있다.
      expect(_norm('부장 | 스포츠기획팀'), _norm('부장 스포츠기획팀'));
      expect(_norm('경영지원실 인사팀 | 팀장'), _norm('경영지원실 인사팀 팀장'));
      expect(_norm('가·나'), _norm('가 나'));
    });

    test('⚠️ `/`는 무시하지 않는다 — 칸막이가 아니라 내용이다', () {
      // `영업대표/부장`, `Module/Pack개발그룹`, `https://…`
      expect(_norm('영업대표/부장'), isNot(_norm('영업대표 부장')));
      expect(_norm('https://a.com'), 'https://a.com');
    });

    test('⚠️ 글자와 숫자는 손대지 않는다', () {
      expect(_norm('02-1234-5678'), '02-1234-5678');
      expect(_norm('(주)한빛'), '(주)한빛');
      expect(_norm('a@b.co.kr'), 'a@b.co.kr');
    });

    test('⚠️ 서로 다른 값이 같아지지 않는다', () {
      expect(_norm('부장'), isNot(_norm('차장')));
      expect(_norm('02-1234-5678'), isNot(_norm('02-1234-5679')));
    });
  });

  test('정답지 대비 필드별 정확도', () {
    final scanPath = Platform.environment['TSV'];
    final truthPath = Platform.environment['TRUTH'];
    if (scanPath == null || truthPath == null) {
      // ignore: avoid_print
      print(
        '건너뜀 — 환경변수 TSV(일괄 스캔 결과)와 TRUTH(정답지)가 필요합니다.\n'
        '예: TSV=~/card-ocr-data/scan_result.tsv '
        'TRUTH=~/card-ocr-data/ocr_truth.tsv',
      );
      return;
    }
    final scanFile = File(scanPath);
    final truthFile = File(truthPath);
    if (!scanFile.existsSync() || !truthFile.existsSync()) {
      // ignore: avoid_print
      print('건너뜀 — 파일을 찾지 못했습니다: $scanPath / $truthPath');
      return;
    }

    final scans = _readTsv(scanFile, '파일명');
    final truths = _readTsv(truthFile, '파일명');

    // 검수를 마친 명함만 센다. 안 본 것을 정답으로 쓰면 그게 다시 추측이다.
    final checked = truths.entries
        .where((e) => (e.value['확인함'] ?? '').trim() == 'Y')
        .map((e) => e.key)
        .where(scans.containsKey)
        .toList();

    // ignore: avoid_print
    print('\n검수 완료 ${checked.length}장 / 정답지 ${truths.length}장');

    // ⚠️ **정답지에 "검수 안 한 행"이 차 있는 것을 알린다**(2026-08-17).
    //
    // 실물을 열어 보니 103행 **전부에 값이 차 있었다.** 그런데 `확인함`이 Y가
    // 아닌 86행은 **인식 결과를 그대로 복사한 씨앗값**이었다 — 616칸이 인식
    // 결과와 100% 같았고, 사람이 손댄 흔적이 한 칸도 없었다.
    //
    // 이 채점기는 Y인 행만 세므로 **숫자가 부풀지는 않는다.** 문제는 **보이지
    // 않는다는 것**이다. 파일을 열면 103행이 다 차 있어 *"정답지 103장"*으로
    // 읽힌다 — 실제로 PM과 담당 세션 둘 다 그렇게 알고 있었다.
    //
    // ⚠️ 추가 198(*"채움률과 정확도는 다르다"*)이 형태만 바꿔 다시 나온 것이다.
    // 그때는 **빈 값을 정상으로 세는 것**이었고, 이번은 **인식 결과를 정답으로
    // 두는 것**이다. 둘 다 *"자기가 낸 답을 자기가 채점"*이다.
    final seeded = truths.length - checked.length;
    if (seeded > 0) {
      // ignore: avoid_print
      print(
        '⚠️ 검수 안 한 $seeded행은 세지 않았습니다 — 그 행들은 정답이 아니라\n'
        '   인식 결과가 복사돼 있을 수 있습니다(자기 답을 자기가 채점하게 됨).\n'
        '   표본을 늘리려면 검수 도구에서 확인함(Y)을 채우십시오.',
      );
    }
    if (checked.isEmpty) {
      // ignore: avoid_print
      print('아직 확인 완료(Y)한 명함이 없습니다.');
      return;
    }

    var totalOk = 0, totalJudged = 0;
    final rows = <String>[];
    final wrong = <String>[];

    for (final field in _fields) {
      var ok = 0, bad = 0, missed = 0, over = 0, both = 0;
      for (final name in checked) {
        final raw = (scans[name]!['원문'] ?? '')
            .split(' ⏐ ')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        if (raw.isEmpty) continue;
        final parsed = OcrScannerService.parseLinesForTesting(raw);
        final got = _norm(switch (field) {
          '이름' => parsed.name,
          '회사' => parsed.company,
          '직함' => parsed.title,
          '부서' => parsed.department,
          '휴대폰' => parsed.phone,
          '사무실' => parsed.officePhone,
          '팩스' => parsed.fax,
          '이메일' => parsed.email,
          '홈페이지' => parsed.website,
          '우편번호' => parsed.postalCode,
          '주소' => parsed.address,
          _ => parsed.addressDetail,
        });
        final want = _norm(truths[name]!['정답_$field'] ?? '');

        if (got.isEmpty && want.isEmpty) {
          both++;
        } else if (got == want) {
          ok++;
        } else if (got.isEmpty) {
          missed++;
          wrong.add('  미검출 $name [$field] 정답="$want"');
        } else if (want.isEmpty) {
          over++;
          wrong.add('  오검출 $name [$field] 넣음="$got"');
        } else {
          bad++;
          wrong.add('  틀림  $name [$field] "$got" ≠ "$want"');
        }
      }
      final judged = ok + bad + missed + over;
      totalOk += ok;
      totalJudged += judged;
      final rate = judged == 0 ? '—' : '${(100 * ok / judged).round()}%';
      rows.add(
        '${field.padRight(5)} 일치$ok 틀림$bad 미검출$missed 오검출$over '
        '둘다빔$both → $rate',
      );
    }

    // ignore: avoid_print
    print('\n=== 필드별 정확도 ===');
    for (final r in rows) {
      // ignore: avoid_print
      print(r);
    }
    // ignore: avoid_print
    print(
      '\n전체 정확도: '
      '${totalJudged == 0 ? '—' : '${(100 * totalOk / totalJudged).round()}%'}'
      ' ($totalOk / $totalJudged)',
    );
    if (wrong.isNotEmpty) {
      // ignore: avoid_print
      print('\n=== 틀린 것 ${wrong.length}건 ===');
      for (final w in wrong.take(60)) {
        // ignore: avoid_print
        print(w);
      }
      if (wrong.length > 60) {
        // ignore: avoid_print
        print('  … 외 ${wrong.length - 60}건');
      }
    }
  });
}

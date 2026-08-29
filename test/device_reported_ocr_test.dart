// globe2030님이 **폴드에서 직접 스캔하다** 알려 주신 결함 셋(2026-08-29).
//
// ## 🚨 셋 다 맥에서는 안 보였다
//
// 같은 명함을 맥 Vision 으로 읽으면 `RAUM` 과 `fax …` 가 **다른 줄**로 갈려
// 결함이 안 나타난다. 기기 ML Kit 은 한 줄로 묶는다.
//
// > **줄 나눔이 다르면 다른 결함이 나온다.**
//
// 오늘 인식 PR 아홉 건(#681~#689)이 전부 맥 Vision 으로 잰 것이었는데, 기기에
// 올리자마자 **10분 만에 셋**이 나왔다. 이 파일은 그 셋을 잠근다.
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  OcrScanResult parse(List<String> lines) =>
      OcrScannerService.parseLinesForTesting(lines);

  group('① 회사명에 연락처 라벨이 딸려 온다 — 「회사명에 fax가 딸려 들어가네」', () {
    const rest = [
      '홍길동',
      '사업 1팀 | 대리',
      'mobile 010-1234-5678',
      'e-mail a@example.com',
    ];

    test('끝에 붙은 라벨을 뗀다', () {
      expect(parse([...rest, 'RAUM fax 031-1234-5678']).company, 'RAUM');
    });

    test('번호가 빠져나간 자국이 남은 줄도 뗀다', () {
      expect(
        parse([...rest, 'tel 031-111-2222 fax 031-1234-5678 RAUM']).company,
        'RAUM',
      );
    });

    test('한글 회사명 뒤에 붙은 것도 뗀다', () {
      expect(
        parse([...rest, '라움소프트 RAUM fax 031-1234-5678']).company,
        '라움소프트 RAUM',
      );
    });

    test('⚠️ 라벨이 말 가운데 정상으로 든 이름은 안 다친다', () {
      // 추가 178·180 에서 반복해 겪은 함정(`SK telecom` 의 `tel`).
      expect(parse([...rest, 'Tel Aviv Trading']).company, 'Tel Aviv Trading');
    });
  });

  group('② 로고 글씨가 직함 칸에 든다 — 김효성 명함', () {
    const rest = ['(주)한빛정보기술', 'John Smith', '010-1234-5678'];

    test('반쯤 읽힌 로고는 직함이 아니다', () {
      expect(parse([...rest, 'GI T ceonitios']).title, isEmpty);
      expect(parse([...rest, 'GIT Clenikloeo']).title, isEmpty);
    });

    test('🚨 직함 키워드는 **낱말 경계**로 본다', () {
      // 초안이 안 돌았던 이유다 — `ceonitios` 안에 `ceo` 가 들어 있어
      // 부분 문자열 매칭이 「직함 낱말이 있다」고 봤다. 이 파일이 :1897
      // 주석에 **이미 적어 둔 함정**인데 그 자리에서 다시 밟았다.
      expect(parse([...rest, 'GI T ceonitios']).title, isEmpty);
    });

    test('⚠️ 대문자 약자로 시작하는 정상 직함은 그대로 둔다', () {
      expect(parse([...rest, 'IT Manager']).title, 'IT Manager');
      expect(
        parse([...rest, 'Business Development']).title,
        'Business Development',
      );
    });
  });

  group('③ 같은 줄의 영문 이름이 회사가 된다 — 전영환 명함', () {
    test('전부 대문자로 인쇄한 영문 이름은 회사 후보에서 미룬다', () {
      final r = parse([
        '전영환 YOUNGWHAN CHUN',
        'AI아키텍처팀 | 선임 Architect',
        'LG CNS',
        '010-1234-5678',
      ]);
      expect(r.name, '전영환');
      expect(r.company, 'LG CNS');
    });

    test('⚠️ 짧은 대문자 약자는 회사다 — `LG CNS` 를 사람으로 읽지 않는다', () {
      // 다른 후보가 없을 때도 회사로 남아야 한다.
      final r = parse(['홍길동', '대리', 'LG CNS', '010-1234-5678']);
      expect(r.company, 'LG CNS');
    });

    test('📌 미루는 것이지 버리는 것이 아니다', () {
      // 대안이 없으면 그대로 쓴다 — 기존 원칙 그대로다.
      final r = parse(['홍길동', '대리', 'YOUNGWHAN CHUN', '010-1234-5678']);
      expect(r.company, 'YOUNGWHAN CHUN');
    });
  });
}

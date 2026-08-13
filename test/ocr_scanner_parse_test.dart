// 국내 명함 레이아웃 패턴을 다양하게 모아 OcrScannerService._parse()의
// 필드 분류 규칙을 검증한다. 실제 ML Kit 인식을 거치지 않고, 이미
// 순서가 정리된 줄 목록(_extractOrderedLines를 거친 뒤의 형태)을 직접
// 넣어서 "규칙 자체가 맞는가"만 따로 테스트한다 — 카메라/이미지 품질
// 변수는 배제.
//
// 2026-08-07: "국내 명함 레이아웃을 먼저 돌려봐"라는 요청으로 작성.
// 실제 명함 100장을 손으로 찍는 대신, 실사용 중 확인된 실패 축(회사명
// 접미사 유무, 이름 띄어쓰기, 직함+이름 결합, 영문 표기, 공공기관 직급
// 등)을 중심으로 대표 패턴을 모았다.
import 'package:flutter_test/flutter_test.dart';
import 'package:connection_trace_ai_flutter/core/services/ocr_scanner_service.dart';

void main() {
  OcrScanResult parse(List<String> lines) =>
      OcrScannerService.parseLinesForTesting(lines);

  group('기본 레이아웃 — 회귀 확인', () {
    test('회사명 접미사 있음 + 표준 순서', () {
      final r = parse([
        '주식회사 커넥션센스',
        '홍길동',
        '대표이사',
        '서울특별시 강남구 테헤란로 123',
        'M 010-1234-5678',
        'E hong@connectionsense.co.kr',
      ]);
      expect(r.name, '홍길동');
      expect(r.company, '주식회사 커넥션센스');
      expect(r.title, '대표이사');
      expect(r.phone, '010-1234-5678');
      expect(r.email, 'hong@connectionsense.co.kr');
    });

    test('오늘 실사용 사례 — 접미사 없는 공공기관식 회사명 + 띄어쓴 이름', () {
      final r = parse([
        '한국도로공사서비스',
        '경기도 성남시 수정구 창업로57번길 11',
        'M010-9347-5453 E cgu@exservice.co.kr',
        '경영지원실 인사팀 | 팀장',
        '최 태 웅',
        'ex service',
      ]);
      expect(r.name, '최태웅', reason: '음절 사이 공백은 제거하고 이름으로 인식해야 함');
      expect(r.company, '한국도로공사서비스', reason: '접미사 없어도 이름 자리에 밀리면 안 됨');
      expect(r.phone, '010-9347-5453', reason: '이메일과 한 줄에 있어도 같이 뽑혀야 함');
      expect(r.email, 'cgu@exservice.co.kr');
    });

    test('모바일+오피스전화가 각각 다른 줄, 이메일이 전화보다 먼저 나옴', () {
      final r = parse([
        '(주)테스트컴퍼니',
        'E test@test.co.kr',
        'M 010-2222-3333',
        'T 02-555-6666',
        '김철수',
        '과장',
      ]);
      expect(r.email, 'test@test.co.kr');
      expect(r.phone, '010-2222-3333');
      expect(r.officePhone, '02-555-6666');
      expect(r.name, '김철수');
      expect(r.title, '과장');
    });
  });

  group('회사명 접미사 확장 후보', () {
    test('유한회사', () {
      final r = parse(['유한회사 다인테크', '이영희', '주임', 'M 010-1111-2222']);
      expect(r.company, contains('다인테크'));
    });
    test('사단법인', () {
      final r = parse(['사단법인 한국소프트웨어협회', '박민수', '사무국장', 'M 010-3333-4444']);
      expect(r.company, contains('한국소프트웨어협회'));
    });
    test('재단법인', () {
      final r = parse(['재단법인 서울문화재단', '정수아', '연구원', 'M 010-5555-6666']);
      expect(r.company, contains('서울문화재단'));
    });
    test('협동조합', () {
      final r = parse(['행복나눔협동조합', '한지민', '이사', 'M 010-7777-8888']);
      expect(r.company, contains('협동조합'));
    });
  });

  group('직함 키워드 확장 후보 — 공공기관 직급', () {
    test('주무관', () {
      final r = parse(['서울특별시청', '김민준', '주무관', 'M 010-1234-0001']);
      expect(r.title, '주무관');
    });
    test('사무관', () {
      final r = parse(['강남구청', '이서연', '사무관', 'M 010-1234-0002']);
      expect(r.title, '사무관');
    });
    test('서기관', () {
      final r = parse(['경기도청', '최유진', '서기관', 'M 010-1234-0003']);
      expect(r.title, '서기관');
    });
  });

  group('이름 판별 경계값', () {
    test('4자 이름(복성 등)은 인식', () {
      final r = parse(['테스트(주)', '황보경준', '대리', 'M 010-9999-0000']);
      expect(r.name, '황보경준');
    });
    test('5자 이름은 이름 정규식은 안 걸리지만 leftover 순서 배정으로 채워짐', () {
      final r = parse(['테스트(주)', '남궁선우진', '대리', 'M 010-9999-0001']);
      // 이름 정규식(2~4자)은 5자를 안 잡지만, 회사명/직함이 키워드로 이미
      // 확정된 상태라 남은 leftover 자리(이름)를 이 줄이 순서상 채운다 —
      // 결과적으로는 맞게 채워지는 케이스(정규식이 아니라 소거법으로).
      expect(r.name, '남궁선우진');
    });
    test('부서명이 한글 2~4자라 이름으로 오인될 위험 — 알려진 한계', () {
      final r = parse(['테스트(주)', '기획팀', '이름없음예시', 'M 010-9999-0002']);
      // "기획팀"이 순수 한글 3자라 이름 정규식에 걸린다 — 의미 이해가 없는
      // 규칙 기반의 알려진 한계. 실패해도 로직 버그는 아니고, 문서화 목적.
      expect(r.name, '기획팀');
    });
  });

  group('직함+이름 한 줄 결합 — 실제 명함 샘플 65장 조사로 확인/수정', () {
    // "곽용환"(LEWIS EXPERT), "이정섭"(사람인), "정우호"(선호라이팀),
    // "윤덕현"(vittz), "김정웅"(JPinnovation) 등 실제 명함에서 직함과
    // 이름이 한 줄에 붙어 나오는 사례가 매우 흔했다(2026-08-07). 순서와
    // 형태(키워드 먼저/이름 먼저/음절별 띄어쓰기/서술형 직함)가 제각각이라
    // 토큰 단위로 분리하는 로직을 추가했다.
    test('직함(키워드) 먼저 + 이름 — "실장 곽용환" 패턴', () {
      final r = parse(['LEWIS EXPERT', '실장 곽용환', 'M 010-8977-9661']);
      expect(r.name, '곽용환');
      expect(r.title, '실장');
    });
    test('이름 먼저 + 직함(키워드) — "이정섭 부장" 패턴', () {
      final r = parse(['(주)사람인', '이정섭 부장', 'M 010-5577-7821']);
      expect(r.name, '이정섭');
      expect(r.title, '부장');
    });
    test('직함(키워드) + 음절별로 띄운 이름 — "대표이사 정 우 호" 패턴', () {
      final r = parse(['선호라이팅(주)', '대표이사　정 우 호', 'C.P. 010-8718-1064']);
      expect(r.name, '정우호');
      expect(r.title, '대표이사');
    });
    test('음절별로 띄운 이름 + 서술형 긴 직함 — "윤 덕 현 컨설팅 및 딜리버리 팀장" 패턴', () {
      final r = parse(['(주)비츠', '윤 덕 현 컨설팅 및 딜리버리 팀장', 'M 010-9497-7666']);
      expect(r.name, '윤덕현');
      expect(r.title, '컨설팅 및 딜리버리 팀장');
    });
    test('직함 키워드가 다른 글자와 붙어 그 자체로 이름 모양(2~4자)인 경우 — 오배정 방지 확인', () {
      final r = parse(['테스트(주)', '전무이사 김철수', 'M 010-8888-9999']);
      // "전무이사"(4자)가 이름 정규식과 우연히 같은 모양이라, 매칭된 키워드
      // "이사"를 포함하는 토큰은 이름 후보에서 제외하는 안전장치가 있다 —
      // 이게 없으면 "전무이사"가 이름으로, "김철수"가 직함으로 뒤바뀐다.
      expect(r.name, '김철수');
      expect(r.title, contains('전무이사'));
    });
    test('직함 키워드 자체가 한글 2~4자 단독 토큰인 경우 — 오배정 방지 확인', () {
      final r = parse(['JPinnovation', '대표 김 정 웅', 'M 010-2020-2680']);
      // "대표"만 놓고 보면 그 자체로 이름 모양(2자)과 구분이 안 된다 —
      // 매칭된 키워드와 정확히 같은 토큰은 이름 후보 판별 전에 제외해야
      // "대표"가 이름으로 오인되지 않는다.
      expect(r.name, '김정웅');
      expect(r.title, '대표');
    });
  });

  group('영문 표기 케이스', () {
    test('영문 전용 이름/회사명 + 영문 직함', () {
      final r = parse(['ABC Company', 'David Kim', 'Sales Manager', 'M 010-4444-5555']);
      expect(r.title, contains('Manager'));
      expect(r.company, 'ABC Company');
      expect(r.name, 'David Kim');
    });
    test('영문 회사 접미사가 전부 대문자("INC.")인 경우', () {
      final r = parse(['NELSON SPORTS, INC.', '김형준', 'M 010-9902-8210']);
      expect(r.company, 'NELSON SPORTS, INC.');
      expect(r.name, '김형준');
    });
  });

  group('전화번호 — 괄호로 감싼 지역번호', () {
    test('"(02)855-5900" 처럼 지역번호 뒤에 괄호가 바로 붙는 경우', () {
      final r = parse(['테스트(주)', '홍길동', '전화 : (02)855-5900(代)']);
      expect(r.officePhone, '02-855-5900');
    });
  });

  group('전화번호 패턴', () {
    test('점(.) 구분 휴대폰 번호', () {
      final r = parse(['테스트(주)', '홍길동', 'M 010.1234.5678']);
      expect(r.phone, '010-1234-5678');
    });
    test('공백 구분 휴대폰 번호', () {
      final r = parse(['테스트(주)', '홍길동', 'M 010 1234 5678']);
      expect(r.phone, '010-1234-5678');
    });
    test('070 인터넷전화만 있고 휴대폰 없음', () {
      final r = parse(['테스트(주)', '홍길동', 'T 070-1234-5678']);
      expect(r.officePhone, '070-1234-5678');
      expect(r.phone, '');
    });
  });

  group('주소 변형', () {
    test('지번 주소(로/길 없이 동만)', () {
      final r = parse(['테스트(주)', '홍길동', '서울특별시 강남구 역삼동 123-45', 'M 010-1234-5678']);
      expect(r.address, contains('역삼동'));
    });
    test('우편번호 + 도로명 + 상세주소 같은 줄, 콤마 구분', () {
      final r = parse([
        '테스트(주)',
        '홍길동',
        '06193 서울특별시 강남구 테헤란로 123, 5층 501호',
        'M 010-1234-5678',
      ]);
      expect(r.postalCode, '06193');
      expect(r.addressDetail, '5층 501호');
    });
    test('우편번호가 괄호로 감싸인 경우 — "(04933) 서울..."', () {
      final r = parse([
        '테스트(주)',
        '홍길동',
        '(04933) 서울특별시 광진구 능동로 400 보건복지행정타운 18층',
        'M 010-1234-5678',
      ]);
      expect(r.postalCode, '04933');
    });
    test('도로명 주소와 상세주소가 다음 줄로 분리', () {
      final r = parse([
        '테스트(주)',
        '홍길동',
        '서울특별시 강남구 테헤란로 123',
        '3층 인사팀',
        'M 010-1234-5678',
      ]);
      expect(r.addressDetail, '3층 인사팀');
    });
  });

  group('회사명 접미사 없음 — 부서명/슬로건이 회사명 자리를 뺏던 실사용 버그', () {
    // 2026-08-07: 사용자가 "이정현,최서연,이상헌 이 잘못 들어감"으로 제보.
    // 셋 다 회사명에 접미사가 없고, leftover에 부서명/슬로건처럼 회사명과
    // 구분 안 되는 줄이 같이 있어서 엉뚱한 줄이 회사명으로 들어갔었다.
    test('이정현(Sovargen) — 부서명 "경영기획실"이 회사명을 대체하던 버그', () {
      final r = parse([
        '이정현',
        '상무(실장)',
        '경영기획실',
        'M 010-6282-1922',
        'T 070-5222-2771',
        'E rosielee@sovargen.com',
        '06223 서울특별시 강남구 논현로86길 16, 2층(역삼동, 제포빌딩)',
        'Sovargen',
      ]);
      expect(r.name, '이정현');
      expect(r.title, '상무(실장)');
      expect(r.company, 'Sovargen');
    });
    test('최서연(Sovargen) — 회귀 확인(원래도 정상 동작하던 케이스)', () {
      final r = parse([
        '최서연',
        '매니저',
        'M 010-8331-7749',
        'T 070-5222-2770',
        'E sychoi@sovargen.com',
        '06223 서울특별시 강남구 논현로86길 16, 2층(역삼동, 제포빌딩)',
        'Sovargen',
      ]);
      expect(r.name, '최서연');
      expect(r.title, '매니저');
      expect(r.company, 'Sovargen');
    });
    test('이상헌(SSIS) — 슬로건 문장이 회사명을 대체하던 버그', () {
      final r = parse([
        '국민 맞춤형 복지를 실현하는 디지털 플랫폼 전문기관',
        'SSiS 한국사회보장정보원',
        '이 상 헌',
        '건강보건사업부 | 과장',
        '(04933) 서울특별시 광진구 능동로 400 보건복지행정타운 18층',
        'T 02-6360-6910 F 02-6360-6930 M 010-9354-5742',
        'E sh0819@ssis.or.kr',
      ]);
      expect(r.name, '이상헌');
      expect(r.title, '건강보건사업부 | 과장');
      expect(r.company, 'SSiS 한국사회보장정보원');
    });

    test('이름이 로고 오인식 텍스트와 한 줄로 뭉친 경우 — "이정현 DA Sovargen"', () {
      // 2026-08-07: "최서연,이정현 모두 회사명을 DA로 인식해서 회사명을
      // 갖고 오지 못하네" 재제보로 확인. 실제 RAW 텍스트는 이름과 로고
      // 오인식 텍스트("DA")+회사명이 같은 행(같은 줄)으로 인식됐다.
      final r = parse([
        '이정현 DA Sovargen',
        '상무(실장) |MO10-6282-1922',
        '경영기획실 T070-5222-2771',
        'E rosielee@sovargen.com',
        '06223 서울특별시 강남구 논현로86길 16, 2층(역삼동, 제포빌딩)',
      ]);
      expect(r.name, '이정현');
      expect(r.title, '상무(실장)');
      // 처음엔 "DA"가 회사명 앞에 그대로 남아도 괜찮다고 봤는데("DA
      // Sovargen"), 실기기 재검증에서 "회사명에 DA 가 들어오네"로 다시
      // 제보돼 이름 바로 뒤 로고 잡음 토큰을 걷어내도록 고쳤다 — 이제
      // "Sovargen" 단독으로 깨끗하게 나와야 한다.
      expect(r.company, 'Sovargen');
    });

    test(
      '로고 오인식 텍스트가 이름과 다른 줄로 인식되는 경우 — "DA"가 단독 줄',
      () {
        // 2026-08-07: 위 "한 줄로 뭉친" 수정을 실기기에 반영했는데도
        // "이정현은 회사명에 DA로 로고값이 들어오고"로 재제보. 같은
        // 카드를 다시 스캔해도 ML Kit이 줄을 나누는 방식이 매번 같지
        // 않아서, 이번엔 "DA"가 이름과 안 붙고 leftover에 독립된 줄로
        // 들어갔다 — leftover 맨 앞이 "DA"라 그대로 회사명이 됐다.
        // 줄 결합 형태에 기대지 않고 _pickCompanyFromLeftover가 짧은
        // 로고 잡음 후보를 건너뛰도록 고쳤다.
        final r = parse([
          '이정현',
          'DA',
          '상무(실장)',
          '경영기획실',
          'M 010-6282-1922',
          'T 070-5222-2771',
          'E rosielee@sovargen.com',
          '06223 서울특별시 강남구 논현로86길 16, 2층(역삼동, 제포빌딩)',
          'Sovargen',
        ]);
        expect(r.name, '이정현');
        expect(r.company, isNot('DA'));
        expect(r.company, contains('Sovargen'));
      },
    );

    test('로고 오인식 텍스트가 이름과 다른 줄로 인식되는 경우 — "A"가 단독 줄', () {
      // 같은 재제보에서 "최서연은 회사명에 A 가 들어옴"도 함께 확인됐다 —
      // 로고 오인식 글자가 카드/스캔마다 다르게 나올 수 있으니(DA, A 등)
      // 특정 글자를 하드코딩해서 걸러내지 않고 "아주 짧은 후보는
      // 후순위"라는 일반 규칙으로 대응한다.
      final r = parse([
        '최서연',
        'A',
        '매니저',
        'M 010-8331-7749',
        'T 070-5222-2770',
        'E sychoi@sovargen.com',
        '06223 서울특별시 강남구 논현로86길 16, 2층(역삼동, 제포빌딩)',
        'Sovargen',
      ]);
      expect(r.name, '최서연');
      expect(r.company, isNot('A'));
      expect(r.company, contains('Sovargen'));
    });
  });

  group('2026-08-07 재검증 — 이메일 공백/이름 부분 띄어쓰기 실사용 버그', () {
    test('이메일 "@" 앞에 공백이 낀 경우 — "alvinkim @greenitkr.com"', () {
      // "김효성은 3번을 스캔해보는데 매번 이메일이 들어오지 않아" 재제보.
      // 실제 RAW 텍스트를 보니 "@" 바로 앞에 공백이 있어서(OCR이 라벨과
      // 아이디 사이를 띄어 읽음) 기존 정규식(공백 불허)이 통째로 매칭에
      // 실패했다.
      final r = parse([
        '기업부설연구소',
        '김효성 연구소장 GIT',
        'Green IT Korea Plus Newness',
        'alvinkim @greenitkr.com',
        '조달우수제품 조달청혁신제품 신가술인증 신제품인증',
        '(주)그린아이티코리아',
        '본사. 경기도 남양주시 다산중앙로 19번길 21, F932호',
        'T. 02.6412.5662 / 031.721.5661 F. 031.624.5619',
      ]);
      expect(r.email, 'alvinkim@greenitkr.com');
    });

    test('이름이 음절 일부만 띄어지고 뒤에 로고 잡음이 붙은 경우 — "이 시영 O ALOYS"', () {
      // "이시영은 이름에 회사 이미지에서 추출된 값이 들어오고" 재제보.
      // 실제 RAW 텍스트는 이름이 "이"(1자)+"시영"(2자)으로 일부만 띄어져
      // 나오고 바로 뒤에 로고 오인식 글자("O")와 영문 회사명("ALOYS")이
      // 붙어 있었다 — 기존 로직은 완전히 한 글자씩 띄어진 이름이나 단일
      // 토큰 이름만 잡아서 이 패턴을 놓치고 줄 전체를 이름 자리에 넣었다.
      final r = parse([
        '이 시영 O ALOYS',
        '부사장/RaD Center',
        '주식회사 알로이스',
        'Mobile O10-2856-5780 Fax, 031-709-0262',
      ]);
      expect(r.name, '이시영');
      expect(r.company, '주식회사 알로이스');
    });

    test('이메일 구분자("@", ".")가 통째로 사라진 경우 — 복구하지 않고 빈 값으로 남긴다', () {
      // 같은 이시영 카드에서 "Email. andy leepaloys cokr"처럼 "@"와 "."이
      // OCR 단계에서 아예 사라진 경우도 확인됐다. 구분자가 없으면 어디서
      // 잘라야 할지 알 수 없어 추측으로 이메일을 만들어내면 잘못된 값이
      // 들어갈 위험이 있다(CLAUDE.md "가짜 데이터를 만들지 않는다" 원칙) —
      // 그래서 이 경우는 고치지 않고 빈 값으로 남는 것이 의도된 동작임을
      // 회귀 테스트로 명시해 둔다.
      final r = parse(['Email. andy leepaloys cokr']);
      expect(r.email, isEmpty);
    });
  });

  group('2026-08-07 재검증 — 도로명 주소가 건물번호 없이 다음 줄로 넘어가는 경우', () {
    test('라움소프트(공은성) — "…대왕판교로" / "644번길 49, 한컴타워 3층" 두 줄', () {
      // "644번길 49가 들어가야하는데 아래 상세주소로 와있네" 재제보로 확인.
      // 실제 원문은 도로명이 "대왕판교로"까지만 한 줄에 있고(건물번호 없이
      // 줄이 끝남), 건물번호("644번길 49")는 다음 줄로 넘어가 있었다.
      // 이전엔 다음 줄 전체를 상세주소로 통째로 넘겨서 주소엔 건물번호가
      // 영영 안 들어가고, 상세주소엔 반대로 도로명 조각("644번길 49")이
      // 섞여 들어가는 문제가 있었다.
      final r = parse([
        '공은성',
        '사업 1팀 | 과장',
        'tel 070-4736-6106',
        'RAUM fax 070-4735-7770',
        '라음 소 프 트 mobile 010-4156-0395',
        'e-mail eskong@raumsoft.co.kr',
        '13493 경기도 성남시 분당구 대왕판교로',
        '644번길 49, 한컴타워 3층',
        'www.raumsoft.co.kr',
      ]);
      expect(r.postalCode, '13493');
      expect(r.address, '경기도 성남시 분당구 대왕판교로644번길 49');
      expect(r.addressDetail, '한컴타워 3층');
    });
  });

  group('팩스 번호 오분류 방지 (2026-08-11)', () {
    String digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

    test('팩스 라벨이 붙은 번호는 사무실 전화로 배정하지 않는다', () {
      final r = parse([
        '주식회사 라음소프트',
        '홍길동',
        'tel 031-123-4567',
        'fax 031-123-4568',
        'M 010-1111-2222',
      ]);
      // 포맷 정규화는 자릿수별로 달라 문자열 대신 숫자만 비교한다.
      expect(digits(r.officePhone), '0311234567'); // tel 쪽
      expect(digits(r.phone), '01011112222');
      // 팩스 번호가 사무실 전화 자리를 차지하지 않았는지 확인
      expect(digits(r.officePhone), isNot('0311234568'));
    });

    test('팩스 번호만 있고 대표전화가 없으면 사무실 전화는 빈다', () {
      final r = parse([
        '주식회사 라음소프트',
        '홍길동',
        'RAUM fax 070-4735-7770',
        'M 010-1111-2222',
      ]);
      expect(r.officePhone, '');
      // 팩스 번호가 이름/회사로 새지 않았는지(회사는 키워드로 이미 잡힘)
      expect(r.name, '홍길동');
      expect(r.company, '주식회사 라음소프트');
    });
  });

  group('직함·회사 키워드 보수적 확장 (2026-08-11)', () {
    test('직함 "회장"', () {
      final r = parse(['(주)커넥션', '홍길동 회장', 'M 010-1234-5678']);
      expect(r.name, '홍길동');
      expect(r.title, '회장');
    });
    test('회사 접미사 "공단"', () {
      final r = parse(['한국산업안전보건공단', '홍길동', '주임', 'M 010-1234-5678']);
      expect(r.company, '한국산업안전보건공단');
      expect(r.name, '홍길동');
    });
    test('회사 접미사 "진흥원"', () {
      final r = parse(['한국콘텐츠진흥원', '이영희', '선임', 'M 010-1234-5678']);
      expect(r.company, '한국콘텐츠진흥원');
      expect(r.name, '이영희');
    });
  });

  group('주소 인식 강화 (2026-08-11, 측정상 주소가 최대 병목)', () {
    test('도(道) 풀네임 — "충청북도 청주시..."도 인식', () {
      final r = parse([
        '주식회사 커넥션',
        '홍길동',
        '충청북도 청주시 상당구 대성로 100',
        'M 010-1234-5678',
      ]);
      expect(r.address, '충청북도 청주시 상당구 대성로 100');
    });

    test('경상남도 풀네임', () {
      final r = parse(['(주)커넥션', '홍길동', '경상남도 창원시 의창구 중앙대로 210']);
      expect(r.address, '경상남도 창원시 의창구 중앙대로 210');
    });

    test('도/시 이름 없이 "강남구 테헤란로 123"으로 시작하는 주소', () {
      final r = parse([
        '주식회사 커넥션',
        '홍길동',
        '강남구 테헤란로 123',
        'M 010-1234-5678',
      ]);
      expect(r.address, '강남구 테헤란로 123');
    });

    test('시+구 두 단계 "성남시 분당구 판교로 235"', () {
      final r = parse(['(주)커넥션', '홍길동', '성남시 분당구 판교로 235']);
      expect(r.address, '성남시 분당구 판교로 235');
    });

    test('시/군/구 + 로/길 + 숫자가 아니면 주소로 오인하지 않는다(오탐 방지)', () {
      // "경영지원본부" 같은 부서명은 로/길+숫자가 없어 주소로 안 잡혀야 한다.
      final r = parse(['(주)커넥션', '홍길동', '경영지원본부', 'M 010-1234-5678']);
      expect(r.address, '');
    });

    test('우편번호가 별도 줄에 홀로 있을 때 인식', () {
      final r = parse([
        '주식회사 커넥션',
        '홍길동',
        '06234',
        '서울특별시 강남구 테헤란로 123',
        'M 010-1234-5678',
      ]);
      expect(r.postalCode, '06234');
      expect(r.address, '서울특별시 강남구 테헤란로 123');
    });

    test('우편번호 대괄호 표기 "[06234]" 별도 줄', () {
      final r = parse(['(주)커넥션', '홍길동', '[06234]', '서울 강남구 테헤란로 123']);
      expect(r.postalCode, '06234');
    });
  });

  group('글자 크기 기반 이름 폴백 — 규칙으로 이름을 확신 못 할 때만', () {
    OcrScanResult parseH(List<({String text, double height})> lines) =>
        OcrScannerService.parseLinesForTestingWithHeights(lines);

    test('규칙으로 이름을 못 찾은 경우, 가장 크게 인쇄된 줄을 이름으로 고른다', () {
      // 영문 이름이라 한글 이름 규칙에 안 걸리고, 직함/회사 키워드도 없어
      // 예전이면 leftover 맨 앞("Global Sales Division")이 이름이 됐다.
      // 이름 "John Smith"가 훨씬 큰 글자이므로 그쪽을 골라야 한다.
      final r = parseH([
        (text: 'Global Sales Division', height: 20),
        (text: 'John Smith', height: 44),
        (text: 'some tagline here', height: 18),
      ]);
      expect(r.name, 'John Smith');
      expect(r.parseShape?.nameSource, OcrNameSource.fontSizePreferred);
    });

    test('높이 정보가 없으면(=0) 기존대로 맨 앞 줄을 이름으로 쓴다 — 회귀 방지', () {
      final r = parseH([
        (text: 'Global Sales Division', height: 0),
        (text: 'John Smith', height: 0),
      ]);
      expect(r.name, 'Global Sales Division');
      expect(r.parseShape?.nameSource, OcrNameSource.leftoverFallback);
    });

    test('가장 큰 줄이 맨 앞 줄보다 눈에 띄게 크지 않으면 기존 동작 유지', () {
      final r = parseH([
        (text: 'Global Sales Division', height: 30),
        (text: 'John Smith', height: 31),
      ]);
      expect(r.name, 'Global Sales Division');
      expect(r.parseShape?.nameSource, OcrNameSource.leftoverFallback);
    });

    test('한글 이름을 규칙으로 확신한 경우엔 글자 크기와 무관하게 그 이름 유지', () {
      // "홍길동"은 한글 이름 규칙(koreanStripped)으로 이미 확신 — 회사명이
      // 더 크더라도 이름은 안 바뀐다.
      final r = parseH([
        (text: '주식회사 커넥션센스', height: 50),
        (text: '홍길동', height: 30),
        (text: 'M 010-1234-5678', height: 20),
      ]);
      expect(r.name, '홍길동');
      expect(r.parseShape?.nameSource, OcrNameSource.koreanStripped);
    });
  });

  // 2026-08-13 (backlog 추가 178). 키워드 목록은 `_containsCi` — 단어 경계가
  // 없는 대문자 contains로 비교된다. 그래서 짧은 영문 약어를 넣으면 엉뚱한
  // 단어 속에 걸리는데, 실제로 'PO'가 "SPORTS"에, 'Global'이 부서명에 걸려
  // 회사명·이름이 통째로 틀어졌다. 직함 검사가 회사 검사보다 먼저 돌며
  // continue하므로, 한 번 잘못 걸리면 회사명은 영영 못 채운다.
  group('키워드가 부분 문자열로 걸리지 않는다 (2026-08-13 회귀 방지)', () {
    test('회사명 속 "SPORTS"를 직함으로 오인하지 않는다', () {
      final r = parse([
        'NELSON SPORTS, INC.',
        'John Smith',
        'Sales Manager',
      ]);
      expect(r.company, 'NELSON SPORTS, INC.');
      expect(r.title, 'Sales Manager');
    });

    test('이메일 줄을 회사명으로 오인하지 않는다 — "e-mail" 속 "AI"', () {
      final r = parse([
        '주식회사 커넥션센스',
        '홍길동',
        'e-mail hong@connectionsense.co.kr',
      ]);
      expect(r.company, '주식회사 커넥션센스');
      expect(r.email, 'hong@connectionsense.co.kr');
    });

    test('직함 "Technical Director"를 회사명으로 오인하지 않는다 — 속의 "Tech"', () {
      final r = parse([
        '주식회사 커넥션센스',
        'John Smith',
        'Technical Director',
      ]);
      expect(r.company, '주식회사 커넥션센스');
      expect(r.title, 'Technical Director');
    });

    test('부서명 "Global Sales Division"이 회사명 자리를 뺏지 않는다', () {
      final r = parse([
        'Global Sales Division',
        'John Smith',
      ]);
      expect(r.company, isNot('Global Sales Division'));
    });
  });

  // 2026-08-13 (backlog 추가 178). rawLines를 파서가 안 채워서 명함 등록
  // 화면의 터치 퀵 매핑 UI가 조용히 안 뜨던 결함(실기기 확인)의 회귀 방지.
  // 필드가 "존재하지만 비어 있는" 상태는 화면을 열어보기 전에는 안 드러난다.
  group('rawLines — 터치 퀵 매핑 UI에 넘길 원문 줄 (2026-08-13 회귀 방지)', () {
    test('인식한 줄이 그대로 rawLines에 담긴다', () {
      final input = [
        '주식회사 커넥션센스',
        '홍길동',
        '대표이사',
        'M 010-1234-5678',
      ];
      final r = parse(input);
      expect(r.rawLines, input);
    });

    test('빈 입력이어도 rawLines는 빈 목록이다(널이 아니다)', () {
      final r = parse([]);
      expect(r.rawLines, isEmpty);
    });
  });
}

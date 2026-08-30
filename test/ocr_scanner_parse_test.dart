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
    test('⚠️ 5자 한글 이름(복성)은 이제 비운다 — 확신 못 하면 비우기(2026-08-22)', () {
      final r = parse(['테스트(주)', '남궁선우진', '대리', 'M 010-9999-0001']);
      // 예전에는 여기서 '남궁선우진'이 채워졌다. 이름 정규식(2~4자)은 5자를
      // 안 잡지만, 회사명·직함이 키워드로 확정된 뒤 남은 leftover 자리를 이
      // 줄이 순서상 채웠다 — 정규식이 아니라 **소거법**으로 맞은 것이다.
      //
      // 사용자 결정(2026-08-22)으로 **약한 폴백에서 한글 값은 비운다.**
      // 그래서 복성 5자 이름도 함께 비워진다.
      //
      // ## 왜 이 손해를 감수하나
      //
      // ML Kit 실기기 측정(96장)에서 이 자리가 넣은 한글 값 4건이 **전부
      // 틀렸고**, 그중 **3건이 5자**였다. 즉 길이로는 복성 이름과 쓰레기를
      // 가를 수 없다 — 둘 다 한글 5자다.
      //
      // ```
      // 5자 쓰레기   3건 / 96장 (3%)   실측
      // 복성 이름     표본 95장에 0건    ⚠️ 실제 빈도는 안 쟀다
      // ```
      //
      // 명함 앱에서 이름이 틀린 채 저장되면 그 사람을 못 찾고 **사용자는 틀린
      // 줄도 모른다.** 빈 칸은 눈에 띈다 — 스캔 화면이 "이름을 찾지 못했다"고
      // 안내하고 직접 채우게 한다.
      //
      // ⚠️ 영문은 비우지 않는다(테스트 여럿이 그 경로를 지킨다).
      expect(r.name, '');
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
      final r = parse([
        'ABC Company',
        'David Kim',
        'Sales Manager',
        'M 010-4444-5555',
      ]);
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

  // 2026-08-14 (backlog 추가 193, 테스터 E-03).
  //
  // ⚠️ **번호 대역이 라벨보다 확실하다.** `01X`는 통신사 휴대폰 대역이고
  // `02`·`0XX`·`070`은 유선/인터넷전화 대역이라 바뀔 수 없다. 반면 한국 명함의
  // `T.`는 "사무실"이 아니라 그냥 "전화"의 관용 표기인 경우가 많다 — 실제로
  // `T. 010-4729-3390` 하나만 적힌 명함이 표본에 있었다(크몽).
  //
  // 그래서 라벨은 **대역이 같아 구분이 안 될 때만** 쓴다.
  group('전화번호: 대역 우선, 라벨은 동률일 때만 (테스터 E-03)', () {
    test('사무실 라벨이라도 010이면 휴대폰이다 — "T."는 관용 표기', () {
      final r = parse(['(주)크몽', '이순환', 'T. 010-4729-3390']);
      expect(r.phone, '010-4729-3390');
      expect(r.officePhone, '');
    });

    test('휴대폰 라벨이라도 070이면 사무실이다 — 대역이 휴대폰이 아니다', () {
      final r = parse(['(주)한빛', '남궁현', 'H.P 070-0000-0004']);
      expect(r.officePhone, '070-0000-0004');
      expect(r.phone, '');
    });

    test('둘 다 010이면 라벨로 가른다 — 진짜 E-03 사례', () {
      // 예전에는 먼저 잡힌 대표전화가 휴대폰 칸을 차지하고 진짜 휴대폰은
      // 버려졌다.
      final r = parse([
        '한빛부동산',
        '남궁현',
        'TEL. 010-0000-0005',
        'H.P 010-0000-0006',
      ]);
      expect(r.phone, '010-0000-0006');
      expect(r.officePhone, '010-0000-0005');
    });

    test('둘 다 010인데 휴대폰 라벨이 먼저 나와도 제자리', () {
      final r = parse([
        '한빛부동산',
        '남궁현',
        'H.P 010-0000-0006',
        'TEL. 010-0000-0005',
      ]);
      expect(r.phone, '010-0000-0006');
      expect(r.officePhone, '010-0000-0005');
    });

    test('라벨이 없으면 대역으로 나눈다 — 회귀 확인', () {
      final r = parse(['(주)한빛', '남궁현', '010-0000-0007', '02-000-0008']);
      expect(r.phone, '010-0000-0007');
      expect(r.officePhone, '02-000-0008');
    });

    test('한 줄에 두 종류 라벨이 섞여도 대역으로 나뉜다 — 회귀 확인', () {
      final r = parse(['(주)한빛', '남궁현', 'M.010-0000-0009 T.02-000-0010']);
      expect(r.phone, '010-0000-0009');
      expect(r.officePhone, '02-000-0010');
    });

    test('팩스 라벨은 여전히 사무실 전화가 되지 않는다 — 회귀 확인', () {
      final r = parse(['(주)한빛', '남궁현', 'FAX. 02-000-0012']);
      expect(r.officePhone, '');
    });
  });

  // 2026-08-14 (backlog 추가 197). 국가번호 표기는 앞의 0이 없어 기존 규칙에
  // 통째로 안 걸렸다 — 103장 표본의 두 장은 전화번호가 하나도 안 잡혔다.
  group('국가번호(+82) 표기 전화번호', () {
    test('+82-10-… 은 휴대폰으로 잡는다', () {
      final r = parse(['LEWIS EXPERT', '실장 곽용환', '+82-10-8977-9661']);
      expect(r.phone, '010-8977-9661');
    });

    test('+82-2-… 는 사무실로 잡는다', () {
      final r = parse(['LEWIS EXPERT', '실장 곽용환', '+82-2-3446-9300']);
      expect(r.officePhone, '02-3446-9300');
    });

    test('+ 없이 점으로 구분한 표기도 잡는다', () {
      final r = parse([
        '(주)한빛',
        '남궁현',
        'M. 82.10.6355.6919',
        'O. 82.2.6077.9901',
      ]);
      expect(r.phone, '010-6355-6919');
      expect(r.officePhone, '02-6077-9901');
    });

    test('서울(02) 4자리 국번을 올바로 끊는다 — 기존 버그', () {
      // 자릿수만 보고 3-3-4로 끊으면 "023-446-9300"이 된다.
      final r = parse(['(주)한빛', '남궁현', 'T. 02-3446-9300']);
      expect(r.officePhone, '02-3446-9300');
    });

    test('국내 표기는 기존대로 — 회귀 확인', () {
      final r = parse(['(주)한빛', '남궁현', '010-0000-0007', '02-000-0008']);
      expect(r.phone, '010-0000-0007');
      expect(r.officePhone, '02-000-0008');
    });
  });

  // 2026-08-14 (backlog 추가 197). OCR이 홈페이지 주소를 직함 줄과 붙여 읽는
  // 경우가 흔하다.
  group('직함 칸에서 웹사이트·이메일을 걷어낸다', () {
    test('직함 줄에 붙은 URL은 저장하지 않는다', () {
      final r = parse([
        '(주)한빛특허',
        '김세전',
        'www.edenpat.com 파트너 변리사',
        '010-0000-0000',
      ]);
      expect(r.title, '파트너 변리사');
    });

    test('직함 줄에 붙은 이메일도 걷어낸다', () {
      final r = parse([
        '(주)한빛',
        '남궁현',
        '이사|본부장 a@hanbit.co.kr',
        '010-0000-0000',
      ]);
      expect(r.title, isNot(contains('@')));
      expect(r.title, contains('본부장'));
    });

    test('URL이 없는 직함은 그대로 — 회귀 확인', () {
      final r = parse(['(주)한빛', '남궁현', '상무', '010-0000-0000']);
      expect(r.title, '상무');
    });
  });

  group('주소 변형', () {
    test('지번 주소(로/길 없이 동만)', () {
      final r = parse([
        '테스트(주)',
        '홍길동',
        '서울특별시 강남구 역삼동 123-45',
        'M 010-1234-5678',
      ]);
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
      // 2026-08-19(추가 321): 부서를 직함에서 갈랐다. 예전에는 이 줄이 통째로
      // 직함이었다(`건강보건사업부 | 과장`) — 사용자 확정으로 규칙이 바뀌었다.
      expect(r.title, '과장');
      expect(r.department, '건강보건사업부');
      // 🚨 **2026-08-30(추가 612): 190장 자가 이 값을 뒤집었다.** 아래 두
      // 검사(추가 278·318)에 적혀 있던 *"로고를 떼지 않는다"* 는 **103장 자로
      // 내린 결정**이었다. 표본이 190장이 되자 같은 모양이 여섯 장 나왔고,
      // 정답지는 **여섯 중 다섯을 「떼라」**고 했다.
      expect(r.company, '한국사회보장정보원');
    });

    // ── 부서 분리 (2026-08-19 사용자 확정, 추가 321) ────────────────────
    //
    // 부서는 직함과 별개 칸이다. 예전에는 갈 곳이 없어 직함에 함께 들어갔고,
    // 정답지도 장마다 갈려서 파서가 이길 수 없었다(추가 286).
    group('부서 분리 (추가 321)', () {
      test('⭐ 직함 줄에 부서가 섞여 있으면 갈라 담는다', () {
        final r = OcrScannerService.parseLinesForTesting([
          '홍길동',
          'ICT 사업본부 상무',
          '(주)테스트',
        ]);
        expect(r.title, '상무');
        expect(r.department, 'ICT 사업본부');
      });

      test('⭐ 부서가 여럿이면 모두 담는다', () {
        final r = OcrScannerService.parseLinesForTesting([
          '홍길동',
          'MNO사업부 로밍마케팅팀 매니저',
          '(주)테스트',
        ]);
        expect(r.title, '매니저');
        expect(r.department, 'MNO사업부 로밍마케팅팀');
      });

      test('⚠️ 부서가 없으면 직함은 그대로다', () {
        final r = OcrScannerService.parseLinesForTesting([
          '홍길동',
          '대표이사',
          '(주)테스트',
        ]);
        expect(r.title, '대표이사');
        expect(r.department, '');
      });

      // ⚠️ 일부러 안 가르는 자리다. 직함 칸이 통째로 부서면 가르지 않는다 —
      // 가르면 직함 칸이 비는데, 그것이 이득인지 손해인지 아직 안 쟀다.
      // 재고 나서 넓힌다(추가 321).
      test('⚠️ 직함 줄이 통째로 부서면 가르지 않는다 — 아직 안 쟀다', () {
        final r = OcrScannerService.parseLinesForTesting([
          '홍길동',
          '경영지원팀',
          '(주)테스트',
        ]);
        expect(r.department, '');
      });
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

    test('로고 오인식 텍스트가 이름과 다른 줄로 인식되는 경우 — "DA"가 단독 줄', () {
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
    });

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
      final r = parse(['주식회사 커넥션', '홍길동', '강남구 테헤란로 123', 'M 010-1234-5678']);
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

    // ⚠️ **대역을 바꿨다**(2026-08-29). 예전에는 첫 줄 대역으로
    //    `Global Sales Division`을 썼는데, 이제 **조직 낱말이 든 줄은 이름
    //    후보에서 빠진다**(52장 실측 — `Marketing Division`이 이름 칸에
    //    들어갔다). 이 검사의 뜻은 *"큰 글자가 이긴다"*이므로 **대역만**
    //    사람 이름 모양으로 바꾼다.
    test('규칙으로 이름을 못 찾은 경우, 가장 크게 인쇄된 줄을 이름으로 고른다', () {
      final r = parseH([
        (text: 'Anna Marie Lee', height: 20),
        (text: 'John Smith', height: 44),
        (text: 'some tagline here', height: 18),
      ]);
      expect(r.name, 'John Smith');
      expect(r.parseShape?.nameSource, OcrNameSource.fontSizePreferred);
    });

    test('높이 정보가 없으면(=0) 기존대로 맨 앞 줄을 이름으로 쓴다 — 회귀 방지', () {
      final r = parseH([
        (text: 'Anna Marie Lee', height: 0),
        (text: 'John Smith', height: 0),
      ]);
      expect(r.name, 'Anna Marie Lee');
      expect(r.parseShape?.nameSource, OcrNameSource.leftoverFallback);
    });

    test('가장 큰 줄이 맨 앞 줄보다 눈에 띄게 크지 않으면 기존 동작 유지', () {
      // 대역 교체 이유는 위 검사 주석 참고(2026-08-29).
      final r = parseH([
        (text: 'Anna Marie Lee', height: 30),
        (text: 'John Smith', height: 31),
      ]);
      expect(r.name, 'Anna Marie Lee');
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
      final r = parse(['NELSON SPORTS, INC.', 'John Smith', 'Sales Manager']);
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
      final r = parse(['주식회사 커넥션센스', 'John Smith', 'Technical Director']);
      expect(r.company, '주식회사 커넥션센스');
      expect(r.title, 'Technical Director');
    });

    test('부서명 "Global Sales Division"이 회사명 자리를 뺏지 않는다', () {
      final r = parse(['Global Sales Division', 'John Smith']);
      expect(r.company, isNot('Global Sales Division'));
    });
  });

  // 2026-08-13 (backlog 추가 180). 실기기에서 확인된 두 갈래 오분류.
  //
  // (1) 회사명 줄이 직함 키워드를 부분 문자열로 품고 있으면, 그 줄이 통째로
  //     직함이 되고 `continue` 탓에 회사명이 영영 빈 값이 됐다.
  // (2) 한글 이름이 인식되지 않으면 명함 위쪽의 큰 영문 로고가 이름 자리를
  //     차지했다("이름에 기업명이 들어가는 경우가 많다"는 사용자 보고).
  group('회사명 줄이 직함으로 소비되지 않는다 (2026-08-13 회귀 방지)', () {
    test('"○○대리점"이 직함이 되지 않는다 — 속의 "대리"', () {
      final r = parse(['한빛전자 강남대리점', '남궁현', '010-0000-0000']);
      expect(r.company, '한빛전자 강남대리점');
      expect(r.name, '남궁현');
      expect(r.title, isNot(contains('대리점')));
    });

    test('"○○관리사무소"가 직함이 되지 않는다 — 속의 "사원"', () {
      final r = parse(['한빛사원아파트관리사무소', '남궁현', '010-0000-0000']);
      expect(r.company, '한빛사원아파트관리사무소');
      expect(r.name, '남궁현');
    });

    test('자격증 줄이 직함 자리를 차지하지 않는다 — 속의 "수석"', () {
      final r = parse(['(주)한빛정보기술', '남궁현', '정보시스템수석감리원', '010-0000-0000']);
      expect(r.company, '(주)한빛정보기술');
      expect(r.name, '남궁현');
      expect(r.title, isNot('정보시스템수석감리원'));
    });

    test('정상 직함 "수석연구원"은 그대로 직함이다 — 회귀 확인', () {
      final r = parse(['(주)한빛정보기술', '남궁현', '수석연구원', '010-0000-0000']);
      expect(r.title, '수석연구원');
      expect(r.name, '남궁현');
    });
  });

  group('회사 로고를 이름으로 쓰지 않는다 (2026-08-13 회귀 방지)', () {
    test('회사명 줄에 통째로 들어 있는 영문 후보는 이름이 되지 않는다', () {
      final r = parse([
        'HANBIT',
        'ICT사업본부 | 상무',
        'M.010-0000-0000',
        'Www.HANBIT.CO. KR',
      ]);
      // 사람 이름을 찾지 못했으므로 비워 둔다 — 로고를 이름으로 저장하는 것보다
      // 낫다(스캔 화면이 "찾지 못했다"고 안내한다).
      expect(r.name, '');
      expect(r.name, isNot('HANBIT'));
    });

    test('회사명이 한글이어도 이메일 도메인으로 로고를 걸러낸다', () {
      // 실기기 재스캔에서 확인: 회사명이 "크림하우스(주)"로 정확히 잡히자
      // 로고 영문과 겹치는 부분이 없어져 회사명 기준 필터가 무력해졌다.
      // 남은 근거가 이메일 도메인이다(globe@creamhouse.net ← CREAMHOUSE).
      final r = parse([
        'HANBIT',
        'CT 사업본부 | 상무',
        'M.P 010-0000-0000',
        'Email globe@hanbit.net',
        '한빛하우스(주)',
      ]);
      expect(r.name, isNot('HANBIT'));
      expect(r.company, '한빛하우스(주)');
    });

    test('접미사 없는 회사명은 도메인과 겹쳐도 회사명 자리를 지킨다 — 회귀 확인', () {
      // 로고 판정은 이름 후보에서만 뺀다. leftover에서 지워 버리면 접미사 없는
      // 회사명(자기 도메인에 들어 있는 경우)이 회사명 자리를 잃는다.
      final r = parse([
        'Sovargen',
        '이정현',
        '경영기획실',
        'M 010-0000-0000',
        'E test@sovargen.com',
      ]);
      expect(r.company, 'Sovargen');
      expect(r.name, '이정현');
    });

    test('한글 이름은 로고 판정에 걸리지 않는다 — 회귀 확인', () {
      final r = parse(['HANBIT', '남궁현', '상무', 'Www.HANBIT.CO. KR']);
      expect(r.name, '남궁현');
    });

    test('회사명과 무관한 영문 이름은 그대로 이름이다 — 회귀 확인', () {
      final r = parse(['NELSON SPORTS, INC.', 'John Smith', 'Sales Manager']);
      expect(r.name, 'John Smith');
      expect(r.company, 'NELSON SPORTS, INC.');
    });

    test('슬로건 조각은 이름이 되지 않는다 — 조사로 끝난다', () {
      // 명함 위쪽 홍보 문구가 OCR에서 여러 줄로 잘리면 그 조각이 한글 2~4자라
      // 이름 규칙에 걸린다. 실기기 재스캔에서 "고객에게"가 이름이 됐다.
      final r = parse([
        '인터넷, 모바일 서비스를 통해',
        '고객에게',
        '성공과 만족을 제공하는 최고의 ICT 전문 기업',
        'HANBIT',
        'CT 사업본부 | 상무',
        '크림하우스(주)',
      ]);
      expect(r.name, isNot('고객에게'));
      expect(r.name, isNot('통해'));
      expect(r.company, '크림하우스(주)');
    });

    test('일반명사 "기업"은 이름이 되지 않는다 — 슬로건 마지막 조각', () {
      // 실기기: "…성공과 만족을 제공하는 최고의 ICT 전문 기업"이 잘려
      // "기업"만 남으면 한글 2자라 이름 규칙에 그대로 걸린다.
      final r = parse([
        '전문',
        '기업',
        'HANBIT',
        'CT 사업본부 | 상무',
        '한빛하우스(주)',
        'M.P 010-0000-0000',
      ]);
      expect(r.name, isNot('기업'));
      expect(r.name, isNot('전문'));
    });

    test('일반명사 필터는 완전 일치일 때만 적용된다 — 회사명 보존', () {
      // 부분 문자열로 걸렀다면 "기업은행"까지 걸려 회사명이 사라진다.
      final r = parse(['기업은행 강남지점', '남궁현', '차장', '010-0000-0000']);
      expect(r.company, contains('기업은행'));
      expect(r.name, '남궁현');
    });

    test('조사로 끝나지 않는 한글 이름은 그대로 둔다 — 회귀 확인', () {
      final r = parse(['(주)한빛정보기술', '남궁현', '상무', '010-0000-0000']);
      expect(r.name, '남궁현');
    });

    test('연락처 라벨만 남은 줄은 이름이 되지 않는다 — "TEL. FAX. 02-…"', () {
      // 67장 실측: 번호를 뽑아 간 뒤 남은 라벨 조각이 이름 칸에 들어갔다.
      final r = parse([
        'TEL.  FAX. 02-0000-0000',
        '(주)한빛정보기술',
        '010-0000-0000',
      ]);
      expect(r.name, isNot(contains('TEL')));
      expect(r.name, isNot(contains('FAX')));
      expect(r.company, '(주)한빛정보기술');
    });

    test('연락처 라벨만 남은 줄은 회사명도 되지 않는다 — "Tel Fax 070-…", "Fax."', () {
      final r = parse(['Tel  Fax 070-0000-0000', 'Fax.', '남궁현', '상무']);
      expect(r.company, isNot(contains('Fax')));
      expect(r.company, isNot(contains('Tel')));
      expect(r.name, '남궁현');
    });

    test('웹사이트+라벨만 있는 줄도 회사명이 되지 않는다', () {
      final r = parse(['www.hanbit.co.kr E-mail', '한빛하우스(주)', '남궁현']);
      expect(r.company, '한빛하우스(주)');
    });

    test('라벨과 겹치는 글자를 품은 회사명은 지켜진다 — "SK telecom"', () {
      // 부분 문자열로 지웠다면 "telecom"에서 TEL이 잘려 나갔을 것이다.
      // 단어 경계로만 지우므로 멀쩡히 남아야 한다.
      final r = parse(['SK telecom', '남궁현', '상무', '010-0000-0000']);
      expect(r.company, 'SK telecom');
      expect(r.name, '남궁현');
    });

    test('라벨 잔여물("M.")은 이름이 되지 않는다', () {
      final r = parse(['M.', '(주)한빛정보기술', '010-0000-0000']);
      expect(r.name, isNot('M.'));
    });
  });

  // 2026-08-14 (backlog 추가 187). 로고체로 자간을 벌려 인쇄한 글자를 붙인다.
  // 이름에만 있던 처리를 파싱 맨 앞으로 옮겨 모든 칸에 같은 규칙이 적용된다.
  group('자간 벌린 글자 붙이기 (2026-08-14)', () {
    test('회사명의 글자 사이 공백을 붙인다', () {
      // "(주)" 뒤의 공백은 정상적인 단어 사이 공백이라 그대로 둔다 —
      // 붙여야 하는 것은 자간을 벌린 "에 이 치 씨 엔 씨" 구간이다.
      final r = parse(['(주) 에 이 치 씨 엔 씨', '정현규', '수석', '010-0000-0000']);
      expect(r.company, '(주) 에이치씨엔씨');
      expect(r.company, isNot(contains('에 이')));
    });

    test('단어 사이 공백은 그대로 둔다 — 회사명', () {
      final r = parse(['주식회사 커넥션 센스', '홍길동', '대표이사']);
      expect(r.company, '주식회사 커넥션 센스');
    });

    test('영문 회사명의 단어 공백은 그대로 둔다 — 회귀 확인', () {
      final r = parse(['NELSON SPORTS, INC.', '김형준', '010-0000-0000']);
      expect(r.company, 'NELSON SPORTS, INC.');
    });

    test('영문 이름의 공백은 그대로 둔다 — 회귀 확인', () {
      final r = parse(['ABC Company', 'David Kim', 'Sales Manager']);
      expect(r.name, 'David Kim');
    });

    test('문장 속 한 글자(및)는 붙이지 않는다 — 회귀 확인', () {
      final r = parse(['(주)비츠', '윤 덕 현 컨설팅 및 딜리버리 팀장', 'M 010-0000-0000']);
      expect(r.name, '윤덕현');
      expect(r.title, '컨설팅 및 딜리버리 팀장');
    });

    test('1글자 토큰이 둘뿐이면 붙이지 않는다', () {
      // "김 밥"처럼 두 개만 떨어져 있는 경우는 자간 벌림으로 보지 않는다.
      final r = parse(['(주)한빛정보기술', '가 나 다', '상무']);
      expect(r.name, '가나다');
    });
  });

  // 2026-08-14 (backlog 추가 183). "확신하지 못하면 비운다" — 약한 폴백에
  // 이름/회사명 모양인 후보만 넣고, 없으면 빈 값으로 둔다. 예전에는 남은 줄
  // 맨 앞을 그냥 써서, 쓰레기를 하나 걸러내면 다음 쓰레기가 그 자리를 채웠다.
  group('확신하지 못하면 비운다 (2026-08-14)', () {
    test('이메일 주소는 이름이 되지 않는다', () {
      final r = parse(['duke@hanbit.co.kr', '(주)한빛정보기술', '010-0000-0000']);
      expect(r.name, isNot(contains('@')));
    });

    test('영문 주소는 이름이 되지 않는다 — 쉼표·숫자', () {
      final r = parse([
        '704, SK V1 TOWER, 25, Yeonmujang 5ga-gil',
        '(주)한빛정보기술',
        '010-0000-0000',
      ]);
      expect(r.name, isNot(contains('TOWER')));
    });

    test('영문 슬로건은 이름이 되지 않는다 — 단어 수', () {
      final r = parse(["I'm a Voyager of value", '(주)한빛정보기술', '010-0000-0000']);
      expect(r.name, isNot(contains('Voyager')));
    });

    test('서술형 한글 문장은 이름이 되지 않는다', () {
      final r = parse(['설계, 제작 및 납품 E-mail.', '(주)한빛정보기술', '010-0000-0000']);
      expect(r.name, isNot(contains('설계')));
    });

    test('직함이 붙은 긴 영문 줄은 이름이 되지 않는다', () {
      final r = parse([
        'Head of R&D Dept. Ko Byoung Ho',
        '(주)한빛정보기술',
        '010-0000-0000',
      ]);
      expect(r.name, isNot(contains('Dept')));
    });

    test('".co.kr" 도메인이 회사 키워드 "Co."에 걸리지 않는다', () {
      // 실측: "서비스 : www.elancer.co.kr 회사: …"가 회사명으로 확정됐다.
      // 도메인의 .co.가 키워드 'Co.'에 걸린 것 — URL을 걷어낸 뒤 판정한다.
      final r = parse(['서비스 : www.hanbit.co.kr', '한빛하우스(주)', '남궁현', '상무']);
      expect(r.company, '한빛하우스(주)');
    });

    test('회사명과 웹사이트가 한 줄에 있으면 회사명으로 인정한다 — 회귀 확인', () {
      // URL을 걷어내도 'INC.'가 남으므로 회사명 판정은 유지돼야 한다.
      final r = parse([
        'NELSON SPORTS, INC. www.nelson.co.kr',
        '김형준',
        '010-0000-0000',
      ]);
      expect(r.company, contains('NELSON SPORTS'));
      expect(r.name, '김형준');
    });

    test('웹사이트 주소는 회사명이 되지 않는다', () {
      final r = parse(['www.hanbit.co.kr', '남궁현', '상무']);
      expect(r.company, isNot(contains('www')));
    });

    test('정상 한글 이름·영문 이름은 그대로 통과한다 — 회귀 확인', () {
      expect(parse(['(주)한빛정보기술', '남궁현', '상무']).name, '남궁현');
      expect(
        parse(['ABC Company', 'David Kim', 'Sales Manager']).name,
        'David Kim',
      );
    });

    test('음절을 띄운 한글 이름도 통과한다 — 회귀 확인', () {
      final r = parse(['한국도로공사서비스', '최 태 웅', '경영지원실 인사팀 | 팀장']);
      expect(r.name, '최태웅');
    });
  });

  // 2026-08-13 (backlog 추가 178). rawLines를 파서가 안 채워서 명함 등록
  // 화면의 터치 퀵 매핑 UI가 조용히 안 뜨던 결함(실기기 확인)의 회귀 방지.
  // 필드가 "존재하지만 비어 있는" 상태는 화면을 열어보기 전에는 안 드러난다.
  group('rawLines — 터치 퀵 매핑 UI에 넘길 원문 줄 (2026-08-13 회귀 방지)', () {
    test('인식한 줄이 그대로 rawLines에 담긴다', () {
      final input = ['주식회사 커넥션센스', '홍길동', '대표이사', 'M 010-1234-5678'];
      final r = parse(input);
      expect(r.rawLines, input);
    });

    test('빈 입력이어도 rawLines는 빈 목록이다(널이 아니다)', () {
      final r = parse([]);
      expect(r.rawLines, isEmpty);
    });
  });

  // 2026-08-14. 사용자 지적: "OCR 추출은 정확히 하고 있는데 분리하는 과정에서
  // 잘못되는구나". 실측 103장에서 이름 미검출 17장 중 16장은 **원문에 이름이
  // 멀쩡히 있었다** — 읽기가 아니라 칸으로 나누는 단계에서 잃고 있었다.
  //
  // 원인이 둘로 갈렸고, 둘 다 "다른 칸이 이름 자리를 먼저 뺏고 나중에 비워지는"
  // 같은 모양이었다. 한 번 뺏기면 진짜 이름을 다시 볼 기회가 없었다.
  group('빈자리를 남에게 뺏기지 않는다 (2026-08-14 실측)', () {
    test('슬로건의 마지막 낱말이 이름 자리를 뺏지 않는다 — card_56 이희규', () {
      // "…ICT 전문 기업"의 마지막 토큰 "기업"이 먼저 이름이 됐다가, 뒤늦게
      // "이건 이름 아님"으로 지워지면서 이름 칸이 통째로 비었다. 걸러내기를
      // 배정하는 순간으로 옮겨서, 걸리면 그 줄을 넘기고 계속 찾게 했다.
      final r = parse([
        '크림하우스주)',
        '성공과 만족을 제공하는 ICT 전문 기업',
        '이희규',
        'ICT사업본부 | 상무',
        'MO10 4504 8595',
        'E globe@creamhouse.co.kr',
      ]);
      expect(r.name, '이희규');
    });

    test('주소 바로 다음 줄의 이름이 상세주소로 먹히지 않는다', () {
      // 예전에는 주소 다음 줄을 **무조건** 상세주소로 삼았다. 명함에서 주소
      // 아래에 이름이나 회사명이 오는 배치가 흔해 그대로 사라졌다.
      final r = parse(['서울특별시 강남구 테헤란로 152', '남궁현', '(주)한빛']);
      expect(r.name, '남궁현');
      expect(r.company, '(주)한빛');
    });

    test('진짜 상세주소(숫자 포함)는 그대로 상세주소로 간다', () {
      final r = parse(['서울특별시 강남구 테헤란로 152', '한컴타워 3층', '남궁현']);
      expect(r.addressDetail, '한컴타워 3층');
      expect(r.name, '남궁현');
    });
  });

  // 사용자 제안(2026-08-14): "추출한 ocr을 분리해서 각 필드에 넣고 빈자리를
  // 재검증하고 진행하도록 하는건 어떨까?" — 1차 배정 뒤 **비어 있는 칸만**
  // 다시 채운다. 이미 채워진 칸은 건드리지 않으므로 잘 되던 명함이 나빠질 수
  // 없다는 것이 이 구조의 핵심이다.
  group('빈자리 재검증 — 주소와 뭉친 이름 (2026-08-14)', () {
    test('주소와 한 줄로 붙어 나온 이름을 건진다', () {
      final r = parse(['박병훈 서울특별시 은평구 통일로 65길 26, 7층', 'M 010-1234-5678']);
      expect(r.name, '박병훈');
      expect(r.address, '서울특별시 은평구 통일로 65길 26');
    });

    test('주소 앞이 회사명이면 이름으로 쓰지 않는다 — "(주)"가 단서', () {
      final r = parse(['(주)한빛 서울특별시 강남구 테헤란로 152']);
      expect(r.name, isEmpty);
    });

    test('다른 규칙이 이름을 이미 찾았으면 힌트를 쓰지 않는다', () {
      // 재검증은 **빈 칸에만** 작동해야 한다. 확신 경로를 덮어쓰면 안 된다.
      final r = parse(['한빛 서울특별시 강남구 테헤란로 152', '남궁현']);
      expect(r.name, '남궁현');
    });
  });

  // 사용자 제안(2026-08-14)을 3단계로 구현한 것의 회귀 방지. 핵심 성질은
  // **이름 칸이 비어 있을 때만 작동한다**는 것 — 그래서 잘 되던 명함이
  // 나빠질 수 없다.
  group('빈자리 재검증 — 직함·원문에서 이름 건지기 (2026-08-14)', () {
    test('직함 칸에 섞여 들어간 이름을 떼어내고 직함도 정리한다 — card_102', () {
      final r = parse(['기업부설연구소', '김효성 연구소장 GIT', '010-1234-5678']);
      expect(r.name, '김효성');
      expect(r.title, isNot(contains('김효성')));
    });

    test('원문 어디에도 못 찾았을 때 마지막으로 줄 전체를 훑는다 — card_134', () {
      final r = parse(['삼성SDI', '중대형 Module/Pack개발그룹', '최호준', 'SAMSUNG SDI']);
      expect(r.name, '최호준');
    });

    test('주소 줄의 지명을 이름으로 쓰지 않는다 — card_104·131·136·18', () {
      // 3단계를 처음 느슨하게 열었더니 103장 중 8장에 지명이 들어왔다.
      // (단독 줄이 아니라 **주소 줄 안에서** 뽑혀 나온 것이 실제 모양이다.)
      final r = parse([
        '경기도 성남시 분당구 판교역로 235',
        'Urban Air Mobility Korea Tech',
        '010-0000-0000',
      ]);
      expect(r.name, isEmpty);
    });

    test('슬로건의 일반명사를 이름으로 쓰지 않는다 — card_131', () {
      // "인터넷, 모바일 서비스를 통해 고객에게 성공과 만족을 제공하는…"
      // 이 문구의 조각들이 전부 한글 2~4자라 이름 규칙에 그대로 걸렸다.
      final r = parse([
        'INOBIZ 벤처확인기업 인터넷, 모바일 서비스를 통해 고객에게',
        '성공과 만족을 제공하는 최고의 ICT 전문 기업',
        'CREAMHOUSE',
        'M.P 010.4504.8595',
        'Email globe@creamhouse.net',
      ]);
      expect(r.name, isEmpty);
    });

    test('두 글자 성씨 이름은 4자까지 인정한다', () {
      final r = parse(['(주)한빛정보기술', '남궁현우', '010-0000-0000']);
      expect(r.name, '남궁현우');
    });

    test('이름을 이미 찾았으면 재검증이 덮어쓰지 않는다', () {
      final r = parse(['홍길동', '김효성 연구소장', '(주)한빛정보기술']);
      expect(r.name, '홍길동');
    });
  });

  // 2026-08-14 저녁. 사용자 제보 "이름이 회사 칸에 들어가 있고, 회사명에
  // 전문기관이 들어감"(card_115)에서 출발해, **이름 후보 사이의 우선순위**가
  // 없다는 구조 문제가 드러났다. 먼저 걸린 것이 이겼다(선착순).
  group('이름 후보 우선순위 — 강한 근거가 이긴다 (2026-08-14)', () {
    test('슬로건 끝자락이 자기 줄에 있는 진짜 이름을 밀어내지 않는다 — card_115', () {
      // "…디지털 플랫폼 전문가관"(OCR이 "전문기관"을 잘못 읽음)의 마지막
      // 토큰이 먼저 이름이 되고, 아래 줄의 `안희원`은 회사 칸으로 밀렸다.
      final r = parse([
        'SSiS 한국사회 보장정보원 국민 맞춤형 복자를 실현하는 디지털 플랫폼 전문가관',
        '안희원',
        '건강보건사업부 | 주임',
        'E ahw@ssis.or.kr www.ssis.or.kr',
      ]);
      expect(r.name, '안희원');
      expect(r.company, isNot('안희원'));
    });

    test('부서명이 직함 키워드에 걸려 이름이 되지 않는다 — card_08', () {
      // "디지털 커뮤니케이션 파트 / 책임"에서 `책임`이 직함 키워드라 앞의
      // `디지털`을 이름으로 갈라냈고, 첫 줄의 `홍승권`을 밀어냈다.
      final r = parse([
        '홍승권 TWINS LG',
        '디지털 커뮤니케이션 파트 / 책임',
        'M.010-8506-0115 E.skhong@sportslg.com',
      ]);
      expect(r.name, '홍승권');
      // ⚠️ **기대를 고쳤다**(2026-08-29). 예전에는 `디지털 커뮤니케이션 파트 /
      //    책임`이 **통째로 직함 칸**에 들어갔고 이 검사는 그것을 지키고 있었다.
      //    지금은 `/`로 묶여 온 직함을 갈라 **직함 `책임` · 부서 `디지털
      //    커뮤니케이션 파트`**로 나눈다 — 명함에 인쇄된 뜻 그대로다.
      //    이 검사의 본래 목적(부서명이 이름 자리를 뺏지 않는지)은 위
      //    `expect(r.name, '홍승권')`이 그대로 지킨다.
      expect(r.title, '책임');
      expect(r.department, contains('디지털'));
    });
  });

  // 사용자 제보(2026-08-14): "card_128 … 직함에 이름의 마지막 글자 '규'가
  // 들어감" + "부서와 직함이 같이 있는 경우"가 있다는 지적.
  group('한 줄 안에서 갈라진 이름을 이어붙인다 (2026-08-14)', () {
    test('직함 + 띄어 읽힌 이름 — card_128 정현규', () {
      final r = parse([
        'DX사업본부 공공시스템부운 공공시스템2팀',
        '수석 정현 규',
        'Mobile. 010-3838-5780',
      ]);
      expect(r.name, '정현규');
      expect(r.title, isNot(contains('규')));
    });

    test('부서명이 이어지는 줄은 이어붙이지 않는다 — 오탐 방지', () {
      final r = parse(['디지털 커뮤니케이션 파트 / 책임', '(주)한빛정보기술', '010-0000-0000']);
      expect(r.name, isEmpty);
    });
  });

  // 사용자 지적(2026-08-14): "한글이름 옆이나 아래 영문이름이 있는 경우도 있음".
  // 한국 명함은 한글 이름과 영문 표기를 나란히 인쇄하는데, OCR이 그 줄을
  // 로고·슬로건과 뭉쳐 읽으면 앞뒤 규칙이 다 빗나가고 **짧은 영문 조각이 이름
  // 자리를 차지했다.**
  group('한글 이름 토큰이 짧은 영문 조각보다 우선한다 (2026-08-14)', () {
    test('로고·슬로건에 파묻힌 한글 이름을 찾는다 — card_02 박병건', () {
      final r = parse([
        'TG360G The DMP Company to Trust',
        'Audience',
        'Targeting Lookalike',
        'Molecule 박병건 | Andy Park',
        '대표이사 | CEO',
        'E. andy.park@tg360tech.com',
      ]);
      expect(r.name, '박병건');
    });

    test('직업명은 이름이 되지 않고, 같은 줄의 나머지가 직함이 된다 — card_26', () {
      // `변리사`는 성씨(변)로 시작하는 3자라 이름 규칙을 그대로 통과했다.
      // 정답은 `김세진`(이메일 sjkim@edenpat.com과 맞는다).
      final r = parse([
        '이든.',
        '특허법률사무소',
        '파트너 변리사 김세진',
        'E. sjkim@edenpat.com www.edenpat.com',
      ]);
      expect(r.name, '김세진');
      expect(r.title, '파트너 변리사');
      expect(r.company, '특허법률사무소');
    });

    test('찾은 이름이 직함 칸에 중복으로 남지 않는다 — card_60', () {
      final r = parse([
        'dany.lee@sk.com 010 3686 8279 Manager 서비스구매팀 이상화 World EXPO 2030',
        'BUSAN, KOREA',
        'SK telecom',
      ]);
      expect(r.name, '이상화');
      expect(r.title, isNot(contains('이상화')));
    });
  });

  // 2026-08-14 저녁. 실측에서 드러난 **구조적 구멍**: 연락처 처리가 줄을
  // 먼저 가져가고 `continue`해서, 같은 줄에 있던 주소·회사명·이름이 통째로
  // 사라졌다. 명함 한 장이 한 줄로 뭉쳐 인식되는 경우가 표본에 여럿 있었다.
  group('한 줄에 뭉친 명함을 끝까지 나눈다 (2026-08-14)', () {
    test('연락처를 걷어낸 나머지에서 주소·회사·이름을 마저 찾는다 — card_18', () {
      final r = parse([
        'T. 02-330-2801 F. 02-6430-0901 M. 010-7315-2800 E. Yqson 1234@kywa.or.kr '
            'Jinyang Bldg 5th F/L, 47 Kyeonggi-daero, Seodaemun-gu, Seoul, Korea, 03752 '
            '03752 서울특별시 서대문구 경기대로 47 진양빌딩 5층 손연기 이사장/ President / CEO '
            'Korea Youth Work Agency KYWA 한국청소년활동진흥원',
        'Son, Yeongi, Ph. D.',
      ]);
      expect(r.address, '서울특별시 서대문구 경기대로 47');
      expect(r.addressDetail, '진양빌딩 5층');
      expect(r.company, '한국청소년활동진흥원');
      expect(r.name, '손연기');
    });

    test('회사명이 주소와 한 줄에 있으면 접미사를 근거로 잘라낸다 — card_31', () {
      final r = parse([
        '(주)고든 08808 서울시 관악구 승방1길 5, 소프트하우스 2층',
        'Mobile 010-4375-4875 Email sjm@godn.kr',
        '신종민',
      ]);
      expect(r.company, '(주)고든');
      expect(r.name, '신종민');
    });

    test('접미사만 남으면 회사명으로 쓰지 않는다 — card_119 회귀 방지', () {
      // `주식회사`만 덩그러니 남은 것은 회사명이 아니라 접미사다.
      final r = parse(['주식회사 서울특별시 강남구 테헤란로 152', 'ALOYS']);
      expect(r.company, isNot('주식회사'));
    });

    test('주소 뒤에 붙은 연락처 라벨은 주소에 넣지 않는다 — card_104', () {
      final r = parse([
        'www.raumsoft.co.kr 644번길 49, 13493 경기도 성남시 분당구 대왕판교로 '
            'e-mail gphong@raumsoft.co.kr mobile 010-6658-1060 사업 1팀 대리 홍관표',
      ]);
      expect(r.address, isNot(contains('e-mail')));
      expect(r.address, isNot(contains('mobile')));
      expect(r.name, '홍관표');
    });

    test('상세주소는 층·호까지만 남긴다', () {
      final r = parse(['서울특별시 서대문구 경기대로 47 진양빌딩 5층 한국청소년활동진흥원']);
      expect(r.addressDetail, '진양빌딩 5층');
      expect(r.company, '한국청소년활동진흥원');
    });
  });

  // 사용자 지적(2026-08-14): "명함에 전화가 없는것 이상하지... 중요 데이터이니
  // 미검출을 확인해" + "국가번호가 들어가는 경우도 확인해".
  //
  // 실측 103장 중 전화 미검출로 제보된 8장을 실물·원문과 대조한 결과,
  // 진짜 결함은 3장이었다(나머지는 이미 고쳐졌거나 명함에 번호가 없었다).
  group('전화 미검출 — 실물 대조로 확인한 3가지 (2026-08-14)', () {
    test('국가번호 뒤 (0) 병기 표기 — card_05', () {
      // `+82 (0)32-…`는 국내 접두 0을 괄호로 병기하는 국제 표기다. 예전에는
      // 정규식이 `(0)`을 못 넘어 전화 세 개가 전부 빈 값이었다.
      final r = parse([
        '(주)한빛정보기술',
        'T+82 (0)32-760-2037 F+82 (0)32-760-2826 M+82 (0)10-8707-2411',
      ]);
      expect(r.phone, '010-8707-2411');
      expect(r.officePhone, '032-760-2037');
    });

    test('한 줄에 국가번호 번호가 여럿이면 전부 처리하고 팩스는 뺀다', () {
      // 줄 전체로 팩스를 가리면 이런 줄은 셋 다 팩스로 보인다 — 각 번호 바로
      // 앞 글자로 가른다.
      final r = parse([
        '(주)한빛정보기술',
        'T+82 (0)32-760-2037 F+82 (0)32-760-2826 M+82 (0)10-8707-2411',
      ]);
      expect(r.officePhone, isNot('032-760-2826'), reason: '팩스가 사무실로 가면 안 됨');
    });

    test('번호가 두 줄로 갈라져 인식된 경우 잇는다 — card_20', () {
      final r = parse([
        'parkjw@sk.com 010 4548 부장 스포츠기획팀 박지웅',
        '1893',
        'SK telecom',
      ]);
      expect(r.phone, '010-4548-1893');
    });

    test('휴대폰 앞자리가 잘려 나간 경우 되살린다 — card_66', () {
      // 실물은 `M. +82 10(7757 1036)`인데 손글씨에 가려 `+8`이 날아갔다.
      // 한국 번호 중 1로 시작하는 10자리는 없으므로 해석이 하나뿐이다.
      final r = parse(['최진영 덕평휴게소 매니저', 'M. 107757 1036']);
      expect(r.phone, '010-7757-1036');
    });

    test('휴대폰 라벨이 없으면 앞자리를 지어내지 않는다', () {
      final r = parse(['(주)한빛정보기술', '107757 1036']);
      expect(r.phone, isNot('010-7757-1036'));
    });

    test('네 자리 숫자가 멀리 떨어져 있으면 잇지 않는다', () {
      final r = parse([
        '010 4548 부장',
        '(주)한빛정보기술',
        '서울특별시 강남구 테헤란로 152',
        '1893',
      ]);
      expect(r.phone, isNot('010-4548-1893'));
    });
  });

  // 103장 전수 측정에서 **회사 60%**로 가장 낮았다. 틀린 39건 중 26건이
  // *"OCR은 제대로 읽었는데 파서가 못 고른 것"*이라 고르기를 손봤다(추가 278).
  group('회사 칸 — 읽어 놓고 못 고르던 것들 (추가 278)', () {
    test('기관 접미사 뒤에 슬로건이 길게 붙어 있어도 기관명만 남긴다', () {
      final r = parse([
        'SSiS 한국사회보장정보원 국민 맞춤형 복지를 실현하는 디지털 플랫폼 전문기관',
        '이현석',
        '건강보건사업부 | 부장',
      ]);
      expect(r.company, contains('한국사회보장정보원'));
      expect(r.company, isNot(contains('맞춤형')));
    });

    test('회사명 뒤에 직함이 붙어 있으면 직함을 뗀다 — card_15·card_17', () {
      final r = parse(['(주)제이투이 영업대표/부장', '서울특별시 성동구 연무장5가길 25, 704호']);
      expect(r.company, '(주)제이투이');
    });

    test('⚠️ 앞 토큰이 직함이면 자르지 않는다 — 회사명이 통째로 사라진다', () {
      final r = parse(['부장 (주)제이투이']);
      expect(r.company, contains('제이투이'));
    });

    test('짝 없는 닫는 괄호는 뗀다 — card_112', () {
      final r = parse([')유에이엠코리아텍(주)', '홍길동']);
      expect(r.company, '유에이엠코리아텍(주)');
    });

    // ⚠️⚠️ 아래 둘은 **하지 않기로 한 것**을 지킨다. 로고를 떼도록 만들었다가
    // 103장으로 재 보고 물렸다 — 3장 얻고 **9장 잃었다**(회사 64% → 60%).
    // 근거는 `_stripCompanyLogoPrefix` 주석에 있다.
    //
    // 🚨 **2026-08-30(추가 612): 아래 첫 검사는 뒤집혔다.**
    //
    // 위 문단은 *"정답지가 로고를 넣을지 말지 **장마다 다르기** 때문이라,
    // 규칙을 정교하게 짜서 풀 문제가 아니다"* 라고 단정했다. **그 단정이
    // 틀렸다** — 190장으로 넓혀 보니 **가르는 신호가 있었다.**
    //
    // ```
    // 뒤가 공공기관 이름   KYWA 한국청소년활동진흥원  →  떼라 (정답지 5장)
    // 뒤가 그 밖           GS 스포츠 · AXA 손해보험    →  두어라
    // ```
    //
    // 📌 **틀린 것은 결론이 아니라 「표본이 이만하면 됐다」는 판단이었다.**
    // 103장에서는 이 모양이 한 장뿐이라 규칙이 보이지 않았다.
    //
    // ⚠️ **그래도 정답지는 아직 한 군데 어긋나 있다** — `card_19` 만 홀로
    // `KYWA 한국청소년활동진흥원` 이다(나머지 다섯은 로고가 없다). 그 한 장은
    // 이 규칙이 못 맞힌다. **다섯을 얻고 하나를 잃는 쪽을 골랐다.**
    test('⭐ 뒤가 공공기관 이름이면 앞 로고를 뗀다 (추가 612로 뒤집힘)', () {
      final r = parse(['KYWA 한국청소년활동진흥원', '홍길동', '기획팀 | 대리']);
      expect(r.company, '한국청소년활동진흥원');
    });

    test('📌 진짜 회사명의 첫 토큰을 자르지 않는다 — SK telecom', () {
      final r = parse(['SK telecom', '홍길동']);
      expect(r.company, contains('SK'));
    });
  });

  // ⚠️ 이 두 칸은 **명함 데이터에는 예전부터 있었는데 인식이 안 뽑았다.**
  // 팩스는 "사무실 전화로 잘못 들어가는 것을 막으려고" 알아본 뒤 **버렸고**,
  // 홈페이지는 "직함 칸을 더럽히지 않으려고" **걷어내 버렸다**. 그래서 손으로
  // 입력할 때만 채워지고, 촬영으로는 **항상 비어 있었다**(2026-08-17 확인).
  group('팩스 — 알아본 값을 버리지 않고 담는다', () {
    test('팩스 라벨이 붙은 번호를 팩스 칸에 담는다', () {
      final r = parse(['(주)한빛정보기술 홍길동 부장', 'FAX. 02-555-1234']);
      expect(r.fax, '02-555-1234');
    });

    test('📌 팩스가 사무실 전화 칸을 차지하지 않는다 — 예전 회귀 보호', () {
      // 이 성질 때문에 원래 팩스를 버렸다. 담기 시작해도 이건 그대로여야 한다.
      final r = parse(['(주)한빛정보기술 홍길동 부장', '팩스 070-1234-5678']);
      expect(r.officePhone, isEmpty);
      expect(r.fax, '070-1234-5678');
    });

    test('한 줄에 T·F·M이 국제표기로 붙어 있어도 셋을 갈라 담는다 — card_05', () {
      final r = parse([
        '홍길동 이사',
        'T+82 (0)32-760-2037 F+82 (0)32-760-2826 M+82 (0)10-8707-2411',
      ]);
      expect(r.officePhone, '032-760-2037');
      expect(r.fax, '032-760-2826');
      expect(r.phone, '010-8707-2411');
    });

    test('팩스가 없으면 빈 값이다 — 지어내지 않는다', () {
      final r = parse(['(주)한빛정보기술 홍길동 부장', 'TEL. 02-555-1234']);
      expect(r.fax, isEmpty);
      expect(r.officePhone, '02-555-1234');
    });
  });

  // 103장에서 팩스를 놓친 16장을 다 뜯어보니 **전부 원문에는 있었다.**
  // 오독은 한 건도 없었다 — 파서가 안 고른 것뿐이다(추가 282).
  //
  // ⚠️ 원인은 `_looksLikeFaxLine`이 **줄 전체**로 판단하는 것이었다. 한국
  // 명함은 `Tel … Fax …`처럼 **한 줄에 둘 다** 적는 경우가 흔한데, 그러면
  // "fax가 있고 tel이 없을 때만"이라는 조건이 통째로 꺼진다.
  group('팩스 — 번호마다 제 라벨을 본다 (추가 282)', () {
    test('한 글자 F 라벨을 알아본다 — 놓친 16장 중 9장이 이 모양', () {
      final r = parse(['홍길동 부장', 'T 031-5178-1621 F031-5178-1599']);
      expect(r.officePhone, '031-5178-1621');
      expect(r.fax, '031-5178-1599');
    });

    test('⭐ 한 줄에 Tel과 Fax가 같이 있어도 갈라 담는다', () {
      // 예전에는 이 줄에서 팩스를 **하나도** 못 담았다.
      final r = parse(['홍길동 부장', 'Tel 02-6053-9142 Fax 070-7600-0812']);
      expect(r.officePhone, '02-6053-9142');
      expect(r.fax, '070-7600-0812');
    });

    test('점으로 끊는 표기도 갈라 담는다 — card_26·card_52', () {
      final r = parse(['홍길동 부장', 'T. 02.6177.7586 F.02.6177.7587']);
      expect(r.officePhone, '02-6177-7586');
      expect(r.fax, '02-6177-7587');
    });

    test('⭐ 앞 번호가 깨져도 팩스가 사무실 칸을 차지하지 않는다 — card_115', () {
      // OCR이 앞 번호를 `02-6360-69/LĻ`로 읽어 규칙에 안 걸린다. 예전에는
      // 뒤의 **팩스가 첫 매칭이 되어 사무실 칸에 들어갔다.**
      // ⚠️ 사용자가 그 번호로 전화를 건다 — 빈 칸이 틀린 번호보다 낫다.
      final r = parse([
        '홍길동 과장',
        'T02-6360-69/LĻ F 02-6360-6930 MO10-5024-8727',
      ]);
      expect(r.fax, '02-6360-6930');
      expect(r.officePhone, isNot('02-6360-6930'));
      expect(r.phone, '010-5024-8727');
    });

    test('⚠️ 낱말 끝의 f는 라벨이 아니다', () {
      // 부분 문자열 함정 — 이 저장소가 반복해 데인 자리다(추가 178·180·182).
      final r = parse(['홍길동 Staff', 'Staff 02-1234-5678']);
      expect(r.fax, isEmpty);
    });

    test('⭐ 대표번호(15xx·18xx)도 사무실 전화로 잡는다', () {
      // `0`으로 시작하지 않아 규칙에 안 걸렸다. 실측 103장에서 두 장이
      // 그것 때문에 사무실 전화가 빈 값이었다.
      final r = parse(['홍길동 부장', 'T. 18779920', 'F. 031 715 7873']);
      expect(r.officePhone, '1877-9920');
      expect(r.fax, '031-715-7873');
    });

    test('대표번호와 팩스가 한 줄에 붙어 있어도 갈라 담는다 — card_123', () {
      final r = parse(['홍길동 부장', 'T1588-3112 F02-468-8251']);
      expect(r.officePhone, '1588-3112');
      expect(r.fax, '02-468-8251');
    });

    test('⚠️ 긴 번호 안의 15xx는 대표번호가 아니다', () {
      // `010-1588-3112`의 뒷부분을 사무실 전화로 뜯어 가면 안 된다.
      final r = parse(['홍길동 부장', 'M 010-1588-3112']);
      expect(r.phone, '010-1588-3112');
      expect(r.officePhone, isEmpty);
    });

    test('OCR이 점을 쉼표로 읽어도 잡는다 — card_51', () {
      final r = parse(['홍길동 부장', 'Tel 02.3468,0020 Fax 02.6008.2059']);
      expect(r.officePhone, '02-3468-0020');
      expect(r.fax, '02-6008-2059');
    });

    test('팩스만 있는 줄은 예전처럼 사무실로 안 간다', () {
      final r = parse(['(주)한빛정보기술 홍길동 부장', '팩스 070-1234-5678']);
      expect(r.fax, '070-1234-5678');
      expect(r.officePhone, isEmpty);
    });
  });

  group('홈페이지 — 걷어내던 것을 칸으로 보낸다', () {
    test('직함과 한 줄로 붙어 있어도 홈페이지만 뽑는다 — card_10·card_103', () {
      final r = parse(['이든특허법률사무소 김이든', 'www.edenpat.com 파트너 변리사']);
      expect(r.website, 'www.edenpat.com');
      // 예전 성질 유지 — 직함 칸에 주소가 섞이지 않는다.
      expect(r.title, isNot(contains('www')));
    });

    test('https:// 형태도 잡는다', () {
      final r = parse(['(주)한빛정보기술 홍길동', 'https://hanbit.co.kr']);
      expect(r.website, 'https://hanbit.co.kr');
    });

    test('⚠️ 이메일 뒷부분을 홈페이지로 오해하지 않는다', () {
      final r = parse(['(주)한빛정보기술 홍길동', 'hong@hanbit.co.kr']);
      expect(r.email, 'hong@hanbit.co.kr');
      expect(r.website, isEmpty);
    });

    test('끝에 붙은 구두점은 뗀다', () {
      final r = parse(['(주)한빛정보기술 홍길동', 'www.hanbit.co.kr,']);
      expect(r.website, 'www.hanbit.co.kr');
    });

    test('홈페이지가 없으면 빈 값이다', () {
      final r = parse(['(주)한빛정보기술 홍길동 부장']);
      expect(r.website, isEmpty);
    });
  });

  // -------------------------------------------------------------------
  // 좌표 전달 — R-05의 선행 조건 (추가 317)
  //
  // 아직 파서가 좌표로 칸을 정하지는 않는다. 여기서 보는 것은 **좌표가
  // 파서까지 실려 오고, 결과에 그대로 남는가**뿐이다. 그것이 안 되면 좌표
  // 규칙을 만들 수도, 재스캔으로 잴 수도 없다.
  // -------------------------------------------------------------------
  group('좌표 전달 (추가 317)', () {
    test('⭐ 좌표를 넣어 파싱하면 결과에 같은 순서로 남는다', () {
      final boxes = <OcrLineBox>[
        (text: '주식회사 테스트', height: 18, top: 10, left: 20, width: 200),
        (text: '홍길동', height: 30, top: 60, left: 20, width: 120),
        (text: '영업팀 | 과장', height: 14, top: 100, left: 20, width: 160),
      ];

      final r = OcrScannerService.parseLinesForTestingWithBoxes(boxes);

      expect(r.rawLineBoxes, hasLength(boxes.length));
      expect(
        r.rawLineBoxes.map((b) => b.text).toList(),
        r.rawLines,
        reason: '좌표 목록과 원문 목록의 순서가 어긋나면 짝을 못 맞춘다',
      );
      expect(r.rawLineBoxes[1].top, 60);
      expect(r.rawLineBoxes[1].left, 20);
      expect(r.rawLineBoxes[1].width, 120);
    });

    test('⚠️ 좌표를 모르는 통로로 만들면 전부 0이다 — "왼쪽 맨 위"가 아니라 "모름"이다', () {
      final r = OcrScannerService.parseLinesForTesting(['주식회사 테스트', '홍길동']);

      expect(r.rawLineBoxes, hasLength(2));
      expect(r.rawLineBoxes.every((b) => b.top == 0 && b.left == 0), isTrue);
      expect(
        r.rawLineBoxes.every((b) => b.width == 0),
        isTrue,
        reason: '좌표를 쓰는 쪽은 이 모양을 보고 좌표 판단을 건너뛰어야 한다',
      );
    });

    test('⭐ 좌표를 넣어도 기존 분류 결과는 그대로다', () {
      // 좌표를 실어 나르기만 하는 단계이므로, 같은 글자면 같은 답이 나와야
      // 한다. 여기가 깨지면 "나르기"가 아니라 이미 규칙을 바꾼 것이다.
      const lines = ['주식회사 테스트', '홍길동', '영업팀 | 과장'];
      final withoutBoxes = OcrScannerService.parseLinesForTesting(lines);
      final withBoxes = OcrScannerService.parseLinesForTestingWithBoxes([
        for (var i = 0; i < lines.length; i++)
          (
            text: lines[i],
            height: 20,
            top: i * 40,
            left: 10,
            width: 150,
          ),
      ]);

      expect(withBoxes.name, withoutBoxes.name);
      expect(withBoxes.company, withoutBoxes.company);
      expect(withBoxes.title, withoutBoxes.title);
    });
  });

  // -------------------------------------------------------------------
  // 로고 접두 — 조건을 붙여 되살린 자리 (추가 318)
  //
  // ⚠️ 2026-08-17에 한 번 물린 규칙이다(3장 얻고 9장 잃음). 그때는 정답지가
  // 장마다 달랐고 조건도 없었다. 99장 검수 뒤 조건(1~2자 + 뒤에 한글)을 붙여
  // 재니 6장 얻고 0장 잃었다.
  //
  // 아래 검사는 **안전장치가 살아 있는지**를 본다. 상한을 넓히거나 "뒤에 한글"
  // 을 빼면 여기가 깨진다 — 깨지면 넓히지 말고 99장으로 다시 재라.
  // -------------------------------------------------------------------
  group('회사 로고 접두 (추가 318)', () {
    String company(List<String> lines) =>
        OcrScannerService.parseLinesForTesting(lines).company;

    test('⭐ 1~2자 영문 뒤에 한글이면 뗀다 — 그림 로고를 잘못 읽은 것이다', () {
      expect(company(['E 서울관광재단', '홍길동', '대표']), '서울관광재단');
      expect(company(['GO 선호라이팅 (주)', '홍길동', '대표']), '선호라이팅 (주)');
    });

    // 🚨 **2026-08-30(추가 612): 「3자 이상은 안 뗀다」가 뒤집혔다.**
    //
    // 예전 규칙은 **길이**로 갈랐다(1~2자만 뗀다). 190장 자에서는 **뒤가
    // 무엇이냐**가 갈랐다 — 뒤가 공공기관 이름이면 그 이름 자체가 온전한
    // 회사명이고 앞의 영문은 로고다. 길이 상한은 그래서 풀었다.
    //
    // ⚠️ **길이 상한을 푼 것이 안전한 이유는 꼬리 조건이 대신 막기 때문이다.**
    // 꼬리 목록에 「보험」·「은행」·「전자」를 넣으면 그 순간 `AXA손해보험` 이
    // 잘린다. 아래 검사가 그것을 지킨다.
    test('⭐ 3자 이상이어도 뒤가 공공기관 이름이면 뗀다', () {
      expect(company(['SSiS 한국사회보장정보원', '홍길동', '주임']),
          '한국사회보장정보원');
      expect(company(['KYWA 한국청소년활동진흥원', '홍길동', '팀장']),
          '한국청소년활동진흥원');
    });

    test('⚠️ 뒤가 영문이면 안 뗀다 — SK telecom의 SK는 회사 이름이다', () {
      expect(company(['SK telecom', '홍길동', '부장']), 'SK telecom');
      expect(company(['DMP Company', '홍길동', '대표']), 'DMP Company');
    });

    test('⭐ 짝 없는 닫는 괄호는 예전대로 뗀다', () {
      expect(company([')유에이엠코리아텍(주)', '홍길동', '부장']),
          '유에이엠코리아텍(주)');
    });
  });

  // 테스터 B(아이폰13, 1.0.0(8)) 제보 — 명함에서 읽은 값이 엉뚱한 칸에
  // 들어간다는 계열의 결함. 실제 명함 원문이 없어 같은 구조(회사 영문명만
  // 있는 뒷면, 키워드에 없는 정상 영문 직함)를 재현한다(2026-08-20).
  //
  // ⚠️ 처음 버전("순수 영문이면 무조건 버린다")은 회사 영문명은 잘 걸렀지만
  // 키워드 목록에 없는 정상 영문 직함까지 같이 막아 정답지 기준 직함
  // 미검출이 6→12건으로 늘었다(배포 전 발견, 병합 안 됨). 그래서 판정
  // 기준을 "전부 대문자인가"로 좁혔다 — 아래 그룹이 그 경계를 고정한다.
  group('직함 칸의 근거 없는 영문 폴백 (테스터 제보, 2026-08-20)', () {
    test('회사 영문명만 있는 뒷면 — 전부 대문자 로고체는 직함을 비운다', () {
      // 뒷면에 회사 영문명("PRIME LOGISTICS")과 부서 잔여 텍스트만 있고
      // 직함 키워드가 하나도 없는 경우 — 예전엔 leftover 맨 앞을 검증 없이
      // 직함으로 썼다.
      final r = parse([
        'PRIME LOGISTICS',
        'DISTRIBUTION CENTER',
        '02-555-1234',
      ]);
      expect(r.title, isNot(contains('DISTRIBUTION')));
      expect(r.title, isEmpty);
    });

    test('LG CNS 사례 재현 — 전부 대문자 회사 영문명이 직함 칸에 들어가지 않는다', () {
      // 실제 접미사가 없는 회사명("LG CNS")은 회사 키워드 목록에 안 걸려
      // 부서 잔여 텍스트가 대신 회사 칸을 차지하는 것과 별개로, 예전엔
      // "LG CNS" 자체가 직함 칸의 leftover 맨 앞으로 밀려 들어갔다.
      final r = parse([
        '김도영',
        'DT OPTIMIZATION',
        'LG CNS',
        'M 010-1234-5678',
      ]);
      expect(r.name, '김도영');
      expect(r.title, isNot('LG CNS'));
    });

    test('키워드가 있는 순수 영문 줄은 그대로 직함이 된다 — 회귀 확인', () {
      // 이 필터는 "직함 키워드도, 이름-직함 분리도 실패한 마지막 폴백"에서만
      // 순수 영문·전부 대문자를 거른다. 키워드가 걸린 titleLine은 영향받지
      // 않는다.
      final r = parse(['NELSON SPORTS, INC.', 'John Smith', 'Sales Manager']);
      expect(r.title, 'Sales Manager');
    });

    test('한글이 섞인 약한 폴백은 그대로 쓴다 — 회귀 확인', () {
      final r = parse(['디지털 커뮤니케이션 파트 / 책임', '(주)한빛정보기술']);
      // '책임'이 직함 키워드라 titleLine으로 바로 잡힌다 — 폴백 경로가 아니다.
      // ⚠️ **기대를 고쳤다**(2026-08-29). 예전에는 `디지털 커뮤니케이션 파트 /
      //    책임`이 **통째로 직함 칸**에 들어갔고 이 검사는 그것을 지키고 있었다.
      //    지금은 `/`로 묶여 온 직함을 갈라 **직함 `책임` · 부서 `디지털
      //    커뮤니케이션 파트`**로 나눈다 — 명함에 인쇄된 뜻 그대로다.
      //    이 검사의 본래 목적(부서명이 이름 자리를 뺏지 않는지)은 위
      //    `expect(r.name, '홍승권')`이 그대로 지킨다.
      expect(r.title, '책임');
      expect(r.department, contains('디지털'));
    });

    test('키워드 목록에 없는 정상 영문 직함(Title Case)은 막지 않는다', () {
      // "전부 대문자면 버린다"로 좁힌 핵심 이유 — 이 세 직함은 키워드
      // 목록(Manager·Director 등)에 없어서 titleLine으로 못 잡히고 이
      // 폴백까지 내려오는데, 회사 로고와 달리 Title Case로 인쇄된다.
      expect(
        parse(['(주)한빛정보기술', 'John Smith', 'Business Development']).title,
        'Business Development',
      );
      expect(
        parse(['(주)한빛정보기술', 'John Smith', 'Account Executive']).title,
        'Account Executive',
      );
      expect(
        parse(['(주)한빛정보기술', 'John Smith', 'Product Owner']).title,
        'Product Owner',
      );
    });
  });

  group('약한 이름 후보(mixedToken) 보수화 — 성씨 모양까지 확인 (P1, 2026-08-20)', () {
    // 배경: 아이폰 실사용 175회 진단에서 이름의 23%가 "약한 근거"로
    // 채워졌다(추가 343). "약"은 `nameLineWeak`(mixedTokenFront/Last) —
    // 한글+영문이 섞인 줄에서 토큰 하나만 떼어 이름으로 쓰는 경로다.
    //
    // 예전엔 "한글 2~4자면" 통과였다. 정답지(103장) 채점에서 이 경로로
    // 뽑힌 이름 중 다섯 장이 실제로 회사·업종 낱말이었다 — "카카오"(도배
    // 업체 명함의 SNS 채널명, card_49), "대한민국"(슬로건 조각, card_59),
    // "장장동일"(OCR 중복 오독, card_64), "하나"(회사 상호 조각, card_108),
    // "혀청"(자격증 나열 줄의 잡음, card_105). 다섯 다 성씨로 시작하지
    // 않거나 정확히 3자(두 글자 성씨는 4자)가 아니었다.
    //
    // 그래서 확정 경로(`_extractPersonNameToken`)가 이미 쓰는 성씨 모양
    // 검사(`_hangulNameLooksReal`)를 이 약한 경로에도 추가했다. 성씨
    // 목록에 없는 진짜 이름(`감동훈`의 `감` 등, 추가 199 근거)은 이
    // 경로에서 빠지지만, 그 경우도 아래 확정 경로들이 대개 대신 찾아준다
    // — 채점기 전/후로 확인했다(이름 85%→88%, 회사·직함 회귀 없음).
    test('업종·SNS 채널명이 성씨 모양이 아니면 이름으로 쓰지 않는다 — card_49', () {
      final r = parse([
        '도배사 박수민',
        '카카오 3333-21-6287869',
      ]);
      // 예전엔 "카카오"(SNS 채널 라벨)가 mixedTokenFront로 이름이 됐다.
      // 지금은 성씨 모양이 아니라 걸러지고, 확정 경로("도배사 박수민"의
      // 직함 분리)가 대신 진짜 이름을 찾는다.
      expect(r.name, '박수민');
      expect(r.parseShape?.nameSource, isNot(OcrNameSource.mixedTokenFront));
    });

    test('4자 슬로건 조각이 성씨 모양이 아니면 이름으로 쓰지 않는다 — card_59', () {
      final r = parse([
        '대한민국 No.1 윤설미 ASIA',
      ]);
      // "대한민국"(4자, 성씨 아님)이 mixedTokenFront로 뽑히는 대신, 같은
      // 줄의 진짜 이름 "윤설미"를 확정 경로(hangulTokenPreferred)가 찾는다.
      expect(r.name, '윤설미');
      expect(r.parseShape?.nameSource, isNot(OcrNameSource.mixedTokenFront));
    });

    test('OCR 중복 오독은 성씨 모양이 아니면 걸러지고, 확정 경로가 재시도한다 — card_64', () {
      final r = parse([
        'BUSAN, KOREA',
        '장 장동일 (Daniel)',
      ]);
      // "장장동일"(중복 오독, 4자, 성씨 아님)이 그대로 이름이 되는 대신
      // 걸러지고, hangulTokenPreferred가 "장동일"을 다시 찾아낸다.
      expect(r.name, '장동일');
    });

    test('짧은 회사 상호 조각은 이름이 되지 않고 빈 값으로 남는다 — card_108', () {
      // 진짜 이름("이의중")이 직함과 공백으로 뭉개져("차장이 의 중") 다른
      // 어느 경로로도 못 찾는 사례 — 그래도 "하나"(2자, 성씨 아님)가
      // 대신 이름이 되는 것보다는 비워 두는 쪽이 낫다(CLAUDE.md 원칙).
      final r = parse([
        '하나 Control',
        '차장이 의 중',
      ]);
      expect(r.name, isNot('하나'));
    });

    test('⚠️ 성씨 목록에 없는 진짜 이름은 이 경로에서 빠질 수 있다 — 알려진 한계', () {
      // "감"(감사와 겹쳐 일부러 뺀 성씨, 추가 199)으로 시작하는 이름은
      // mixedToken 경로로는 못 찾는다. 이 카드는 확정 경로(koreanStripped
      // — 이름이 온전히 제 줄에 있음)로 이미 잡히므로 실제 정답지에서는
      // 영향이 없었지만, 로고와 완전히 한 줄로 뭉치면 비워질 수 있다.
      final r = parse(['이랜서 감동훈', 'M 010-4381-0042']);
      expect(r.name, isNot('감동훈')); // 알려진 한계 — 회귀 아님, 원래도 못 찾던 모양
    });
  });

  group('P0② — 이름란이 회사 영문명으로 자동 변경 (테스터 B, 2026-08-20)', () {
    // 재현: "뒷장 촬영 후 이름란이 회사 영문명으로 자동 변경". 뒷면이 영문
    // 전용이고 이름·직함·회사 셋 다 순수 영문일 때, leftover 순서(카드 위
    // 인쇄 순서)가 이르다는 이유만으로 회사 영문명("LG CNS")이 이름 자리를
    // 차지했다. 오늘 이미 검증한 신호(Title Case = 사람 이름)를 재사용해,
    // **사람 이름 모양(또는 한글)인 후보가 있으면 그것부터** 이름으로 본다.
    test('회사 영문명이 이름보다 먼저 인쇄돼도 이름 자리를 뺏지 않는다', () {
      final r = parse(['LG CNS', 'DT Optimization', 'Kim Do Young']);
      expect(r.name, 'Kim Do Young');
      expect(r.parseShape?.nameSource, OcrNameSource.leftoverFallback);
    });

    test('이름이 먼저 인쇄되면 원래도 맞았다 — 회귀 확인', () {
      final r = parse(['Kim Do Young', 'DT Optimization', 'LG CNS']);
      expect(r.name, 'Kim Do Young');
    });

    test('사람 이름 모양 후보가 하나도 없으면 기존대로 맨 앞 줄을 쓴다', () {
      // 접미사 없는 진짜 회사명은 사람 이름과 형태가 같아 구별이 안 된다
      // (SK telecom·Sovargen). 이 경우 우선순위를 매길 근거가 없으므로
      // 손대지 않는다 — 알려진 한계.
      final r = parse(['SOVARGEN', 'DT OPTIMIZATION']);
      expect(r.name, 'SOVARGEN');
    });
  });

  group('P0③ — 회사명란에 영문 이름이 잘못 입력됨 (테스터 B, 2026-08-20)', () {
    // 재현: "회사명 입력란에 영문 이름이 잘못 입력됨". 한글 이름은 이미
    // 확정됐는데(koreanStripped), 회사명에 접미사가 없어 leftover에서
    // 골라야 할 때 사람 영문 이름("Kim Do Young")이 진짜 회사명("LG CNS")
    // 보다 먼저 나와 회사 자리를 차지했다.
    test('영문 이름이 회사 영문명보다 먼저 인쇄돼도 회사 자리를 뺏지 않는다', () {
      final r = parse([
        '김도영',
        'Kim Do Young',
        'DT Optimization 수석',
        'LG CNS',
        'M 010-1234-5678',
      ]);
      expect(r.name, '김도영');
      expect(r.company, 'LG CNS');
    });

    test('짧은 라벨 잔재(한 단어, Title Case)는 사람 이름으로 보지 않는다 — card_107 회귀 방지', () {
      // "Fax."처럼 Title Case인 한 단어짜리 라벨 잔재까지 "사람 이름
      // 모양"으로 보면, 진짜(비록 잡음이지만) leftover 회사 후보가 밀려나고
      // 더 나쁜 후보가 대신 뽑힌다 — 103장 채점에서 실제로 -1을 냈다. 사람
      // 이름은 최소 두 단어(성+이름)라는 신호로 좁혀 막는다.
      final r = parse([
        '개발협력부장 Tel.',
        '양공현 Fax.',
        'Mobile.',
        'E-mail. gong@rainbowyouth.or.kr',
        'Migrant-Youth',
      ]);
      expect(r.company, isNot('E-mail. . kr'));
    });
  });

  group('이메일 라벨 잔재 정리 (테스터 제보, 신규 등록 96건 실측, 2026-08-21)', () {
    // 실측 근거: 신규 등록 96건 중 "E."로 시작한 이메일 4건 전부가 라벨
    // 잔재를 붙인 채 저장됐다 — 라벨의 마침표가 이메일 로컬파트 허용
    // 문자(".")와 같아서 이메일 정규식이 라벨까지 통째로 삼킨 것이다.
    test('"E." 라벨이 로컬파트에 붙어도 걷어낸다', () {
      final r = parse([
        '조원창',
        'LG CNS',
        'M.010-3144-2154',
        'E.wcho@lgcns.com',
      ]);
      expect(r.email, 'wcho@lgcns.com');
    });

    test('"E." 라벨 — 실측 4건 중 나머지 세 건도 동일하게 걷어낸다', () {
      expect(parse(['E.msseo@lgcns.com']).email, 'msseo@lgcns.com');
      expect(parse(['E.skhong@sportslg.com']).email, 'skhong@sportslg.com');
      expect(parse(['E.kdw0054@incross.com']).email, 'kdw0054@incross.com');
    });

    test('"E-mail:"/"Email " 단어형 라벨도 걷어낸다', () {
      expect(
        parse(['E-mail:test@test.co.kr']).email,
        'test@test.co.kr',
      );
      expect(
        parse(['Email test@test.co.kr']).email,
        'test@test.co.kr',
      );
    });

    test('구분자 없이 라벨과 붙은 경우는 건드리지 않는다 — 오탐 위험', () {
      // "Ejuyeon@sto.or.kr" — 라벨 "E"와 아이디 사이에 마침표/공백 같은
      // 구분자가 전혀 없다. 라벨이 붙은 것인지 원래 아이디 앞글자("juyeon"
      // 앞에 우연히 E가 더 붙은 것)인지 규칙만으로 가릴 수 없어 그대로 둔다.
      final r = parse(['Ejuyeon@sto.or.kr']);
      expect(r.email, 'Ejuyeon@sto.or.kr');
    });

    test('회귀 방지 — 소문자 "e"로 시작하는 정상 아이디는 건드리지 않는다', () {
      // 같은 96건 표본에 실재하는 정상 이메일. 라벨은 인쇄가 대문자("E.")인
      // 반면 실제 로컬파트는 소문자 이니셜식 표기가 흔해서, 대소문자를
      // 신호로 나눴다 — 소문자까지 같이 지우면 이 값들이 깨진다.
      expect(parse(['e.kim@company.com']).email, 'e.kim@company.com');
      expect(
        parse(['eric.maeng@sovargen.com']).email,
        'eric.maeng@sovargen.com',
      );
      expect(parse(['eomysj@handballkorea.com']).email, 'eomysj@handballkorea.com');
    });

    test('회귀 방지 — 대문자 "E"로 시작해도 뒤에 구분자가 없으면 그대로 둔다', () {
      expect(parse(['Erictest@company.com']).email, 'Erictest@company.com');
    });

    test('회귀 방지 — "l"로 시작하는 정상 아이디는 건드리지 않는다', () {
      // 같은 96건 표본에 "lee@…"/"leeh@…" 계열이 다수 실재한다 — 세로
      // 구분선(│)이 OCR에서 소문자 l로 잘못 읽히는 사례가 보고됐지만, 그
      // 잔재를 이메일 값 앞에서 지우는 규칙은 넣지 않았다: "l"로 시작하는
      // 진짜 아이디(성씨 "이"의 로마자 표기 "Lee")가 실제로 흔해서, 문자열
      // 규칙만으로는 구분선 잔재와 실제 아이디를 가를 수 없다(오탐이 더
      // 위험 — CLAUDE.md 4절). 파서가 뽑는 이메일 값 자체는 애초에 공백으로
      // 분리된 "고립 토큰"(예: "…kr l www…")을 삼키지 않으므로(로컬파트
      // 정규식이 공백을 허용하지 않음), 이 값들은 원래도 깨지지 않는다.
      expect(parse(['lee@sovargen.com']).email, 'lee@sovargen.com');
      expect(parse(['leeh@sto.or.kr']).email, 'leeh@sto.or.kr');
    });

    test('@ 앞뒤 공백은 라벨 정리와 별개로 이미 붙여져 저장된다 — 회귀 확인', () {
      // 실측: "E jihyun @sto.or.kr" 원문이 "jihyun@sto.or.kr"로 정상
      // 저장됐다. "E "는 로컬파트 정규식이 공백을 허용하지 않아 애초에
      // 매치에 안 들어가고, "@" 앞의 공백은 기존 로직(추가 시점 불명,
      // `_parse`의 emailRegExp 주석 참고)이 이미 붙여 왔다 — 새 규칙과는
      // 무관하게 유지되는지만 잠근다.
      final r = parse(['E jihyun @sto.or.kr']);
      expect(r.email, 'jihyun@sto.or.kr');
    });

    test('이름 중간 공백은 이어붙이지 않는다 — 범위 밖(의도적)', () {
      // 실측: "E.seungho. lee@lgcns.com" 원문은 실제로는
      // "seungho.lee@lgcns.com"이어야 하지만, "seungho." 뒤에 공백이 있어
      // 로컬파트 정규식이 거기서 끊긴다. 그 결과 앞부분("seungho.")을 통째로
      // 놓치고 "lee@lgcns.com"만 남는다 — 틀린 값이지만 "존재하지 않는
      // 값을 추측해 붙이는 것"보다 안전하다(CLAUDE.md "가짜 데이터를 만들지
      // 않는다"). 이름 중간 공백까지 이어붙이는 규칙은 일부러 넣지 않았다.
      final r = parse(['E.seungho. lee@lgcns.com']);
      expect(r.email, 'lee@lgcns.com');
    });
  });
}

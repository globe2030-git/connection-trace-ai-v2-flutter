import 'package:flutter/foundation.dart';
import '../models/contact_model.dart';
import '../../core/utils/geo_utils.dart';

class ContactsRepository extends ChangeNotifier {
  List<ContactModel> _contacts = [
    const ContactModel(
      id: 'c1',
      name: '김민준',
      company: '테크노바',
      title: '이사 / 파트너십',
      phone: '010-8977-9661',
      email: 'minjun.kim@technova.co.kr',
      geo: GeoPosition(lat: 37.5012, lng: 127.0375), // 140m away
      tags: ['IT/테크', '핵심인맥', '스타트업'],
      talkingPoints: [
        '최근 테크노바 AI 에이전트 솔루션 출시 축하 인사 나누기',
        '다음 주 수요일 기술 세미나 참석 여부 확인하기',
        '지난번 제안했던 공동 파트너십 워크숍 일정 조율하기'
      ],
      isPriority: true,
      memo: '테헤란로 세미나에서 인연이 됨. 신규 AI 프로젝트에 협업 관심 높음.',
    ),
    const ContactModel(
      id: 'c2',
      name: '한소율',
      company: '바이오넥스트',
      title: '팀장 / R&D 파트너십',
      phone: '010-3456-7890',
      email: 'soyul.han@bionext.co.kr',
      geo: GeoPosition(lat: 37.5035, lng: 127.0392), // 420m away
      tags: ['바이오', '연구개발', '동문'],
      talkingPoints: [
        '최근 상장 준비 관련 축하 및 안부 나누기',
        '바이오 데이터 분석 인프라 구축 건 조언 구하기',
        '다음 달 업계 컨퍼런스 사전 미팅 일정 체크'
      ],
      isPriority: true,
      memo: 'KAIST 동문. 바이오 R&D 데이터 플랫폼 구축에 깊은 지식 보유.',
    ),
    const ContactModel(
      id: 'c3',
      name: '오현우',
      company: '글로벌커넥트',
      title: '영업본부장',
      phone: '010-5566-7788',
      email: 'hw.oh@globalconnect.com',
      geo: GeoPosition(lat: 37.5078, lng: 127.0421), // 950m away
      tags: ['영업', '글로벌', '마케팅'],
      talkingPoints: [
        '동남아 시장 진출 전략 모범 사례 문의하기',
        '분기별 네트워크 조찬 모임 참석 여부 묻기',
        '신규 해외 네트워킹 행사 추천 부탁하기'
      ],
      isPriority: false,
      memo: '글로벌 마케팅 및 판로 개척 관련 유용한 인사이트가 많으심.',
    ),
    const ContactModel(
      id: 'c4',
      name: '박지민',
      company: '쿠팡',
      title: '수석 디자이너',
      phone: '010-7788-9900',
      email: 'jimin.park@coupang.com',
      geo: GeoPosition(lat: 37.5120, lng: 127.0510), // 1.8km away
      tags: ['디자인', 'UX/UI', '이커머스'],
      talkingPoints: [
        '최근 라이브한 디자인 시스템 업데이트 안부 묻기',
        '모바일 UX 3D 인터랙션 모범 사례 피드백 공유하기'
      ],
      isPriority: false,
      memo: 'UX 디자인 세미나 발표자로 만남.',
    )
  ];

  List<ContactModel> get contacts => List.unmodifiable(_contacts);

  void addContact(ContactModel newContact) {
    _contacts = [newContact, ..._contacts];
    notifyListeners();
  }

  void togglePriority(String id) {
    _contacts = _contacts.map((c) {
      if (c.id == id) {
        return c.copyWith(isPriority: !c.isPriority);
      }
      return c;
    }).toList();
    notifyListeners();
  }
}

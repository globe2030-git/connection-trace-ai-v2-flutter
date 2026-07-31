import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact_model.dart';
import '../../core/utils/geo_utils.dart';

class ContactsRepository extends ChangeNotifier {
  static const String _storageKey = 'saved_contacts_v2';

  List<ContactModel> _contacts = [
    ContactModel(
      id: 'c1',
      name: '김민준',
      company: '테크노바',
      title: '이사 / 파트너십',
      phone: '010-8977-9661',
      officePhone: '02-555-1234',
      email: 'minjun.kim@technova.co.kr',
      address: '서울특별시 강남구 테헤란로 123 (역삼동)',
      avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      geo: const GeoPosition(lat: 37.5012, lng: 127.0375),
      tags: ['IT/테크', '핵심인맥', '스타트업'],
      talkingPoints: [
        '최근 테크노바 AI 에이전트 솔루션 출시 축하 인사 나누기',
        '다음 주 수요일 기술 세미나 참석 여부 확인하기',
        '지난번 제안했던 공동 파트너십 워크숍 일정 조율하기'
      ],
      commLogs: [
        CommunicationLogModel(
          type: 'call',
          summary: '수신 통화 (04분 12초) - AI 프로젝트 파트너십 회의 결과 공유',
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        CommunicationLogModel(
          type: 'kakao',
          summary: '카카오톡 메세지 - "다음 주 수요일 기술 세미나 자료 보내드립니다!"',
          timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        CommunicationLogModel(
          type: 'email',
          summary: '이메일 수신 - [테크노바] 2026 Q3 공동 사업 제안서 첨부.pdf',
          timestamp: DateTime.now().subtract(const Duration(days: 1)),
        ),
        CommunicationLogModel(
          type: 'sms',
          summary: '문자 메시지 - "역삼동 오시면 연락주세요. 커피 한 잔 하시죠."',
          timestamp: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ],
      isPriority: true,
      memo: '테헤란로 세미나에서 인연이 됨. 신규 AI 프로젝트에 협업 관심 높음.',
    ),
    ContactModel(
      id: 'c2',
      name: '한소율',
      company: '바이오넥스트',
      title: '팀장 / R&D 파트너십',
      phone: '010-3456-7890',
      officePhone: '02-345-6789',
      email: 'soyul.han@bionext.co.kr',
      address: '서울특별시 서초구 반포대로 45 (서초동)',
      avatarUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=150',
      geo: const GeoPosition(lat: 37.5035, lng: 127.0392),
      tags: ['바이오', '연구개발', '동문'],
      talkingPoints: [
        '최근 상장 준비 관련 축하 및 안부 나누기',
        '바이오 데이터 분석 인프라 구축 건 조언 구하기',
        '다음 달 업계 컨퍼런스 사전 미팅 일정 체크'
      ],
      commLogs: [
        CommunicationLogModel(
          type: 'email',
          summary: '이메일 수신 - 바이오 헬스케어 데이터 연동 스펙 문의',
          timestamp: DateTime.now().subtract(const Duration(hours: 4)),
        ),
        CommunicationLogModel(
          type: 'kakao',
          summary: '카카오톡 메세지 - "KAIST 동문회 날짜 확정되었습니다."',
          timestamp: DateTime.now().subtract(const Duration(days: 1)),
        ),
        CommunicationLogModel(
          type: 'call',
          summary: '발신 통화 (02분 45초) - R&D 과제 공동 신청 논의',
          timestamp: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ],
      isPriority: true,
      memo: 'KAIST 동문. 바이오 R&D 데이터 플랫폼 구축에 깊은 지식 보유.',
    ),
    ContactModel(
      id: 'c3',
      name: '오현우',
      company: '글로벌커넥트',
      title: '영업본부장',
      phone: '010-5566-7788',
      email: 'hw.oh@globalconnect.com',
      address: '서울특별시 영등포구 여의대로 88 (여의도동)',
      avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
      geo: const GeoPosition(lat: 37.5078, lng: 127.0421),
      tags: ['영업', '글로벌', '마케팅'],
      talkingPoints: [
        '동남아 시장 진출 전략 모범 사례 문의하기',
        '분기별 네트워크 조찬 모임 참석 여부 묻기',
        '신규 해외 네트워킹 행사 추천 부탁하기'
      ],
      commLogs: [
        CommunicationLogModel(
          type: 'call',
          summary: '부재중 전화 - 오현우 본부장',
          timestamp: DateTime.now().subtract(const Duration(hours: 6)),
        ),
        CommunicationLogModel(
          type: 'sms',
          summary: '문자 메시지 - "여의도 조찬 모임 참석 안내 드립니다."',
          timestamp: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ],
      isPriority: false,
      memo: '글로벌 마케팅 및 판로 개척 관련 유용한 인사이트가 많으심.',
    ),
  ];

  ContactsRepository() {
    _loadFromDisk();
  }

  List<ContactModel> get contacts => List.unmodifiable(_contacts);

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _contacts = jsonList.map((j) => ContactModel.fromJson(j as Map<String, dynamic>)).toList();
        notifyListeners();
      } else {
        // Save initial seed contacts so future restarts persist
        await _saveToDisk();
      }
    } catch (e) {
      debugPrint('Error loading saved contacts: $e');
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _contacts.map((c) => c.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('Error saving contacts to disk: $e');
    }
  }

  void addContact(ContactModel newContact) {
    _contacts = [newContact, ..._contacts];
    notifyListeners();
    _saveToDisk();
  }

  void updateContact(ContactModel updatedContact) {
    _contacts = _contacts.map((c) {
      if (c.id == updatedContact.id) {
        return updatedContact;
      }
      return c;
    }).toList();
    notifyListeners();
    _saveToDisk();
  }

  void deleteContact(String id) {
    _contacts.removeWhere((c) => c.id == id);
    notifyListeners();
    _saveToDisk();
  }

  void togglePriority(String id) {
    _contacts = _contacts.map((c) {
      if (c.id == id) {
        return c.copyWith(isPriority: !c.isPriority);
      }
      return c;
    }).toList();
    notifyListeners();
    _saveToDisk();
  }
}

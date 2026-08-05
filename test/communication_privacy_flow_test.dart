import 'package:connection_trace_ai_flutter/core/services/ai_briefing_service.dart';
import 'package:connection_trace_ai_flutter/core/services/email_sync_service.dart';
import 'package:connection_trace_ai_flutter/data/models/contact_model.dart';
import 'package:connection_trace_ai_flutter/data/models/my_profile_model.dart';
import 'package:connection_trace_ai_flutter/presentation/features/briefing/views/ai_data_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final contact = ContactModel(
    id: 'contact-1',
    name: '김연결',
    company: '커넥션',
    title: '대표',
    phone: '01012345678',
    email: 'contact@example.com',
    tags: const ['파트너'],
    interests: const ['골프'],
    talkingPoints: const [],
    memo: '다음 달 행사 논의',
    commLogs: [
      CommunicationLogModel(
        id: 'selected-log',
        type: 'sms',
        summary: '선택한 문자 내용',
        timestamp: DateTime(2026, 8, 2),
      ),
      CommunicationLogModel(
        id: 'excluded-log',
        type: 'kakao',
        summary: '제외할 카카오톡 내용',
        timestamp: DateTime(2026, 8, 1),
      ),
    ],
  );

  const profile = MyProfileModel(
    name: '사용자',
    title: '매니저',
    company: '테스트사',
    phone: '',
    email: '',
    address: '',
  );

  // 프롬프트 자체는 이제 서버(functions/src/index.ts의 buildPrompt)에서 조립된다.
  // 클라이언트가 여전히 책임지는 부분은 "요청 페이로드에 정확히 무엇을
  // 담아 보내는가"이므로, 그 경계에서 개인정보 최소전송 원칙을 검증한다.
  test('요청 페이로드에는 호출자가 명시적으로 선택한 소통 기록만 매핑된다', () {
    final mapped = [
      contact.commLogs.first,
    ].map(AiBriefingService.formatCommunicationLog).join('\n');

    expect(mapped, contains('선택한 문자 내용'));
    expect(mapped, isNot(contains('제외할 카카오톡 내용')));
  });

  test('상대방 요약에는 태그와 메모가 포함된다', () {
    final summary = AiBriefingService.buildContactSummary(contact);

    expect(summary, contains('김연결'));
    expect(summary, contains('파트너'));
    expect(summary, contains('다음 달 행사 논의'));
  });

  test('관심사는 요청 페이로드의 별도 필드로 그대로 전달된다', () {
    // interests/weatherSummary는 서버 프롬프트에 함께 들어가지만, 클라이언트
    // 쪽에서는 문자열로 미리 합치지 않고 원본 그대로 넘긴다(functions/src의
    // GenerateBriefingRequest 형식과 동일).
    expect(contact.interests.join(', '), '골프');
  });

  test('과거 저장 데이터도 ID와 출처가 보완되어 복원된다', () {
    final legacy = CommunicationLogModel.fromJson({
      'type': 'call',
      'summary': '통화 메모',
      'timestamp': '2026-08-01T10:00:00.000',
      'isAutoSynced': true,
    });

    expect(legacy.id, isNotEmpty);
    expect(legacy.source, 'legacy');
    expect(CommunicationLogModel.fromJson(legacy.toJson()).id, legacy.id);
  });

  test('Gmail internalDate 밀리초를 기기 시각으로 변환한다', () {
    final parsed = EmailSyncService.parseInternalDate('1785661200000');
    expect(parsed.millisecondsSinceEpoch, 1785661200000);
  });

  testWidgets('AI 전송 동의 전에는 생성 버튼을 누를 수 없다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDataReviewSheet(
            contact: contact,
            myProfile: profile,
          ),
        ),
      ),
    );

    final button = find.widgetWithText(ElevatedButton, '동의하고 AI 가이드 만들기');
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

    await tester.ensureVisible(find.byType(Checkbox).last);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();

    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
  });
}

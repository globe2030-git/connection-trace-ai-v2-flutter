import 'package:connection_trace_ai_flutter/core/services/ai_briefing_service.dart';
import 'package:connection_trace_ai_flutter/core/services/email_sync_service.dart';
import 'package:connection_trace_ai_flutter/data/models/ai_provider.dart';
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

  test('AI 프롬프트에는 호출자가 명시적으로 선택한 소통 기록만 포함된다', () {
    final prompt = AiBriefingService.buildPrompt(
      contact: contact,
      myProfile: profile,
      communicationLogs: [contact.commLogs.first],
    );

    expect(prompt, contains('선택한 문자 내용'));
    expect(prompt, isNot(contains('제외할 카카오톡 내용')));
  });

  test('AI 프롬프트에 관심사와(있으면) 날씨 정보가 포함된다', () {
    final promptWithWeather = AiBriefingService.buildPrompt(
      contact: contact,
      myProfile: profile,
      communicationLogs: const [],
      weatherSummary: '맑음, 24°C',
    );

    expect(promptWithWeather, contains('골프'));
    expect(promptWithWeather, contains('맑음, 24°C'));

    final promptWithoutWeather = AiBriefingService.buildPrompt(
      contact: contact,
      myProfile: profile,
      communicationLogs: const [],
    );

    expect(promptWithoutWeather, isNot(contains('오늘 상대방 지역 날씨')));
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
            provider: AiProvider.openai,
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

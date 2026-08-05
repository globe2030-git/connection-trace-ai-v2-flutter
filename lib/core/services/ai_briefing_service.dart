import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/contact_model.dart';
import '../../data/models/my_profile_model.dart';

class AiBriefingException implements Exception {
  final String message;
  AiBriefingException(this.message);
  @override
  String toString() => message;
}

/// Cloud Functions(`generateBriefing`)가 아직 배포되지 않았을 때 던진다.
/// 서버 배포가 끝나 [AiBriefingService.kAiServiceDeployed]를 true로 바꾸기
/// 전까지는 호출을 시도하지 않고 바로 이 예외로 안내한다.
class AiServiceUnavailableException extends AiBriefingException {
  AiServiceUnavailableException()
    : super('AI 브리핑 서비스 준비 중이에요. 곧 제공될 예정이에요.');
}

/// 서버가 하루/월 사용 한도 초과로 거절했을 때. 메시지는 서버
/// (functions/src/index.ts의 HttpsError)가 준 안내문을 그대로 쓴다.
class AiQuotaExceededException extends AiBriefingException {
  AiQuotaExceededException(super.message);
}

/// 커넥션센스가 제공하는 AI로 상대방과의 대화 포인트를 생성한다.
///
/// 예전에는 사용자가 직접 발급받은 API 키로 Claude/ChatGPT/Gemini를 각자
/// 호출했지만(BYOK), 비개발자에게 API 키 발급이 너무 높은 진입장벽이라는
/// 판단에 따라 앱 운영사 소유 키로 서버(Cloud Functions)가 대신 호출하는
/// 구조로 바꿨다. 클라이언트는 더 이상 어떤 키도 다루지 않는다.
///
/// 서버 함수는 functions/src/index.ts의 generateBriefing — 하루 10회/월
/// 100회 한도, Gemini 호출, Firestore 트랜잭션 기반 사용량 카운팅까지 이미
/// 구현되어 있지만, Firebase 프로젝트가 아직 Blaze 요금제로 전환되지 않아
/// 배포되지 않은 상태다(task #43·#44). 배포가 끝나면 [kAiServiceDeployed]만
/// true로 바꾸면 된다.
class AiBriefingService {
  static const _timeout = Duration(seconds: 30);
  static const _region = 'asia-northeast3';

  /// 하루/월 사용 한도 — 실제 값은 functions/src/index.ts의
  /// DAILY_LIMIT/MONTHLY_LIMIT가 최종 진실이며, 여기는 화면 안내용 표시값이다.
  static const int dailyLimit = 10;
  static const int monthlyLimit = 100;

  /// Cloud Functions 배포 완료 여부 — task #44에서 배포 후 true로 변경.
  static const bool kAiServiceDeployed = false;

  static Future<List<String>> generateTalkingPoints({
    required ContactModel contact,
    required MyProfileModel myProfile,
    required List<CommunicationLogModel> communicationLogs,
    // 오늘 상대방 지역 날씨 요약(예: "맑음, 24°C"). 호출부(AiDataReviewSheet)가
    // WeatherService로 미리 조회해 동의 화면에 보여준 뒤 여기로 넘긴다.
    // geo가 없거나 조회에 실패했으면 null — 그 경우 프롬프트에서 조용히 생략된다.
    String? weatherSummary,
  }) async {
    if (!kAiServiceDeployed) {
      throw AiServiceUnavailableException();
    }

    final callable = FirebaseFunctions.instanceFor(
      region: _region,
    ).httpsCallable('generateBriefing');

    try {
      final result = await callable
          .call<Map<String, dynamic>>({
            'contactSummary': buildContactSummary(contact),
            'myProfileSummary': buildMyProfileSummary(myProfile),
            'communicationLogs': communicationLogs
                .map(formatCommunicationLog)
                .toList(),
            if (weatherSummary != null) 'weatherSummary': weatherSummary,
            'interests': contact.interests.join(', '),
          })
          .timeout(_timeout);

      final points = (result.data['talkingPoints'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      if (points.isEmpty) throw AiBriefingException('AI가 빈 응답을 반환했습니다.');
      return points;
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'not-found':
        case 'unavailable':
          throw AiServiceUnavailableException();
        case 'resource-exhausted':
          throw AiQuotaExceededException(e.message ?? '사용 한도에 도달했어요.');
        default:
          throw AiBriefingException(e.message ?? 'AI 응답을 받지 못했습니다.');
      }
    } on TimeoutException {
      throw AiBriefingException('요청 시간이 초과됐습니다. 잠시 후 다시 시도해 주세요.');
    }
  }

  @visibleForTesting
  static String buildContactSummary(ContactModel contact) {
    final lines = <String>[
      '이름: ${contact.name}',
      '직함/회사: ${contact.title} / ${contact.company}',
      '태그: ${contact.tags.isEmpty ? '없음' : contact.tags.join(', ')}',
      if ((contact.memo ?? '').trim().isNotEmpty) '메모: ${contact.memo}',
    ];
    return lines.join('\n');
  }

  @visibleForTesting
  static String buildMyProfileSummary(MyProfileModel myProfile) {
    return '이름: ${myProfile.name}\n직함/회사: ${myProfile.title} / ${myProfile.company}';
  }

  /// 전달받은 소통 기록 하나를 서버로 보낼 한 줄 텍스트로 바꾼다. 여기 들어오는
  /// 목록은 [AiDataReviewSheet]에서 사용자가 명시적으로 체크한 항목만이라,
  /// 이 함수 자체는 "무엇을 포함할지"가 아니라 "어떻게 표현할지"만 책임진다.
  @visibleForTesting
  static String formatCommunicationLog(CommunicationLogModel log) =>
      '[${_channelLabel(log.type)}] ${log.summary}';

  static String _channelLabel(String type) => switch (type) {
    'call' => '통화 메모',
    'sms' => '문자',
    'email' => '이메일',
    'kakao' => '카카오톡',
    _ => '소통 기록',
  };
}

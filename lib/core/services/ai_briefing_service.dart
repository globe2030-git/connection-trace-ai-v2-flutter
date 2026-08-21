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

/// 서버 함수가 아직 배포되지 않았거나(`kAiServiceDeployed == false`) 함수를
/// 찾지 못한 경우(`not-found`). 사용자가 할 수 있는 일이 없는 상태다.
class AiServiceUnavailableException extends AiBriefingException {
  AiServiceUnavailableException() : super('AI 브리핑 서비스 준비 중이에요. 곧 제공될 예정이에요.');
}

/// 서버는 살아 있는데 일시적으로 응답하지 못하는 경우(`unavailable`).
///
/// **"준비 중"과 반드시 구분해야 한다.** 예전에는 둘을 같은 예외로 묶어
/// 일시적 장애에도 "서비스 준비 중이에요"라고 안내했는데, 사용자는 기능이
/// 아직 출시되지 않은 것으로 이해하고 **다시 시도하지 않는다.** 실제로는
/// 잠시 후 되는 상황이므로 그렇게 말해야 한다.
class AiServiceTemporarilyDownException extends AiBriefingException {
  AiServiceTemporarilyDownException()
    : super('AI 서버가 잠시 응답하지 못하고 있어요. 잠시 후 다시 시도해 주세요.');
}

/// 앱 인증(App Check) 실패. 우리 앱임을 증명하지 못한 경우.
///
/// 사용자 잘못이 아니고 사용자가 고칠 수도 없는 상황이라, 원인을 설명하기보다
/// 할 수 있는 일을 알려준다. 예전에는 이 경우가 기본 분기로 떨어져 서버가 준
/// 영문 원문("Unauthenticated")이 그대로 화면에 나왔다.
class AiAppCheckRejectedException extends AiBriefingException {
  AiAppCheckRejectedException()
    : super(
        '앱 인증에 실패했어요. 앱을 최신 버전으로 업데이트한 뒤 다시 시도해 주세요.\n'
        '계속 같은 문제가 생기면 설정 → 1:1 문의로 알려주세요.',
      );
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
/// 100회 한도, Gemini 호출, Firestore 트랜잭션 기반 사용량 카운팅까지 구현돼
/// 2026-08-07 Blaze 전환 후 asia-northeast3에 배포 완료됐다(task #41·#43·#44).
/// 한도는 아직 구독 등급 구분 없이 전 사용자 동일하다(#58, 별도 작업 예정).
class AiBriefingService {
  static const _timeout = Duration(seconds: 30);

  /// 서버 함수가 배포된 리전. 다른 서비스(관리자 사용량 조회 등)도 같은 리전을
  /// 불러야 하므로 공개한다 — 리전이 어긋나면 함수를 못 찾아 실패한다.
  static const String region = 'asia-northeast3';

  /// 하루/월 사용 한도.
  ///
  /// ⚠️ **`functions/src/index.ts`의 `DAILY_LIMIT`/`MONTHLY_LIMIT`과 반드시
  /// 같은 값이어야 한다.** 판정은 서버가 하고 여기는 표시만 하는데, 두 값이
  /// 어긋나면 화면에 "3회 남음"이라고 띄워 놓고 서버가 거절하는(또는 그 반대)
  /// 상황이 된다. 언어가 달라 상수를 공유할 수 없으므로 **바꿀 때 두 파일을
  /// 함께 고치는 수밖에 없다.**
  ///
  /// 🚧 **직원 테스트 기간 한정 20.** 테스터가 하루에 여러 번 눌러 봐야 하는데
  /// 10회에 막히면 "AI가 안 된다"는 제보만 쌓이고 정작 봐야 할 것을 못 본다.
  ///
  /// 📌 **2026-08-18: "10으로 되돌린다"(옛 P0-11)는 없어졌다.** 사용자가 하루
  /// 한도 제도 자체를 없애기로 확정했고, 그 항목은 **P1-5(지갑 전환)에 흡수**됐다
  /// — 지갑이 켜지는 시점에 이 상수와 서버의 `DAILY_LIMIT`이 **함께 사라진다.**
  ///
  /// ⚠️ **그래서 "그냥 둬도 되는 값"이 된 것은 아니다.** 원래 취지는 *"설계의
  /// 2배 비용 상한으로 출시하지 않는다"*였고, 그 취지는 **지갑이 실제로 켜질
  /// 때까지 살아 있다.** 지갑 전환 없이 스토어에 나가는 경로가 생기면 그때는
  /// 다시 10으로 되돌려야 한다.
  ///
  /// ⚠️ 서버(`functions/src/index.ts`의 `DAILY_LIMIT`)와 **반드시 같은 값**이어야
  /// 한다. 판정은 서버가 하고 앱은 표시만 하므로 어긋나면 화면엔 "남음"인데
  /// 서버가 거절한다.
  static const int dailyLimit = 20;
  static const int monthlyLimit = 100;

  /// Cloud Functions 배포 완료 여부 — task #44에서 배포 후 true로 변경.
  static const bool kAiServiceDeployed = true;

  static Future<List<String>> generateTalkingPoints({
    required ContactModel contact,
    required MyProfileModel myProfile,
    required List<CommunicationLogModel> communicationLogs,
    // 오늘 상대방 지역 날씨 요약(예: "맑음, 24°C"). 호출부(AiDataReviewSheet)가
    // WeatherService로 미리 조회해 동의 화면에 보여준 뒤 여기로 넘긴다.
    // geo가 없거나 조회에 실패했으면 null — 그 경우 프롬프트에서 조용히 생략된다.
    String? weatherSummary,
    // 통화/문자/카카오톡 자동 연동이 없는 상황을 보완하기 위해 동의 화면에서
    // 사용자가 직접 적어 넣은 메모(선택). 비어 있으면 null.
    String? extraNote,
    // F-07(재생성 다양성): "새로 생성"을 누르기 직전 화면에 떠 있던 대화 포인트.
    // 서버(buildPrompt)가 이 문장들을 피해 다른 각도로 만들도록 지시한다.
    // 최초 생성이면 비어 있거나 null — 그때는 제외 지시가 붙지 않는다.
    List<String>? previousPoints,
  }) async {
    if (!kAiServiceDeployed) {
      throw AiServiceUnavailableException();
    }

    final callable = FirebaseFunctions.instanceFor(
      region: region,
    ).httpsCallable('generateBriefing');

    try {
      final result = await callable
          .call<Map<String, dynamic>>({
            'contactSummary': buildContactSummary(contact),
            'myProfileSummary': buildMyProfileSummary(myProfile),
            'communicationLogs': communicationLogs
                .map(formatCommunicationLog)
                .toList(),
            'weatherSummary': ?weatherSummary,
            'extraNote': ?extraNote,
            'interests': contact.interests.join(', '),
            // 비어 있으면 아예 보내지 않는다 — 서버는 없는 값으로 취급해
            // 제외 지시를 생략한다(입력 토큰도 아낀다).
            if ((previousPoints ?? const <String>[]).isNotEmpty)
              'previousPoints': previousPoints,
          })
          .timeout(_timeout);

      final points = (result.data['talkingPoints'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      if (points.isEmpty) throw AiBriefingException('AI가 빈 응답을 반환했습니다.');
      return points;
    } on FirebaseFunctionsException catch (e) {
      // 서버가 주는 코드별로 "사용자가 무엇을 할 수 있는지"가 다르다.
      // 뭉뚱그리면 다시 시도하면 될 상황에 포기하거나(그 반대) 하게 된다.
      switch (e.code) {
        case 'not-found':
          // 함수가 배포되지 않았다 — 사용자가 할 수 있는 일이 없다.
          throw AiServiceUnavailableException();
        case 'unavailable':
        case 'internal':
          // 서버는 있는데 지금 안 된다 — 잠시 후 되면 되는 상황.
          throw AiServiceTemporarilyDownException();
        case 'unauthenticated':
          // App Check 거부 또는 로그인 만료. 서버가 주는 원문이 영문
          // ("Unauthenticated")이라 그대로 노출하면 안 된다.
          throw AiAppCheckRejectedException();
        case 'failed-precondition':
          // 앱 무결성 확인(App Check)에 걸렸다. 이용자가 다시 눌러도 같은
          // 결과이므로 "다시 시도"라고 하지 않는다.
          //
          // ⚠️ 예전에는 이 코드가 아래 default 로 떨어져 "AI 응답을 받지
          // 못했어요" 로 뭉개졌다. 서버는 이미 무엇이 문제인지 정확히
          // 말하고 있었는데 **앱이 그 말을 지운 셈**이었다(2026-08-21
          // 실기기에서 확인 — 카카오로 로그인한 뒤 AI 가 막혔는데, 화면만
          // 보고는 무결성 문제인지 통신 문제인지 가릴 수 없었다).
          throw AiAppCheckRejectedException();
        case 'resource-exhausted':
          // 서버 문구가 이미 한글이고 어느 한도인지(일/월)까지 알려주므로
          // 그대로 쓴다.
          throw AiQuotaExceededException(e.message ?? '사용 한도에 도달했어요.');
        default:
          // 남은 경우에도 영문이 새어 나가지 않게 우리 문구를 쓴다.
          throw AiBriefingException('AI 응답을 받지 못했어요. 잠시 후 다시 시도해 주세요.');
      }
    } on TimeoutException {
      throw AiBriefingException('응답이 오지 않았어요. 통신 상태를 확인한 뒤 다시 시도해 주세요.');
    } catch (e) {
      // 통신이 아예 안 되는 경우 등 Functions 예외로 오지 않는 실패도 있다.
      // 여기서 막지 않으면 화면에 개발자용 예외 문자열이 그대로 나온다.
      debugPrint('AI 브리핑 실패: ${e.runtimeType}');
      throw AiBriefingException('AI 가이드를 만들지 못했어요. 통신 상태를 확인한 뒤 다시 시도해 주세요.');
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

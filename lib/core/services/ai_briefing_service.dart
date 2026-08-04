import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/models/ai_provider.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/my_profile_model.dart';

class AiBriefingException implements Exception {
  final String message;
  AiBriefingException(this.message);
  @override
  String toString() => message;
}

/// 사용자가 직접 연동한 AI 제공사(Claude/ChatGPT/Gemini) API로 상대방과의
/// 대화 포인트를 실시간 생성한다. Dart/Flutter용 공식 Anthropic SDK가 없어서
/// (Python/TS/Java 등에만 있음) 세 제공사 모두 REST API를 직접 호출한다.
class AiBriefingService {
  static const _timeout = Duration(seconds: 30);

  static Future<List<String>> generateTalkingPoints({
    required AiProvider provider,
    required String apiKey,
    required String model,
    required ContactModel contact,
    required MyProfileModel myProfile,
    required List<CommunicationLogModel> communicationLogs,
    // 오늘 상대방 지역 날씨 요약(예: "맑음, 24°C"). 호출부(AiDataReviewSheet)가
    // WeatherService로 미리 조회해 동의 화면에 보여준 뒤 여기로 넘긴다.
    // geo가 없거나 조회에 실패했으면 null — 그 경우 프롬프트에서 조용히 생략된다.
    String? weatherSummary,
  }) async {
    final prompt = buildPrompt(
      contact: contact,
      myProfile: myProfile,
      communicationLogs: communicationLogs,
      weatherSummary: weatherSummary,
    );
    switch (provider) {
      case AiProvider.anthropic:
        return _callAnthropic(apiKey: apiKey, model: model, prompt: prompt);
      case AiProvider.openai:
        return _callOpenAi(apiKey: apiKey, model: model, prompt: prompt);
      case AiProvider.gemini:
        return _callGemini(apiKey: apiKey, model: model, prompt: prompt);
    }
  }

  @visibleForTesting
  static String buildPrompt({
    required ContactModel contact,
    required MyProfileModel myProfile,
    required List<CommunicationLogModel> communicationLogs,
    String? weatherSummary,
  }) {
    final commLogSummary = communicationLogs.isEmpty
        ? '최근 소통 기록 없음'
        : communicationLogs.map((l) => '- [${l.type}] ${l.summary}').join('\n');

    // 타겟 사용자는 낯을 가려 먼저 연락하기를 어려워하는 사람 — "왜 갑자기
    // 연락했지" 싶지 않게, 날씨/근황처럼 자연스러운 소재로 부담 없이 안부를
    // 전할 수 있는 문장을 만들도록 톤을 명시한다.
    final contextLines = <String>[
      '이름: ${contact.name}',
      '직함/회사: ${contact.title} / ${contact.company}',
      '태그: ${contact.tags.isEmpty ? '없음' : contact.tags.join(', ')}',
      '관심사: ${contact.interests.isEmpty ? '없음' : contact.interests.join(', ')}',
      '메모: ${contact.memo ?? '없음'}',
      if (weatherSummary != null) '오늘 상대방 지역 날씨: $weatherSummary',
    ];

    return '''
당신은 비즈니스 네트워킹 어시스턴트입니다. 사용자는 낯을 가리는 편이라 먼저
연락하는 것을 어색해합니다. 아래 정보를 참고해 사용자가 상대방에게 부담 없이
자연스럽게 안부를 전하며 인연을 이어갈 수 있는 대화 포인트를 만들어 주세요.

[나(사용자) 정보]
이름: ${myProfile.name}
직함/회사: ${myProfile.title} / ${myProfile.company}

[상대방 정보]
${contextLines.join('\n')}

[최근 소통 기록]
$commLogSummary

각 대화 포인트는 한 문장, 한국어로, 실제로 그대로 말할 수 있는 구체적인 문장으로
작성하세요. 날씨 정보가 있다면 그중 한 문장 정도에 자연스럽게 녹여도 좋습니다.
상대방의 관심사나 직함/업종과 관련된 일반적인 화제(업계 동향, 최근 이슈 등 당신이
알고 있는 상식 수준의 내용)를 자연스럽게 언급하는 문장을 하나 포함해도 좋습니다 —
단, 확인되지 않은 구체적 사실·사건을 지어내지 마세요. 번호/불릿/설명 없이 대화
포인트 문장만 줄바꿈으로 구분해서 정확히 3개 작성하세요.
''';
  }

  static List<String> _parseLines(String raw) {
    return raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => l.replaceFirst(RegExp(r'^[\d.\-*•]+\s*'), ''))
        .map((l) => l.replaceAll(RegExp(r'^"|"$'), ''))
        .take(3)
        .toList();
  }

  static Future<List<String>> _callAnthropic({
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final response = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'max_tokens': 400,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw AiBriefingException(_extractErrorMessage(response));
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final blocks = json['content'] as List<dynamic>? ?? [];
    final text = blocks
        .map((b) => (b as Map<String, dynamic>)['text']?.toString() ?? '')
        .join('\n');
    final points = _parseLines(text);
    if (points.isEmpty) throw AiBriefingException('AI가 빈 응답을 반환했습니다.');
    return points;
  }

  static Future<List<String>> _callOpenAi({
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final response = await http
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw AiBriefingException(_extractErrorMessage(response));
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>? ?? [];
    final text = choices.isEmpty
        ? ''
        : ((choices.first as Map<String, dynamic>)['message']
                      as Map<String, dynamic>?)?['content']
                  ?.toString() ??
              '';
    final points = _parseLines(text);
    if (points.isEmpty) throw AiBriefingException('AI가 빈 응답을 반환했습니다.');
    return points;
  }

  static Future<List<String>> _callGemini({
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    final response = await http
        .post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
          ),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw AiBriefingException(_extractErrorMessage(response));
    }

    final json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final candidates = json['candidates'] as List<dynamic>? ?? [];
    String text = '';
    if (candidates.isNotEmpty) {
      final content =
          (candidates.first as Map<String, dynamic>)['content']
              as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? [];
      text = parts
          .map((p) => (p as Map<String, dynamic>)['text']?.toString() ?? '')
          .join('\n');
    }
    final points = _parseLines(text);
    if (points.isEmpty) throw AiBriefingException('AI가 빈 응답을 반환했습니다.');
    return points;
  }

  static String _extractErrorMessage(http.Response response) {
    try {
      final json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final err = json['error'];
      if (err is Map && err['message'] != null) {
        return err['message'].toString();
      }
      if (err is String) return err;
    } catch (_) {}
    return 'AI 응답을 받지 못했습니다 (HTTP ${response.statusCode}). API 키/모델명을 확인해 주세요.';
  }
}

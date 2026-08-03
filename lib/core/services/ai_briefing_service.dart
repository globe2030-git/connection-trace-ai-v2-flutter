import 'dart:convert';

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
  }) async {
    final prompt = _buildPrompt(contact: contact, myProfile: myProfile);
    switch (provider) {
      case AiProvider.anthropic:
        return _callAnthropic(apiKey: apiKey, model: model, prompt: prompt);
      case AiProvider.openai:
        return _callOpenAi(apiKey: apiKey, model: model, prompt: prompt);
      case AiProvider.gemini:
        return _callGemini(apiKey: apiKey, model: model, prompt: prompt);
    }
  }

  static String _buildPrompt({required ContactModel contact, required MyProfileModel myProfile}) {
    final commLogSummary = contact.commLogs.isEmpty
        ? '최근 소통 기록 없음'
        : contact.commLogs.take(5).map((l) => '- [${l.type}] ${l.summary}').join('\n');

    return '''
당신은 비즈니스 네트워킹 어시스턴트입니다. 아래 정보를 참고해 사용자가 상대방을 다시 만났을 때 자연스럽게 꺼낼 수 있는 대화 포인트를 만들어 주세요.

[나(사용자) 정보]
이름: ${myProfile.name}
직함/회사: ${myProfile.title} / ${myProfile.company}

[상대방 정보]
이름: ${contact.name}
직함/회사: ${contact.title} / ${contact.company}
태그: ${contact.tags.isEmpty ? '없음' : contact.tags.join(', ')}
메모: ${contact.memo ?? '없음'}

[최근 소통 기록]
$commLogSummary

각 대화 포인트는 한 문장, 한국어로, 실제로 그대로 말할 수 있는 구체적인 문장으로
작성하세요. 번호/불릿/설명 없이 대화 포인트 문장만 줄바꿈으로 구분해서 정확히
3개 작성하세요.
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

  static Future<List<String>> _callAnthropic({required String apiKey, required String model, required String prompt}) async {
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

    if (response.statusCode != 200) throw AiBriefingException(_extractErrorMessage(response));

    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final blocks = json['content'] as List<dynamic>? ?? [];
    final text = blocks.map((b) => (b as Map<String, dynamic>)['text']?.toString() ?? '').join('\n');
    final points = _parseLines(text);
    if (points.isEmpty) throw AiBriefingException('AI가 빈 응답을 반환했습니다.');
    return points;
  }

  static Future<List<String>> _callOpenAi({required String apiKey, required String model, required String prompt}) async {
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

    if (response.statusCode != 200) throw AiBriefingException(_extractErrorMessage(response));

    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = json['choices'] as List<dynamic>? ?? [];
    final text = choices.isEmpty ? '' : ((choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?)?['content']?.toString() ?? '';
    final points = _parseLines(text);
    if (points.isEmpty) throw AiBriefingException('AI가 빈 응답을 반환했습니다.');
    return points;
  }

  static Future<List<String>> _callGemini({required String apiKey, required String model, required String prompt}) async {
    final response = await http
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey'),
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

    if (response.statusCode != 200) throw AiBriefingException(_extractErrorMessage(response));

    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final candidates = json['candidates'] as List<dynamic>? ?? [];
    String text = '';
    if (candidates.isNotEmpty) {
      final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? [];
      text = parts.map((p) => (p as Map<String, dynamic>)['text']?.toString() ?? '').join('\n');
    }
    final points = _parseLines(text);
    if (points.isEmpty) throw AiBriefingException('AI가 빈 응답을 반환했습니다.');
    return points;
  }

  static String _extractErrorMessage(http.Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final err = json['error'];
      if (err is Map && err['message'] != null) return err['message'].toString();
      if (err is String) return err;
    } catch (_) {}
    return 'AI 응답을 받지 못했습니다 (HTTP ${response.statusCode}). API 키/모델명을 확인해 주세요.';
  }
}

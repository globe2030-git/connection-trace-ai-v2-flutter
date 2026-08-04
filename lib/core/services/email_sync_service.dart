import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../../data/models/contact_model.dart';
import 'google_auth_gateway.dart';

/// Gmail API로 특정 인맥과 주고받은 이메일을 실제로 읽어와 소통 이력으로
/// 가져온다. 통화/문자와 달리 이메일은 모든 플랫폼(Android/iOS/웹)에서 동일한
/// Google 로그인(OAuth) 방식으로 동작한다.
///
/// 단, 코드만으로는 동작하지 않는다 — Google Cloud Console에서 OAuth 클라이언트
/// ID를 먼저 발급받아 안드로이드(SHA-1 지문)/iOS(번들 ID)에 등록해야 로그인
/// 자체가 가능하다. 이 설정 전에는 [signIn]이 예외를 던진다.
class EmailSyncService {
  static const _gmailReadonlyScope =
      'https://www.googleapis.com/auth/gmail.readonly';
  static GoogleSignInAccount? _currentAccount;

  static bool get isSignedIn => _currentAccount != null;
  static String? get signedInEmail => _currentAccount?.email;

  /// Google 계정으로 로그인하고 Gmail 읽기 권한을 요청한다.
  static Future<GoogleSignInAccount> signIn() async {
    // clientId를 명시적으로 넘기지 않으면 각 플랫폼의 기본 설정 파일에서
    // 읽는다(Android: strings.xml의 default_web_client_id 또는 앱 서명 SHA-1로
    // 자동 매칭, iOS: Info.plist의 GIDClientID, 웹: index.html의 meta 태그).
    await GoogleAuthGateway.ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    await account.authorizationClient.authorizeScopes([_gmailReadonlyScope]);
    _currentAccount = account;
    return account;
  }

  static Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _currentAccount = null;
  }

  /// 로그인된 Gmail 계정에서 [contactEmail]과 주고받은(보낸/받은) 최근 메일을
  /// 조회한다. 본문 전체는 가져오지 않고 제목/날짜/짧은 Gmail 미리보기만
  /// 가져온다. 호출자가 선택 화면을 보여 준 뒤 선택한 항목만 저장해야 한다.
  static Future<List<CommunicationLogModel>> syncEmails(
    String contactEmail, {
    int limit = 10,
  }) async {
    final account = _currentAccount;
    if (account == null) {
      throw StateError('먼저 Google 계정으로 로그인해 주세요.');
    }
    if (contactEmail.trim().isEmpty) {
      return [];
    }

    final headers = await account.authorizationClient.authorizationHeaders([
      _gmailReadonlyScope,
    ], promptIfNecessary: true);
    if (headers == null) {
      throw StateError('이메일 접근 권한을 받지 못했습니다.');
    }

    final listUri = Uri.https(
      'gmail.googleapis.com',
      '/gmail/v1/users/me/messages',
      {'q': 'from:$contactEmail OR to:$contactEmail', 'maxResults': '$limit'},
    );
    final listResp = await http.get(listUri, headers: headers);
    if (listResp.statusCode != 200) {
      throw StateError('Gmail 조회에 실패했습니다 (${listResp.statusCode}).');
    }
    final listData = jsonDecode(listResp.body) as Map<String, dynamic>;
    final messages = (listData['messages'] as List<dynamic>?) ?? const [];

    final logs = await Future.wait(
      messages.map((message) async {
        final id = (message as Map<String, dynamic>)['id'] as String;
        final detailUri = Uri.https(
          'gmail.googleapis.com',
          '/gmail/v1/users/me/messages/$id',
          {
            'format': 'metadata',
            'metadataHeaders': ['Subject', 'Date'],
          },
        );
        final detailResp = await http.get(detailUri, headers: headers);
        if (detailResp.statusCode != 200) return null;

        final detail = jsonDecode(detailResp.body) as Map<String, dynamic>;
        final headerList =
            (detail['payload'] as Map<String, dynamic>?)?['headers']
                as List<dynamic>? ??
            const [];

        String? subject;
        for (final h in headerList) {
          final entry = h as Map<String, dynamic>;
          if (entry['name'] == 'Subject') subject = entry['value'] as String?;
        }

        final cleanSubject = (subject ?? '').trim();
        final snippet = (detail['snippet'] as String? ?? '').trim();
        final summary = [
          cleanSubject.isEmpty ? '(제목 없음)' : cleanSubject,
          if (snippet.isNotEmpty) snippet,
        ].join(' — ');

        return CommunicationLogModel(
          id: 'gmail_$id',
          type: 'email',
          summary: truncateSummary(summary),
          timestamp: parseInternalDate(detail['internalDate']?.toString()),
          source: 'gmail',
        );
      }),
    );

    final validLogs = logs.whereType<CommunicationLogModel>().toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return validLogs;
  }

  @visibleForTesting
  static DateTime parseInternalDate(String? raw) {
    final milliseconds = int.tryParse(raw ?? '');
    if (milliseconds == null) return DateTime.now();
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  @visibleForTesting
  static String truncateSummary(String value, {int maxLength = 500}) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1)}…';
  }
}

import 'package:url_launcher/url_launcher.dart';

class PhoneCallService {
  static Future<bool> makeCall(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanNumber');
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri);
    }
    return false;
  }

  /// 문자 앱을 연다 — 본문은 채우지 않는다.
  ///
  /// 브리핑 화면(`briefing_overlay_view.dart`)의 문자 보내기는 "고른 대화
  /// 포인트"를 본문에 미리 채워 넣지만, 명함 상세 시트에는 그런 문맥이 없다
  /// (2026-08-21, 브리프 ⑤). 같은 `sms:` 스킴을 그대로 쓰므로 새 플러그인은
  /// 없다.
  static Future<bool> sendSms(String phoneNumber) async {
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('sms:$cleanNumber');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// 메일 앱을 수신인만 채운 채로 연다 — 제목·본문은 채우지 않는다(위와
  /// 같은 이유, 2026-08-21 브리프 ⑤). `mailto:` 스킴 재사용.
  static Future<bool> sendEmail(String email) async {
    final uri = Uri.parse('mailto:$email');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

}

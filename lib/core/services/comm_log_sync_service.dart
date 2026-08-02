import 'dart:io';
import 'package:call_log/call_log.dart' as call_log_pkg;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/models/contact_model.dart';

/// 실제 기기의 통화기록/문자 메시지를 읽어와 특정 인맥의 소통 이력으로
/// 가져온다. 안드로이드 전용 — iOS는 OS 정책상 앱이 통화기록/문자 메시지에
/// 접근하는 것 자체가 원천 차단되어 있어(제3자 앱에는 관련 API가 아예
/// 없음), 이 서비스의 모든 메서드는 iOS/웹에서 [UnsupportedError]를 던진다.
class CommLogSyncService {
  // kIsWeb을 먼저 검사해야 함 — 웹에서는 Platform.isAndroid 접근 자체가
  // UnsupportedError를 던지므로, && 단락 평가로 웹일 때 뒤쪽을 안 보게 한다.
  static bool get isSupportedOnThisPlatform => !kIsWeb && Platform.isAndroid;

  /// 지역번호/국가번호 표기가 달라도 같은 번호로 인식할 수 있도록 숫자만
  /// 남기고 마지막 9자리로 비교한다(휴대폰 010-XXXX-XXXX 기준 9자리면
  /// 국가번호 유무와 무관하게 안정적으로 매칭됨).
  static String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
  }

  static Future<bool> requestPermissions() async {
    if (!isSupportedOnThisPlatform) return false;
    final statuses = await [Permission.phone, Permission.sms].request();
    return statuses.values.every((s) => s.isGranted);
  }

  /// 해당 전화번호와 일치하는 최근 통화 기록을 가져온다.
  static Future<List<CommunicationLogModel>> syncCallLogs(
    String phoneNumber, {
    int limit = 20,
  }) async {
    if (!isSupportedOnThisPlatform) {
      throw UnsupportedError('통화 기록 연동은 안드로이드 기기에서만 지원됩니다.');
    }
    final granted = await Permission.phone.request();
    if (!granted.isGranted) {
      throw StateError('통화 기록 접근 권한이 거부되었습니다. 설정에서 권한을 허용해 주세요.');
    }

    final target = _normalizePhone(phoneNumber);
    if (target.isEmpty) return [];

    final entries = await call_log_pkg.CallLog.get();
    final matched = entries
        .where((e) => e.number != null && _normalizePhone(e.number!) == target)
        .toList()
      ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

    return matched.take(limit).map((e) {
      final typeLabel = _callTypeLabel(e.callType);
      final duration = e.duration;
      final durationLabel = (duration != null && duration > 0)
          ? ' (${(duration ~/ 60).toString().padLeft(2, '0')}분 ${(duration % 60).toString().padLeft(2, '0')}초)'
          : '';
      return CommunicationLogModel(
        type: 'call',
        summary: '$typeLabel$durationLabel',
        timestamp: e.timestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(e.timestamp!)
            : DateTime.now(),
        isAutoSynced: true,
      );
    }).toList();
  }

  /// 해당 전화번호와 주고받은 최근 문자 메시지(수신함+발신함)를 가져온다.
  static Future<List<CommunicationLogModel>> syncSmsMessages(
    String phoneNumber, {
    int limit = 20,
  }) async {
    if (!isSupportedOnThisPlatform) {
      throw UnsupportedError('문자 메시지 연동은 안드로이드 기기에서만 지원됩니다.');
    }
    final granted = await Permission.sms.request();
    if (!granted.isGranted) {
      throw StateError('문자 메시지 접근 권한이 거부되었습니다. 설정에서 권한을 허용해 주세요.');
    }

    final target = _normalizePhone(phoneNumber);
    if (target.isEmpty) return [];

    final messages = await SmsQuery().querySms(
      kinds: const [SmsQueryKind.inbox, SmsQueryKind.sent],
      count: 500,
      sort: true,
    );
    final matched = messages
        .where((m) => m.address != null && _normalizePhone(m.address!) == target)
        .toList();

    return matched.take(limit).map((m) {
      final direction = m.kind == SmsMessageKind.sent ? '발신' : '수신';
      final body = (m.body ?? '').trim();
      final preview = body.length > 40 ? '${body.substring(0, 40)}...' : body;
      return CommunicationLogModel(
        type: 'sms',
        summary: '$direction 문자 - "$preview"',
        timestamp: m.date ?? DateTime.now(),
        isAutoSynced: true,
      );
    }).toList();
  }

  static String _callTypeLabel(call_log_pkg.CallType? type) {
    switch (type) {
      case call_log_pkg.CallType.incoming:
        return '수신 통화';
      case call_log_pkg.CallType.outgoing:
        return '발신 통화';
      case call_log_pkg.CallType.missed:
        return '부재중 통화';
      case call_log_pkg.CallType.rejected:
        return '거절한 통화';
      case call_log_pkg.CallType.blocked:
        return '차단된 통화';
      case call_log_pkg.CallType.voiceMail:
        return '음성사서함';
      default:
        return '통화';
    }
  }
}

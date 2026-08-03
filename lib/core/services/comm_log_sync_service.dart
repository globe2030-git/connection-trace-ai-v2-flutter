import '../../data/models/contact_model.dart';

/// 과거 통화기록·문자 자동 수집 실험 API의 호환용 안전 스텁.
///
/// iOS에는 일반 앱용 조회 API가 없고, Android도 스토어 배포 앱은 기본
/// 전화/SMS 앱 등 제한된 예외가 아니면 관련 권한을 사용할 수 없다. 출시
/// 앱에서는 사용자 입력/붙여넣기만 지원하며 이 서비스는 항상 비활성이다.
class CommLogSyncService {
  static bool get isSupportedOnThisPlatform => false;

  static Future<bool> requestPermissions() async => false;

  /// 해당 전화번호와 일치하는 최근 통화 기록을 가져온다.
  static Future<List<CommunicationLogModel>> syncCallLogs(
    String phoneNumber, {
    int limit = 20,
  }) async {
    throw UnsupportedError('통화기록 자동 수집은 출시 앱에서 지원하지 않습니다. 통화 후 메모를 이용해 주세요.');
  }

  /// 해당 전화번호와 주고받은 최근 문자 메시지(수신함+발신함)를 가져온다.
  static Future<List<CommunicationLogModel>> syncSmsMessages(
    String phoneNumber, {
    int limit = 20,
  }) async {
    throw UnsupportedError('문자 자동 수집은 출시 앱에서 지원하지 않습니다. 필요한 내용만 붙여넣어 주세요.');
  }
}

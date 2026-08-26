import 'package:shared_preferences/shared_preferences.dart';

import '../utils/contact_export_name.dart';

/// 내보낼 때 쓸 **주소록 이름 형식** 설정(추가 494).
///
/// ## 무엇을 기억하나
///
/// 둘이다 — **어떤 형식인지**와 **물어본 적이 있는지.** 둘을 갈라 두는 이유는
/// *"아직 안 물었다"* 와 *"물었고 이름만을 골랐다"* 가 다르기 때문이다. 하나로
/// 합치면 이름만을 고른 사람에게 **첫 내보내기마다 계속 묻게** 된다.
///
/// (같은 구분을 광고 수신 동의에서도 쓴다 — `AdConsentService` 의 `answered`.)
///
/// ## 개인정보
///
/// 여기 들어가는 것은 **형식 선택값뿐**이다. 이름·번호 같은 명함 내용은
/// 넣지 않는다 — `shared_preferences` 는 암호화되지 않는다(CLAUDE.md 4절).
class ContactExportSettingsService {
  static const String _formatKey = 'contact_export_name_format_v1';
  static const String _askedKey = 'contact_export_name_asked_v1';

  /// 지금 쓸 형식. 읽지 못하면 **가장 덜 개입하는 쪽**(이름만)이다.
  Future<ContactExportNameFormat> format() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ContactExportNameFormat.fromStorage(prefs.getString(_formatKey));
    } catch (_) {
      return ContactExportNameFormat.nameOnly;
    }
  }

  /// 형식을 물어본 적이 있나.
  ///
  /// 읽기에 실패하면 `true` 를 준다 — **묻지 않는 쪽**이다. 실패했다고 물으면
  /// 저장도 실패할 테니 **매번 다시 묻게** 된다.
  Future<bool> hasAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_askedKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  /// 고른 형식을 적는다. 저장에 실패하면 `false`.
  Future<bool> save(ContactExportNameFormat format) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_formatKey, format.storageKey);
      await prefs.setBool(_askedKey, true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

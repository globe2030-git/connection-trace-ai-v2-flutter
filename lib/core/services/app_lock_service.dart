/// **앱 잠금** — 생체인증(또는 기기 잠금 수단)으로 앱 진입을 막는다.
///
/// ## 왜 세션 만료가 아니라 이것인가 (추가 456에서 승인, 569에서 착수)
///
/// 처음 나온 물음은 *"1개월 이상 안 쓰면 자동 로그아웃되던데 새 규정인가?"*
/// 였다. **오히려 없어진 규정이었고**(구 개인정보 보호법 §39조의6, 2023-09-15
/// 폐지) **자동 로그아웃은 폐지 전에도 법적 의무가 아니었다.**
///
/// 🚨 **그리고 이 앱에서 세션 만료는 손해가 더 크다** — 재로그인 → 명함 복원
/// 대기 → *"데이터가 사라졌다"* 오해 → **로그인 방법을 잊고 새 계정.**
/// 2026-08-28에 그 흐름이 실제로 났다(추가 556·565·567).
///
/// ⭐ **앱 잠금은 보호가 더 강하고 재로그인이 없다** — 기기 잠금이 풀려도 앱은
/// 잠긴다. 이 앱에는 **제3자(명함 주인)의 개인정보**가 수백 장 들어 있어
/// *"아무것도 안 한다"*도 답이 아니다 — 그들이 감수한 적 없는 위험이다.
///
/// ## 기본은 꺼짐이다
///
/// 켜는 것은 이용자의 선택이다. 기본으로 켜면 **명함 하나 보려고 매번 얼굴을
/// 들이대야 하고**, 그 부담은 이 앱을 매일 열지 않는 사람일수록 크다.
library;

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱을 다시 열었을 때 **잠글지** 판단한다 — 순수 계산이라 검사로 고정한다.
///
/// ## 🚨 「돌아올 때마다 잠근다」로 하면 안 된다
///
/// 명함 촬영·갤러리 선택·주소 검색은 **다른 화면으로 잠깐 나갔다 오는 흐름**
/// 이다. 그때마다 잠그면 **명함 한 장 등록하는 데 인증을 세 번** 하게 된다.
/// 그래서 **떠나 있던 시간**으로 판단한다.
///
/// ⚠️ [awayFor]가 `null`이면 **앱을 새로 켠 것**이다 — 무조건 잠근다.
bool shouldLockOnResume({
  required bool enabled,
  required Duration? awayFor,
  Duration grace = const Duration(seconds: 30),
}) {
  if (!enabled) return false;
  if (awayFor == null) return true;
  return awayFor >= grace;
}

class AppLockService {
  AppLockService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// 켜짐 여부. **개인정보가 아니라 참·거짓 하나**라 일반 저장소로 충분하다.
  static const String _prefsKey = 'app_lock_enabled_v1';

  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefsKey) ?? false;
    } catch (e) {
      // 못 읽으면 **꺼진 것으로 본다.** 여기서 켜진 것으로 틀리면 이용자가
      // 자기 앱에 못 들어간다 — 되돌릴 방법이 앱 안에 없다.
      debugPrint('앱 잠금 설정 읽기 실패: ${e.runtimeType}');
      return false;
    }
  }

  Future<void> setEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      debugPrint('앱 잠금 설정 쓰기 실패: ${e.runtimeType}');
    }
  }

  /// 이 기기가 생체인증(또는 기기 잠금 수단)을 쓸 수 있나.
  ///
  /// ⚠️ **켜기 전에 반드시 확인한다.** 못 쓰는 기기에서 켜 두면 **앱에 영영
  /// 못 들어간다.**
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      debugPrint('생체인증 지원 확인 실패: ${e.runtimeType}');
      return false;
    }
  }

  /// 인증을 요청한다. 성공하면 `true`.
  ///
  /// 📌 `biometricOnly: false`다 — 지문·얼굴이 없어도 **기기 PIN·패턴**으로
  /// 열 수 있어야 한다. 생체만 허용하면 등록을 지운 이용자가 갇힌다.
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: '명함첩을 열려면 본인 확인이 필요합니다',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (e) {
      // 취소·실패·미지원 전부 여기로 온다. 잠긴 채로 둔다.
      debugPrint('앱 잠금 인증 실패: ${e.runtimeType}');
      return false;
    }
  }
}

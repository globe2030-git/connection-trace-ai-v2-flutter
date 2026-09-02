import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/ad_consent_service.dart';
import '../../../../core/services/terms_consent_service.dart';
import '../../../../core/utils/image_file_cache.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sns_auth_provider.dart';
import '../../../common/legal_document_view.dart';
import '../../../common/social_oauth_view.dart';
import '../widgets/official_social_button.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import 'email_signup_view.dart';
import 'signup_consent_view.dart';

/// 앱 진입을 막는 SNS·이메일 로그인 화면. Google은 기존 Gmail 연동에서 이미
/// 쓰던 google_sign_in을 그대로 재사용해 바로 동작하고, Apple은 iOS/macOS에서만
/// 정상 동작하는 버튼으로 보여준다(`SnsAuthProvider.apple.isAvailable` 참고 —
/// Android에서는 버튼 자체를 렌더링하지 않는다).
///
/// ## 동의는 ⑨(SignupConsentView)로 통합됐다(2026-08-31, 추가 632)
///
/// 예전에는 만 14세 확인 체크박스가 이 화면에 있었다. 지금은 **어느 버튼을
/// 눌러도 ⑨가 먼저 뜨고**, 필수 3종(만14세·약관·방침)을 그 화면에서 확인한다
/// — 자세한 설계는
/// `docs/planning/specs/email-signup-unified-consent-2026-08-31.md` 참고.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  SnsAuthProvider? _loadingProvider;
  String? _errorMessage;

  /// ⑨(`SignupConsentView`)에서 미리 골라 둔 동의값. **화면(이 State)이 살아
  /// 있는 동안만** 메모리로 들고 있는다 — uid가 아직 없는 시점(OAuth/이메일
  /// 계정 생성 전)에 받은 값이라 서버에 곧바로 쓸 수 없다.
  ///
  /// 🚨 **을) 화면 생존 동안 보유하는 방식이다**(설계 §2, 3차 왕복 확정).
  /// OAuth가 취소/실패해도 이 값은 지우지 않는다 — 다른 소셜 버튼으로
  /// 재시도해도 ⑨를 다시 안 띄운다. 재시도가 흔한 경로(비밀번호 오타·OAuth
  /// 취소)인데 매번 다시 물으면 마찰이 크다.
  ///
  /// 이 저장소에 이미 같은 패턴이 있다(`briefing_overlay_view.dart`의
  /// `_consentedSelection`).
  ///
  /// ⚠️ **어느 provider의 이메일 채널 규칙을 쓸지는 이 값에 저장해 두지
  /// 않는다** — [_applyPendingConsent]를 부르는 자리마다 **실제로 로그인에
  /// 성공한 provider**를 그때그때 넘긴다(설계 §1 끝부분 — 예: 네이버로 시작
  /// → 취소 → 구글로 재시도하면, 처음 ⑨를 그렸던 provider가 아니라 실제로
  /// 성공한 구글 기준으로 걸러야 한다).
  ConsentChoice? _pendingConsent;

  Future<void> _signIn(SnsAuthProvider provider) async {
    setState(() {
      _loadingProvider = provider;
      _errorMessage = null;
    });
    final auth = context.read<AuthRepository>();
    try {
      switch (provider) {
        case SnsAuthProvider.google:
          await auth.signInWithGoogle();
          // Apple은 프로필 사진을 아예 안 주지만 Google 계정에는 있는 경우가
          // 많다 — 최초 로그인이라 내 명함이 아직 비어 있으면 그 사진을
          // 기본값으로 채워 넣는다(사용자 제안, 2026-08-08). 실패해도
          // 로그인 자체를 막지 않는다.
          if (mounted) await _prefillAvatarFromGoogle(auth.photoUrl);
        case SnsAuthProvider.apple:
          await auth.signInWithApple();
        case SnsAuthProvider.kakao:
        case SnsAuthProvider.naver:
          // 인증 화면을 띄우는 일은 화면이 맡고, 저장소는 결과만 받는다.
          await auth.signInWithSocial(
            provider,
            (target) => SocialOauthView.show(context, target),
          );
        case SnsAuthProvider.email:
          // 이메일은 `_startSignIn`이 EmailSignupView로 따로 보낸다 — 여기
          // 도달하면 배선 오류다.
          throw AuthException('이메일 로그인은 별도 화면에서 진행합니다.');
      }
      // 성공했으면(예외 없이 여기 도달) 미리 받아 둔 동의를 적용한다.
      // Apple 취소처럼 예외 없이 조용히 반환되는 경로도 있으므로,
      // firebaseUid로 실제 로그인 성공 여부를 다시 확인한다.
      if (mounted) {
        final uid = context.read<AuthRepository>().firebaseUid;
        if (uid != null) unawaited(_applyPendingConsent(uid, provider));
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      // 중괄호는 dart format 이 이 줄을 쪼개면서 필요해졌다(2026-08-25).
      // 원래는 한 줄이라 lint 에 안 걸렸는데, 같은 파일을 포맷하면 갈라지면서
      // curly_braces_in_flow_control_structures 가 새로 뜬다. info 를 늘리지
      // 않는 것이 규약이라(CLAUDE.md 3절) 여기서 닫아 둔다.
      if (mounted) {
        setState(() => _errorMessage = '로그인 중 문제가 발생했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  /// 소셜 버튼이든 "이메일로 시작하기"든, **처음 누르면 ⑨를 먼저 보여준다**
  /// (설계 §1). 이미 ⑨를 통과했으면([_pendingConsent] != null) 다시 보여주지
  /// 않고 곧바로 로그인/가입 흐름으로 넘어간다.
  Future<void> _startSignIn(SnsAuthProvider provider) async {
    if (_pendingConsent == null) {
      final choice = await Navigator.of(context).push<ConsentChoice>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SignupConsentView(provider: provider),
        ),
      );
      if (!mounted) return;
      if (choice == null) return; // 취소·뒤로가기 — 로그인 화면에 그대로 남는다
      setState(() => _pendingConsent = choice);
    }
    if (provider == SnsAuthProvider.email) {
      await _openEmailSignup();
    } else {
      await _signIn(provider);
    }
  }

  Future<void> _openEmailSignup() async {
    setState(() => _errorMessage = null);
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const EmailSignupView(),
      ),
    );
    if (success != true || !mounted) return;
    final uid = context.read<AuthRepository>().firebaseUid;
    if (uid != null) {
      unawaited(_applyPendingConsent(uid, SnsAuthProvider.email));
    }
  }

  /// [_pendingConsent]를 서버에 실제로 적용한다 — **계정이 실제로 만들어진
  /// 뒤(uid를 확보한 뒤)에만** 부른다(설계 §2·§4).
  ///
  /// 🚨 **`context`를 쓰지 않는다.** 로그인 성공 직후 `AuthGate`가 위젯
  /// 트리를 통째로 갈아 끼우므로, 이 함수 안에서 `context`나 `mounted`를
  /// 확인하면 호출 자체가 취소될 수 있다 — `AuthRepository
  /// ._storeAppleRefreshTokenOnServer`가 같은 이유로 같은 패턴을 쓴다.
  Future<void> _applyPendingConsent(String uid, SnsAuthProvider provider) async {
    final consent = _pendingConsent;
    if (consent == null) return;
    await AdConsentService().applyFreshSignupChoice(
      uid: uid,
      email: consent.adEmail,
      push: consent.adPush,
      emailChannelAvailable: adEmailChannelAvailable(provider),
    );
    // 필수 동의 3종(약관·방침·만 14세)은 ⑨에서 이미 받았지만 지금까지
    // 아무 데도 안 남았다(P1-17). 광고 동의와 같은 자리에서 함께 남긴다.
    // ⚠️ 실패해도 가입을 막지 않는다 — 동의는 이미 받았고, 못 남긴 것은
    // 우리 쪽 사정이다. 대신 표시를 남겨 다음 실행에서 다시 시도한다.
    await TermsConsentService().recordSignupConsent(uid);
  }

  /// 로그인이 진행 중이라 버튼이 눌리지 않을 때 이유를 말한다(2026-08-30,
  /// 추가 626의 원칙 유지). 만 14세 게이트가 ⑨로 옮겨가면서, 이제 버튼이
  /// 눌리지 않는 유일한 이유는 "다른 로그인이 진행 중"이다.
  void _promptBusy() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('잠시만요, 로그인을 진행하고 있어요.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  /// 최초 로그인이라 내 명함이 아직 비어 있고 프로필 사진도 없으면, Google
  /// 계정 사진을 내려받아 기본값으로 채운다. 이름/직함 등 나머지 필드는
  /// 그대로 비워 둬(가짜 정보 금지 원칙) 사용자가 "내 프로필" 화면에서
  /// 직접 채우게 한다 — 사진 하나만 미리 채워 넣는 것뿐이라 `isSetUp`
  /// 판정(이름 기준)에는 영향이 없다.
  Future<void> _prefillAvatarFromGoogle(String? photoUrl) async {
    if (photoUrl == null || photoUrl.isEmpty || !mounted) return;
    final profileRepo = context.read<MyProfileRepository>();
    final profile = profileRepo.profile;
    if (profile.isSetUp || profile.avatarPath != null) return;

    try {
      final response = await http
          .get(Uri.parse(photoUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final docsDir = await getApplicationDocumentsDirectory();
      final savedPath = '${docsDir.path}/my_profile_avatar.jpg';
      await File(savedPath).writeAsBytes(response.bodyBytes);
      // 파일명이 고정이라 캐시를 비우지 않으면 **다른 계정으로 로그인해도 옛
      // 사진이 그대로 보인다.** 본인 프로필 사진 선택과 같은 함정이다(E-07).
      await evictImageFileCache(savedPath);

      await profileRepo.updateProfile(profile.copyWith(avatarPath: savedPath));
    } catch (e) {
      // 프로필 사진은 부가 편의 기능이라 실패해도 로그인 흐름을 막지 않는다.
      debugPrint('Google 프로필 사진 미리 채우기 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 로그아웃 뒤에도 남는 값이라(설계:
    // docs/planning/specs/login-recent-provider-2026-08-29.md) 로그인 화면을
    // 열 때마다 최신값을 구독한다.
    final lastProvider = context.watch<AuthRepository>().lastProvider;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Image.asset('assets/images/brand/ci.png', width: 140),
              ),
              const SizedBox(height: 24),
              const Text(
                '커넥션센스 시작하기',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'SNS 계정으로 간편하게 시작하세요.\n로그인 정보는 이 기기에만 안전하게 저장됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              _SnsButton(
                provider: SnsAuthProvider.google,
                isLoading: _loadingProvider == SnsAuthProvider.google,
                isDisabled: _loadingProvider != null,
                isRecent: lastProvider == SnsAuthProvider.google,
                onPressed: () => _startSignIn(SnsAuthProvider.google),
                onBlockedTap: _promptBusy,
              ),
              // Apple 로그인이 지원되지 않는 플랫폼(Android 등)에서는 버튼을
              // 아예 그리지 않는다 — 비활성 버튼으로 "준비 중"을 보여주는 건
              // Apple 로그인을 지원하지 않는 것처럼 보여 오히려 혼란스럽다.
              // 카카오·네이버는 **빌드에 키가 들어 있을 때만** 보인다.
              // 눌러도 안 되는 버튼을 두면 이용자는 고장으로 읽는다.
              for (final p in const [
                SnsAuthProvider.kakao,
                SnsAuthProvider.naver,
              ])
                if (p.isAvailable) ...[
                  const SizedBox(height: 12),
                  _SnsButton(
                    provider: p,
                    isLoading: _loadingProvider == p,
                    isDisabled: _loadingProvider != null,
                    isRecent: lastProvider == p,
                    onPressed: () => _startSignIn(p),
                    onBlockedTap: _promptBusy,
                  ),
                ],
              if (SnsAuthProvider.apple.isAvailable) ...[
                const SizedBox(height: 12),
                _SnsButton(
                  provider: SnsAuthProvider.apple,
                  isLoading: _loadingProvider == SnsAuthProvider.apple,
                  isDisabled: _loadingProvider != null,
                  isRecent: lastProvider == SnsAuthProvider.apple,
                  onPressed: () => _startSignIn(SnsAuthProvider.apple),
                  onBlockedTap: _promptBusy,
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Divider(color: AppColors.borderSubtle, height: 1),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '또는',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ),
                  const Expanded(
                    child: Divider(color: AppColors.borderSubtle, height: 1),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _loadingProvider != null
                      ? null
                      : () => _startSignIn(SnsAuthProvider.email),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.cardSurface,
                    side: const BorderSide(color: AppColors.borderSubtle),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mail_outline,
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                      SizedBox(width: 10),
                      Text(
                        '이메일로 시작하기',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 약관규제법 제3조(명시 의무) 대응. 약관·방침 동의는 **⑨
              // (SignupConsentView)의 체크박스**로 받고, 이 고지는 그와 별개로
              // "명시" 의무를 채운다 — ⑨를 보지 않고 이탈하는 사람(예: 취소
              // 후 로그인 화면만 보다 나가는 경우)도 이 화면은 보므로 최소
              // 고지를 유지한다.
              const SizedBox(height: 20),
              _LegalNotice(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.destructive,
                  ),
                ),
              ],
              if (kDebugMode) ...[
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: () =>
                        context.read<AuthRepository>().signInAsGuest(),
                    child: const Text(
                      '디버그: 로그인 건너뛰기 (QA용, release 빌드엔 없음)',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnsButton extends StatelessWidget {
  final SnsAuthProvider provider;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback onPressed;

  /// 눌리지 않을 때 이유를 말할 자리. `OfficialSocialButton.onBlockedTap` 참고.
  ///
  /// 🚨 **선택 인자로 뒀다가 애플 버튼에서 빠뜨렸다**(2026-08-31, globe2030님
  /// 실기기 제보: *"애플 로그인만 알림이 나오지 않아"*). 버튼을 만드는 자리가
  /// **셋으로 흩어져 있어서**(구글 · 카카오·네이버 루프 · 애플) 둘만 고치고
  /// 하나를 놓쳤다. **자동 검사는 위젯 단위라 이 누락을 못 봤다.**
  ///
  /// 📌 **그래서 필수로 바꿨다** — 안 넘기면 컴파일이 안 된다. 새 제공자를
  /// 더할 때도 똑같이 막힌다. **「잊지 말자」로 막지 않고 형으로 막는다.**
  final VoidCallback onBlockedTap;

  /// 지난번에 이 수단으로 로그인에 성공했으면 true — 「최근」 배지를 그린다.
  /// 설계: docs/planning/specs/login-recent-provider-2026-08-29.md §3.
  final bool isRecent;

  const _SnsButton({
    required this.provider,
    required this.isLoading,
    required this.isDisabled,
    required this.onPressed,
    required this.onBlockedTap,
    this.isRecent = false,
  });

  /// 제공자가 정한 버튼 색.
  ///
  /// ⚠️ **카카오·네이버는 색을 바꿀 수 없다.** 각자 버튼 가이드가 지정 컬러를
  /// 못박고 있다(네이버: "지정 컬러는 변경할 수 없으며", 카카오: 노란색 고정).
  /// 우리 화면 색에 맞추려고 바꾸면 규정 위반이고, 네이버는 사전 검수 항목이다.
  ///
  /// 📌 **로고는 아직 안 들어갔다.** 공식 애셋(PNG)을 받아 `assets/`에 넣어야
  /// 하고, 임의로 그리는 것은 금지돼 있다("로고 형태를 변경하거나 다른 형태와
  /// 조합하는 것은 금지"). 지금은 색과 문구만 규정대로 맞춰 두고, 애셋이
  /// 들어오면 `_ProviderIcon`에서 갈아 끼운다.
  /// 구글·애플용 배경색. 카카오·네이버는 공식 버튼 이미지를 통째로 쓰므로
  /// 여기까지 오지 않는다(`_OfficialButtonArt.of` 참고).
  // ⚠️ 이메일은 `_SnsButton`을 쓰지 않는다(로그인 화면에서 별도
  // `OutlinedButton`으로 그린다) — 그래도 열거형 분기는 남김없이 적는다
  // (위 소셜 아이콘 스위치와 같은 이유).
  Color? get _brandColor => switch (provider) {
    SnsAuthProvider.google ||
    SnsAuthProvider.apple ||
    SnsAuthProvider.kakao ||
    SnsAuthProvider.naver ||
    SnsAuthProvider.email =>
      null,
  };

  @override
  Widget build(BuildContext context) {
    final isAvailable = provider.isAvailable;
    final brand = _brandColor;
    final official = OfficialButtonArt.of(provider);
    final Widget button;
    if (official != null) {
      button = OfficialSocialButton(
        art: official,
        isLoading: isLoading,
        onPressed: isDisabled ? null : onPressed,
        onBlockedTap: isDisabled ? onBlockedTap : null,
      );
    } else {
      button = _buildDefaultButton(isAvailable, brand);
    }
    // 카카오·네이버는 공식 버튼 이미지를 통째로 쓰므로(브랜드 가이드가 다른
    // 요소를 위에 얹는 것을 금지할 수 있어) 배지를 버튼 **이미지 위**가
    // 아니라 버튼을 감싸는 Stack의 여백에 그린다. 구글·애플도 같은 위치에
    // 그려 두 종류의 버튼이 시각적으로 다르게 보이지 않게 한다.
    if (!isRecent) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        const Positioned(top: -8, right: 10, child: _RecentBadge()),
      ],
    );
  }

  Widget _buildDefaultButton(bool isAvailable, Color? brand) {
    // ⚠️ `OutlinedButton` 은 `onPressed: null` 이면 **탭 자체가 안 들어온다.**
    //    그래서 눌리지 않을 때만 바깥에서 탭을 받아 이유를 말한다.
    if (isDisabled) {
      return GestureDetector(
        onTap: onBlockedTap,
        behavior: HitTestBehavior.opaque,
        child: AbsorbPointer(child: _buildDefaultButtonInner(isAvailable, brand)),
      );
    }
    return _buildDefaultButtonInner(isAvailable, brand);
  }

  Widget _buildDefaultButtonInner(bool isAvailable, Color? brand) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: (!isAvailable || isDisabled) ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: brand ?? AppColors.cardSurface,
          disabledBackgroundColor: brand ?? AppColors.cardSurface,
          side: BorderSide(color: brand ?? AppColors.borderSubtle),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ProviderIcon(provider: provider),
                  const SizedBox(width: 10),
                  Text(
                    isAvailable
                        ? '${provider.displayName}로 계속하기'
                        : '${provider.displayName}로 계속하기 (준비 중)',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: isAvailable
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 「최근」배지 — 강조하지 않게, 옅게. 다른 버튼을 고르기 어려워 보이면
/// 안 된다는 요구(globe2030님, 설계 §3)에 따라 accent 계열 색을 쓰지 않는다.
/// 탭 대상이 아니다 — 버튼 전체가 이미 탭 대상이다.
class _RecentBadge extends StatelessWidget {
  const _RecentBadge();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.bgBase,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: const Text(
          '최근',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _ProviderIcon extends StatelessWidget {
  final SnsAuthProvider provider;
  const _ProviderIcon({required this.provider});

  @override
  Widget build(BuildContext context) {
    // ⚠️ 이 함수는 예전에 "Apple이 아니면 구글 G"였다. 카카오·네이버를 넣으면서
    // 여기를 안 고쳐 **카카오 버튼에 구글 G가 붙었다**(2026-08-20 실기기에서
    // 발견). 제공자를 추가할 때 같이 고쳐야 하는 자리라 분기를 명시적으로 둔다.
    //
    // 📌 카카오·네이버는 공식 버튼 이미지를 통째로 쓰므로 이 함수를 타지
    // 않는다(_OfficialSocialButton). **심볼만 떼어 여기 아이콘으로 넣을 수
    // 없다** — 카카오 가이드가 "심볼 없이 카카오 로그인 버튼을 구성할 수
    // 없습니다", "기능 아이콘을 카카오 로그인 버튼의 심볼로 사용할 수
    // 없습니다"를 못박고 있어 조합 자체가 규정 밖이다.
    return switch (provider) {
      SnsAuthProvider.apple => const Icon(
        Icons.apple,
        size: 22,
        color: AppColors.textPrimary,
      ),
      SnsAuthProvider.google => const Text(
        'G',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.accent,
        ),
      ),
      SnsAuthProvider.kakao ||
      SnsAuthProvider.naver ||
      SnsAuthProvider.email =>
        const SizedBox.shrink(),
    };
  }
}

/// 로그인 화면 하단의 약관·방침 고지. 각 문서 이름을 눌러 바로 열 수 있어야
/// "명시했다"고 볼 수 있으므로 링크로 만든다.
class _LegalNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontSize: 12,
      color: AppColors.textMuted,
      height: 1.5,
    );
    final link = base.copyWith(
      color: AppColors.accentText,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.accentText,
    );

    // 🚨 **한글은 아무 글자에서나 줄이 바뀐다**(2026-08-31, globe2030님 실기기
    //    제보: *"개인정보처리방에서 줄바꿈이 되어 어색해"*).
    //
    // 좁은 화면에서 **문서 이름 한가운데**가 갈렸다 — `개인정보처리방` / `침에`.
    // 그 이름은 **약관·방침 화면과 글자까지 같아야** 이용자가 같은 것으로
    // 알아본다(약관규제법 §3 명시 의무). **갈리면 다른 이름처럼 보인다.**
    //
    // 📌 **줄 바꿀 자리를 우리가 정한다.** 「계속하기를 누르면」 뒤에서 한 번
    //    끊으면, 좁은 화면에서도 문서 이름 둘이 한 줄에 온전히 들어간다.
    //    넓은 화면에서는 두 줄이 되지만 **가운데 정렬이라 자연스럽다.**
    //
    // ⚠️ **낱말 사이에 보이지 않는 문자를 넣는 방법은 쓰지 않았다** — 문서
    //    이름이 다른 곳(`LegalDocument.title`)과 글자가 달라지고, 복사하면
    //    이상한 값이 붙는다.
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: '계속하기를 누르면\n'),
          TextSpan(
            text: LegalDocument.terms.title,
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => showLegalDocument(context, LegalDocument.terms),
          ),
          const TextSpan(text: '과 '),
          TextSpan(
            text: LegalDocument.privacy.title,
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => showLegalDocument(context, LegalDocument.privacy),
          ),
          const TextSpan(text: '에 동의하는 것으로 봅니다.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

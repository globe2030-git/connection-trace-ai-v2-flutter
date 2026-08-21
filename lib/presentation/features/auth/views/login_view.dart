import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../../core/utils/image_file_cache.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sns_auth_provider.dart';
import '../../../common/social_oauth_view.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../common/legal_document_view.dart';

/// 앱 진입을 막는 SNS 로그인 화면. Google은 기존 Gmail 연동에서 이미 쓰던
/// google_sign_in을 그대로 재사용해 바로 동작하고, Apple은 iOS/macOS에서만
/// 정상 동작하는 버튼으로 보여준다(`SnsAuthProvider.apple.isAvailable` 참고 —
/// Android에서는 버튼 자체를 렌더링하지 않는다). 카카오는 이번 범위에서
/// 제외했다.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  SnsAuthProvider? _loadingProvider;
  String? _errorMessage;

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
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '로그인 중 문제가 발생했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
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

      await profileRepo.updateProfile(
        profile.copyWith(avatarPath: savedPath),
      );
    } catch (e) {
      // 프로필 사진은 부가 편의 기능이라 실패해도 로그인 흐름을 막지 않는다.
      debugPrint('Google 프로필 사진 미리 채우기 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(child: Image.asset('assets/images/brand/ci.png', width: 140)),
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
              const SizedBox(height: 40),
              _SnsButton(
                provider: SnsAuthProvider.google,
                isLoading: _loadingProvider == SnsAuthProvider.google,
                isDisabled: _loadingProvider != null,
                onPressed: () => _signIn(SnsAuthProvider.google),
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
                    onPressed: () => _signIn(p),
                  ),
                ],
              if (SnsAuthProvider.apple.isAvailable) ...[
                const SizedBox(height: 12),
                _SnsButton(
                  provider: SnsAuthProvider.apple,
                  isLoading: _loadingProvider == SnsAuthProvider.apple,
                  isDisabled: _loadingProvider != null,
                  onPressed: () => _signIn(SnsAuthProvider.apple),
                ),
              ],
              // 약관규제법 제3조(명시 의무) 대응. v1은 별도 체크박스 대신
              // 고지 문구 방식을 쓴다 — 개인정보는 계약 이행에 필요한
              // 최소분만 처리해 별도 동의가 필요 없고(개인정보 보호법
              // 제15조 제1항 제4호), 위치·AI 전송은 각각 별도 동의 화면이
              // 이미 있기 때문. 선택 동의 항목(마케팅 수신 등)이 생기면
              // 체크박스 방식으로 올려야 한다.
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

  const _SnsButton({
    required this.provider,
    required this.isLoading,
    required this.isDisabled,
    required this.onPressed,
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
  Color? get _brandColor => switch (provider) {
    SnsAuthProvider.kakao => AppColors.channelKakao,
    SnsAuthProvider.naver => AppColors.brandNaver,
    SnsAuthProvider.google || SnsAuthProvider.apple => null,
  };

  Color? get _brandTextColor => switch (provider) {
    SnsAuthProvider.kakao => AppColors.brandKakaoLabel,
    SnsAuthProvider.naver => Colors.white,
    SnsAuthProvider.google || SnsAuthProvider.apple => null,
  };

  @override
  Widget build(BuildContext context) {
    final isAvailable = provider.isAvailable;
    final brand = _brandColor;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: (!isAvailable || isDisabled) ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: brand ?? AppColors.cardSurface,
          disabledBackgroundColor: brand ?? AppColors.cardSurface,
          side: BorderSide(
            color: brand ?? AppColors.borderSubtle,
          ),
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
                  // 로고가 없는 제공자는 간격도 없애야 라벨이 가운데 온다.
                  if (provider != SnsAuthProvider.kakao &&
                      provider != SnsAuthProvider.naver)
                    const SizedBox(width: 10),
                  Text(
                    isAvailable
                        ? '${provider.displayName}로 계속하기'
                        : '${provider.displayName}로 계속하기 (준비 중)',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: isAvailable
                          ? (_brandTextColor ?? AppColors.textPrimary)
                          : AppColors.textMuted,
                    ),
                  ),
                ],
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
    // 📌 카카오·네이버는 공식 로고 애셋을 받아야 한다 — 가이드가 "로고 형태를
    // 변경하거나 다른 형태와 조합하는 것은 금지"라고 못박고 있어 임의로 그릴 수
    // 없다. 애셋이 들어오기 전까지는 **아무 표시도 하지 않는다.** 남의 로고를
    // 흉내 내는 것보다 없는 편이 낫다.
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
      SnsAuthProvider.kakao || SnsAuthProvider.naver => const SizedBox.shrink(),
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

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: '계속하기를 누르면 '),
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

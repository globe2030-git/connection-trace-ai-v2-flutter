import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sns_auth_provider.dart';
import '../../../../data/repositories/auth_repository.dart';

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
        case SnsAuthProvider.apple:
          await auth.signInWithApple();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '로그인 중 문제가 발생했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDarkSlate,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(child: Image.asset('assets/CI.png', width: 140)),
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
              if (SnsAuthProvider.apple.isAvailable) ...[
                const SizedBox(height: 12),
                _SnsButton(
                  provider: SnsAuthProvider.apple,
                  isLoading: _loadingProvider == SnsAuthProvider.apple,
                  isDisabled: _loadingProvider != null,
                  onPressed: () => _signIn(SnsAuthProvider.apple),
                ),
              ],
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

  @override
  Widget build(BuildContext context) {
    final isAvailable = provider.isAvailable;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: (!isAvailable || isDisabled) ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.cardDark,
          disabledBackgroundColor: AppColors.cardDark,
          side: const BorderSide(color: AppColors.borderDark),
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

class _ProviderIcon extends StatelessWidget {
  final SnsAuthProvider provider;
  const _ProviderIcon({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider == SnsAuthProvider.apple) {
      return const Icon(Icons.apple, size: 22, color: AppColors.textPrimary);
    }
    return const Text(
      'G',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.accent,
      ),
    );
  }
}

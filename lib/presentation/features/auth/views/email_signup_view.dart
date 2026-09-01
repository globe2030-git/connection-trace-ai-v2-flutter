import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/repositories/auth_repository.dart';
import 'password_reset_view.dart';

/// ⑧ 이메일+비밀번호 가입/로그인(추가 632, 2026-08-31).
///
/// **로그인/가입을 가르는 화면을 따로 두지 않는다** — "계속하기"를 누르면
/// `AuthRepository.signInOrSignUpWithEmail`이 **가입을 먼저** 시도하고,
/// 계정이 이미 있으면(`email-already-in-use`) 그 안에서 로그인으로
/// 폴백한다(추가 636에서 순서를 뒤집었다 — 이메일 열거 방지가 켜진 프로젝트에서는
/// signIn을 먼저 타면 `user-not-found`가 나오지 않아 가입 분기에 영원히
/// 못 간다). 이유는 `docs/planning/specs/email-signup-unified-consent-2026-08-31.md`
/// §7 "갈래 UI" 판단과 `AuthRepository.signInOrSignUpWithEmail`의 문서
/// 주석 참고 — 존재 여부를 미리 물으면 그 자체가 열거 취약점이다.
///
/// 이 화면은 **⑨(SignupConsentView)를 통과한 뒤에만** 뜬다 — `LoginView
/// ._startSignIn`이 순서를 보장한다.
///
/// **비밀번호 확인 칸이 없다**(추가 640, 2026-08-31). 이 화면이 가입과
/// 로그인을 겸하게 되면서(추가 636) "확인"은 로그인하는 사람에게는 뜻이
/// 없어졌다 — 이미 정해 둔 비밀번호를 다시 입력해 맞는지 볼 이유가 없다.
/// 가입인지 로그인인지는 화면에 들어가기 전에는 알 수 없고(이메일 열거
/// 방지 때문에 서버에 미리 물을 수도 없다) 서로 다른 화면으로 가를 수도
/// 없으므로, 확인칸 대신 "보기" 아이콘(`suffixIcon`)으로 오타를 눈으로
/// 확인하게 한다.
class EmailSignupView extends StatefulWidget {
  const EmailSignupView({super.key});

  @override
  State<EmailSignupView> createState() => _EmailSignupViewState();
}

class _EmailSignupViewState extends State<EmailSignupView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _busy = false;
  String? _errorMessage;

  /// 비밀번호가 틀렸을 때만 켜진다 — 재설정(⑩) 링크를 보여줄 근거.
  bool _offerPasswordReset = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _errorMessage = '올바른 이메일 주소를 입력해 주세요.';
        _offerPasswordReset = false;
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        _errorMessage = '6자 이상의 비밀번호를 입력해 주세요.';
        _offerPasswordReset = false;
      });
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
      _offerPasswordReset = false;
    });

    final auth = context.read<AuthRepository>();
    try {
      await auth.signInOrSignUpWithEmail(email, password);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _offerPasswordReset = e.offerPasswordReset;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '로그인 중 문제가 발생했습니다. 다시 시도해 주세요.';
        _offerPasswordReset = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPasswordReset() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PasswordResetView(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('이메일로 계속하기'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '이메일 주소와 비밀번호를 입력해 주세요.\n'
                '이미 가입한 이메일이면 로그인하고, 아니면 새로 가입합니다.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              _FieldLabel('이메일'),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: _inputDecoration('you@example.com'),
                enabled: !_busy,
              ),
              const SizedBox(height: 16),
              _FieldLabel('비밀번호'),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                autofillHints: const [AutofillHints.password],
                decoration: _inputDecoration('6자 이상').copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                enabled: !_busy,
                onSubmitted: _busy ? null : (_) => _submit(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.destructive,
                  ),
                ),
                if (_offerPasswordReset) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy ? null : _openPasswordReset,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        '비밀번호를 잊으셨나요? 재설정하기',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentText,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '계속하기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: _busy ? null : _openPasswordReset,
                  child: const Text(
                    '비밀번호를 잊으셨나요?',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
      filled: true,
      fillColor: AppColors.cardSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

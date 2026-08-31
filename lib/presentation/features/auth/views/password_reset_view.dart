import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/repositories/auth_repository.dart';

/// ⑩ 비밀번호 재설정(추가 632, 2026-08-31, §5-3).
///
/// 🚨 **가입한 이메일인지 알려주지 않는다.** 존재하지 않는 이메일을 넣어도
/// 메일을 보냈을 때와 **화면상 똑같은 결과**를 보여준다 —
/// `AuthRepository.sendPasswordReset`이 `user-not-found`를 조용히 삼키고
/// 성공으로 반환하기 때문에, 이 화면은 그 값을 그대로 믿고 보여주면 된다.
/// 계정 존재 여부를 노출하는 것 자체가 정보 유출이다(누가 가입했는지 알려줌).
class PasswordResetView extends StatefulWidget {
  const PasswordResetView({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<PasswordResetView> createState() => _PasswordResetViewState();
}

class _PasswordResetViewState extends State<PasswordResetView> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  bool _busy = false;
  bool _sent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = '올바른 이메일 주소를 입력해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await context.read<AuthRepository>().sendPasswordReset(email);
      if (!mounted) return;
      setState(() => _sent = true);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '메일을 보내지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('비밀번호 재설정'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: _sent ? _buildSentState() : _buildFormState(),
        ),
      ),
    );
  }

  Widget _buildFormState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '가입할 때 쓴 이메일 주소를 입력해 주세요.\n비밀번호를 재설정할 수 있는 메일을 보내드려요.',
          style: TextStyle(
            fontSize: 13,
            height: 1.55,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          enabled: !_busy,
          decoration: InputDecoration(
            hintText: 'you@example.com',
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13.5,
            ),
            filled: true,
            fillColor: AppColors.cardSurface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
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
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 12.5, color: AppColors.destructive),
          ),
        ],
        const SizedBox(height: 20),
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
                    '재설정 메일 보내기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSentState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          size: 44,
          color: AppColors.accent,
        ),
        const SizedBox(height: 16),
        const Text(
          '메일을 보냈어요',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '입력하신 주소로 이메일이 발송됐어요.\n받은 메일함(스팸함 포함)을 확인해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            height: 1.55,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.borderSubtle),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('닫기'),
          ),
        ),
      ],
    );
  }
}

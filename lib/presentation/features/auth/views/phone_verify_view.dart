import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/phone_verification_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../settings/views/inquiry_view.dart';

/// 휴대전화번호 확인 화면 (추가 565).
///
/// ## 자리
///
/// ```
/// 로그인 화면(만 14세 ☑) → SNS 로그인 → 🆕 이 화면 → 광고 동의 → 앱
/// ```
///
/// 🚨 **건너뛰기가 없다**(globe2030님 확정). 그래서 이 화면에는 닫기·뒤로가
/// 없고, [AuthGate]가 인증 전에는 앱 본체 대신 이 화면을 그린다. 광고 동의가
/// `Navigator.push`로 떴다 사라지는 것과 **구조가 다르다** — 그쪽은 선택이고
/// 이쪽은 필수다.
///
/// ## ⚠️ 「본인확인」이 아니다
///
/// 화면 어디에도 그 말을 쓰지 않는다. 정보통신망법 §23의3의 「본인확인업무」는
/// 지정 기관만 할 수 있는 법정 용어라, 우리가 하는 것을 그렇게 부르면 과태료
/// 조문의 외관을 스스로 만든다(법률 조사 판단). **「휴대전화번호 확인」**만
/// 쓴다.
///
/// ## 🚨 타이머는 표시일 뿐이다
///
/// 남은 시간을 화면이 세지만 **막는 것은 서버다.** 기기 시계를 돌려도
/// 서버가 거부한다. 타이머가 0이 되기 전에 눌러도 마찬가지다.
class PhoneVerifyView extends StatefulWidget {
  const PhoneVerifyView({super.key, required this.onVerified});

  /// 인증이 끝났을 때. [AuthGate]가 이걸 받아 앱 본체로 넘어간다.
  final VoidCallback onVerified;

  @override
  State<PhoneVerifyView> createState() => _PhoneVerifyViewState();
}

class _PhoneVerifyViewState extends State<PhoneVerifyView> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  /// 인증번호를 한 번이라도 받았는가. 받기 전에는 코드 칸을 안 그린다
  /// (**빈 칸을 그리지 않는다** — 이 저장소 규칙).
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  /// 재전송까지 남은 초. 🚨 **서버가 준 값에서 시작한다.**
  int _resendLeft = 0;
  Timer? _ticker;

  /// 상한에 걸렸는가. 걸리면 문의 안내를 보여 준다.
  bool _blocked = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _ticker?.cancel();
    if (seconds <= 0) {
      setState(() => _resendLeft = 0);
      return;
    }
    setState(() => _resendLeft = seconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendLeft -= 1);
      if (_resendLeft <= 0) t.cancel();
    });
  }

  Future<void> _requestCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final res = await PhoneVerificationService.request(_phoneController.text);
    if (!mounted) return;

    setState(() {
      _busy = false;
      switch (res.result) {
        case PhoneOtpRequestResult.sent:
          _codeSent = true;
          _blocked = false;
          // 서버가 정한 간격이 곧 유효시간이라(추가 563), 여기서 3분을
          // 다시 계산하지 않는다.
          _startCountdown(res.retryAfterMs != null
              ? (res.retryAfterMs! / 1000).ceil()
              : 180);
        case PhoneOtpRequestResult.tooSoon:
          _startCountdown(((res.retryAfterMs ?? 0) / 1000).ceil());
          _error = '아직 다시 받을 수 없어요.';
        case PhoneOtpRequestResult.dailyCap:
          _blocked = true;
          _error = '오늘 받을 수 있는 횟수를 다 썼어요.';
        case PhoneOtpRequestResult.invalidNumber:
          _error = '휴대전화번호를 다시 확인해 주세요.';
        case PhoneOtpRequestResult.sendFailed:
          _error = '인증번호를 보내지 못했어요. 잠시 후 다시 시도해 주세요.';
        case PhoneOtpRequestResult.unknown:
          _error = '문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
      }
    });
  }

  Future<void> _confirmCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final res = await PhoneVerificationService.confirm(
      phone: _phoneController.text,
      code: _codeController.text,
    );
    if (!mounted) return;

    if (res == PhoneOtpConfirmResult.verified) {
      widget.onVerified();
      return;
    }

    setState(() {
      _busy = false;
      switch (res) {
        case PhoneOtpConfirmResult.expired:
          // 추가 563에서 확정한 문구 그대로.
          _error = '시간이 지났어요, 다시 받기';
          _codeController.clear();
          _startCountdown(0);
        case PhoneOtpConfirmResult.mismatch:
          _error = '인증번호가 맞지 않아요.';
        case PhoneOtpConfirmResult.tooManyAttempts:
          _error = '여러 번 틀려서 이 인증번호는 못 써요. 다시 받아 주세요.';
          _codeController.clear();
          _startCountdown(0);
        case PhoneOtpConfirmResult.noChallenge:
          _error = '인증번호를 먼저 받아 주세요.';
        case PhoneOtpConfirmResult.alreadyTaken:
          // ⏸️ 1차 범위에서는 잇지 않는다(추가 564). 어긋남을 드러내고
          // 사람에게 넘긴다.
          _blocked = true;
          _error = '이 번호는 이미 다른 계정에 연결되어 있어요.';
        case PhoneOtpConfirmResult.unknown:
        case PhoneOtpConfirmResult.verified:
          _error = '문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 🚨 뒤로가기로 빠져나갈 수 없다 — 건너뛰기가 없다는 방침이 여기서
    // 지켜진다. 막지 않으면 안드로이드 뒤로가기 한 번으로 뚫린다.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgBase,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '휴대전화번호 확인',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '기기를 바꾸거나 다른 방법으로 들어와도 명함을 그대로 찾으려면 '
                  '번호를 한 번 확인합니다.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                _label('휴대전화번호'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        controller: _phoneController,
                        hint: '010 0000 0000',
                        keyboardType: TextInputType.phone,
                        // 숫자·하이픈만 — 서버가 다시 다듬지만 여기서도 막는다.
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9\-+ ]')),
                          LengthLimitingTextInputFormatter(20),
                        ],
                        enabled: !_busy,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _secondaryButton(
                      label: _resendLeft > 0 ? _mmss(_resendLeft) : '인증번호 받기',
                      onTap: _resendLeft > 0 || _busy ? null : _requestCode,
                    ),
                  ],
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 15),
                  _label('인증번호'),
                  const SizedBox(height: 6),
                  _field(
                    controller: _codeController,
                    hint: '6자리',
                    keyboardType: TextInputType.number,
                    formatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    enabled: !_busy,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.destructive,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _infoBox(),
                if (_blocked) ...[
                  const SizedBox(height: 12),
                  _blockedBox(context),
                ],
                const SizedBox(height: 24),
                _primaryButton(
                  label: '확인하고 시작하기',
                  onTap: !_codeSent || _busy ? null : _confirmCode,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _mmss(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _label(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required TextInputType keyboardType,
    required List<TextInputFormatter> formatters,
    required bool enabled,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      enabled: enabled,
      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 15, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.cardSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderFunctional),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderFunctional),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }

  Widget _secondaryButton({required String label, VoidCallback? onTap}) {
    final disabled = onTap == null;
    return SizedBox(
      width: 104,
      height: 50,
      child: Material(
        color: disabled ? AppColors.bgBase : AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: disabled ? AppColors.textMuted : AppColors.accentText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({required String label, VoidCallback? onTap}) {
    final disabled = onTap == null;
    return SizedBox(
      height: 52,
      child: Material(
        color: disabled ? AppColors.borderFunctional : AppColors.accent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: disabled ? AppColors.textMuted : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이 단계에서 확인하는 것',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 7),
          // ⚠️ 과장하지 않는다 — 우리가 하는 것은 "이 번호로 오는 인증번호를
          // 받으시는지"까지다. 이름·생년월일을 통신사에 맞춰 보지 않는다.
          Text(
            '이 번호로 오는 인증번호를 받으시는지만 봅니다.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.75,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 상한에 걸렸거나 번호가 이미 쓰이고 있을 때.
  ///
  /// 🚨 **막힌 사람을 그냥 두지 않는다.** 그날 가입을 못 하게 된다.
  /// ⚠️ 고객센터 전화번호는 아직 없어서(월요일 항목) **가짜 번호를 넣지
  /// 않고** 이미 있는 「1:1 문의」로 보낸다.
  Widget _blockedBox(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentSoftStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '도움이 필요하시면 알려 주세요',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.accentText,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '문의를 남겨 주시면 확인해 드립니다.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.65,
              color: AppColors.accentText,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const InquiryView()),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '1:1 문의하기',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

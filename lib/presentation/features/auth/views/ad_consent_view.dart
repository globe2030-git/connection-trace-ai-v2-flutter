import 'package:flutter/material.dart';

import '../../../../core/services/ad_consent_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sns_auth_provider.dart';

/// 광고성 정보 수신 동의 화면(추가 472 · 시행 2026-09-15).
///
/// 로그인 직후, **아직 답한 적 없는 계정에게만 한 번** 보인다.
///
/// ## 🚨 배치가 법 요건이다 — 순서를 바꾸지 말 것
///
/// 처음에는 셋을 나란히 놓았다. 법무 회신(추가 473 Q10-②다)이 **실제 결함**을
/// 짚었다.
///
/// ```
/// 이메일 ✅ / 앱 알림 ✅ / 개인정보 이용 ❌
///   → 수신 동의는 있는데 이메일 주소·토큰을 광고 목적으로 쓸 근거가 없다
///   → 보내면 §15 위반, 안 보내면 이용자는 "동의했는데 왜 안 오나"
/// ```
///
/// **형식은 `[선택]`인데 실질은 전제**인 항목을 다른 선택 항목과 똑같이 보이게
/// 둔 것이라, 시행령 §17①2호(구체적·명확)에 어긋날 소지가 있다.
///
/// → **해법은 개수를 줄이는 것이 아니라 순서를 뒤집는 것이다.**
///
/// ```
/// 1. 개인정보 이용 동의   맨 위
/// 2. 매체 선택            위가 켜져야 열린다
/// ```
///
/// ⚠️ **반대로 매체를 켰다고 위가 자동으로 켜지게 하지 마라.** 자동 체크는
/// *"기본값 동의"*와 같은 평가를 받을 수 있다(안내서 p.12).
///
/// ## 지키는 것들
///
/// | 무엇 | 근거 |
/// |---|---|
/// | `[선택]` 배지를 **세 항목 전부에** | 시행령 §17④ |
/// | 셋 다 꺼진 채로 시작 | 기본값 동의 금지(안내서 p.12) |
/// | 하나도 안 골라도 진행 | 시행령 §17①1호 · 법 §22⑤ |
/// | 제목에 **"광고성 정보"**를 명시 | *"새 소식"* 같은 완곡한 이름은 **동의를 무효로 만든다**(안내서 p.12 — *"마케팅 동의"*조차 금지) |
/// | 전송자 명칭 표기 | 안내서 p.12 |
/// | 문구 버전 기록 | 나중에 배치를 바꾸면 **이미 받은 동의의 유효 범위**가 달라진다 |
///
/// ## 🚨 네이버 계정에는 이메일 항목을 보이지 않는다
///
/// [adEmailChannelAvailable] 참조. 네이버가 주는 것은 소유가 확인되지 않은
/// **"연락처 이메일"**이라 **남의 주소일 수 있다.**
class AdConsentView extends StatefulWidget {
  const AdConsentView({
    super.key,
    required this.provider,
    required this.onSubmit,
    this.initialEmail = false,
    this.initialPush = false,
    this.submitLabel = '시작하기',
    this.footnote = '하나도 선택하지 않고 시작하셔도 괜찮아요',
    this.dismissOnSubmit = false,
  });

  /// 답을 제출했을 때 **화면을 닫을지.**
  ///
  /// ## 🚨 왜 이 값이 생겼나 — 두 번에 걸쳐 드러났다
  ///
  /// **① 저장 실패**(2026-08-26 폴드): `firestore.rules` 가 아직 배포되지 않아
  /// 서버가 쓰기를 거부하는데(`PERMISSION_DENIED`), **그러면 이 화면을 지나갈
  /// 수가 없었다.** [submitLabel] 을 눌러도 *"설정을 저장하지 못했어요"* 만
  /// 뜨고 제자리다.
  ///
  /// **② 저장 성공**(같은 날, rules 배포 직후): 실패를 고쳤더니 **성공해도
  /// 못 나갔다.** `if (ok) return;` 이라 성공 경로에는 **화면을 닫는 코드가
  /// 아예 없었다.**
  ///
  /// 📌 **①이 ②를 가리고 있었다.** 배포 전에는 항상 실패했으니 성공 경로가
  /// 한 번도 안 돌았고, 그래서 **비어 있다는 것이 안 보였다.** 앞의 결함을
  /// 고치자마자 뒤의 결함이 같은 증상으로 나타났다 — 화면은 똑같이 안 닫히는데
  /// 이번에는 로그에 `PERMISSION_DENIED` 조차 없었다.
  ///
  /// ⚠️ **화면은 "받지 않으셔도 모든 기능을 그대로 쓰실 수 있어요" 라고
  /// 말하는데 실제로는 앱에 들어갈 수가 없었다.** 안드로이드 뒤로가기가 유일한
  /// 탈출구였고 그런 안내는 어디에도 없다.
  ///
  /// 📌 **자동 테스트는 둘 다 통과하고 있었다** — 화면이 *"안내를 띄운다"* 까지는
  /// 맞게 돌았기 때문이다. **규칙은 지켰는데 사람이 갇혔다.**
  ///
  /// ## 첫 물음과 설정에서 다르게 다룬다
  ///
  /// | | 제출했을 때 |
  /// |---|---|
  /// | **첫 물음**(`true`) | 성공이든 실패든 **닫는다** — 앱을 못 쓰게 막으면 안 된다 |
  /// | **설정**(`false`) | 머문다 — 바꾸러 들어온 사람이고, 결과를 화면에서 본다 |
  ///
  /// 실패해도 닫는 것이 안전하다. 저장이 안 됐으니 **동의하지 않은 상태**로
  /// 남고, 그 상태에서는 아무것도 보내지 않는다.
  final bool dismissOnSubmit;

  /// 설정에서 다시 열 때의 현재 값.
  ///
  /// ⚠️ **설정에서도 같은 화면을 쓴다.** 잠금 구조(전제 → 매체)를 따로 만들면
  /// 두 화면이 어긋나고, 어긋나는 순간 한쪽이 법 요건을 잃는다.
  final bool initialEmail;
  final bool initialPush;
  final String submitLabel;
  final String footnote;

  /// 로그인에 쓴 제공자. 이메일 항목을 보일지 정한다.
  final SnsAuthProvider? provider;

  /// 이용자가 [시작하기]를 눌렀을 때. 저장은 부르는 쪽이 한다.
  ///
  /// **서버 저장에 실패하면 `false`를 돌려주어야 한다** — 이 화면이 체크를
  /// 되돌리고 이유를 알린다. 서버는 거부했는데 화면만 켜진 채 넘어가면
  /// 이용자는 동의한 줄 알고, 그건 동의 없는 이용이 된다.
  final Future<bool> Function({required bool email, required bool push})
      onSubmit;

  /// 화면 문구·배치의 버전. 동의 기록과 함께 남긴다.
  ///
  /// ⚠️ **배치를 바꾸면 이 값을 올려라.** 나중에 A안↔B안을 바꾸면 이미 받은
  /// 동의가 **무엇에 대한 동의였는지**가 달라진다(법무 회신 추가 473 Q10-④4).
  static const String textVersion = 'ad-consent-a-2026-09-15';

  @override
  State<AdConsentView> createState() => _AdConsentViewState();
}

class _AdConsentViewState extends State<AdConsentView> {
  late bool _useAgreed = widget.initialEmail || widget.initialPush;
  late bool _email = widget.initialEmail;
  late bool _push = widget.initialPush;
  bool _busy = false;

  bool get _emailAvailable => adEmailChannelAvailable(widget.provider);

  /// 개인정보 이용 동의를 끄면 매체 선택도 함께 꺼진다.
  ///
  /// 켜 둔 채로 잠그기만 하면 **"쓸 근거는 없는데 받겠다고 한 상태"**가 화면에
  /// 남는다. 그 상태가 저장되면 안 되므로 값 자체를 내린다.
  void _setUseAgreed(bool value) {
    setState(() {
      _useAgreed = value;
      if (!value) {
        _email = false;
        _push = false;
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final email = _email;
    final push = _push;
    final ok = await widget.onSubmit(email: email, push: push);
    if (!mounted) return;
    setState(() => _busy = false);
    // 🚨 **첫 물음이면 성공해도 닫는다.** 성공 경로에 닫는 코드가 없어서
    //    `rules` 를 배포한 직후 **저장은 되는데 못 나가는** 상태가 됐다
    //    (2026-08-26 폴드, [dismissOnSubmit] 주석 참고).
    if (ok) {
      if (widget.dismissOnSubmit) Navigator.of(context).pop();
      return;
    }

    // 🚨 **첫 물음이면 실패해도 닫는다.** 여기서 머물면 앱에 들어갈 길이 없다.
    if (widget.dismissOnSubmit) {
      final navigator = Navigator.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('지금은 저장하지 못했어요. 설정에서 언제든 다시 하실 수 있어요.'),
        ),
      );
      navigator.pop();
      return;
    }

    // 설정에서 들어온 경우. **화면을 이 화면에 들어올 때의 값으로 되돌리고**
    // 이유를 알린다. 무조건 false 로 내리면 설정에서 켜져 있던 사람에게
    // "꺼진 것처럼" 보여 서버 상태와 화면이 반대로 어긋난다.
    setState(() {
      _email = widget.initialEmail;
      _push = widget.initialPush;
      _useAgreed = widget.initialEmail || widget.initialPush;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 30, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _OptionalBadge(),
                    const SizedBox(height: 13),
                    const Text(
                      // ⚠️ "새 소식"처럼 부르면 동의가 무효가 될 수 있다.
                      '광고성 정보 수신 동의',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      // 전송자 명칭을 밝힌다(안내서 p.12).
                      '커넥션센스(크림하우스주식회사)가 보내는 새 기능 소식, '
                      '이벤트·할인 안내 등 광고성 정보를 받으시겠어요?',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.62,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '받지 않으셔도 모든 기능을 그대로 쓰실 수 있어요.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── ① 전제: 개인정보 이용 동의 (반드시 맨 위) ──
                    _ConsentCard(
                      child: _UseAgreementRow(
                        checked: _useAgreed,
                        onChanged: _busy ? null : _setUseAgreed,
                        emailShown: _emailAvailable,
                      ),
                    ),
                    const SizedBox(height: 14),

                    _Divider(enabled: _useAgreed),
                    const SizedBox(height: 14),

                    // ── ② 매체: 위가 켜져야 열린다 ──
                    _ConsentCard(
                      child: Column(
                        children: [
                          if (_emailAvailable) ...[
                            _ChannelRow(
                              title: '이메일로 광고성 정보 받기',
                              subtitle: '가입하신 이메일 주소로 보내드려요',
                              checked: _email,
                              enabled: _useAgreed && !_busy,
                              onChanged: (v) => setState(() => _email = v),
                            ),
                            const _RowDivider(),
                          ],
                          _ChannelRow(
                            title: '앱 알림으로 광고성 정보 받기',
                            subtitle: '휴대폰 알림으로 보내드려요',
                            checked: _push,
                            enabled: _useAgreed && !_busy,
                            onChanged: (v) => setState(() => _push = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    const _NoticeCard(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 51,
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
                          : Text(
                              widget.submitLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // 🚨 **나가는 길이 둘인데 하나만 화면에 있었다**(2026-08-30,
                  //    globe2030님 실기기 제보).
                  //
                  // ```
                  // 화면에 있던 길   아무것도 안 고르고 「시작하기」 → 「거부」로 답이 기록된다
                  // 화면에 없던 길   뒤로가기                     → 답 없이 넘어간다
                  // ```
                  //
                  // 이용자는 뒤로가기를 **동의로 읽었다.** 그래서 그 길을
                  // 화면에 올려 이름을 붙인다. 뒤로가기도 같은 처리를 한다.
                  //
                  // ⚠️ **「거부」와 다르다.** 이쪽은 답을 미루는 것이라
                  //    30일 뒤 다시 묻는다.
                  if (widget.dismissOnSubmit)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: const Text(
                        '나중에 할게요',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    // 하나도 안 골라도 진행된다는 것을 화면에서 말한다
                    // (시행령 §17①1호 · 법 §22⑤).
                    widget.footnote,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `[선택]` 배지. 시행령 §17④가 **선택할 수 있다는 사실을 명확히 표시**하도록
/// 요구한다. 법무 회신은 이것을 **세 항목 전부에** 붙이라고 했다.
class _OptionalBadge extends StatelessWidget {
  const _OptionalBadge({this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 11,
        vertical: dense ? 2 : 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '선택',
        style: TextStyle(
          fontSize: dense ? 10.5 : 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.accentText,
        ),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: AppColors.cardShadow, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: child,
    );
  }
}

/// 전제가 되는 개인정보 이용 동의. **맨 위에 온다.**
class _UseAgreementRow extends StatelessWidget {
  const _UseAgreementRow({
    required this.checked,
    required this.onChanged,
    required this.emailShown,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;

  /// 네이버 계정이면 이메일 항목이 없으므로 **이용 항목에서도 뺀다.**
  /// 받지도 않을 항목을 고지하면 그것대로 사실과 다르다.
  final bool emailShown;

  @override
  Widget build(BuildContext context) {
    final items = emailShown
        ? '이메일 주소 · 앱 알림을 보내기 위한 기기 알림 토큰'
        : '앱 알림을 보내기 위한 기기 알림 토큰';
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!checked),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Box(checked: checked, enabled: onChanged != null),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _OptionalBadge(dense: true),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          '광고성 정보를 보내기 위해 아래 개인정보를 이용하는 데 동의합니다',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  _Detail(label: '이용 항목', value: items),
                  _Detail(label: '이용 목적', value: '광고성 정보 전송'),
                  _Detail(
                    label: '보유 기간',
                    value: '수신 동의를 철회하시거나 회원 탈퇴하실 때까지',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '동의하지 않으셔도 서비스 이용에 아무런 제한이 없어요',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 위 항목이 켜져야 아래가 열린다는 것을 눈으로 보이게 하는 줄.
class _Divider extends StatelessWidget {
  const _Divider({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.accentText : AppColors.textMuted;
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: AppColors.borderSubtle)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            enabled ? '받을 방법을 골라 주세요' : '위에 동의하시면 아래를 고를 수 있어요',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: AppColors.borderSubtle)),
      ],
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 15),
        color: const Color(0xFFF0F2F5),
      );
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.title,
    required this.subtitle,
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // 잠긴 상태를 흐리게 보여 준다. 숨기지 않는 이유는, 무엇을 고를 수 있는지
    // 먼저 보여야 위 항목에 동의할지 판단할 수 있기 때문이다.
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: InkWell(
        onTap: enabled ? () => onChanged(!checked) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
          child: Row(
            children: [
              _Box(checked: checked, enabled: enabled),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _OptionalBadge(dense: true),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.checked, required this.enabled});

  final bool checked;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 23,
      height: 23,
      margin: const EdgeInsets.only(top: 1),
      decoration: BoxDecoration(
        color: checked ? AppColors.accent : AppColors.cardSurface,
        border: checked
            ? null
            : Border.all(color: const Color(0xFFC9CFD9), width: 1.8),
        borderRadius: BorderRadius.circular(7),
      ),
      child: checked
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : null,
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '알아두실 점',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 8),
          // ⚠️ 아래 셋은 발송 쪽에서 실제로 지켜야 한다. 화면에만 적고 안 지키면
          //    이 문장이 그대로 증거가 된다.
          _Bullet('광고성 정보에는 제목 앞에 (광고)가 붙어요'),
          _Bullet('밤 9시부터 아침 8시까지는 보내지 않아요'),
          _Bullet('설정 → 알림에서 언제든 끄실 수 있어요'),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('· ', style: TextStyle(color: AppColors.textMuted)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

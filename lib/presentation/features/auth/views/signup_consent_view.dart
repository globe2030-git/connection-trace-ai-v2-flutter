import 'package:flutter/material.dart';

import '../../../../core/services/ad_consent_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sns_auth_provider.dart';
import '../../../common/legal_document_view.dart';
import '../widgets/consent_widgets.dart';

/// ⑨ "시작하기 전에" — 통합 동의 화면(추가 632, 2026-08-31).
///
/// 로그인 화면에서 **어느 버튼(소셜·이메일)을 눌러도 이 화면이 먼저** 뜬다.
/// 자세한 설계는
/// `docs/planning/specs/email-signup-unified-consent-2026-08-31.md` 참고.
///
/// ## 이 화면이 하는 일과 안 하는 일
///
/// | 항목 | 이 화면에서 |
/// |---|---|
/// | 만 14세·이용약관·개인정보처리방침(필수 3종) | 체크해야 진행할 수 있다. **서버에 저장하지 않는다**(§3-1 — 주기 재확인 의무가 없는 1회성 게이트라 성격이 안 바뀐다) |
/// | 광고성 정보 수신(선택 1종) | 값을 골라 [ConsentChoice]로 돌려준다. **이 화면 자체는 저장하지 않는다** — uid를 아직 모르기 때문이다(§2) |
///
/// 저장은 로그인/가입이 실제로 성공해 uid가 생긴 뒤 `LoginView`가
/// `AdConsentService.applyFreshSignupChoice`로 한다.
class SignupConsentView extends StatefulWidget {
  const SignupConsentView({super.key, required this.provider});

  /// 어느 버튼을 눌러 이 화면에 왔는지 — 이메일 채널 노출 여부를 정한다
  /// (네이버만 이메일 항목이 빠진다, [adEmailChannelAvailable]).
  final SnsAuthProvider provider;

  @override
  State<SignupConsentView> createState() => _SignupConsentViewState();
}

class _SignupConsentViewState extends State<SignupConsentView> {
  bool _age = false;
  bool _terms = false;
  bool _privacy = false;

  bool _adUseAgreed = false;
  bool _adEmail = false;
  bool _adPush = false;

  bool get _emailAvailable => adEmailChannelAvailable(widget.provider);
  bool get _allRequired => _age && _terms && _privacy;

  /// "필수 항목에 모두 동의" — **필수 3종만** 켠다. 광고(선택)는 건드리지
  /// 않는다 — `ad_consent_view.dart`의 `_setUseAgreed`와 같은 원칙(추가 457,
  /// 방통위·KISA 안내서: 선택 항목은 반드시 따로 눌러야 켜진다).
  void _toggleAllRequired(bool value) {
    setState(() {
      _age = value;
      _terms = value;
      _privacy = value;
    });
  }

  /// 광고 수신 전제를 끄면 매체 선택도 함께 꺼진다(`ad_consent_view.dart`의
  /// `_setUseAgreed`와 같은 이유 — 쓸 근거 없이 받겠다고 한 상태가 남으면
  /// 안 된다).
  void _setAdUseAgreed(bool value) {
    setState(() {
      _adUseAgreed = value;
      if (!value) {
        _adEmail = false;
        _adPush = false;
      }
    });
  }

  void _submit() {
    if (!_allRequired) return;
    Navigator.of(
      context,
    ).pop(ConsentChoice(adEmail: _adEmail, adPush: _adPush));
  }

  /// 동의하지 않고 나간다.
  ///
  /// 🚨 **막지 않고 말해 준다.** 필수 동의를 안 하면 이용계약이 서지 않으므로
  /// 서비스를 쓸 수 없는 것이 맞지만, **막아야 할 것은 「가입 진행」이지
  /// 「화면을 벗어나는 것」이 아니다.** 나갈 길을 없애면 갇힌 것처럼 느껴지고,
  /// 그것은 「자유로운 동의」와 어울리지 않는다(광고 동의에서 정한 원칙과 같다
  /// — 추가 514·CLAUDE.md 4절).
  ///
  /// 📌 **이 화면에서 나가도 계정은 만들어지지 않는다** — 동의가 로그인보다
  /// 먼저라 아직 uid 가 없다. 그런데 **화면이 그 사실을 말해 주지 않으면**
  /// 사용자는 "가입이 된 건가?"를 알 수 없다. 광고 동의 사고가 정확히 그
  /// 자리였다(로직은 맞았고 화면이 말해 주지 않은 것이 틀렸다).
  Future<void> _cancel() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        title: const Text('동의하지 않고 나갈까요?'),
        content: const Text(
          '필수 항목에 동의하지 않으면 커넥션센스를 이용하실 수 없습니다.\n\n'
          '지금 나가시면 가입은 진행되지 않으며, 입력하신 내용도 저장되지 않습니다.',
          style: TextStyle(fontSize: 13.5, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('계속 보기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '나가기',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
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
                    const Text(
                      '시작하기 전에',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    const Text(
                      '커넥션센스를 시작하려면 아래 필수 항목에 동의해 주세요.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── 전체 동의(필수 3종만) ──
                    ConsentCard(
                      child: _AllRequiredRow(
                        checked: _allRequired,
                        onChanged: _toggleAllRequired,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── 필수 3종 ──
                    ConsentCard(
                      child: Column(
                        children: [
                          _RequiredRow(
                            label: '만 14세 이상입니다',
                            checked: _age,
                            onChanged: (v) => setState(() => _age = v),
                          ),
                          const RowDivider(),
                          _RequiredRow(
                            label: '이용약관에 동의',
                            checked: _terms,
                            onChanged: (v) => setState(() => _terms = v),
                            onViewTap: () =>
                                showLegalDocument(context, LegalDocument.terms),
                          ),
                          const RowDivider(),
                          _RequiredRow(
                            label: '개인정보처리방침 확인',
                            checked: _privacy,
                            onChanged: (v) => setState(() => _privacy = v),
                            onViewTap: () => showLegalDocument(
                              context,
                              LegalDocument.privacy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── 선택: 광고성 정보 수신 ──
                    const OptionalBadge(),
                    const SizedBox(height: 9),
                    const Text(
                      '광고성 정보 수신 동의',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '커넥션센스(크림하우스주식회사)가 보내는 새 기능 소식, '
                      '이벤트·할인 안내 등 광고성 정보를 받으시겠어요? '
                      '받지 않으셔도 모든 기능을 그대로 쓰실 수 있어요.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.55,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConsentCard(
                      child: Column(
                        children: [
                          ChannelRow(
                            title: '광고성 정보 수신',
                            subtitle: '이벤트·혜택 소식을 보내드려요',
                            checked: _adUseAgreed,
                            enabled: true,
                            onChanged: _setAdUseAgreed,
                          ),
                          if (_emailAvailable) ...[
                            const RowDivider(),
                            ChannelRow(
                              title: '이메일로 받기',
                              subtitle: '가입하신 이메일 주소로 보내드려요',
                              checked: _adEmail,
                              enabled: _adUseAgreed,
                              onChanged: (v) => setState(() => _adEmail = v),
                            ),
                          ],
                          const RowDivider(),
                          ChannelRow(
                            title: '앱 알림으로 받기',
                            subtitle: '휴대폰 알림으로 보내드려요',
                            checked: _adPush,
                            enabled: _adUseAgreed,
                            onChanged: (v) => setState(() => _adPush = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              child: SizedBox(
                width: double.infinity,
                height: 51,
                child: FilledButton(
                  onPressed: _allRequired ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '동의하고 시작하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            // 🚨 나가는 길을 화면에 둔다. 기기 뒤로가기로만 나갈 수 있으면
            // "나가는 길이 둘인데 하나만 화면에 있는" 상태가 된다(추가 514).
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: TextButton(
                onPressed: _cancel,
                child: const Text(
                  '동의하지 않고 나가기',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ⑨에서 확정된 동의값. `Navigator.pop(context, ConsentChoice(...))`로
/// 돌려준다 — 취소·뒤로가기는 `null`을 돌려준다(기본 `Navigator.pop()` 동작).
///
/// 필수 3종(만14세·약관·방침)은 여기 담지 않는다 — 서버에 저장하지 않으므로
/// 화면을 나가는 순간 값을 들고 있을 이유가 없다(§3-1).
@immutable
class ConsentChoice {
  const ConsentChoice({required this.adEmail, required this.adPush});

  final bool adEmail;
  final bool adPush;
}

/// "필수 항목에 모두 동의" — **"전체 동의"가 아니다.** 선택 항목(광고)은
/// 켜지 않는다.
class _AllRequiredRow extends StatelessWidget {
  const _AllRequiredRow({required this.checked, required this.onChanged});

  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        child: Row(
          children: [
            ConsentCheckbox(checked: checked, enabled: true),
            const SizedBox(width: 13),
            const Expanded(
              child: Text(
                '필수 항목에 모두 동의',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 필수 항목 한 줄(체크박스 + `[필수]` 배지 + 라벨). [onViewTap]이 있으면
/// "보기 ›" 버튼을 오른쪽에 더한다 — 약관·방침처럼 원문을 확인할 수 있어야
/// 하는 항목용이다.
///
/// ⚠️ **"보기" 버튼은 체크박스 토글과 별개의 형제 위젯이다.** 같은 `InkWell`
/// 안에 넣으면 탭이 겹쳐 "보기"를 눌렀는데 체크까지 같이 토글되거나 그
/// 반대가 될 수 있다.
class _RequiredRow extends StatelessWidget {
  const _RequiredRow({
    required this.label,
    required this.checked,
    required this.onChanged,
    this.onViewTap,
  });

  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onViewTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 2, 6, 2),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onChanged(!checked),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    ConsentCheckbox(checked: checked, enabled: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            height: 1.45,
                          ),
                          children: [
                            const TextSpan(
                              text: '[필수] ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.accentText,
                              ),
                            ),
                            TextSpan(text: label),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onViewTap != null)
            TextButton(
              onPressed: onViewTap,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('보기 ›', style: TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

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
import '../widgets/official_social_button.dart';
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

  /// 만 14세 이상 확인. **체크해야 로그인 버튼이 눌린다.**
  ///
  /// ## 왜 있나
  ///
  /// 방침(`privacy-policy.html`)과 약관(`terms-of-service.html`) 세 군데가
  /// **"만 14세 미만의 가입을 제한한다"**고 선언하고 있는데, 그것을 확인하는
  /// 수단이 앱에 하나도 없었다(2026-08-25 실측: `lib/` 전체에 연령 확인 코드
  /// 0건). **선언은 있고 뒷받침이 없는 상태**였고, 방침과 구현이 어긋나는 것
  /// 자체가 리스크라는 것은 이 저장소가 BYOK 서술로 이미 겪었다.
  ///
  /// ⚠️ **광고 수신 동의를 켜면 제재의 성격이 바뀐다** — 만 14세 미만에게
  /// 광고성 정보를 보내면 과태료가 아니라 **과징금(매출 3% 이하)**이다
  /// (정보통신망법 §64조의2①2호, 추가 457 법률 조사).
  ///
  /// ## 왜 체크박스인가 — 생년월일을 받지 않는다
  ///
  /// 개인정보위 가이드라인이 권장하는 **자기 확인 체크**다. 검증은 아니지만
  /// **물었고 이용자가 답했다는 기록**이 남는다. 무엇보다 **개인정보를 새로
  /// 수집하지 않아서**, 최소수집을 위해 생년월일에서 연도를 뺀 기존 판단
  /// (`my_profile_model.dart`의 `birthMonthDay`)과 부딪치지 않는다.
  ///
  /// ## 왜 광고 동의 화면이 아니라 여기인가
  ///
  /// 법률 조사(추가 457)의 판단이다 — **만 14세는 필수이고 광고는 선택**이라,
  /// 한 화면에 섞으면 이용자가 *"다 체크해야 하는구나"*로 읽어 **선택 동의의
  /// 자유가 흐려진다.** 그래서 가입 흐름에 둔다.
  ///
  /// ⚠️ **그런데 이 앱에는 가입 흐름이 따로 없다** — SNS 로그인뿐이라
  /// **로그인 = 가입**이고 가입 화면이 존재하지 않는다. 그래서 로그인 화면이
  /// 곧 가입 화면이고, 여기가 놓을 수 있는 유일한 자리다.
  ///
  /// 📌 **기억하지 않는다.** 로그인할 때마다 다시 묻는다 — 계정이 아니라
  /// 기기에 기억하면 계정을 바꿔도 안 묻게 되고, 계정에 기억하려면 로그인이
  /// 먼저여야 해서 순서가 꼬인다. 세션이 사실상 무기한이라 로그인 화면 자체를
  /// 자주 보지 않으므로(추가 456) 매번 묻는 부담이 작다.
  bool _ageConfirmed = false;

  /// 만 14세 확인을 잠깐 강조한다. [_promptAgeConfirm] 이 켜고 몇 초 뒤 끈다.
  bool _ageHighlight = false;

  /// 🚨 **눌리지 않는 버튼이 이유를 말하게 한다**(2026-08-30, 추가 626).
  ///
  /// 카카오·네이버 버튼은 **공식 브랜드 이미지를 통째로** 쓰므로 비활성이어도
  /// **밝은 노랑·초록 그대로**다. 이용자는 멀쩡해 보이는 버튼을 눌렀는데
  /// 아무 일도 안 일어나는 것을 본다 — **고장으로 읽는다.**
  ///
  /// 📌 **막지 말고 말한다.** 로그인은 여전히 시작되지 않지만, **왜 안 되는지**
  /// 는 알려 준다. 오늘 광고 동의에서 고친 것과 같은 원칙이다.
  ///
  /// ⚠️ **버튼을 흐리게 만들지 않았다** — 카카오·네이버는 버튼 가이드가 지정
  /// 컬러를 못박고 있고, 투명도 조정이 허용되는지 **원문을 확인하지 않았다.**
  /// 네이버는 사전 검수 항목이라 더 조심스럽다. **확인 전에는 손대지 않는다.**
  void _promptAgeConfirm() {
    if (_ageConfirmed) return;
    setState(() => _ageHighlight = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('만 14세 이상 확인에 체크해 주세요.'),
          duration: Duration(seconds: 3),
        ),
      );
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _ageHighlight = false);
    });
  }

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
              _AgeConfirmRow(
                checked: _ageConfirmed,
                highlight: _ageHighlight,
                onChanged: _loadingProvider != null
                    ? null
                    : (v) => setState(() => _ageConfirmed = v),
              ),
              const SizedBox(height: 20),
              _SnsButton(
                provider: SnsAuthProvider.google,
                isLoading: _loadingProvider == SnsAuthProvider.google,
                isDisabled: _loadingProvider != null || !_ageConfirmed,
                isRecent: lastProvider == SnsAuthProvider.google,
                onPressed: () => _signIn(SnsAuthProvider.google),
                onBlockedTap: _promptAgeConfirm,
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
                    isDisabled: _loadingProvider != null || !_ageConfirmed,
                    isRecent: lastProvider == p,
                    onPressed: () => _signIn(p),
                    onBlockedTap: _promptAgeConfirm,
                  ),
                ],
              if (SnsAuthProvider.apple.isAvailable) ...[
                const SizedBox(height: 12),
                _SnsButton(
                  provider: SnsAuthProvider.apple,
                  isLoading: _loadingProvider == SnsAuthProvider.apple,
                  isDisabled: _loadingProvider != null || !_ageConfirmed,
                  isRecent: lastProvider == SnsAuthProvider.apple,
                  onPressed: () => _signIn(SnsAuthProvider.apple),
                ),
              ],
              // 약관규제법 제3조(명시 의무) 대응. 약관·방침 동의는 여전히
              // **고지 문구 방식**이다 — 개인정보는 계약 이행에 필요한
              // 최소분만 처리해 별도 동의가 필요 없고(개인정보 보호법
              // 제15조 제1항 제4호), 위치·AI 전송은 각각 별도 동의 화면이
              // 이미 있기 때문.
              //
              // ⚠️ 이 자리에 있던 *"선택 동의 항목(마케팅 수신 등)이 생기면
              // 체크박스 방식으로 올려야 한다"*는 예고는 **2026-08-25에
              // 현실이 됐다.** 다만 위에 올린 체크박스는 마케팅이 아니라
              // **만 14세 확인**이다(필수 확인이라 성격이 다르다).
              // 광고 수신 동의는 **별도 화면**으로 만들고 있다(추가 454) —
              // 필수와 선택을 한 화면에 섞으면 선택 동의의 자유가 흐려진다는
              // 법률 조사 판단(추가 457)에 따른 것이다.
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

/// 만 14세 이상 확인 줄. 로그인 버튼 **위**에 둔다 — 체크해야 아래가 눌린다는
/// 것이 순서로 보여야 한다.
///
/// 📌 기본값은 **꺼짐**이다. 미리 켜 두면 "물었다"고 할 수 없다.
class _AgeConfirmRow extends StatelessWidget {
  final bool checked;

  /// `null`이면 누를 수 없다(로그인 진행 중).
  final ValueChanged<bool>? onChanged;

  /// 눌리지 않는 버튼을 누른 직후 잠깐 켜진다 — 시선을 여기로 데려온다.
  final bool highlight;

  const _AgeConfirmRow({
    required this.checked,
    required this.onChanged,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      checked: checked,
      label: '만 14세 이상입니다. 필수 확인 항목입니다.',
      child: InkWell(
        // 글자를 눌러도 켜지게 한다 — 작은 네모만 노리게 하지 않는다.
        onTap: enabled ? () => onChanged!(!checked) : null,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight ? AppColors.accent : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: checked,
                  onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
                  activeColor: AppColors.accent,
                  side: const BorderSide(
                    color: AppColors.borderFunctional,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
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
                      const TextSpan(text: '만 14세 이상입니다'),
                    ],
                  ),
                ),
              ),
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
  final VoidCallback? onBlockedTap;

  /// 지난번에 이 수단으로 로그인에 성공했으면 true — 「최근」 배지를 그린다.
  /// 설계: docs/planning/specs/login-recent-provider-2026-08-29.md §3.
  final bool isRecent;

  const _SnsButton({
    required this.provider,
    required this.isLoading,
    required this.isDisabled,
    required this.onPressed,
    this.onBlockedTap,
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
  Color? get _brandColor => switch (provider) {
    SnsAuthProvider.google || SnsAuthProvider.apple => null,
    SnsAuthProvider.kakao || SnsAuthProvider.naver => null,
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
    if (isDisabled && onBlockedTap != null) {
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

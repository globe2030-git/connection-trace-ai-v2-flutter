import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sns_auth_provider.dart';

/// 제공자가 배포하는 **공식 로그인 버튼 이미지**의 제원.
///
/// ## ⚠️ 왜 우리 버튼 모양을 쓰지 않나
///
/// 카카오 가이드가 이렇게 못박고 있다.
///
/// > - "심볼 없이 카카오 로그인 버튼을 구성할 수 없습니다"
/// > - "기능 아이콘을 카카오 로그인 버튼의 심볼로 사용할 수 없습니다"
/// > - "컨테이너 박스의 radius는 12 픽셀로 적용합니다"
///
/// 즉 **심볼이 반드시 있어야 하고, 그 심볼을 우리가 그리거나 다른 아이콘으로
/// 대신할 수 없다.** 심볼만 따로 주는 애셋도 없다 — 배포되는 것은 완성형
/// 버튼 이미지뿐이다. 그래서 **버튼 이미지를 통째로 쓴다.**
///
/// ⚠️ 이전 구현은 우리 버튼에 브랜드색만 입히고 *"○○로 계속하기"* 라고 적어
/// 뒀다. 카카오 기준으로 **심볼이 없고, radius 도 16이었고, 문구도 규정
/// 밖**이었다 — 셋이 한꺼번에 어긋나 있었다. 네이버는 사전 검수 항목이라
/// 이런 어긋남이 그대로 반려 사유가 된다.
class OfficialButtonArt {
  /// 버튼 이미지 경로.
  final String asset;

  /// ⚠️ **이미지 뒤에 까는 색.** 이미지의 실제 픽셀색과 **같아야** 한다 —
  /// 다르면 이음매가 보인다. 짐작하지 말고 PNG 를 읽어서 확인할 것.
  final Color background;

  /// ⚠️ 컨테이너 모서리. 이미지의 모서리는 투명하므로 **여기 값이 겉모양을
  /// 결정한다.** 이미지의 모서리보다 크게 잡으면 그 틈으로 배경이 비친다.
  final double radius;

  /// 이미지의 1x 높이. 이보다 크게 늘리지 않는다.
  final double artHeight;

  /// 화면 낭독기에 읽어 줄 이름. ⚠️ 이미지 **안의 글자는 낭독되지 않는다.**
  final String label;

  /// 로딩 표시 색. ⚠️ **바탕색마다 다르다** — 노란 바탕에 흰 동그라미를 그리면
  /// 거의 안 보여서, 이용자는 눌렀는데 아무 반응이 없다고 읽는다.
  final Color spinner;

  const OfficialButtonArt({
    required this.asset,
    required this.background,
    required this.radius,
    required this.artHeight,
    required this.label,
    required this.spinner,
  });

  /// 공식 버튼이 있는 제공자면 그 제원을, 없으면 `null`.
  static OfficialButtonArt? of(SnsAuthProvider provider) => switch (provider) {
    // 카카오: 완성형 **좁은 형(narrow)** 183×45.
    //
    // ⚠️ 처음에는 넓은 형(wide, 300×45)을 썼는데 **실기기에서 어색했다** —
    // 넓은 형은 심볼이 왼쪽 끝에 고정되고 글자만 가운데 오는 구조라, 우리처럼
    // 화면 폭을 꽉 채우는 버튼에 넣으면 심볼과 글자가 멀찍이 떨어져 보인다.
    // 좁은 형은 심볼과 글자가 붙어 있어 통째로 가운데 놓인다 — 네이버
    // center 형·구글 버튼과 같은 모양이 된다.
    //
    // 📌 둘 다 공식 애셋이므로 고르는 것은 규정 안이다. 넓히는 것도
    // 허용된다("컨테이너의 좌, 우 방향으로 동일하게 확장합니다").
    //
    // radius 12 는 가이드가 지정한 값이다 — 우리 화면의 다른 버튼(16)에
    // 맞추려고 바꾸면 규정 위반이다.
    SnsAuthProvider.kakao => const OfficialButtonArt(
      asset: 'assets/images/social/kakao_login_narrow.png',
      background: AppColors.channelKakao,
      radius: 12,
      artHeight: 45,
      label: '카카오 로그인',
      spinner: AppColors.brandKakaoLabel, // 노란 바탕 → 검정 85%
    ),
    // 네이버: Light·green·**narrow·H48** 210×48.
    //
    // ⚠️ center 형(368×56)을 쓰다 바꿨다. 카카오와 같은 이유이면서, 이유가
    // 하나 더 있다 — **폭이 넓어 좁은 화면에서 먼저 줄어든다.**
    //
    //   가용폭 288dp(360dp 폰) 기준
    //     center 368 → 78%로 줄어든다. 초록 버튼 안 글자만 작아지고
    //                  위아래에 초록 띠가 생긴다. 카카오(183)는 안 줄어드니
    //                  **두 버튼의 글자 크기가 눈에 띄게 달라진다**
    //     narrow 230 → 줄어들지 않는다
    //
    // 📌 비율을 지켜야 하므로(가이드) 폭이 모자라면 **높이까지 함께** 줄어든다.
    // 가로로만 늘이거나 줄일 수 없다.
    //
    // ⚠️ **H56(56 높이)이 아니라 H48을 쓴다.** 우리 버튼이 52 높이라, 56짜리를
    // 넣으면 **모든 화면에서 늘 7%씩 줄어든 채** 그려진다(52/56). 줄여도
    // 규정 위반은 아니지만, 애셋이 설계된 크기 그대로 또렷하게 나오는 편이
    // 낫다. 48은 52 안에 그대로 들어간다.
    //
    // 📌 이건 **테스트가 잡았다** — 눈으로는 7% 축소가 안 보였다.
    // ⚠️ 색은 **브랜드 초록(#03C75A)이 아니다.** 실측값은 #03A94D 다
    // (app_colors.dart 주석 참고). 모서리 6.5px 도 애셋에서 잰 값이라,
    // 컨테이너는 그보다 살짝 작은 6 으로 둬 틈이 안 생기게 한다.
    SnsAuthProvider.naver => const OfficialButtonArt(
      asset: 'assets/images/social/naver_login_narrow.png',
      background: AppColors.brandNaverButton,
      radius: 6,
      artHeight: 48,
      label: '네이버 로그인',
      spinner: Colors.white, // 초록 바탕 → 흰색
    ),
    SnsAuthProvider.google || SnsAuthProvider.apple || SnsAuthProvider.email =>
      null,
  };
}

/// 공식 버튼 이미지를 그대로 쓰는 로그인 버튼.
///
/// ## 화면 폭에 맞추는 방법 — ⚠️ 늘이지 않는다
///
/// 카카오 가이드는 넓히는 것을 허용하되 조건을 단다.
///
/// > "컨테이너의 좌, 우 방향으로 동일하게 확장합니다"
/// > "컨테이너의 크기에 따라 심볼과 레이블 크기 비율을 **유지하여** 확대합니다"
///
/// 이미지를 가로로만 늘이면 심볼과 글자가 함께 늘어나 규정을 어긴다. 그래서
/// **이미지는 늘이지 않고**, 같은 색 컨테이너를 넓힌 뒤 그 위에 원래 비율의
/// 이미지를 얹는다. 두 색이 같은 값이라 이음매가 보이지 않는다.
///
/// 📌 좁은 화면에서는 `BoxFit.scaleDown` 이 비율을 지킨 채 줄여 준다.
/// 늘리지는 않으므로 큰 화면에서 흐려지지 않는다.
class OfficialSocialButton extends StatelessWidget {
  final OfficialButtonArt art;
  final bool isLoading;
  final VoidCallback? onPressed;

  /// 🚨 **눌리지 않을 때 「왜 안 되는지」를 말할 자리**(2026-08-30, 추가 626).
  ///
  /// 카카오·네이버 버튼은 **공식 브랜드 이미지를 통째로** 쓴다. 그래서
  /// [onPressed] 가 `null` 이어도 **밝은 노랑·초록 그대로**이고, 이용자는
  /// 멀쩡해 보이는 버튼을 눌렀는데 **아무 일도 안 일어나는** 것을 본다.
  ///
  /// ⚠️ **이 파일이 이미 그 원칙을 알고 있었다** — 로그인 화면 주석에
  /// *"눌러도 안 되는 버튼을 두면 이용자는 고장으로 읽는다"* 가 있고, 애플
  /// 버튼은 그래서 **아예 안 그린다.** 그런데 이 자리에는 적용이 안 됐다.
  ///
  /// 📌 **막지 말고 말한다** — 오늘 광고 동의에서 고친 것과 같은 원칙이다.
  /// 눌러도 로그인은 시작되지 않되, **왜 안 되는지는 알려 준다.**
  final VoidCallback? onBlockedTap;

  const OfficialSocialButton({
    super.key,
    required this.art,
    required this.isLoading,
    required this.onPressed,
    this.onBlockedTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: art.background,
        borderRadius: BorderRadius.circular(art.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed ?? onBlockedTap,
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: art.spinner,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Image.asset(
                      art.asset,
                      height: art.artHeight,
                      fit: BoxFit.scaleDown,
                      semanticLabel: art.label,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}


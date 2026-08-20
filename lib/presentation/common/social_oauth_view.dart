import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/services/social_oauth.dart';
import '../../core/theme/app_colors.dart';

/// 카카오·네이버 인증 화면을 웹뷰로 띄우고 **인가 코드만** 들고 돌아온다.
///
/// ## 어떻게 도나
///
/// ```
/// 1. 제공자의 인증 주소를 연다
/// 2. 이용자가 로그인하고 동의한다
/// 3. 제공자가 우리 redirect_uri 로 되돌린다
/// 4. ⭐ 그 이동을 가로채서 code 를 꺼내고 창을 닫는다
/// ```
///
/// **4번이 핵심이다.** `redirect_uri`에 실제 페이지를 올려 둘 필요가 없다 —
/// 웹뷰가 그 주소로 *이동하려는 순간* 막고 주소창의 값만 읽는다. 그래서
/// 서버에 `/oauth/kakao` 같은 경로를 만들지 않아도 된다.
///
/// ## ⚠️ 여기서 토큰을 만들지 않는다
///
/// 손에 들어오는 것은 인가 코드뿐이고, 그것을 액세스 토큰으로 바꾸려면
/// `client_secret`이 필요하다 — 앱에 넣을 수 없는 값이라 서버가 한다.
/// 이 화면은 코드를 들고 돌아오기만 한다.
class SocialOauthView extends StatefulWidget {
  final SocialProvider provider;

  const SocialOauthView({super.key, required this.provider});

  /// 인증 화면을 띄우고 결과를 받는다.
  ///
  /// 이용자가 뒤로 가기로 닫으면 `null`이 아니라 **취소**로 돌아온다 —
  /// 부르는 쪽이 `null` 검사를 잊어 조용히 아무 일도 안 일어나는 것을 막는다.
  static Future<OauthOutcome> show(
    BuildContext context,
    SocialProvider provider,
  ) async {
    final result = await Navigator.push<OauthOutcome>(
      context,
      MaterialPageRoute(builder: (_) => SocialOauthView(provider: provider)),
    );
    return result ?? const OauthFailed('로그인을 취소했어요.');
  }

  @override
  State<SocialOauthView> createState() => _SocialOauthViewState();
}

class _SocialOauthViewState extends State<SocialOauthView> {
  late final WebViewController _controller;
  late final String _state;
  bool _isLoading = true;

  /// 결과를 **한 번만** 돌려주기 위한 빗장.
  ///
  /// ⚠️ 없으면 리다이렉트를 가로챈 뒤에도 웹뷰가 다른 이동을 일으켜
  /// `Navigator.pop`이 두 번 불릴 수 있다. 그러면 그 뒤 화면까지 닫힌다.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _state = generateState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 카카오·네이버 인증 화면은 흰 배경이다. 기본 투명으로 두면 로딩 중에
      // 뒤 화면이 비쳐 깜빡이는 것처럼 보인다.
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;

            if (isRedirect(uri, widget.provider)) {
              _finish(readRedirect(uri, expectedState: _state));
              // ⚠️ 실제로 이동시키면 안 된다. 그 주소에는 페이지가 없어서
              // 오류 화면이 잠깐 스치고, 이용자에게는 고장으로 보인다.
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            // 리다이렉트를 막은 뒤에도 오류가 한 번 들어오는 기기가 있다.
            // 이미 끝났으면 무시한다 — 성공을 실패로 뒤집으면 안 된다.
            if (_finished) return;
            debugPrint('[SocialOauth] 로드 오류: ${error.errorCode}');
          },
        ),
      );

    _controller.loadRequest(
      authorizeUrl(provider: widget.provider, state: _state),
    );
  }

  void _finish(OauthOutcome outcome) {
    if (_finished || !mounted) return;
    _finished = true;
    Navigator.pop(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 뒤로 가기는 막지 않는다. 다만 결과를 "취소"로 채워 돌려준다.
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && result == null) _finished = true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: AppColors.cardSurface,
          foregroundColor: Colors.white,
          title: Text('${widget.provider.displayName} 로그인'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: '닫기',
            onPressed: () => _finish(const OauthFailed('로그인을 취소했어요.')),
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';

/// 앱에서 보여줄 법적 고지 문서.
///
/// 문서 본문은 `docs/legal/`에 HTML로 두고 Firebase Hosting에 올려 둔다.
/// 앱에 문안을 복사해 두지 않는 이유: 두 벌을 관리하면 개정할 때 어긋나고,
/// **문서 불일치 자체가 법적 리스크**가 되기 때문이다. 웹에 올려 두면 앱을
/// 업데이트하지 않아도 개정 내용이 곧바로 반영된다.
enum LegalDocument {
  /// 약관·정책 목록 페이지. **사업자 정보 표(전자상거래법 제10조)가 여기
  /// 있다** — 앱에 같은 값을 복사해 두지 않기 위해 이 페이지로 보낸다
  /// (2026-08-10). 예전에는 설정에 사업자 정보를 하드코딩한 다이얼로그가
  /// 있었는데, 주소나 대표자가 바뀌면 앱까지 고쳐 배포해야 했다.
  // `index`는 enum이 이미 쓰는 이름이라(순번 getter) 그대로 못 쓴다.
  legalIndex('법적 고지', 'index'),
  terms('서비스 이용약관', 'terms-of-service'),
  privacy('개인정보처리방침', 'privacy-policy'),
  permissions('앱 접근권한 안내', 'app-permissions'),
  accountDeletion('계정 및 데이터 삭제 안내', 'account-deletion');

  const LegalDocument(this.title, this.slug);

  final String title;
  final String slug;

  static const String _baseUrl = 'https://connection-sense.web.app';

  Uri get uri => Uri.parse('$_baseUrl/$slug');
}

Future<void> showLegalDocument(BuildContext context, LegalDocument doc) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => LegalDocumentView(document: doc)));
}

/// 법적 고지 문서를 앱 안 웹뷰로 보여준다.
///
/// 웹뷰 구성은 [AddressSearchView]와 같은 패턴을 따른다. 네트워크가 없거나
/// 로딩에 실패하면 빈 화면을 보여주는 대신 **실패했다는 사실과 브라우저로
/// 여는 대안**을 준다 — 법적 고지는 "안 보이면 그만"인 화면이 아니라 이용자가
/// 반드시 확인할 수 있어야 하는 화면이기 때문이다.
class LegalDocumentView extends StatefulWidget {
  final LegalDocument document;

  const LegalDocumentView({super.key, required this.document});

  @override
  State<LegalDocumentView> createState() => _LegalDocumentViewState();
}

class _LegalDocumentViewState extends State<LegalDocumentView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(AppColors.bgBase)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            // 하위 리소스(css 등) 실패까지 전체 실패로 처리하면 본문이 멀쩡히
            // 떠 있는데도 오류 화면이 뜬다. 문서 본문 요청이 실패한 경우만
            // 오류로 본다.
            if (error.isForMainFrame == false) return;
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      )
      ..loadRequest(widget.document.uri);
  }

  Future<void> _openInBrowser() async {
    final uri = widget.document.uri;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: Text(widget.document.title),
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '브라우저로 열기',
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: _hasError
          ? _ErrorState(onRetryInBrowser: _openInBrowser)
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
              ],
            ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetryInBrowser;

  const _ErrorState({required this.onRetryInBrowser});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_off_outlined,
              size: 40,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            const Text(
              '문서를 불러오지 못했습니다',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetryInBrowser,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('브라우저로 열기'),
            ),
          ],
        ),
      ),
    );
  }
}

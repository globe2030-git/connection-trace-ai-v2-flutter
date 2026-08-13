import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';

/// 도로명(또는 지번) 주소와, 다음 우편번호 서비스가 함께 주는 건물명(있는
/// 경우)을 같이 담는다 — 아파트/오피스텔처럼 건물명이 있는 주소는 상세주소
/// 칸에 자동으로 채워 넣을 수 있게 하기 위함.
class AddressSearchResult {
  /// 목록에 보인 그대로의 주소 문장(도로명/지번 + 참고항목).
  ///
  /// 예전에는 도로명주소만 넘겨받아 "경기 성남시 분당구 판교역로 235 (삼평동,
  /// 에이치스퀘어)"가 "경기 성남시 분당구 판교역로 235"로 짧아졌고, 사용자
  /// 눈에는 주소가 잘린 것처럼 보였다(backlog 추가 83).
  final String address;
  final String? buildingName;
  final String? postalCode;

  /// 같은 위치의 도로명 주소와 지번 주소. 표시·저장에는 쓰지 않고 **좌표 조회
  /// 실패 시 재시도**에만 쓴다([geocodeFallback] 참고).
  ///
  /// 왜 필요한가: OS 지오코더가 도로명 주소로는 좌표를 못 찾는데 지번으로는
  /// 찾는 경우가 실사용에서 확인됐고, **그 반대도 있을 수 있다**(2026-08-14).
  /// 좌표가 없으면 그 인맥은 주변 지도에 아예 안 뜬다. 우편번호 서비스는 두
  /// 표기를 함께 주는데 예전에는 둘 다 버리고 표시용 문장만 넘겼다.
  final String? roadAddress;
  final String? jibunAddress;

  /// 좌표 조회에 재시도로 쓸 **표시하지 않은 쪽** 주소. 사용자가 도로명을
  /// 골랐으면 지번을, 지번을 골랐으면 도로명을 돌려준다. 어느 쪽을 골랐는지에
  /// 상관없이 한 번 더 시도할 수 있어야 해서 방향을 고정하지 않았다.
  String? get geocodeFallback {
    final shown = address.trim();
    for (final candidate in [roadAddress, jibunAddress]) {
      final c = (candidate ?? '').trim();
      if (c.isNotEmpty && !shown.contains(c) && c != shown) return c;
    }
    return null;
  }

  const AddressSearchResult({
    required this.address,
    this.buildingName,
    this.roadAddress,
    this.jibunAddress,
    this.postalCode,
  });
}

/// 웹뷰가 스스로 열 수 있는 주소인지 판별한다.
///
/// 웹뷰는 `http`/`https`와 앱에 포함된 `file` 자산만 열 수 있다. 그 밖의
/// 스킴(`kakaomap://`, `intent://`, `market://` 등)으로 이동을 시도하면
/// `ERR_UNKNOWN_URL_SCHEME` 오류 페이지가 떠서 진행 중이던 화면을 덮어쓴다.
bool isWebViewNavigable(String url) {
  final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
  return scheme == null ||
      scheme.isEmpty ||
      scheme == 'http' ||
      scheme == 'https' ||
      scheme == 'file' ||
      scheme == 'about' ||
      scheme == 'data';
}

/// 다음(카카오) 우편번호 서비스를 웹뷰로 띄워 실제 도로명주소를 검색·선택하게
/// 한다(API 키가 필요 없는 무료 공개 서비스). 주소를 고르면 [AddressSearchResult]를
/// 반환하며 팝업을 닫는다. 검색 없이 닫으면 null을 반환한다.
class AddressSearchView extends StatefulWidget {
  // OCR 스캔 결과나 기존 입력값처럼 "이미 갖고 있던 주소 텍스트"를 넘겨
  // 받으면, 사용자가 다음 우편번호 검색창에 처음부터 다시 타이핑하지
  // 않아도 되게 돕는다. 다음 우편번호 위젯(postcode.v2.js)은 검색어를
  // 미리 채워 넣는 공식 파라미터를 제공하지 않아서(iframe이 다른
  // origin이라 직접 DOM 조작도 불가), 화면 상단에 원문을 보여주고
  // 자동으로 클립보드에 복사해 "검색창에 붙여넣기만 하면" 되게 한다.
  final String? initialQuery;

  const AddressSearchView({super.key, this.initialQuery});

  @override
  State<AddressSearchView> createState() => _AddressSearchViewState();
}

class _AddressSearchViewState extends State<AddressSearchView> {
  /// 다음 우편번호 위젯이 부모 창으로 결과를 넘길 수 있도록 https origin을
  /// 부여하기 위한 기준 주소. 이 주소로 요청을 보내지는 않는다.
  static const String _baseUrl = 'https://connection-sense.web.app/';

  late final WebViewController _controller;
  bool _isLoading = true;
  /// 초기 검색어로 자동 검색했음을 알리는 안내를 띄울지.
  bool _showAutoSearchNotice = false;

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery?.trim();
    // 검색어는 HTML 로드 시 `q` 옵션으로 직접 넣는다(_withInitialQuery).
    // 예전에는 클립보드에 복사해 두고 사용자가 붙여넣게 했는데, 웹뷰 안에서는
    // 붙여넣기가 잘 되지 않아 사실상 쓸 수 없었다(사용자 제보, 2026-08-12).
    _showAutoSearchNotice = query != null && query.isNotEmpty;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'FlutterAddressChannel',
        onMessageReceived: (message) {
          if (message.message == 'CLOSED') {
            Navigator.pop(context);
            return;
          }
          try {
            final data = jsonDecode(message.message) as Map<String, dynamic>;
            final fullAddress = data['fullAddress'] as String?;
            final roadAddress = data['roadAddress'] as String?;
            final jibunAddress = data['jibunAddress'] as String?;
            final buildingName = data['buildingName'] as String?;
            final zonecode = data['zonecode'] as String?;
            // 목록에 보인 문장을 그대로 쓴다. 예전 저장분과의 호환을 위해
            // fullAddress가 없으면 기존 방식으로 물러선다.
            final address =
                (fullAddress != null && fullAddress.trim().isNotEmpty)
                ? fullAddress
                : (roadAddress != null && roadAddress.trim().isNotEmpty)
                      ? roadAddress
                      : jibunAddress;
            if (address == null || address.trim().isEmpty) {
              debugPrint('[AddressSearch] 주소가 비어 결과 없이 닫음');
              Navigator.pop(context);
              return;
            }
            Navigator.pop(
              context,
              AddressSearchResult(
                address: address,
                roadAddress:
                    (roadAddress != null && roadAddress.trim().isNotEmpty)
                    ? roadAddress.trim()
                    : null,
                jibunAddress:
                    (jibunAddress != null && jibunAddress.trim().isNotEmpty)
                    ? jibunAddress.trim()
                    : null,
                buildingName:
                    (buildingName != null && buildingName.trim().isNotEmpty)
                    ? buildingName.trim()
                    : null,
                postalCode: (zonecode != null && zonecode.trim().isNotEmpty)
                    ? zonecode.trim()
                    : null,
              ),
            );
          } catch (e) {
            debugPrint('[AddressSearch] 파싱 실패, 결과 없이 닫음: $e');
            Navigator.pop(context);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            if (isWebViewNavigable(request.url)) {
              return NavigationDecision.navigate;
            }
            // 다음 우편번호 위젯에는 "카카오맵에서 찾기" 같은 앱 스킴 링크가
            // 섞여 있다(kakaomap://search?q=...). 웹뷰는 http(s)가 아닌 스킴을
            // 처리하지 못해 ERR_UNKNOWN_URL_SCHEME 오류 페이지로 넘어가고,
            // 그 페이지가 웹뷰를 덮어써서 주소 선택 흐름 자체가 끊긴다
            // (실기기에서 확인 — backlog 추가 81).
            //
            // 그래서 웹뷰 안에서는 막고, 해당 앱이 깔려 있으면 외부로 넘긴다.
            // 깔려 있지 않으면 아무 일도 일어나지 않는다 — 주소 검색 화면은
            // 그대로 유지되므로 사용자는 계속 주소를 고를 수 있다.
            debugPrint('[AddressSearch] 앱 스킴 차단: ${request.url}');
            _launchExternalApp(request.url);
            return NavigationDecision.prevent;
          },
        ),
      )
      ;
    _loadPage();
  }

  /// 페이지를 `file://`이 아니라 **https origin**을 가진 상태로 띄운다.
  ///
  /// 다음 우편번호 위젯은 내부 iframe에서 부모 창으로 결과를 넘기는데,
  /// `loadFlutterAsset`으로 띄우면 origin이 `file://`(= 불투명 origin)이라
  /// 이 전달이 막힌다. 그러면 주소를 선택해도 `oncomplete`가 호출되지 않고
  /// 위젯이 대체 경로(카카오맵 앱 열기, `kakaomap://search?q=...`)로 빠져
  /// **검색은 되는데 선택만 안 되는** 상태가 된다(실기기에서 확인 —
  /// backlog 추가 81).
  ///
  /// HTML 자체는 앱 안에 그대로 두고 `baseUrl`만 https로 지정한다 — 문서를
  /// 서버에서 내려받지 않으므로 네트워크 왕복이 늘지 않는다.
  /// HTML 안에서 초기 검색어가 들어갈 자리. 이 문자열을 실제 검색어로 바꿔
  /// 넣는다.
  Future<void> _loadPage() async {
    try {
      final html = await rootBundle.loadString('assets/web/address_search.html');
      await _controller.loadHtmlString(
        injectInitialQuery(html, widget.initialQuery),
        baseUrl: _baseUrl,
      );
    } catch (e) {
      debugPrint('[AddressSearch] 페이지 로드 실패: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _launchExternalApp(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // 외부 앱 실행 실패는 무시한다 — 주소 검색을 계속할 수 있으면 된다.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.cardSurface,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.search, size: 20),
            SizedBox(width: 8),
            Text('도로명주소 검색'),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          if (_showAutoSearchNotice) _buildAutoSearchBanner(),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(color: AppColors.accentText),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoSearchBanner() {
    return Material(
      color: AppColors.accentText.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () => setState(() => _showAutoSearchNotice = false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.search, size: 16, color: AppColors.accentText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '\'${widget.initialQuery!.trim()}\'(으)로 검색했어요 — 결과가 없으면 검색어를 줄여 보세요',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.accentText,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.close, size: 16, color: AppColors.accentText),
            ],
          ),
        ),
      ),
    );
  }
}

/// 주소 검색 HTML의 자리표시자를 실제 검색어로 바꾼다.
///
/// 다음 우편번호 서비스는 `embed(el, {q: '검색어'})`로 초기 검색을 지원한다.
/// 예전에는 이 통로를 몰라 클립보드에 복사해 두고 사용자가 붙여넣게 했는데,
/// 웹뷰 안에서는 붙여넣기가 잘 되지 않아 사실상 쓸 수 없었다(사용자 제보,
/// 2026-08-12: 안드로이드·아이폰 모두).
///
/// ⚠️ 검색어는 사용자가 입력하거나 OCR이 읽은 값이라 따옴표·역슬래시·줄바꿈이
/// 섞일 수 있다. 그대로 끼워 넣으면 자바스크립트 문자열이 깨져 **검색 화면
/// 자체가 뜨지 않는다** — `jsonEncode`로 감싸 안전한 리터럴로 만든다.
/// 자리표시자를 감싼 따옴표까지 함께 바꾸므로 HTML 쪽에 따옴표를 남기지 않는다.
@visibleForTesting
String injectInitialQuery(String html, String? query) {
  return html.replaceFirst(
    "'$kInitialQueryToken'",
    jsonEncode(query?.trim() ?? ''),
  );
}

/// HTML 안에서 초기 검색어가 들어갈 자리.
const String kInitialQueryToken = '__INITIAL_QUERY__';

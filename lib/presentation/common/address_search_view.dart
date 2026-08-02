import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';

/// 다음(카카오) 우편번호 서비스를 웹뷰로 띄워 실제 도로명주소를 검색·선택하게
/// 한다(API 키가 필요 없는 무료 공개 서비스). 주소를 고르면 도로명주소
/// 문자열을 반환하며 팝업을 닫는다. 검색 없이 닫으면 null을 반환한다.
class AddressSearchView extends StatefulWidget {
  const AddressSearchView({super.key});

  @override
  State<AddressSearchView> createState() => _AddressSearchViewState();
}

class _AddressSearchViewState extends State<AddressSearchView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
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
            final roadAddress = data['roadAddress'] as String?;
            final jibunAddress = data['jibunAddress'] as String?;
            final result = (roadAddress != null && roadAddress.trim().isNotEmpty)
                ? roadAddress
                : jibunAddress;
            Navigator.pop(context, result);
          } catch (_) {
            Navigator.pop(context);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadFlutterAsset('assets/web/address_search.html');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.cardDark,
        foregroundColor: Colors.white,
        title: const Text('🔍 도로명주소 검색'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: AppColors.accentText)),
        ],
      ),
    );
  }
}

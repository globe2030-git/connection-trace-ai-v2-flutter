import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';

/// 도로명(또는 지번) 주소와, 다음 우편번호 서비스가 함께 주는 건물명(있는
/// 경우)을 같이 담는다 — 아파트/오피스텔처럼 건물명이 있는 주소는 상세주소
/// 칸에 자동으로 채워 넣을 수 있게 하기 위함.
class AddressSearchResult {
  final String address;
  final String? buildingName;
  final String? postalCode;

  const AddressSearchResult({
    required this.address,
    this.buildingName,
    this.postalCode,
  });
}

/// 다음(카카오) 우편번호 서비스를 웹뷰로 띄워 실제 도로명주소를 검색·선택하게
/// 한다(API 키가 필요 없는 무료 공개 서비스). 주소를 고르면 [AddressSearchResult]를
/// 반환하며 팝업을 닫는다. 검색 없이 닫으면 null을 반환한다.
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
            final buildingName = data['buildingName'] as String?;
            final zonecode = data['zonecode'] as String?;
            final address =
                (roadAddress != null && roadAddress.trim().isNotEmpty)
                ? roadAddress
                : jibunAddress;
            if (address == null || address.trim().isEmpty) {
              Navigator.pop(context);
              return;
            }
            Navigator.pop(
              context,
              AddressSearchResult(
                address: address,
                buildingName:
                    (buildingName != null && buildingName.trim().isNotEmpty)
                    ? buildingName.trim()
                    : null,
                postalCode: (zonecode != null && zonecode.trim().isNotEmpty)
                    ? zonecode.trim()
                    : null,
              ),
            );
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
            const Center(
              child: CircularProgressIndicator(color: AppColors.accentText),
            ),
        ],
      ),
    );
  }
}

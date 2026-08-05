import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/presentation/common/address_search_view.dart';

/// 다음 우편번호 위젯에는 "카카오맵에서 찾기" 같은 앱 스킴 링크가 섞여 있다.
/// 웹뷰가 이를 열려고 하면 ERR_UNKNOWN_URL_SCHEME 오류 페이지가 화면을
/// 덮어써서 주소 선택 흐름이 끊긴다(backlog 추가 80, 실기기에서 확인).
void main() {
  group('isWebViewNavigable', () {
    test('웹뷰가 직접 열 수 있는 주소는 통과시킨다', () {
      const allowed = [
        'https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js',
        'http://example.com/page',
        'file:///android_asset/flutter_assets/assets/web/address_search.html',
        'about:blank',
        'data:text/html,<b>hi</b>',
        '/relative/path',
      ];
      for (final url in allowed) {
        expect(isWebViewNavigable(url), isTrue, reason: url);
      }
    });

    test('앱 스킴은 막는다', () {
      const blocked = [
        'kakaomap://search?q=%EA%B2%BD%EA%B8%B0',
        'KAKAOMAP://search?q=x',
        'intent://scan/#Intent;scheme=zxing;end',
        'market://details?id=net.daum.android.map',
        'tel:010-0000-0000',
        'mailto:someone@example.com',
      ];
      for (final url in blocked) {
        expect(isWebViewNavigable(url), isFalse, reason: url);
      }
    });
  });
}

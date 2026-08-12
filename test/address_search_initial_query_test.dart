import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/presentation/common/address_search_view.dart';

/// 주소 검색 초기 검색어 주입 테스트(사용자 제보, 2026-08-12).
///
/// 예전에는 입력칸의 주소를 **클립보드에 복사**해 두고 사용자가 웹뷰 검색창에
/// 직접 붙여넣게 했는데, 웹뷰 안에서는 붙여넣기가 잘 되지 않아 안드로이드·
/// 아이폰 모두에서 사실상 쓸 수 없었다. 이제 다음 우편번호 서비스의 `q` 옵션에
/// 검색어를 직접 넣는다.
///
/// 주입이 잘못되면 자바스크립트 문자열이 깨져 **검색 화면 자체가 뜨지 않으므로**,
/// 따옴표·역슬래시가 섞인 값까지 안전한지 여기서 고정한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('⭐ 실제 HTML 자산에 자리표시자가 있고, 검색어가 주입된다', () async {
    final html = await rootBundle.loadString('assets/web/address_search.html');
    expect(
      html.contains("'$kInitialQueryToken'"),
      isTrue,
      reason: 'HTML에서 자리표시자를 지우면 주입이 조용히 실패한다',
    );

    final injected = injectInitialQuery(html, '서울특별시 강남구 테헤란로 123');
    expect(injected.contains(kInitialQueryToken), isFalse);
    expect(injected.contains('서울특별시 강남구 테헤란로 123'), isTrue);
  });

  test('검색어가 없으면 빈 문자열이 들어간다(자동 검색 안 함)', () {
    const html = "var INITIAL_QUERY = '$kInitialQueryToken';";
    expect(injectInitialQuery(html, null), 'var INITIAL_QUERY = "";');
    expect(injectInitialQuery(html, '   '), 'var INITIAL_QUERY = "";');
  });

  test('앞뒤 공백은 없애고 넣는다', () {
    const html = "var INITIAL_QUERY = '$kInitialQueryToken';";
    expect(injectInitialQuery(html, '  강남구  '), 'var INITIAL_QUERY = "강남구";');
  });

  test('⭐ 따옴표·역슬래시·줄바꿈이 섞여도 자바스크립트가 깨지지 않는다', () {
    const html = "var INITIAL_QUERY = '$kInitialQueryToken';";
    const nasty = '''서울 "강남" \\ 테헤란로
123''';

    final out = injectInitialQuery(html, nasty);

    // jsonEncode 결과와 정확히 같아야 한다 — 그래야 JS 문자열로 안전하다.
    expect(out, 'var INITIAL_QUERY = ${jsonEncode(nasty.trim())};');
    // 원문 따옴표가 이스케이프되지 않은 채 남아 있으면 안 된다.
    expect(out.contains('"강남"'), isFalse);
    // 줄바꿈이 그대로 들어가면 문법 오류가 난다.
    expect(out.split('\n').length, 1);
  });
}

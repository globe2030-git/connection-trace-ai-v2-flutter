// 카카오·네이버 로그인의 주소 만들기·되돌아온 주소 읽기(추가 362).
//
// ## 이 테스트가 막는 것
//
// **① 남의 주소로 코드가 새어 나가는 것.** 되돌아오는 주소를 `startsWith`로
// 느슨하게 보면 `connection-sense.web.app.evil.com` 같은 주소가 통과한다.
// 통과하면 **인가 코드가 공격자에게 넘어간다.**
//
// **② 다른 곳에서 시작된 응답을 받아들이는 것(CSRF).** `state`를 대조하지
// 않으면 남이 만든 인증 결과로 로그인이 성립한다.
//
// **③ 이용자가 "취소"를 눌렀을 때 영문 오류가 그대로 뜨는 것.**
import 'dart:math';

import 'package:connection_trace_ai_flutter/core/services/social_oauth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('되돌아오는 주소', () {
    test('제공자마다 경로가 다르다', () {
      expect(
        redirectUriFor(SocialProvider.kakao),
        'https://connection-sense.web.app/oauth/kakao',
      );
      expect(
        redirectUriFor(SocialProvider.naver),
        'https://connection-sense.web.app/oauth/naver',
      );
    });

    test('우리 주소는 알아본다', () {
      expect(
        isRedirect(
          Uri.parse('https://connection-sense.web.app/oauth/kakao?code=x'),
          SocialProvider.kakao,
        ),
        isTrue,
      );
    });

    group('⭐ 남의 주소를 우리 것으로 읽으면 인가 코드가 새어 나간다', () {
      test('호스트 뒤에 붙인 주소를 거른다', () {
        expect(
          isRedirect(
            Uri.parse('https://connection-sense.web.app.evil.com/oauth/kakao'),
            SocialProvider.kakao,
          ),
          isFalse,
        );
      });

      test('앞에 붙인 주소도 거른다', () {
        expect(
          isRedirect(
            Uri.parse('https://evil.com/connection-sense.web.app/oauth/kakao'),
            SocialProvider.kakao,
          ),
          isFalse,
        );
      });

      test('http는 거른다 — 평문으로 코드가 나간다', () {
        expect(
          isRedirect(
            Uri.parse('http://connection-sense.web.app/oauth/kakao'),
            SocialProvider.kakao,
          ),
          isFalse,
        );
      });

      test('제공자가 다르면 거른다', () {
        expect(
          isRedirect(
            Uri.parse('https://connection-sense.web.app/oauth/naver'),
            SocialProvider.kakao,
          ),
          isFalse,
        );
      });

      test('경로가 더 깊으면 거른다', () {
        expect(
          isRedirect(
            Uri.parse('https://connection-sense.web.app/oauth/kakao/extra'),
            SocialProvider.kakao,
          ),
          isFalse,
        );
      });
    });
  });

  group('state — 다른 곳에서 시작된 응답을 막는다', () {
    test('충분히 길고 매번 다르다', () {
      final a = generateState();
      final b = generateState();
      expect(a.length, 32);
      expect(a, isNot(b));
    });

    test('영숫자만 쓴다 — URL에서 깨지지 않게', () {
      expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(generateState()), isTrue);
    });

    test('⭐ state가 다르면 코드를 받아들이지 않는다', () {
      final r = readRedirect(
        Uri.parse('https://connection-sense.web.app/oauth/kakao?code=c&state=남의것'),
        expectedState: '내것',
      );
      expect(r, isA<OauthFailed>());
    });

    test('state가 아예 없어도 거부한다', () {
      final r = readRedirect(
        Uri.parse('https://connection-sense.web.app/oauth/kakao?code=c'),
        expectedState: 'abc',
      );
      expect(r, isA<OauthFailed>());
    });
  });

  group('되돌아온 주소 읽기', () {
    test('정상이면 코드를 준다', () {
      final r = readRedirect(
        Uri.parse('https://connection-sense.web.app/oauth/kakao?code=c1&state=s1'),
        expectedState: 's1',
      );
      expect(r, isA<OauthCode>());
      expect((r as OauthCode).code, 'c1');
    });

    test('코드가 비어 있으면 실패로 본다', () {
      final r = readRedirect(
        Uri.parse('https://connection-sense.web.app/oauth/kakao?code=&state=s1'),
        expectedState: 's1',
      );
      expect(r, isA<OauthFailed>());
    });

    group('⭐ 이용자가 취소했을 때 영문 오류를 띄우지 않는다', () {
      test('access_denied 는 "취소"로 읽는다', () {
        final r = readRedirect(
          Uri.parse(
            'https://connection-sense.web.app/oauth/kakao'
            '?error=access_denied&error_description=User+denied&state=s1',
          ),
          expectedState: 's1',
        );
        expect((r as OauthFailed).message, contains('취소'));
      });

      test('그 밖의 오류는 다시 시도하라고 안내한다', () {
        final r = readRedirect(
          Uri.parse(
            'https://connection-sense.web.app/oauth/naver'
            '?error=invalid_request&state=s1',
          ),
          expectedState: 's1',
        );
        final f = r as OauthFailed;
        expect(f.message, contains('다시'));
        expect(f.message, isNot(contains('invalid_request')));
      });

      test('⚠️ 오류가 있으면 state 대조보다 먼저 처리한다', () {
        // 취소하면 제공자가 state를 안 돌려주는 경우가 있다. 그때 "응답이
        // 올바르지 않다"고 뜨면 이용자는 고장으로 읽는다.
        final r = readRedirect(
          Uri.parse(
            'https://connection-sense.web.app/oauth/kakao?error=access_denied',
          ),
          expectedState: 's1',
        );
        expect((r as OauthFailed).message, contains('취소'));
      });
    });
  });

  group('인증 화면 주소', () {
    test('카카오는 kauth.kakao.com 으로 간다', () {
      final u = authorizeUrl(provider: SocialProvider.kakao, state: 'st');
      expect(u.host, 'kauth.kakao.com');
      expect(u.queryParameters['response_type'], 'code');
      expect(u.queryParameters['state'], 'st');
      expect(
        u.queryParameters['redirect_uri'],
        'https://connection-sense.web.app/oauth/kakao',
      );
    });

    test('네이버는 nid.naver.com 으로 간다', () {
      final u = authorizeUrl(provider: SocialProvider.naver, state: 'st');
      expect(u.host, 'nid.naver.com');
      expect(u.path, '/oauth2.0/authorize');
    });

    test('📌 scope를 넣지 않는다 — 동의항목은 콘솔 한 곳에서만 정한다', () {
      final u = authorizeUrl(provider: SocialProvider.kakao, state: 'st');
      expect(u.queryParameters.containsKey('scope'), isFalse);
    });

    test('state가 URL 인코딩된다', () {
      final u = authorizeUrl(provider: SocialProvider.naver, state: 'a b&c');
      expect(u.toString(), isNot(contains('a b&c')));
      expect(u.queryParameters['state'], 'a b&c');
    });
  });

  group('설정 여부', () {
    test('키를 안 넣고 빌드하면 설정 안 된 것으로 본다', () {
      // --dart-define 없이 도는 테스트 환경에서는 둘 다 비어 있다.
      // 화면은 이 값을 보고 버튼을 숨긴다 — 눌러도 안 되는 버튼을 두지 않는다.
      expect(isConfigured(SocialProvider.kakao), kKakaoRestKey.isNotEmpty);
      expect(isConfigured(SocialProvider.naver), kNaverClientId.isNotEmpty);
    });
  });

  group('서버와 맞춘 이름', () {
    test('⚠️ 바꾸면 서버도 함께 바꿔야 한다', () {
      expect(SocialProvider.kakao.wireName, 'kakao');
      expect(SocialProvider.naver.wireName, 'naver');
    });

    test('화면에 보이는 이름은 한글이다', () {
      expect(SocialProvider.kakao.displayName, '카카오');
      expect(SocialProvider.naver.displayName, '네이버');
    });
  });

  test('generateState 는 주입한 난수원을 쓴다 — 재현 가능한 테스트를 위해', () {
    final a = generateState(Random(1));
    final b = generateState(Random(1));
    expect(a, b);
  });
}

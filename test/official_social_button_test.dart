import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/data/models/sns_auth_provider.dart';
import 'package:connection_trace_ai_flutter/presentation/features/auth/widgets/official_social_button.dart';

/// ⚠️ **좁은 화면에서 공식 버튼 이미지가 줄어들지 않는지**를 못박는다.
///
/// 공식 버튼은 이미지라서 **비율을 지켜야 한다**(가이드 규정 — 가로로만
/// 늘이거나 줄일 수 없다). 그래서 폭이 모자라면 **높이까지 함께 줄어든다.**
/// 그러면 브랜드색 버튼은 52 높이 그대로인데 안의 글자만 작아지고 위아래에
/// 색 띠가 생긴다.
///
/// 📌 **눈으로는 잘 안 잡히는 자리다.** 확인에 쓴 폴드 커버 화면은 411dp 라
/// 오히려 넓어서, 흔한 360dp 폰에서만 드러난다. 그래서 자동으로 잰다.
///
/// ⚠️ 이 테스트는 **계산이 아니라 실제로 그려서 잰다** — `BoxFit.scaleDown`
/// 이 정말 어떻게 동작하는지를 본다. 같은 계산을 테스트에 한 벌 더 쓰면
/// 구현이 틀렸을 때 테스트도 똑같이 틀린다.
void main() {
  /// 화면 폭 [width] 에서 버튼을 그리고 **이미지가 실제로 몇 dp로 그려졌는지**
  /// 돌려준다. 로그인 화면과 같은 좌우 여백(28)을 준다.
  Future<Size> renderedArt(WidgetTester tester, SnsAuthProvider provider, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final art = OfficialButtonArt.of(provider)!;
    final widget = MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              OfficialSocialButton(art: art, isLoading: false, onPressed: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(widget);

    // ⚠️ **이미지를 실제로 불러와야 폭이 잰다.** 안 불러오면 높이는 우리가 준
    // 값이 들어가지만 폭은 0으로 나온다 — 처음에 그 0을 보고 "폭이 0이다"라고
    // 읽을 뻔했다. 폭은 이미지의 원래 비율에서 나오므로 디코딩이 끝나야 한다.
    await tester.runAsync(() async {
      await precacheImage(AssetImage(art.asset), tester.element(find.byType(Image)));
    });
    await tester.pumpWidget(widget);
    await tester.pump();

    return tester.getSize(find.byType(Image));
  }

  group('⚠️ 좁은 화면에서도 공식 버튼이 줄어들지 않는다', () {
    // 흔한 안드로이드 폭. ⚠️ 폴드 커버(411)보다 좁아서 여기서만 드러난다.
    for (final width in [360.0, 411.0, 480.0]) {
      testWidgets('카카오 — ${width.toInt()}dp 에서 원래 크기 그대로', (tester) async {
        final size = await renderedArt(tester, SnsAuthProvider.kakao, width);
        expect(size.height, 45, reason: '줄어들면 글자가 작아지고 위아래에 노란 띠가 생긴다');
        expect(size.width, 183);
      });

      testWidgets('네이버 — ${width.toInt()}dp 에서 원래 크기 그대로', (tester) async {
        final size = await renderedArt(tester, SnsAuthProvider.naver, width);
        expect(size.height, 48, reason: '줄어들면 카카오와 글자 크기가 달라 보인다');
        expect(size.width, 210);
      });
    }

    testWidgets('⚠️ 정말 좁은 화면(260dp)에서는 자리가 모자란다 — 그때만 줄어든다', (tester) async {
      // 여유폭 = 화면폭 − 56(화면 여백) − 16(버튼 안 여백).
      // 210 짜리가 안 들어가려면 282dp 아래로 내려가야 한다 — 실제 폰에는
      // 없는 폭이다. 그래도 한 번은 밟아 봐야 "안 줄어든다"가 우연이 아니다.
      final size = await renderedArt(tester, SnsAuthProvider.naver, 260);
      expect(size.width, lessThan(210), reason: '이 폭에서는 자리가 모자라야 한다');

      // ⚠️ **여기서 재는 것은 상자이지 그려진 그림이 아니다.** 자리가 모자라면
      // 상자는 폭만 잘리고 높이는 48 그대로 남는다. 그 안에서 BoxFit.scaleDown
      // 이 그림을 비율대로 줄여 그린다 — 그 결과는 이 방법으로 못 잰다.
      //
      // 📌 처음에는 높이가 줄어들 것으로 보고 `height < 48` 을 기대했다가
      // 틀렸다. **못 재는 것을 잰다고 적어 두면 다음 사람이 그 말을 믿는다.**
      // 그래서 위 검사들(폭이 원래 크기와 정확히 같은지)이 진짜 근거다 —
      // 상자가 안 잘렸다는 것은 그림도 안 줄었다는 뜻이기 때문이다.
      expect(size.height, 48);
    });
  });

  group('제원', () {
    test('⚠️ 네이버 바탕색은 브랜드 초록이 아니다 — 버튼 초록이다', () {
      // #03C75A(브랜드 워드마크)를 쓰면 이미지와 색이 달라 이음매가 보인다.
      // 공식 버튼 PNG 픽셀 실측값은 #03A94D 다.
      expect(OfficialButtonArt.of(SnsAuthProvider.naver)!.background.toARGB32(),
          0xFF03A94D);
    });

    test('⚠️ 카카오 모서리는 가이드가 지정한 12 다', () {
      // "컨테이너 박스의 radius는 12 픽셀로 적용합니다".
      // 화면의 다른 버튼(16)에 맞추려고 바꾸면 규정 위반이다.
      expect(OfficialButtonArt.of(SnsAuthProvider.kakao)!.radius, 12);
    });

    test('구글·애플은 공식 버튼 이미지를 쓰지 않는다', () {
      expect(OfficialButtonArt.of(SnsAuthProvider.google), isNull);
      expect(OfficialButtonArt.of(SnsAuthProvider.apple), isNull);
    });

    test('⚠️ 화면 낭독기용 이름이 있다 — 이미지 안의 글자는 낭독되지 않는다', () {
      expect(OfficialButtonArt.of(SnsAuthProvider.kakao)!.label, '카카오 로그인');
      expect(OfficialButtonArt.of(SnsAuthProvider.naver)!.label, '네이버 로그인');
    });
  });
}

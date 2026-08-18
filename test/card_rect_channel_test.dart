
import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:connection_trace_ai_flutter/core/services/card_rect_detector.dart';

/// ⚠️ **"검출이 안 된다"에 섞인 세 가지를 갈라 놓았는지** 확인한다.
///
/// 이 화면에는 되돌림 장치가 있다 — 사각형을 6초간 못 찾으면 자동 촬영에서
/// 검출 조건을 뺀다. 그런데 **네이티브 등록을 빠뜨려도 똑같이 6초 뒤 조건이
/// 풀려 자동 촬영이 정상 동작한다.** 화면상으로는 예전과 구분이 안 된다.
///
/// | 상태 | 성격 |
/// |---|---|
/// | 채널 없음(`missing`) | **결함** |
/// | 채널 오류(`failing`) | **결함** |
/// | 채널 정상인데 미검출(`working`) | **설계대로** |
///
/// 구분이 없으면 다음 사람이 *"폴백 잘 되네"*로 읽고 넘어간다 — 이 저장소가
/// 반복해서 만난 *"코드는 맞는데 실물이 틀린"* 유형이다.

/// 검출기에 넣을 가짜 프레임.
///
/// 실제 픽셀 값은 보지 않는다 — 여기서 확인하는 것은 **채널이 어떻게
/// 응답했나**이지 검출 품질이 아니다(그건 실기기에서만 잰다).
CameraImage fakeFrame({int width = 640, int height = 480}) =>
    CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
        planes: [
          CameraImagePlane(
            bytes: Uint8List(width * height),
            bytesPerRow: width,
          ),
        ],
        width: width,
        height: height,
      ),
    );

/// 네이티브가 돌려주는 응답 모양.
///
/// ⚠️ 좌표만 오지 않는다 — **진단값이 함께** 온다. 실기기에서 앱 로그를
/// 볼 수 없다는 것이 실측으로 드러나(iOS 26), *"왜 안 잡히지"*를 가를
/// 숫자를 이 통로로 받아 화면에 띄우기 때문이다.
Map<String, Object?> okResponse({
  List<double> quads = const [],
  int observations = 0,
  int meanLuma = 118,
  bool imageOk = true,
}) => <String, Object?>{
  'quads': quads,
  'observations': observations,
  'meanLuma': meanLuma,
  'imageOk': imageOk,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('연결확인용/card_rect');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // ⚠️ **검사가 제품 기본값에 기대면 안 된다**(2026-08-17).
  //
  // 이 파일은 원래 `cardRectDetectionEnabled`가 켜져 있는 것을 전제로 돌았다.
  // 그래서 **기본값을 끄자 7건이 한꺼번에 깨졌다** — 채널을 아예 안 부르므로
  // 상태가 `unknown`에서 움직이지 않는다.
  //
  // 코드가 틀린 것이 아니라 **검사가 전제를 안 적어 둔 것**이었다. 여기서
  // 명시적으로 켜고, 끝나면 되돌린다. 그러면 **기본값이 어느 쪽이든 이 검사는
  // 같은 것을 잰다.**
  late bool savedEnabled;
  setUp(() {
    savedEnabled = cardRectDetectionEnabled.value;
    cardRectDetectionEnabled.value = true;
  });

  tearDown(() {
    cardRectDetectionEnabled.value = savedEnabled;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('아직 안 불러 봤으면 unknown', () {
    expect(
      CardRectDetector(channel: channel, supportedOverride: true).channelState,
      CardRectChannelState.unknown,
    );
  });

  test('네이티브가 없으면 missing — ⚠️ 결함으로 읽어야 하는 상태', () async {
    // 핸들러를 붙이지 않으면 MissingPluginException이 난다 —
    // AppDelegate 등록을 빠뜨린 빌드와 같은 상황이다.
    final detector = CardRectDetector(
      channel: channel,
      supportedOverride: true,
    );
    await detector.detect(fakeFrame(), sensorOrientation: 90);

    expect(detector.channelState, CardRectChannelState.missing);
    // 매 프레임 예외로 로그를 뒤덮지 않도록 즉시 끈다.
    expect(detector.isDisabled, isTrue);
  });

  test('채널이 오류를 돌려주면 failing — ⚠️ 이것도 결함', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'bad_frame');
    });

    final detector = CardRectDetector(
      channel: channel,
      supportedOverride: true,
    );
    for (var i = 0; i < 6; i++) {
      await detector.detect(fakeFrame(), sensorOrientation: 90);
    }

    expect(detector.channelState, CardRectChannelState.failing);
    expect(detector.isDisabled, isTrue);
  });

  test('📌 사각형을 못 찾아도 채널이 응답했으면 working — 설계대로', () async {
    // 여기가 핵심이다. 빈 결과는 **결함이 아니다** — 조명·거리 문제일 뿐이다.
    messenger.setMockMethodCallHandler(channel, (call) async => okResponse());

    final detector = CardRectDetector(
      channel: channel,
      supportedOverride: true,
    );
    final result = await detector.detect(fakeFrame(), sensorOrientation: 90);

    expect(result, isNull);
    expect(detector.channelState, CardRectChannelState.working);
    expect(detector.isDisabled, isFalse);
  });

  test('사각형을 돌려주면 명함 판정까지 이어진다', () async {
    // 640×480 프레임 한가운데의 명함(비율 1.6).
    messenger.setMockMethodCallHandler(channel, (call) async {
      const left = 120.0, top = 100.0, w = 400.0, h = 250.0;
      return okResponse(
        observations: 1,
        quads: <double>[
          left / 640,
          top / 480,
          (left + w) / 640,
          top / 480,
          (left + w) / 640,
          (top + h) / 480,
          left / 640,
          (top + h) / 480,
        ],
      );
    });

    final detector = CardRectDetector(
      channel: channel,
      supportedOverride: true,
    );
    final result = await detector.detect(fakeFrame(), sensorOrientation: 90);

    expect(result, isNotNull);
    expect(result!.isCardLike, isTrue);
    expect(detector.channelState, CardRectChannelState.working);
    // ⚠️ 진단값도 함께 담겨 와야 한다 — 실기기에서 화면으로 판정하는 근거다.
    expect(detector.lastDiagnostics?.observations, 1);
    expect(detector.lastDiagnostics?.imageOk, isTrue);
    expect(detector.lastDiagnostics?.frameWidth, 640);
  });

  test('⚠️ 이미지를 못 만들었으면 그 사실이 진단값에 남는다', () async {
    // 폭·행길이가 어긋나면 Vision은 아예 불리지도 않는다. 예전에는 그냥
    // 빈 결과라 **"못 찾았다"와 구분이 안 됐다.**
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => okResponse(imageOk: false, meanLuma: 0),
    );

    final detector = CardRectDetector(
      channel: channel,
      supportedOverride: true,
    );
    await detector.detect(fakeFrame(), sensorOrientation: 90);

    expect(detector.lastDiagnostics?.imageOk, isFalse);
    expect(detector.lastDiagnostics?.summary, contains('⚠️이미지실패'));
    // 채널 자체는 정상이다 — 이걸 섞으면 엉뚱한 곳을 고치게 된다.
    expect(detector.channelState, CardRectChannelState.working);
  });

  test('보내는 인자에 밝기 평면과 크기가 담긴다', () async {
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      return okResponse();
    });

    await CardRectDetector(
      channel: channel,
      supportedOverride: true,
    ).detect(fakeFrame(width: 320, height: 240), sensorOrientation: 90);

    expect(seen?.method, 'detect');
    final args = seen!.arguments as Map;
    expect(args['width'], 320);
    expect(args['height'], 240);
    expect(args['bytesPerRow'], 320);
    // ⚠️ 색은 보내지 않는다 — 사각형 검출에 필요 없고, 보내면 프레임마다
    // 옮기는 양이 세 배가 된다.
    expect((args['luma'] as Uint8List).length, 320 * 240);
  });

  test('앞의 검출이 끝나기 전 프레임은 버린다 — 큐가 쌓이면 테두리가 늦게 따라온다', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return okResponse();
    });

    final detector = CardRectDetector(
      channel: channel,
      supportedOverride: true,
    );
    final first = detector.detect(fakeFrame(), sensorOrientation: 90);
    // 아직 안 끝난 사이에 들어온 프레임.
    final second = await detector.detect(fakeFrame(), sensorOrientation: 90);
    await first;

    expect(second, isNull);
    expect(calls, 1);
  });

  group('⚠️ 큰 프레임은 줄여서 보낸다 (2026-08-16 실측)', () {
    test('아이폰이 준 3024×4032는 그대로 보내지 않는다', () {
      // 밝기 평면만 12MB다. 초당 8프레임이면 100MB/초를 채널로 옮기게 된다 —
      // 인계 문서가 이번 작업의 진짜 위험으로 짚은 "매 프레임 도는 일"이다.
      final result = downsampleLuma(
        Uint8List(3024 * 4032),
        width: 3024,
        height: 4032,
        bytesPerRow: 3024,
      );

      expect(result.step, greaterThan(1));
      expect(result.width, lessThanOrEqualTo(1024));
      expect(result.height, lessThanOrEqualTo(1024));
      expect(result.bytes.length, result.width * result.height);
      // 12MB → 약 0.76MB(6.25%). 프레임마다 옮기는 양이 16분의 1이 된다.
      expect(result.bytes.length, lessThan(3024 * 4032 ~/ 10));
    });

    test('작은 프레임은 복사 없이 그대로 쓴다', () {
      final source = Uint8List(640 * 480);
      final result = downsampleLuma(
        source,
        width: 640,
        height: 480,
        bytesPerRow: 640,
      );

      expect(result.step, 1);
      expect(identical(result.bytes, source), isTrue);
      expect(result.width, 640);
    });

    test('⚠️ 행 패딩이 있으면 작아도 다시 채워 넣는다', () {
      // 폭과 행 길이가 다른 채로 넘기면 네이티브가 이미지를 어긋나게 읽는다.
      final result = downsampleLuma(
        Uint8List(704 * 480),
        width: 640,
        height: 480,
        bytesPerRow: 704,
      );

      expect(result.width, 640);
      expect(result.bytes.length, 640 * 480);
    });

    test('줄여도 밝기 값은 원본에서 집어 온다', () {
      // 왼쪽 절반이 밝고 오른쪽 절반이 어두운 가짜 프레임.
      const w = 2048, h = 2048;
      final source = Uint8List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          source[y * w + x] = x < w ~/ 2 ? 200 : 20;
        }
      }
      final result = downsampleLuma(
        source,
        width: w,
        height: h,
        bytesPerRow: w,
      );

      expect(result.bytes.first, 200);
      expect(result.bytes[result.width - 1], 20);
    });
  });

  test('평면이 없는 프레임은 채널을 부르지 않는다', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return okResponse();
    });

    final empty = CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
        planes: const [],
        width: 640,
        height: 480,
      ),
    );
    await CardRectDetector(
      channel: channel,
      supportedOverride: true,
    ).detect(empty, sensorOrientation: 90);

    expect(calls, 0);
  });
}

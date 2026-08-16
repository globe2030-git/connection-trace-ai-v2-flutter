import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/card_quad_geometry.dart';

/// 카메라 프레임에서 **명함 테두리(사각형)를 찾는** 서비스 — B′ 1단계.
///
/// ## 왜 이게 있나
///
/// 지금까지는 화면에 **고정된 가이드 상자**를 그려 놓고 사용자가 거기에
/// 명함을 맞추게 했다. 리멤버를 비롯한 경쟁 앱은 **명함에 달라붙는 테두리**를
/// 보여준다. 명함 인식이 경쟁 앱보다 떨어지면 사용자는 이 앱의 값어치(AI가
/// 첫 문장을 만들어 주는 것)를 보기도 전에 떠난다.
///
/// ## 왜 기성 문서 스캐너가 아닌가 (A안 → B′)
///
/// 2026-08-16에 애플·구글의 기성 문서 스캐너를 붙여 봤는데(A안, 추가 266),
/// **아이폰에서 갈렸다.** 기성품은 **자기 화면을 통째로 들고 오고** 그 화면은
/// 우리가 못 고친다 — 문서용이라 명함 여러 장을 한꺼번에 잡았고 안내가
/// 영어로 나왔다.
///
/// 애플 Vision에는 **화면까지 주는 것**(`VNDocumentCameraViewController`)과
/// **검출만 주는 것**(`VNDetectRectanglesRequest`)이 따로 있다. 후자를 쓰면
/// **화면은 우리 것으로 두고 "사각형 어디 있나"만 OS에 물을 수 있다.**
///
/// ## 지금 어디까지 되나
///
/// | 플랫폼 | 엔진 | 상태 |
/// |---|---|---|
/// | iOS | `VNDetectRectanglesRequest` | ✅ 이 파일이 붙인다 |
/// | Android | OpenCV(`dartcv4`) | ⏳ 아직 — [isSupportedOnThisPlatform]가 false |
///
/// ⚠️ **안드로이드가 아직 없어도 앱은 그대로 돌아간다.** 검출이 없으면 부르는
/// 쪽이 **기존 고정 가이드 상자로 되돌아간다** — 최악의 경우가 지금과 같도록
/// 만든 것이 이 작업의 안전선이다.
///
/// ## ⚠️ 이 저장소의 첫 MethodChannel
///
/// `MethodChannel`은 Dart에서 플랫폼 네이티브 코드(Swift·Kotlin)를 부르는
/// 통로다. 이 저장소에는 지금까지 하나도 없었고 전부 pub 패키지로 해결해
/// 왔다. 여기서 직접 쓰는 이유는 **남의 화면이 딸려 오는 것이 A안에서 아팠던
/// 바로 그 지점**이라, 화면 없이 Vision 호출부만 가져오기 위해서다.
///
/// 다음 사람이 네이티브를 붙일 때 본보기가 되므로 **짧고 읽기 쉽게** 둔다.
/// 네이티브 쪽은 `ios/Runner/CardRectDetectorPlugin.swift`에 있다.
class CardRectDetector {
  CardRectDetector({
    @visibleForTesting MethodChannel? channel,
    @visibleForTesting this.supportedOverride,
  }) : _channel = channel ?? const MethodChannel(channelName);

  /// 테스트에서 플랫폼 판정을 대신하는 값.
  ///
  /// 왜 필요한가: [isSupportedOnThisPlatform]은 실기기 플랫폼을 보는데,
  /// `flutter test`는 맥에서 돈다. 이 구멍이 없으면 **채널 다루는 부분을
  /// 한 줄도 검사할 수 없다** — 그리고 검사 못 하는 자리가 바로 이 저장소가
  /// 반복해서 결함을 낸 자리다.
  @visibleForTesting
  final bool? supportedOverride;

  /// 네이티브와 약속한 통로 이름. Swift 쪽과 **글자 그대로 같아야** 한다.
  static const String channelName = 'connectionsense/card_rect';

  final MethodChannel _channel;

  /// 한 번에 한 프레임만 네이티브로 보낸다.
  ///
  /// ⚠️ 카메라는 초당 30~60프레임을 준다. 앞의 검출이 끝나기 전에 다음 것을
  /// 보내면 **큐가 쌓여 화면이 밀린다** — 검출 결과가 1초 전 장면을 가리키게
  /// 되는데, 그러면 테두리가 손을 따라오지 못하고 뒤늦게 따라붙는다.
  bool _inFlight = false;

  /// 네이티브가 응답하지 않을 때 영영 막히지 않도록.
  static const _timeout = Duration(milliseconds: 800);

  /// 이 플랫폼에서 검출이 되나.
  ///
  /// ⚠️ 웹·데스크톱에서 `Platform`을 만지면 예외가 난다. `kIsWeb`을 먼저 본다.
  static bool get isSupportedOnThisPlatform {
    if (kIsWeb) return false;
    // 안드로이드는 OpenCV(dartcv4) 도입 후에 켠다. 지금 켜면 매 프레임
    // 네이티브를 불러 실패만 받는다.
    return Platform.isIOS;
  }

  /// 검출 시도가 실패한 횟수. 연달아 실패하면 아예 끈다.
  ///
  /// 왜: 채널이 없는 빌드(네이티브 등록을 빠뜨린 경우)에서 **매 프레임 예외가
  /// 나면 로그가 뒤덮인다.** 실기기 검증 중에 정작 봐야 할 로그가 묻힌다.
  int _consecutiveFailures = 0;
  static const _maxConsecutiveFailures = 5;
  bool get isDisabled => _consecutiveFailures >= _maxConsecutiveFailures;

  CardRectChannelState _channelState = CardRectChannelState.unknown;

  /// ⚠️ **"검출이 안 된다"에는 서로 다른 세 가지가 섞여 있다.**
  ///
  /// | 상태 | 무엇 | 성격 |
  /// |---|---|---|
  /// | [CardRectChannelState.missing] | 네이티브가 등록 안 됨 | **결함** |
  /// | [CardRectChannelState.failing] | 채널은 있는데 응답이 실패·지연 | **결함** |
  /// | [CardRectChannelState.working] | 채널 정상. 사각형을 못 찾았을 뿐 | **설계대로** |
  ///
  /// 이걸 안 나누면 **채널이 안 뚫린 것이 정상 폴백으로 위장한다** —
  /// 화면상으로는 예전처럼 잘 도는 것처럼 보이기 때문이다. 이 저장소에서
  /// 반복된 *"코드는 맞는데 실물이 틀린"* 유형이 정확히 이 자리에 난다.
  CardRectChannelState get channelState => _channelState;

  /// 마지막 응답에 담겨 온 진단값. 아직 없으면 null.
  CardRectDiagnostics? lastDiagnostics;

  /// 카메라 프레임 한 장에서 명함 사각형을 찾는다.
  ///
  /// [sensorOrientation]은 카메라가 알려 준 센서 각도다. **그 값만으로
  /// 회전을 정하지 않는다** — 실제 프레임 모양까지 보고 [quarterTurnsForFrame]이
  /// 정한다(아이폰이 이미 세로인 프레임을 주는 것을 실측으로 확인했다).
  ///
  /// 돌려주는 좌표는 **표시 좌표**(0~1, 화면 방향 기준)다.
  /// 아직 못 찾았거나 이 플랫폼이 아니면 null.
  Future<CardRectDetection?> detect(
    CameraImage image, {
    required int sensorOrientation,
  }) async {
    final supported = supportedOverride ?? isSupportedOnThisPlatform;
    if (!supported || isDisabled || _inFlight) return null;
    if (image.planes.isEmpty) return null;

    final quarterTurns = quarterTurnsForFrame(
      sensorOrientation: sensorOrientation,
      frameWidth: image.width,
      frameHeight: image.height,
    );

    _inFlight = true;
    try {
      final plane = image.planes.first;
      // ⚠️ **줄여서 보낸다.** 아이폰이 실제로 준 프레임이 3024×4032였다
      // (2026-08-16 실측) — 밝기 평면만 **12MB**다. 초당 8프레임이면 100MB를
      // 옮기는 셈이라 발열·배터리로 바로 돌아온다.
      //
      // 정규화 좌표를 돌려받으므로 **줄여도 결과 좌표는 그대로**다.
      final frame = downsampleLuma(
        plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
      );
      final result = await _channel
          .invokeMethod<Map<Object?, Object?>>('detect', <String, Object?>{
            // Y(밝기) 평면만 보낸다. 사각형 검출에 색은 필요 없고, 색까지
            // 보내면 프레임마다 옮기는 양이 세 배가 된다.
            'luma': frame.bytes,
            'width': frame.width,
            'height': frame.height,
            'bytesPerRow': frame.width,
          })
          .timeout(_timeout);

      // 여기까지 왔으면 **채널은 뚫려 있다.** 사각형을 못 찾은 것과
      // 채널이 없는 것은 다른 일이다.
      _consecutiveFailures = 0;
      _channelState = CardRectChannelState.working;
      if (result == null) return null;

      // ⚠️ 네이티브는 좌표만 주지 않고 **진단값을 함께** 준다. 실기기에서
      // 로그를 볼 수 없다는 것이 실측으로 드러났기 때문이다(iOS 26에서
      // `idevicesyslog`에 앱 로그가 안 올라오고 `flutter run`도 못 붙는다).
      // 이 값들이 없으면 *"왜 안 잡히는지"*를 추측하게 된다.
      final rawQuads = result['quads'];
      lastDiagnostics = CardRectDiagnostics(
        frameWidth: image.width,
        frameHeight: image.height,
        meanLuma: (result['meanLuma'] as num?)?.toInt() ?? -1,
        observations: (result['observations'] as num?)?.toInt() ?? -1,
        imageOk: result['imageOk'] as bool? ?? false,
      );

      if (rawQuads is! List || rawQuads.isEmpty) return null;
      final flat = rawQuads.map((e) => (e as num).toDouble()).toList();
      return detectionFromFlat(
        flat,
        bufferSize: Size(image.width.toDouble(), image.height.toDouble()),
        quarterTurns: quarterTurns,
      );
    } on TimeoutException {
      _consecutiveFailures++;
      _channelState = CardRectChannelState.failing;
      return null;
    } on PlatformException catch (e) {
      _consecutiveFailures++;
      _channelState = CardRectChannelState.failing;
      // ⚠️ 명함 내용은 절대 로그에 남기지 않는다(CLAUDE.md 4절). 여기서
      // 찍는 것은 채널 오류 코드뿐이고 이미지는 포함되지 않는다.
      if (!kReleaseMode) {
        debugPrint('[CARDRECT] 채널 오류: ${e.code}');
      }
      return null;
    } on MissingPluginException {
      // ⚠️ **네이티브가 등록되지 않은 빌드다 — 이건 결함이다.**
      //
      // 조용히 끄면 기존 가이드 상자로 돌아가 화면상으로는 멀쩡해 보인다.
      // 그래서 상태를 남긴다 — 부르는 쪽이 "설계대로 폴백"과 구분해서
      // 로그에 적을 수 있게.
      _consecutiveFailures = _maxConsecutiveFailures;
      _channelState = CardRectChannelState.missing;
      return null;
    } finally {
      _inFlight = false;
    }
  }
}

/// 네이티브가 넘긴 좌표 배열을 **화면 방향으로 돌려 후보 중 하나를 고른다.**
///
/// 서비스 본체에서 떼어 낸 이유는 하나다 — **여기가 `flutter test`로 검사할
/// 수 있는 부분의 끝**이기 때문이다. 카메라도 네이티브도 없이 좌표만 넣어
/// 결과를 확인할 수 있다.
///
/// 명함으로 통과한 후보가 없으면 **가장 큰 후보를 그 판정과 함께** 돌려준다.
/// 왜 null이 아닌가: 실기기에서 *"왜 안 잡히지"*를 추측하지 않기 위해서다.
/// 이 프로젝트는 자동 촬영 게이트에서 **대비인 줄 알았는데 실제로 막은 건
/// 톤 비율이었던** 일을 겪었다. 무엇이 떨어뜨렸는지 남는 편이 낫다.
///
/// ⚠️ 부르는 쪽은 [CardRectDetection.isCardLike]를 보고 판단해야 한다.
/// 돌아왔다고 해서 명함이 잡힌 것이 아니다.
CardRectDetection? detectionFromFlat(
  List<double>? flat, {
  required Size bufferSize,
  required int quarterTurns,
  CardShapeCriteria criteria = const CardShapeCriteria(),
}) {
  final bufferQuads = cardQuadsFromFlat(flat);
  if (bufferQuads.isEmpty) return null;

  // 90°·270°로 돌리면 가로세로가 뒤바뀐다.
  final displaySize = quarterTurns.isEven
      ? bufferSize
      : Size(bufferSize.height, bufferSize.width);
  final displayQuads = bufferQuads
      .map((quad) => rotateQuadClockwise(quad, quarterTurns))
      .toList();

  final best = pickBestCardQuad(displayQuads, displaySize, criteria: criteria);
  if (best != null) {
    return CardRectDetection(
      quad: best,
      displaySize: displaySize,
      verdict: CardShapeVerdict.ok,
    );
  }

  var fallback = displayQuads.first;
  var fallbackArea = cardQuadAreaFraction(fallback);
  for (final quad in displayQuads.skip(1)) {
    final area = cardQuadAreaFraction(quad);
    if (area > fallbackArea) {
      fallbackArea = area;
      fallback = quad;
    }
  }
  return CardRectDetection(
    quad: fallback,
    displaySize: displaySize,
    verdict: judgeCardShape(fallback, displaySize, criteria: criteria),
  );
}

/// 네이티브가 응답에 함께 담아 보낸 **실측 진단값**.
///
/// ⚠️ 이것을 화면에 띄우는 이유: 이 기기에서는 **앱 로그를 볼 수 없다.**
/// `flutter run`이 앱에 못 붙고(2026-08-16 두 차례), `idevicesyslog`에도
/// 앱이 찍는 줄이 하나도 안 올라온다(실측). 그래서 *"왜 안 잡히지"*를
/// 가르려면 **이미 뚫려 있는 통로로 숫자를 받아 화면에 띄우는** 수밖에 없다.
///
/// | 값 | 무엇을 가르나 |
/// |---|---|
/// | [imageOk] | 밝기 이미지를 만들 수 있었나 — false면 **폭·행길이가 어긋난 것** |
/// | [meanLuma] | 넘어온 이미지가 실제 장면인가 — 0이나 엉뚱하면 **이미지가 깨진 것** |
/// | [observations] | Vision이 내놓은 **원본 개수**(우리가 거르기 전) |
///
/// [observations]가 0이면 Vision이 못 찾은 것이고, 0보다 큰데 화면에 테두리가
/// 없으면 **우리 명함 판정이 걸러낸 것**이다 — 완전히 다른 문제다.
@immutable
class CardRectDiagnostics {
  const CardRectDiagnostics({
    required this.frameWidth,
    required this.frameHeight,
    required this.meanLuma,
    required this.observations,
    required this.imageOk,
  });

  final int frameWidth;
  final int frameHeight;
  final int meanLuma;
  final int observations;
  final bool imageOk;

  /// 디버그 화면에 한 줄로 띄울 요약.
  String get summary =>
      '${frameWidth}x$frameHeight'
      '${imageOk ? '' : ' ⚠️이미지실패'}'
      ' 밝기$meanLuma obs$observations';
}

/// 네이티브 채널이 지금 어떤 상태인가.
///
/// ⚠️ **[working]과 [missing]을 화면으로는 구분할 수 없다.** 둘 다 "테두리가
/// 안 보이고 예전처럼 동작"으로 보인다. 그런데 앞은 설계대로이고 뒤는
/// 결함이다 — 구분을 로그로 남기지 않으면 다음 사람이 *"폴백 잘 되네"*로
/// 읽고 넘어간다.
enum CardRectChannelState {
  /// 아직 한 번도 안 불러 봤다.
  unknown,

  /// 채널이 응답한다. 사각형을 못 찾는 것은 **별개 문제**다.
  working,

  /// ⚠️ 네이티브가 등록되지 않았다 — **결함**. `AppDelegate` 확인.
  missing,

  /// ⚠️ 채널은 있는데 오류·지연이 반복된다 — **결함**.
  failing,
}

/// 검출 결과 한 건.
@immutable
class CardRectDetection {
  const CardRectDetection({
    required this.quad,
    required this.displaySize,
    required this.verdict,
  });

  /// **표시 좌표**(0~1)의 네 귀퉁이.
  final CardQuad quad;

  /// 표시 방향 기준 프레임 크기(px). 길이·각도를 잴 때 필요하다.
  final Size displaySize;

  /// 명함처럼 생겼는지.
  final CardShapeVerdict verdict;

  /// 자동 촬영에 쓸 수 있는 검출인가.
  bool get isCardLike => verdict == CardShapeVerdict.ok;
}

/// 검출 결과가 잠깐씩 끊기는 것을 메워 주는 유지 장치.
///
/// ⚠️ 왜 필요한가: 검출은 **매 프레임 성공하지 않는다.** 초점이 흔들리거나
/// 손 그림자가 지나가면 한두 프레임 비는데, 그때마다 테두리를 지우면
/// **화면에서 깜빡인다.** 사람 눈에는 "잘 안 잡힌다"로 읽힌다.
///
/// 마지막 검출을 [holdDuration] 동안 들고 있다가 그 뒤에 놓는다.
///
/// ⚠️ **자동 촬영 판정에는 이 유지값을 쓰면 안 된다** — 명함을 치웠는데
/// 유지 시간 동안 찍히는 일이 생긴다. 테두리를 **그리는 데만** 쓴다.
class CardRectHold {
  CardRectHold({this.holdDuration = const Duration(milliseconds: 400)});

  final Duration holdDuration;
  CardRectDetection? _last;
  DateTime? _lastAt;

  /// 새 검출을 넣는다. null이면 "이번 프레임은 못 찾았다"는 뜻이다.
  void update(CardRectDetection? detection, DateTime now) {
    if (detection != null) {
      _last = detection;
      _lastAt = now;
    }
  }

  /// 지금 화면에 그릴 테두리. 유지 시간이 지났으면 null.
  CardRectDetection? visibleAt(DateTime now) {
    final at = _lastAt;
    if (at == null || now.difference(at) > holdDuration) return null;
    return _last;
  }

  void clear() {
    _last = null;
    _lastAt = null;
  }
}

/// 카메라 센서 방향으로 **버퍼를 몇 번 돌려야 하는지** 구한다.
///
/// 이 화면은 세로 전용(`portraitUp` 고정)이므로 기기 방향은 항상 0으로 본다.
/// 그러면 필요한 회전은 센서 방향 그대로다 — 대부분의 후면 카메라가 90이다.
int quarterTurnsForSensor(int sensorOrientation) {
  final normalized = ((sensorOrientation % 360) + 360) % 360;
  return normalized ~/ 90;
}

/// ⚠️ **실제 프레임 모양까지 보고** 회전 횟수를 정한다 (2026-08-16 실측).
///
/// [quarterTurnsForSensor]만 쓰면 틀린다. 아이폰에서 실제로 들어온 프레임이
/// **3024×4032 — 이미 세로**였다(화면 캡처로 확인). 센서 방향이 90이라고
/// 90° 돌리면 **테두리가 옆으로 누워 엉뚱한 곳에 그려진다.**
///
/// 규칙은 단순하다.
///
/// | 버퍼 모양 | 어떻게 |
/// |---|---|
/// | **이미 세로**(높이 > 폭) | 화면과 방향이 같다 → **안 돌린다** |
/// | 가로(폭 ≥ 높이) | 센서 방향대로 돌린다 |
///
/// 이 화면이 세로 전용이라서 성립하는 규칙이다.
///
/// ⚠️ **폴더블을 펼치면 안드로이드가 앱의 방향 제한을 무시한다**(이 화면이
/// 이미 겪은 문제, `_guideFrameSizeFor` 주석 참고). 안드로이드 검출을 켤 때
/// **커버·펼침 양쪽에서 반드시 다시 재야 한다.**
int quarterTurnsForFrame({
  required int sensorOrientation,
  required int frameWidth,
  required int frameHeight,
}) {
  if (frameHeight > frameWidth) return 0;
  return quarterTurnsForSensor(sensorOrientation);
}

/// 줄여 놓은 밝기 평면.
@immutable
class DownsampledLuma {
  const DownsampledLuma({
    required this.bytes,
    required this.width,
    required this.height,
    required this.step,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// 몇 픽셀마다 하나씩 집었나(1이면 그대로).
  final int step;
}

/// 밝기 평면을 **성기게 집어** 줄인다.
///
/// ⚠️ 왜 필요한가 (2026-08-16 실측): 아이폰이 준 프레임이 **3024×4032**였다.
/// 밝기 평면만 **12MB**이고, 초당 8프레임을 보내면 **100MB/초**를 채널로
/// 옮기게 된다. 인계 문서가 *"매 프레임 도는 일"*을 이번 작업의 진짜 위험으로
/// 짚은 것이 바로 이 지점이다.
///
/// 보간하지 않고 **N픽셀마다 하나씩 집는다**(nearest). 사각형 테두리를 찾는
/// 데는 충분하고, 매 프레임 도는 일이라 가벼운 쪽이 맞다.
///
/// 📌 **결과 좌표에는 영향이 없다** — 네이티브가 0~1 정규화 좌표를 돌려주기
/// 때문이다. 줄인 이미지에서 찾은 사각형의 상대 위치는 원본과 같다.
///
/// [targetMaxDimension]보다 긴 변이 크면 그만큼 성기게 집는다.
@visibleForTesting
DownsampledLuma downsampleLuma(
  Uint8List source, {
  required int width,
  required int height,
  required int bytesPerRow,
  int targetMaxDimension = 1024,
}) {
  final longest = width > height ? width : height;
  // 긴 변이 목표 이하가 되는 **가장 작은** 간격. 올림해야 목표를 넘지 않는다.
  var step = (longest + targetMaxDimension - 1) ~/ targetMaxDimension;
  if (step < 1) step = 1;
  if (step <= 1) {
    // ⚠️ 행 패딩이 없을 때만 그대로 넘긴다. 패딩이 있으면 폭과 행 길이가
    // 달라 **네이티브가 이미지를 잘못 읽는다.**
    if (bytesPerRow == width) {
      return DownsampledLuma(
        bytes: source,
        width: width,
        height: height,
        step: 1,
      );
    }
    step = 1;
  }

  final outWidth = (width + step - 1) ~/ step;
  final outHeight = (height + step - 1) ~/ step;
  final out = Uint8List(outWidth * outHeight);
  var index = 0;
  for (var y = 0; y < height; y += step) {
    final rowStart = y * bytesPerRow;
    for (var x = 0; x < width; x += step) {
      final source_ = rowStart + x;
      out[index++] = source_ < source.length ? source[source_] : 0;
    }
  }
  return DownsampledLuma(
    bytes: out,
    width: outWidth,
    height: outHeight,
    step: step,
  );
}

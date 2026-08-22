import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/card_quad_geometry.dart';
import 'card_rect_worker.dart';

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
/// | 플랫폼 | 엔진 | 어떻게 부르나 |
/// |---|---|---|
/// | iOS | `VNDetectRectanglesRequest` | **MethodChannel**(Swift) |
/// | Android | OpenCV(`dartcv4`) | **별도 isolate**(Dart에서 직접) |
///
/// ⚠️ **부르는 길은 다른데 돌려받는 것은 똑같다.** 좌표도 진단값도 같은
/// 모양이라, 이 파일 아래쪽(판정·좌표 변환·크롭·화면)은 **플랫폼을 모른다.**
/// 그 계약이 갈리면 **화면의 진단 줄이 두 플랫폼에서 다르게 보이기 시작한다.**
///
/// ⚠️ **검출이 실패해도 앱은 그대로 돌아간다.** 부르는 쪽이 **기존 고정 가이드
/// 상자로 되돌아간다** — 최악의 경우가 지금과 같도록 만든 것이 이 작업의
/// 안전선이다.
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
/// 검출을 **끄고 켜는 스위치**(release 빌드 제외).
///
/// ## 왜 필요한가 — 2단계 대조
///
/// 두 경로를 나란히 재려면 **같은 기기에서 번갈아 켤 수 있어야** 한다. 그런데
/// B′는 기존 촬영 화면 **안에** 들어갔기 때문에, 이 스위치가 없으면
/// **"기존 고정 가이드"를 고를 방법이 아예 없다.**
///
/// | 스위치 | 무엇이 도나 |
/// |---|---|
/// | 켬 | **B′** — 명함을 찾아 그 테두리대로 자른다 |
/// | **끔(기본)** | **기존 고정 가이드 상자**로 자른다(예전 그대로) |
///
/// ## ⚠️ 왜 기본이 꺼짐인가 (2026-08-17 사용자 확정)
///
/// 처음 병합될 때 **기본이 켜짐이었다.** 그런데 우리가 정한 순서는 이랬다:
///
/// ```
/// 1단계  새 경로로 추가          ✅
/// 2단계  실제 명함으로 나란히 재기  ← 아직 안 함
/// 3단계  이기면 기본값 교체        ⚠️ 이미 돼 있었다
/// ```
///
/// **2단계의 관문(*"필드 정확도가 나빠지면 멈춘다"*)이 돌기 전에 3단계가
/// 됐다.** 우리가 만든 게이트를 우리가 건너뛴 것이다.
///
/// 📌 **끄는 데 드는 값이 0이다.** 측정용 스위치가 화면에 있어 잴 때만 켜면
/// 되므로, *"끄면 측정이 늦어진다"*는 이유가 성립하지 않는다.
///
/// **측정이 끝나고 이기면 그때 근거를 갖고 켠다.**
///
/// ⚠️ 끄면 **검출 코드가 아예 안 돈다** — 프레임도 안 보내고 테두리도 안 그린다.
/// "그리기만 끄는" 것이 아니라 **경로 자체가 예전이 된다.** 그래야 비교가 된다.
///
/// 📌 이것은 **되돌림 장치이기도 하다.** 실기기에서 문제가 나면 코드를 되돌리기
/// 전에 이 스위치부터 내려 확인할 수 있다.
/// ## ⚠️ 2026-08-17 — **스위치를 둘로 갈랐다** (추가 293)
///
/// 예전에는 이 하나가 **검출과 자르기를 같이** 켰다. 그래서 *"빈 화면 촬영만
/// 막고 자르기는 예전 것을 쓰자"*가 **불가능했다** — 켜면 자르기까지 바뀌었다.
///
/// ```
/// cardRectDetectionEnabled  검출을 돌린다   → 빈 화면·손을 자동 촬영에서 막는다
/// cardRectCropEnabled       자르기를 B′로   → **기본 켬**(2026-08-17 사용자 확정)
///
/// ⚠️ 이 줄은 오래 *"기본 꺼짐(추가 277에서 안 쓰기로 함)"*으로 남아 있었다.
/// 아래 본문이 2026-08-17에 "켠다"로 바뀌었는데 이 요약표만 안 고쳐진 것이다 —
/// **이 줄만 보고 판단하면 자르기가 꺼져 있다고 읽는다.** 실제 값은 아래
/// `ValueNotifier<bool>(true)`다.
/// ```
///
/// **검출은 기본 켬**이다. 실기기에서 두 기기로 확인했다(추가 293) —
/// 빈 책상·손은 판정에서 떨어지고, 명함은 양쪽 다 잡혔다(비율 1.80).
final ValueNotifier<bool> cardRectDetectionEnabled = ValueNotifier<bool>(true);

/// 자르기까지 **검출된 테두리로** 할지(B′).
///
/// ## ✅ 사용자 확정 (2026-08-17) — **켠다**
///
/// 추가 277에서는 껐다. *"인식률이 나아진다는 증거가 없다"*는 이유였다.
/// **그 판단의 근거가 그 뒤 달라졌다.**
///
/// | | 그때 | 지금 |
/// |---|---|---|
/// | 검출이 되나 | 아이폰에서 *"후보없음"* | **두 기기 다 잡음**(비율 1.80) |
/// | 재는 자 | ⚠️ 틀린 정답지 | 103장 전수 검수본 |
/// | 표본 | 5~6장 | 103장 |
///
/// 📌 그때 판정을 못 낸 것은 **검출이 나빠서가 아니라 잴 수가 없어서**였다.
///
/// ⚠️ **아직 안 잰 것**: 잘린 결과의 인식률. B′는 명함만 잘라 깔끔하지만
/// **멀리서 찍으면 해상도가 떨어진다**(예전 측정 1,208~2,353px로 들쭉날쭉).
/// 검출이 실패하면 **기존 고정 가이드로 되돌아간다** — 최악이 지금과 같다.
final ValueNotifier<bool> cardRectCropEnabled = ValueNotifier<bool>(true);

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
  ///
  /// | 플랫폼 | 엔진 | 어디 |
  /// |---|---|---|
  /// | iOS | `VNDetectRectanglesRequest` | `ios/Runner/CardRectDetectorPlugin.swift` |
  /// | Android | OpenCV(기성 `org.opencv:opencv`) | `android/.../CardRectDetectorPlugin.kt` |
  ///
  /// **둘이 같은 채널·같은 응답 모양을 쓴다.** 이 파일은 어느 쪽인지 모른다.
  static bool get isSupportedOnThisPlatform {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  /// 검출 시도가 실패한 횟수. 연달아 실패하면 아예 끈다.
  ///
  /// 왜: 채널이 없는 빌드(네이티브 등록을 빠뜨린 경우)에서 **매 프레임 예외가
  /// 나면 로그가 뒤덮인다.** 실기기 검증 중에 정작 봐야 할 로그가 묻힌다.
  int _consecutiveFailures = 0;
  static const _maxConsecutiveFailures = 5;
  bool get isDisabled => _consecutiveFailures >= _maxConsecutiveFailures;

  /// 안드로이드에서 쓰는 검출 일꾼(별도 isolate).
  ///
  /// ⚠️ 아이폰에서는 만들지 않는다 — 그쪽은 네이티브 채널이 같은 역할을 한다.
  CardRectWorker? _worker;
  bool _workerSpawning = false;

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
    // ⚠️ 스위치가 내려가 있으면 **아무것도 하지 않는다.** 프레임도 안 보낸다 —
    // 2단계 대조에서 "예전 경로"가 정말 예전이어야 하기 때문이다.
    if (!cardRectDetectionEnabled.value) return null;
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
      // ⚠️ **여기만 플랫폼별로 갈린다.** 아래는 전부 공용이다.
      final result = Platform.isAndroid
          ? await _detectWithWorker(frame)
          : await _channel
                .invokeMethod<Map<Object?, Object?>>(
                  'detect',
                  <String, Object?>{
                    // Y(밝기) 평면만 보낸다. 사각형 검출에 색은 필요 없고,
                    // 색까지 보내면 프레임마다 옮기는 양이 세 배가 된다.
                    'luma': frame.bytes,
                    'width': frame.width,
                    'height': frame.height,
                    'bytesPerRow': frame.width,
                  },
                )
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
      final bufferSize = Size(image.width.toDouble(), image.height.toDouble());
      final flat = rawQuads is List
          ? rawQuads.map((e) => (e as num).toDouble()).toList()
          : const <double>[];
      final detection = flat.isEmpty
          ? null
          : detectionFromFlat(
              flat,
              bufferSize: bufferSize,
              quarterTurns: quarterTurns,
            );

      // ⚠️ **떨어진 후보의 값도 남긴다.** "떨어졌다"만 보면 얼마나 모자랐는지
      // 몰라 또 짐작하게 된다 — 이 기준을 두 번 짐작으로 정했다가 두 번 다
      // 진짜 명함을 막았다.
      lastDiagnostics = CardRectDiagnostics(
        frameWidth: image.width,
        frameHeight: image.height,
        meanLuma: (result['meanLuma'] as num?)?.toInt() ?? -1,
        observations: (result['observations'] as num?)?.toInt() ?? -1,
        imageOk: result['imageOk'] as bool? ?? false,
        topAreaFraction: detection == null
            ? null
            : cardQuadAreaFraction(detection.quad),
        topAspectRatio: detection == null
            ? null
            : cardQuadAspectRatio(detection.quad, detection.displaySize),
      );

      return detection;
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

  /// 안드로이드: 일꾼 isolate에 프레임을 보내고, **채널과 같은 모양**으로
  /// 바꿔 돌려준다.
  ///
  /// ⚠️ 일꾼을 못 띄우면 [CardRectChannelState.missing]으로 남긴다 — 아이폰에서
  /// 네이티브 등록을 빠뜨린 것과 **같은 성격의 결함**이고, 둘 다 화면에서는
  /// "테두리가 안 보인다"로 똑같이 보이기 때문이다.
  Future<Map<Object?, Object?>?> _detectWithWorker(
    DownsampledLuma frame,
  ) async {
    var worker = _worker;
    if (worker == null) {
      // 띄우는 동안 들어온 프레임은 그냥 버린다 — 기다리면 프레임이 밀린다.
      if (_workerSpawning) return null;
      _workerSpawning = true;
      worker = await CardRectWorker.spawn();
      _workerSpawning = false;
      if (worker == null) {
        _consecutiveFailures = _maxConsecutiveFailures;
        _channelState = CardRectChannelState.missing;
        return null;
      }
      _worker = worker;
    }

    final result = await worker.detect(
      frame.bytes,
      width: frame.width,
      height: frame.height,
      timeout: _timeout,
    );
    return result?.toChannelMap();
  }

  /// 화면을 닫을 때 부른다. **안 부르면 isolate가 남는다.**
  ///
  /// 아이폰에서는 할 일이 없다 — 네이티브 채널은 앱이 들고 있다.
  void dispose() {
    _worker?.dispose();
    _worker = null;
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
    this.topAreaFraction,
    this.topAspectRatio,
  });

  final int frameWidth;
  final int frameHeight;
  final int meanLuma;
  final int observations;
  final bool imageOk;

  /// 가장 큰 후보의 **넓이 비율**과 **가로세로비**.
  ///
  /// ⚠️ **왜 이걸 띄우나**: 최소 넓이 기준을 두 번 짐작으로 정했고 **두 번 다
  /// 진짜 명함을 막았다**(15% → 실측 6.7% → 폴드 편 화면에서는 그보다도 작아
  /// 2%에서도 떨어졌다). *"떨어졌다"*만 보면 **얼마나 모자랐는지 몰라 또
  /// 짐작하게 된다.** 값을 보여 주면 **재고 정할 수 있다.**
  final double? topAreaFraction;
  final double? topAspectRatio;

  /// 디버그 화면에 한 줄로 띄울 요약.
  String get summary {
    final area = topAreaFraction;
    final ratio = topAspectRatio;
    final shape = area == null || ratio == null
        ? ''
        : ' 넓이${(area * 100).toStringAsFixed(1)}%'
              ' 비율${ratio.toStringAsFixed(2)}';
    return '${frameWidth}x$frameHeight'
        '${imageOk ? '' : ' ⚠️이미지실패'}'
        ' 밝기$meanLuma obs$observations$shape';
  }
}

/// 검출기가 지금 어떤 상태인가.
///
/// ⚠️ **부르는 길은 플랫폼마다 다르다** — 아이폰은 네이티브 채널, 안드로이드는
/// 별도 isolate다. 그래서 화면·로그에는 "채널"이 아니라 **"검출기"**라고 쓴다.
/// 안드로이드에서 "채널"이라고 하면 있지도 않은 것을 가리키게 된다.
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

  /// ⚠️ 검출기를 아예 띄우지 못했다 — **결함**.
  ///
  /// 아이폰이면 `AppDelegate`의 채널 등록을, 안드로이드면 isolate를 띄우지
  /// 못한 것이다.
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

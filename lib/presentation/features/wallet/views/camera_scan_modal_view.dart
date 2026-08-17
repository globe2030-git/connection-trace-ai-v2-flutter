import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/card_quad_geometry.dart';
import '../../../../core/utils/card_photo_downscale.dart';
import '../../../../core/utils/card_quad_warp.dart';
import '../../../../core/utils/frame_contrast.dart';
// ⚠️ 측정 전용 — backlog 277이 끝나면 이 import와 쓰는 곳을 함께 지운다.
import '../../../../core/utils/measure_sample_sink.dart';
import '../../../../core/utils/scan_rotation.dart';
import '../../../../core/utils/scan_temp_cleanup.dart';
import '../../../../core/services/card_rect_detector.dart';
import '../../../../core/services/ocr_scanner_service.dart';
import 'card_rect_overlay.dart';
import 'manual_crop_view.dart';

class CameraScanModalView extends StatefulWidget {
  /// 지금 찍는 면("앞면"/"뒷면"). 화면 아래에 항상 띄운다.
  ///
  /// 명함 한 장은 앞면과 뒷면까지가 최대인데(추가 189), 카메라 화면에는 지금
  /// 무엇을 찍는 중인지 표시가 없어서 뒷면 스캔을 고르고 들어와도 알 수 없었다.
  /// 다른 명함 앱들이 공통으로 이 라벨을 두고 있다(2026-08-14 참고 자료).
  final String sideLabel;

  const CameraScanModalView({super.key, this.sideLabel = '앞면'});

  @override
  State<CameraScanModalView> createState() => _CameraScanModalViewState();
}

class _CameraScanModalViewState extends State<CameraScanModalView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // 국내 명함 표준 규격(90×50mm, 가로세로비 약 1.8:1)이지만, 가이드
  // 프레임 자체는 세로로 긴 모양(비율을 뒤집음)으로 그린다. 폰은 계속
  // 세로로 잡고, 명함을 시계 방향으로 90도 돌려서 그 세로 프레임 안에
  // 맞춰 넣는 방식 — 2026-08-03에 화면 자체를 가로로 고정했다가 "버튼
  // 조작이 어려워졌다"는 피드백으로 되돌렸고, 이후 다시 화면 회전
  // 방식으로 시도했으나(2026-08-06 오전) 사용자가 다른 명함 앱 영상을
  // 보여주며 "이 방법이 아니다"라고 정정함 — 화면/기기는 그대로 세로
  // 유지하고 명함만 돌려서 넣는 게 맞는 방식이었다(2026-08-06 저녁,
  // backlog 추가 85). 세로 프레임에 맞춰 명함을 최대한 크게(고해상도로)
  // 담을 수 있는 장점도 있다. 촬영 후 [_cropToGuideFrame]에서 크롭한
  // 결과물을 고정 -90도(반시계) 회전시켜 정방향으로 되돌린다 — 기기
  // 회전이 없으므로 EXIF 기반이 아니라 항상 같은 방향으로 고정 회전.
  // 실제 픽셀 크기는 화면 크기별로 [_guideFrameSizeFor]가 다시 계산한다.
  static const _cardAspectRatio = 184 / 330;

  // 자동 촬영 안정성 감지 파라미터 — 명함이 프레임 안에서 흔들리지 않고
  // 멈춰 있다고 판단되면 자동으로 셔터를 누른다. 셔터 버튼을 손가락으로
  // 눌러서 생기는 순간적인 흔들림(모션 블러)이 OCR 인식률을 떨어뜨리는
  // 주된 원인이라, 사용자가 직접 누르지 않아도 되게 하는 게 목적.
  // 임계값을 넉넉히 잡아 자연스러운 손떨림 정도는 "불안정"으로 치지 않게
  // 하고(정렬 여유), 실제 촬영은 프레임 개수가 아니라 안정 상태가 시작된
  // 시점부터 경과 시간으로 판단한다(기기 프레임레이트와 무관하게 일정
  // 시간 유지되면 촬영). 유지 시간은 2026-08-06 저녁 사이 0.15초 → 1초 →
  // 0.5초 → 0.25초 → 0.2초로 여러 차례 재조정됐다(짧다/길다 피드백이
  // 반복돼 왔다는 뜻 — 값 자체보다 "사용자가 직접 다시 조정을 요청할 수
  // 있다"는 점을 기억할 것). 임계값은 "가이드 안에
  // 훨씬 정확히 들어와야(≈95%) 촬영되면 좋겠다"는 요청에 맞춰 다시
  // 좁혔다 — 실제로 카드-가이드 겹침 비율을 픽셀 단위로 재는 건 아니고
  // (별도의 문서 경계 검출이 필요한 더 큰 작업), 전체 화면 흔들림
  // 허용치를 좁혀서 더 정확히 멈춰야만 "안정"으로 인정되게 하는 근사치.
  /// ⚠️ **실측으로 고쳤다.** 폰을 손도 대지 않고 거치한 상태에서 이 값이
  /// **5.2~8.4**로 나왔다(로그 측정 2026-08-14). 기준이 8.0이었으니 **가만히
  /// 둔 폰조차 절반은 "불안정"으로 판정**됐고, 손에 들면 더 자주 넘었다 —
  /// 사용자 제보 "명함에 가이드를 제대로 놓은 것 같은데 파란색이 잘 보이지
  /// 않아"의 주된 원인이다.
  ///
  /// 이 값은 과거에 *"가이드 안에 훨씬 정확히 들어와야 촬영되면 좋겠다"*는
  /// 요청으로 좁혔던 것인데, 좁힌 대상이 **"명함이 잘 맞춰졌는가"가 아니라
  /// "폰이 안 흔들리는가"**였다. 의도한 효과는 못 얻고 촬영만 어려워졌다.
  ///
  /// 처음엔 14로 넓혔더니 이번엔 **계속 자동 촬영**됐다(제보 "계속 자동촬영이
  /// 되"). 거치 상태가 5.2~8.4니 14는 웬만한 움직임까지 "정지"로 봤다.
  ///
  /// **측정한 잡음 바닥(8.4) 바로 위인 10으로 잡는다.** 진짜 멈췄을 때만
  /// 통과하고, 8.0처럼 잡음에 파묻히지도 않는다. 흐린 사진이 늘 위험은 촬영
  /// 직후 **"글자가 또렷한가요?" 확인 화면**이 받아 준다.
  static const _stabilityDiffThreshold = 10.0;
  static const _requiredStableDuration = Duration(milliseconds: 200);
  static const _sampleGridSize = 24;
  static const _autoCaptureWarmup = Duration(milliseconds: 900);

  /// **다시 찍기** 뒤 자동 촬영을 잠깐 멈추는 시간(추가 293).
  ///
  /// ⚠️ 다시 찍기를 누르면 명함은 **그대로 화면에 있다.** 예전에는 워밍업
  /// 0.9초만 지나면 **곧바로 또 찍혔다** — 사용자는 다시 겨눌 틈도, 나갈 틈도
  /// 없었다. 실기기에서 *"다시찍기 할 때는 X가 터치되지 않음"*으로 나타났다
  /// (곧바로 다시 확인 화면이 떠서 누를 대상이 사라진 것이다).
  ///
  /// 📌 자동 촬영을 **끄는 것이 아니라 미루는 것**이다. 이 시간이 지나고도
  /// 명함이 가만히 있으면 평소처럼 찍힌다.
  static const _retakeCooldown = Duration(seconds: 3);

  /// 이 시각까지는 자동 촬영을 하지 않는다.
  DateTime? _autoCaptureBlockedUntil;
  // 카메라는 초당 30~60프레임을 보내지만 흔들림 판단에는 8fps면
  // 충분하다. 나머지 프레임은 즉시 버려 CPU·배터리 사용을 줄인다.
  static const _frameAnalysisInterval = Duration(milliseconds: 125);

  /// 테두리 검출을 **얼마 만에 한 번** 돌릴지(추가 293).
  ///
  /// ⚠️ 흔들림 판단(24×24 격자 표본)은 싸지만 **검출은 비싸다** — 안드로이드는
  /// OpenCV, 아이폰은 Vision이 매 프레임 돈다. 실기기에서 **발열이 느껴진다**는
  /// 지적을 받아 검출만 따로 늦춘다.
  ///
  /// 📌 흔들림 판단은 8fps 그대로 둔다. 같이 늦추면 **자동 촬영 반응이 함께
  /// 둔해진다** — 그건 사용자가 바로 느낀다.
  ///
  /// 명함을 놓고 잠깐 멈추는 동작이라 **초당 세 번이면 충분하다.**
  static const _rectDetectionInterval = Duration(milliseconds: 320);

  DateTime? _lastRectDetectAt;

  /// 가이드 프레임 안쪽 밝기의 **표준편차** 하한. 이 아래면 "볼 것이 없다"로
  /// 보고 자동 촬영하지 않는다.
  ///
  /// 왜 필요한가: 예전 자동 촬영 조건은 **"화면이 흔들리지 않으면"** 하나뿐이라
  /// **명함이 있는지는 보지 않았다.** 그래서 빈 벽이나 책상을 향해 가만히 들고
  /// 있으면 — 오히려 가장 안정적이라 — 자동으로 찍혔다(테스터 E-01
  /// "촬영 버튼을 누르지 않았는데 빈 공간이 촬영됨"). 역설적으로 빈 공간이 더
  /// 잘 찍히는 구조였다.
  ///
  /// 글자가 있는 명함은 밝고 어두운 픽셀이 섞여 표준편차가 크고(대개 25 이상),
  /// 민무늬 벽·책상은 거의 평평하다(10 미만). **낮게 잡아 명백히 빈 장면만**
  /// 막는다 — 임계값을 높이면 진짜 명함까지 자동 촬영이 안 되는데, 그쪽이 더
  /// 나쁜 고장이다(셔터는 언제든 직접 누를 수 있다).
  /// ⚠️ **이 값은 추측으로 정하면 안 된다.** 처음 10.0으로 잡았다가 진짜 명함이
  /// 자동 촬영되지 않는 회귀를 냈다(사용자 제보 2026-08-14 "조절하고 나니까
  /// 명함을 가이드가 파란색으로 변하지를 않아").
  ///
  /// 원인: 격자가 24×24로 거칠어서 **명함 글자를 거의 밟지 못한다.** 대부분의
  /// 샘플이 바탕에 떨어져 표준편차가 생각보다 훨씬 작다. 촘촘한 체커보드로
  /// 만든 테스트가 실제 샘플링 밀도를 반영하지 못했다 — 숫자만 보고 세운
  /// 가설이 틀린 또 하나의 사례다.
  ///
  /// 그래서 **민무늬 면만 겨우 걸러낼 만큼** 낮춘다. 실기기에서 실제 값을 읽어
  /// 본 뒤에 다시 조인다(디버그 빌드에 값이 화면에 뜬다).
  /// **실측으로 정했다.** 명함을 가이드에 맞췄을 때 26~39가 나왔다(사용자
  /// 측정 2026-08-14). 민무늬 벽은 센서 잡음 수준이라 한 자릿수다. 그 사이인
  /// 15로 잡아 **빈 면만 막고 명함은 넉넉히 통과**시킨다.
  ///
  /// ⚠️ 처음 10.0으로 짐작했을 때 명함이 안 찍힌다는 제보가 있었는데,
  /// **막은 것은 대비가 아니라 톤 비율이었다**(아래 참고). 숫자를 받기 전에
  /// 원인을 단정한 것이 잘못이었다.
  static const _minCenterContrast = 15.0;

  /// 가이드 안쪽에서 **한쪽 톤이 차지해야 하는 최소 비율**.
  ///
  /// 명함은 바탕이 지배적이라 대개 0.75 이상이다. 책상·벽 **모서리**는 밝은
  /// 면과 어두운 면이 반반이라 0.5 근처에 머문다 — 대비만 보면 오히려 커서
  /// 걸러지지 않던 장면이다. 밝은 명함과 어두운 명함을 모두 받으려고
  /// **더 많은 쪽**을 본다.
  /// 같은 이유로 느슨하게 잡는다. 모서리(0.5)와 명함을 가르되, 실측 전까지는
  /// **막지 않는 쪽**으로 기운다.
  /// ⚠️ **지금은 꺼져 있다(0 = 항상 통과).**
  ///
  /// 0.65로 잡았을 때 진짜 명함이 자동 촬영되지 않았다. 명함의 대비는 26~39로
  /// 넉넉했으므로 **막은 것은 이 톤 비율**이다 — 명함의 실제 톤 값이 0.65보다
  /// 작았다는 뜻인데, 그 값을 아직 재지 못했다.
  ///
  /// **재보니 이 방법으로는 못 가른다.**
  ///
  /// | 장면 | 대비 | 톤 |
  /// |---|---|---|
  /// | 명함 | 26~39 | **0.653** |
  /// | 평범한 책상 | 20.3~20.5 | **0.604~0.611** |
  ///
  /// 톤 차이가 **0.04**뿐이다. "명함은 바탕이 지배적이라 0.75 이상"이라는 내
  /// 가설이 틀렸다 — 실제 명함은 0.65 근처다. 기준을 0.63에 두면 이론상
  /// 갈리지만 여유가 0.02라 조명·각도가 조금만 달라져도 뒤집혀 **또 명함을
  /// 막는다.**
  ///
  /// 그래서 **켜지 않는다.** 각이 진 빈 곳을 가르려면 밝기가 아니라
  /// **문서 경계 검출**이 필요하다(통합본 R-02) — 별도 작업이다.
  static const _minDominantToneRatio = 0.0;

  /// "볼 것이 있는가" 게이트를 **실제로 막는 데 쓸지**.
  ///
  /// 켜져 있지만 **대비 조건만** 작동한다(톤 비율은 0이라 항상 통과).
  ///
  /// 임계값을 두 번 짐작으로 정했고 두 번 다 **진짜 명함을 막았다**(제보
  /// "파란색으로 변하지를 않아", "자동 촬영 잘 안됨"). 그래서 지금은 **실측한
  /// 값이 있는 조건만** 켠다 — 명함 대비 26~39를 재고 나서 15로 잡았다.
  ///
  /// 모서리를 가르는 톤 조건은 명함의 톤 값을 읽은 뒤에 켠다.
  static const _contentGateEnabled = true;

  late AnimationController _laserController;
  CameraController? _controller;
  bool _isInitializing = true;
  String? _initError;
  bool _isFlashOn = false;
  bool _isCapturing = false;
  bool _isStreamingForAutoCapture = false;
  bool _isFrameStable = false;

  /// 디버그 빌드에서만 화면에 띄우는 "대비 / 지배톤" 실측값.
  ///
  /// ⚠️ **매 프레임 갱신하면 읽을 수 없다** — 초당 8번 바뀌어 사용자가 값을
  /// 못 봤다(제보 "숫자가 계속 바뀌니까 못봤어"). 그래서 **본 값의 범위를
  /// 누적**하고 갱신을 0.7초에 한 번으로 늦춘다. 한 장면을 2~3초 비추면
  /// 그 장면의 대표값이 범위로 남는다. 화면의 숫자를 누르면 범위를 지운다.
  String? _debugMetrics;
  double? _debugContrastMin, _debugContrastMax;
  double? _debugToneMin, _debugToneMax;
  DateTime? _debugShownAt;
  DateTime? _stableSince;
  List<int>? _previousLumaSample;
  DateTime? _streamStartedAt;
  DateTime? _lastAnalyzedAt;

  // ───────── 명함 테두리 검출(B′) ─────────
  //
  // ⚠️ **기존 자동 촬영 판정을 지우지 않는다.** 대비·흔들림 값은 실기기에서
  // 여러 차례 다듬은 것이고(2026-08-06·08-14), 여기서는 **조건을 하나 더할
  // 뿐**이다 — "사각형이 잡혔고 + 안 흔들리면 찍는다".
  //
  // 그리고 **검출이 없어도 앱은 예전 그대로 돌아간다.** 안드로이드는 아직
  // 검출이 없고, 아이폰에서도 실패할 수 있다. 그때는 고정 가이드 상자로
  // 되돌아간다 — 최악의 경우가 지금과 같도록 만드는 것이 이 작업의 안전선이다.
  final CardRectDetector _rectDetector = CardRectDetector();

  /// 화면에 그릴 테두리(깜빡임 방지용 유지 장치).
  final CardRectHold _rectHold = CardRectHold();

  /// 카메라 센서가 몇 도 돌아 있나 — 카메라를 연 뒤에 정해진다.
  ///
  /// ⚠️ 이 값만으로 회전을 정하면 틀린다. 아이폰이 실제로 준 프레임은
  /// **이미 세로**(3024×4032)였다 — 실제 회전은 프레임 모양까지 보고
  /// [quarterTurnsForFrame]이 정한다.
  int _sensorOrientation = 0;

  /// 지금 화면에 그리고 있는 검출. null이면 고정 가이드 상자만 보인다.
  CardRectDetection? _visibleDetection;

  /// 마지막으로 **명함처럼 생긴** 사각형을 본 시각.
  ///
  /// ⚠️ 이 값을 그대로 쓰지 않고 [_hasRecentCardRect]로 나이를 본다. 검출은
  /// 비동기라 결과가 늦게 도착하는데, 그냥 bool로 들고 있으면 **명함을
  /// 치웠는데도 참으로 남아** 엉뚱한 순간에 찍힌다.
  DateTime? _lastCardRectAt;

  /// 이 화면을 연 뒤 사각형을 **한 번이라도** 찾았나.
  bool _everFoundCardRect = false;

  /// 촬영 순간에 쓰던 검출 — 크롭에 쓴다.
  CardRectDetection? _detectionAtCapture;

  /// 검출 결과가 이 시간 안에 들어왔어야 "지금 명함이 보인다"로 친다.
  ///
  /// ⚠️ **[_rectDetectionInterval]보다 넉넉히 길어야 한다.** 발열 때문에 검출
  /// 주기를 0.32초로 늘렸는데(추가 293), 예전 값 0.5초를 그대로 두면 검출이
  /// 조금만 늦어도 *"명함이 안 보인다"*가 되어 **테두리가 깜빡이고 자동 촬영이
  /// 어긋난다.** 주기의 세 배쯤 준다.
  static const _cardRectFreshness = Duration(milliseconds: 900);

  /// ⚠️ **되돌림 장치.** 스트림을 시작하고 이 시간이 지나도록 사각형을 한
  /// 번도 못 찾으면 검출 조건을 뺀다.
  ///
  /// 왜 필요한가: 검출이 붙었는데 이 기기·이 조명에서 잘 안 잡히면
  /// **자동 촬영이 통째로 죽는다.** 그건 지금보다 나쁜 상태다. 이 프로젝트는
  /// 자동 촬영 조건을 조였다가 *"파란색으로 변하지를 않아"*, *"자동 촬영 잘
  /// 안됨"* 제보를 **두 번** 받았다.
  ///
  /// ⚠️ 이 장치에는 함정이 있다 — **네이티브 등록을 빠뜨려도 똑같이 조건이
  /// 풀려 예전처럼 잘 도는 것처럼 보인다.** 그래서 [_logRectStateOnce]가
  /// "결함"과 "설계대로"를 갈라 남긴다.
  static const _cardRectGrace = Duration(seconds: 6);

  bool get _hasRecentCardRect {
    final at = _lastCardRectAt;
    return at != null && DateTime.now().difference(at) <= _cardRectFreshness;
  }

  /// 자동 촬영에 "사각형이 잡혔을 것"을 요구하나.
  bool get _requiresCardRect => requiresCardRectGate(
    supported: CardRectDetector.isSupportedOnThisPlatform,
    detectorDisabled: _rectDetector.isDisabled,
    // ⚠️ **시간이 아니라 검출기 상태로** 정한다. 예전에는 몇 초 안에 못 잡으면
    // 조건을 풀어 줬는데, 실기기에서 **빈 벽과 손바닥이 6초 뒤 그대로 찍혔다** —
    // 유예가 곧 "6초 뒤에는 아무거나 찍는다"였다(추가 293).
    detectorAnswering:
        _rectDetector.channelState == CardRectChannelState.working,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 지난번에 버려진 임시 파일을 먼저 치운다(기다리지 않는다).
    unawaited(_sweepOldScanTemp());
    // 이 화면은 **세로 전용**이다. 안내부터가 "명함을 시계 방향으로 90° 돌려서
    // 넣어주세요"이고, 가이드 프레임의 긴 변을 **화면 폭** 기준으로 잡는다.
    // 가로로 돌리면 폭이 높이보다 커져 가이드가 화면 밖으로 넘친다 — 실기기에서
    // `BOTTOM OVERFLOWED BY 52 PIXELS`가 떴다(사용자 제보 2026-08-14
    // "핸드폰을 90도 돌리니까 아래에 노란색이 보여").
    //
    // ⚠️ 그 노란 줄무늬는 **debug 빌드에서만** 보인다. release에서는 경고 없이
    // 촬영 버튼 아래 안내가 잘린다 — 보이지 않을 뿐 더 나쁘다.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (!OcrScannerService.isSupportedOnThisPlatform) {
      setState(() => _isInitializing = false);
      return;
    }
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // 검출 좌표를 화면 방향으로 되돌리는 데 쓴다 — 안 맞추면 테두리가
      // 엉뚱한 곳에 그려진다.
      _sensorOrientation = backCamera.sensorOrientation;
      controller = CameraController(
        backCamera,
        // OCR 인식률 개선 요청(2026-08-06 밤)에 대응해 veryHigh(약 1080p)
        // 에서 기기가 지원하는 최대 해상도로 올렸다 — 명함 글자가 원본에서
        // 차지하는 실제 픽셀 수가 많을수록 ML Kit 인식률이 좋아진다. 파일
        // 용량/처리 시간이 늘지만 이 화면은 어차피 한 장씩 찍는 흐름이라
        // 감내 가능한 트레이드오프로 판단.
        ResolutionPreset.max,
        enableAudio: false,
        // takePicture()의 실제 촬영 결과물 포맷과는 무관하고(항상 JPEG),
        // startImageStream()으로 안정성(흔들림) 감지용 프레임을 받아오기
        // 위한 포맷 — yuv420이 플랫폼 간 가장 널리 지원됨.
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      // 권한 요청 다이얼로그와 겹치거나 카메라가 다른 프로세스에 점유된
      // 경우 등, initialize()가 예외 없이 그냥 끝없이 대기만 하는 경우가
      // 있었다(사용자 제보 — 화면이 로딩 스피너에서 멈춤). 일정 시간 안에
      // 안 끝나면 에러로 처리해 재시도 버튼이 뜨게 한다.
      await controller.initialize().timeout(const Duration(seconds: 12));
      if (!mounted) {
        await controller.dispose();
        return;
      }
      // 명함은 보통 10~15cm 거리에서 가깝게 촬영하는데, 초점 관련 설정을
      // 전혀 안 건드리면 기기에 따라 초기 초점이 먼 거리에 맞춰진 채
      // 안 움직이거나(특히 iOS) 흐릿하게 남는 경우가 있었다(사용자 제보 —
      // "카메라 초점이 흐려"). 가이드 프레임이 있는 화면 중앙에 지속
      // 자동초점 지점을 명시적으로 지정해 근거리에서도 계속 초점을
      // 다시 잡도록 한다. 지원 안 하는 기기/플랫폼은 조용히 무시.
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
        await controller.setExposureMode(ExposureMode.auto);
        await controller.setExposurePoint(const Offset(0.5, 0.5));
      } catch (_) {}
      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
      await _startAutoCaptureStream();
    } catch (e) {
      // 타임아웃으로 포기한 뒤 initialize()가 뒤늦게 성공해도 카메라를
      // 계속 붙들고 있으면 재시도 시 "카메라 사용 중" 에러가 나므로
      // 반드시 놓아준다.
      try {
        await controller?.dispose();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _initError = '카메라를 시작할 수 없습니다.\n설정에서 카메라 접근 권한을 확인해 주세요.\n($e)';
        _isInitializing = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // 긴급재난문자 등으로 잠깐 inactive가 됐다가 바로 resumed로 돌아오는
      // 경우, 컨트롤러를 dispose하기 전에 먼저 화면(CameraPreview)에서
      // 떼어내야 한다 — setState 없이 필드만 바꾸면 아직 화면에 남아 있는
      // CameraPreview가 이미 dispose된 컨트롤러를 계속 참조하게 되어
      // 화면이 검정으로 멈춰버리는 문제가 있었다.
      final wasStreaming = _isStreamingForAutoCapture;
      setState(() {
        _controller = null;
        _isStreamingForAutoCapture = false;
        _isFrameStable = false;
        _stableSince = null;
        _isInitializing = true;
      });
      () async {
        if (wasStreaming) {
          try {
            await controller.stopImageStream();
          } catch (_) {}
        }
        await controller.dispose();
      }();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null) {
        _initCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 이 화면을 벗어나면 회전 제한을 반드시 푼다 — 안 그러면 앱 전체가 세로로
    // 묶인다.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    // 검출 일꾼(안드로이드의 별도 isolate)을 반드시 놓아준다 —
    // 안 놓으면 화면을 여닫을 때마다 isolate가 쌓인다.
    _rectDetector.dispose();
    _laserController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = !_isFlashOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _isFlashOn = next);
    } catch (_) {
      // 일부 기기는 토치를 지원하지 않음 — 조용히 무시.
    }
  }

  /// 카메라 프리뷰 스트림을 받아 연속된 프레임 간 밝기 차이(흔들림 정도)를
  /// 측정한다. 일정 프레임 이상 안정 상태가 유지되면 자동으로 촬영한다.
  /// 정밀한 카드 사각형 인식(엣지 검출)까지는 아니고 "흔들리지 않고 멈춰
  /// 있는가"만 보는 가벼운 방식이지만, 셔터를 손으로 눌러서 생기는 흔들림을
  /// 없애는 실제 목적에는 충분하다.
  Future<void> _startAutoCaptureStream() async {
    final controller = _controller;
    if (controller == null || _isStreamingForAutoCapture) return;
    _streamStartedAt = DateTime.now();
    _stableSince = null;
    _previousLumaSample = null;
    _lastAnalyzedAt = null;
    try {
      await controller.startImageStream(_onCameraFrame);
      _isStreamingForAutoCapture = true;
    } catch (_) {
      // 스트리밍이 안 되는 기기/상태면 조용히 포기 — 수동 셔터 버튼은 계속 동작.
    }
  }

  Future<void> _stopAutoCaptureStream() async {
    final controller = _controller;
    if (controller == null || !_isStreamingForAutoCapture) return;
    _isStreamingForAutoCapture = false;
    // 프레임이 끊기면 검출도 끊긴다. 마지막 테두리를 지워 **멈춘 화면 위에
    // 낡은 테두리가 남는 것**을 막는다.
    _rectHold.clear();
    _lastCardRectAt = null;
    if (mounted && _visibleDetection != null) {
      setState(() => _visibleDetection = null);
    }
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  void _onCameraFrame(CameraImage image) {
    if (_isCapturing || !mounted) return;
    final now = DateTime.now();
    final lastAnalyzedAt = _lastAnalyzedAt;
    if (lastAnalyzedAt != null &&
        now.difference(lastAnalyzedAt) < _frameAnalysisInterval) {
      return;
    }
    _lastAnalyzedAt = now;
    // 카메라가 막 열렸을 때 자동 노출/초점이 안정되기 전까지는 안정 여부
    // 판단을 건너뛴다 — 오탐(초점 잡는 중인데 "안정됨"으로 오인) 방지.
    final startedAt = _streamStartedAt;
    // 다시 찍기 직후에는 잠깐 쉰다 — 겨누고 나갈 틈을 준다.
    final blockedUntil = _autoCaptureBlockedUntil;
    if (blockedUntil != null && now.isBefore(blockedUntil)) return;
    if (startedAt != null && now.difference(startedAt) < _autoCaptureWarmup) {
      return;
    }

    // 명함 테두리 검출을 **얹는다**(B′). 결과는 늦게 도착하므로 여기서
    // 기다리지 않는다 — 기다리면 프레임 콜백이 막혀 화면이 끊긴다.
    //
    // ⚠️ `image`의 바이트는 이 콜백이 끝나면 카메라가 재사용한다. 아래
    // [CardRectDetector.detect]는 **첫 await 전에** 바이트를 읽어 채널
    // 메시지로 넘기므로 안전하다. 그 순서를 바꾸면 조용히 깨진 프레임을 본다.
    // ⚠️ 검출은 흔들림 판단보다 **드물게** 돌린다(발열).
    final lastDetectAt = _lastRectDetectAt;
    if (lastDetectAt == null ||
        now.difference(lastDetectAt) >= _rectDetectionInterval) {
      _lastRectDetectAt = now;
      unawaited(_runRectDetection(image));
    }

    final sample = _sampleLuma(image);
    final previous = _previousLumaSample;
    _previousLumaSample = sample;
    if (previous == null || previous.length != sample.length) return;

    double diffSum = 0;
    for (var i = 0; i < sample.length; i++) {
      diffSum += (sample[i] - previous[i]).abs();
    }
    final avgDiff = diffSum / sample.length;

    // 흔들리지 않는 것만으로는 부족하다 — **가이드 안에 볼 것이 있어야** 한다.
    // 대비 하나로는 모자랐다. 책상·벽 모서리처럼 **각이 진 빈 곳**은 밝은 면과
    // 어두운 면이 반반이라 대비가 오히려 크다(사용자 제보 "빈공간을 찍지는
    // 않는데 각이진 빈곳은 자동 촬영되").
    //
    // 명함은 **바탕이 지배적**이고 글자가 소수다 — 밝든 어둡든 한쪽 톤이
    // 대부분이다. 모서리 장면은 대략 반반이라 여기서 갈린다.
    final contrast = centerFrameContrast(sample, gridSize: _sampleGridSize);
    final dominantTone = centerDominantToneRatio(
      sample,
      gridSize: _sampleGridSize,
    );
    final wouldBlock =
        contrast < _minCenterContrast || dominantTone < _minDominantToneRatio;
    // 게이트가 꺼져 있으면 판단만 하고 막지는 않는다 — 위 상수 주석 참고.
    final hasContent = _contentGateEnabled ? !wouldBlock : true;

    // 임계값을 추측으로 정했다가 진짜 명함을 막는 회귀를 냈다. 실기기에서
    // **실제 장면의 값을 읽을 수 있어야** 제대로 정할 수 있다 — 디버그
    // 빌드에서만 화면에 띄운다(테스터 배포는 release라 보이지 않는다).
    if (kDebugMode) {
      _debugContrastMin = _debugContrastMin == null
          ? contrast
          : math.min(_debugContrastMin!, contrast);
      _debugContrastMax = _debugContrastMax == null
          ? contrast
          : math.max(_debugContrastMax!, contrast);
      _debugToneMin = _debugToneMin == null
          ? dominantTone
          : math.min(_debugToneMin!, dominantTone);
      _debugToneMax = _debugToneMax == null
          ? dominantTone
          : math.max(_debugToneMax!, dominantTone);
      final shownAt = _debugShownAt;
      if (shownAt == null ||
          now.difference(shownAt) >= const Duration(milliseconds: 700)) {
        _debugShownAt = now;
        final text =
            '대비 ${_debugContrastMin!.toStringAsFixed(1)}'
            '~${_debugContrastMax!.toStringAsFixed(1)} · '
            '톤 ${_debugToneMin!.toStringAsFixed(2)}'
            '~${_debugToneMax!.toStringAsFixed(2)}'
            '${wouldBlock ? ' · 지금이면 막힘' : ''}';
        if (text != _debugMetrics) setState(() => _debugMetrics = text);
        // 화면의 작은 글씨는 읽기 어렵다는 제보가 있었다. 같은 값을 로그로도
        // 남겨 `adb logcat`으로 뽑을 수 있게 한다 — 사람이 카메라를 향하게
        // 하고, 값은 기계가 읽는 쪽이 정확하다.
        //
        // ⚠️ 숫자만 남긴다. 명함 내용은 찍지 않는다(개인정보, CLAUDE.md 4절).
        debugPrint(
          '[CARDGATE] contrast=${contrast.toStringAsFixed(1)} '
          'tone=${dominantTone.toStringAsFixed(3)} '
          'stableDiff=${avgDiff.toStringAsFixed(1)} '
          'wouldBlock=$wouldBlock',
        );
      }
    }

    // 검출이 붙어 있으면 **"사각형이 잡혔을 것"까지 요구한다**(B′). 붙어
    // 있지 않거나(안드로이드) 이 기기에서 잘 안 잡히면 [_requiresCardRect]가
    // false가 되어 예전 판정 그대로 돈다.
    final rectOk = !_requiresCardRect || _hasRecentCardRect;
    if (!kReleaseMode) _logRectStateOnce();

    if (avgDiff < _stabilityDiffThreshold && hasContent && rectOk) {
      _stableSince ??= now;
    } else {
      _stableSince = null;
    }

    final stableSince = _stableSince;
    final nowStable = stableSince != null;
    if (nowStable != _isFrameStable) {
      setState(() => _isFrameStable = nowStable);
    }

    if (stableSince != null &&
        now.difference(stableSince) >= _requiredStableDuration) {
      _stableSince = null;
      _capturePhoto();
    }
  }

  /// 마지막 검출이 떨어진 이유(디버그 화면용).
  CardShapeVerdict? _lastRectVerdict;

  /// 마지막으로 화면에 띄운 진단 요약(갱신 판단용).
  String? _lastDiagSummary;

  /// 마지막 크롭의 **긴 변**(px). 검출 크롭이 아니었으면 null.
  ///
  /// ⚠️ **촬영 거리가 그대로 해상도가 된다**(2026-08-16 실측).
  ///
  /// | 거리 | 크롭 긴 변 | 명함 90mm 기준 |
  /// |---|---|---|
  /// | 가까이 | 1,786px | 약 390dpi |
  /// | 멀리 | **993px** | 약 **280dpi** ← 문서 스캔 표준 미달 |
  ///
  /// 기존 경로는 가이드 상자를 **고정 크기**로 잘라 거리와 무관하게 2,000px대가
  /// 나왔다. 검출 크롭은 명함에 딱 맞게 자르므로 이 전제가 깨진다.
  ///
  /// 그리고 이 크롭이 **곧 OCR 입력**이다 — `card_photo_downscale.dart`가
  /// *"축소를 크롭 단계에 넣으면 인식률이 떨어진다"*고 경고하는 그 자리에,
  /// 이제 **촬영 거리**가 들어앉았다.
  ///
  /// 막지는 않는다(사용자 결정 2026-08-16). **확인 화면에서 알리기만** 하고,
  /// 다시 찍을지는 사용자가 고른다 — 이미 *"글자가 또렷한가요?"* 관문이 있다.
  int? _lastCropLongEdge;

  /// ⚠️ 측정 전용 — 마지막으로 남긴 측정본 파일 이름. 277이 끝나면 지운다.
  String? _lastMeasureSavedName;

  /// 마지막 크롭 결과 요약(release 빌드 제외).
  ///
  /// ⚠️ **이 숫자가 이번 작업의 갈림길이다.** 잘라낸 긴 변이 축소 임계
  /// (1,600px)를 넘지 않으면 `contact_image_service`가 축소를 건너뛰고,
  /// 저장본이 커져 **무료 200장 한도의 근거가 흔들린다**(인계 문서 5절).
  ///
  /// 로그로 확인할 수 없는 기기라 **확인 화면에 띄운다** — `flutter run`이
  /// 앱에 못 붙고 `idevicesyslog`에도 앱 로그가 안 올라온다(2026-08-16 실측).
  String? _lastCropSummary;

  /// 검출이 지금 어떤 상태인지 **한 줄로** 만든다(release 빌드 제외).
  ///
  /// ⚠️ 화면에 이 줄이 보이는 것 자체가 **새 빌드가 깔렸다는 증거**다.
  /// 이 기기에서는 `flutter run`이 앱에 못 붙고 `idevicesyslog`에도 앱
  /// 로그가 안 올라온다(2026-08-16 실측) — **화면이 유일한 창구**다.
  String _rectDebugLabel() {
    final state = switch (_rectDetector.channelState) {
      CardRectChannelState.unknown => '대기',
      CardRectChannelState.working => '검출기OK',
      CardRectChannelState.missing => '⚠️검출기없음(결함)',
      CardRectChannelState.failing => '⚠️검출기오류(결함)',
    };
    final found = _visibleDetection != null
        ? '명함잡힘'
        : (_lastRectVerdict == null ? '후보없음' : '떨어짐:${_lastRectVerdict!.name}');
    final gate = _requiresCardRect ? '조건적용' : '조건해제';
    final diag = _rectDetector.lastDiagnostics;
    final diagLine = diag == null ? '' : '\n${diag.summary}';
    return '$state · $found · $gate$diagLine';
  }

  bool _rectStateLogged = false;

  /// ⚠️ **"검출이 안 붙었다"와 "검출이 붙었는데 못 찾았다"를 갈라 적는다.**
  ///
  /// 6초 폴백([_cardRectGrace])에는 함정이 하나 있다 — **네이티브 등록을
  /// 빠뜨려도 6초 뒤 조건이 풀려 자동 촬영이 정상 동작한다.** 화면상으로는
  /// 예전과 똑같이 멀쩡해 보이므로, 그대로 두면 다음 사람이 *"폴백 잘 되네"*로
  /// 읽고 넘어간다.
  ///
  /// | 로그 | 성격 |
  /// |---|---|
  /// | 채널 없음 · 채널 오류 | **결함** — 고쳐야 한다 |
  /// | 채널 정상, 미검출 | **설계대로** — 조명·거리 문제 |
  void _logRectStateOnce() {
    if (_rectStateLogged) return;
    if (!CardRectDetector.isSupportedOnThisPlatform) return;
    // ⚠️ **일부러 끈 것을 결함처럼 알리지 않는다**(2026-08-17 측정 중 발견).
    //
    // 2단계 대조에서 검출 스위치를 내리자 *"검출기를 한 번도 부르지
    // 못했습니다"*가 떴다. **정상 동작인데 결함 문구가 나온 것**이다 —
    // 그대로 두면 다음 사람이 **없는 문제를 찾는다.**
    if (!cardRectDetectionEnabled.value) {
      _rectStateLogged = true;
      debugPrint('[CARDRECT] 검출 꺼짐(측정 스위치) — 기존 고정 가이드로 돕니다');
      return;
    }
    final startedAt = _streamStartedAt;
    if (startedAt == null) return;

    if (_everFoundCardRect) {
      _rectStateLogged = true;
      debugPrint('[CARDRECT] 검출기 정상 — 사각형 검출 확인됨');
      return;
    }
    if (DateTime.now().difference(startedAt) < _cardRectGrace) return;

    _rectStateLogged = true;
    switch (_rectDetector.channelState) {
      case CardRectChannelState.missing:
        debugPrint(
          '[CARDRECT] ⚠️ 결함: 검출기를 띄우지 못했습니다. '
          '아이폰이면 AppDelegate 등록, 안드로이드면 isolate를 확인하십시오 '
          '— 기존 가이드로 폴백합니다',
        );
      case CardRectChannelState.failing:
        debugPrint('[CARDRECT] ⚠️ 결함: 검출기 오류·지연이 반복됩니다 — 기존 가이드로 폴백합니다');
      case CardRectChannelState.working:
        debugPrint(
          '[CARDRECT] 설계대로: 검출기는 정상인데 '
          '${_cardRectGrace.inSeconds}초간 사각형을 못 찾아 조건을 해제합니다',
        );
      case CardRectChannelState.unknown:
        debugPrint('[CARDRECT] ⚠️ 검출기를 한 번도 부르지 못했습니다 — 프레임이 들어오는지 확인하십시오');
    }
  }

  /// 프레임 한 장을 검출기에 보내고, 결과를 화면·자동 촬영 판정에 반영한다.
  ///
  /// ⚠️ **테두리를 그리는 값과 자동 촬영에 쓰는 값을 나눈다.**
  ///
  /// | | 무엇을 쓰나 | 왜 |
  /// |---|---|---|
  /// | 테두리 그리기 | [_rectHold]가 잠깐 붙잡아 둔 값 | 한두 프레임 비어도 안 깜빡이게 |
  /// | 자동 촬영 판정 | [_lastCardRectAt]의 **나이** | 명함을 치웠는데 찍히면 안 되니까 |
  ///
  /// 붙잡아 둔 값으로 촬영까지 판단하면 **유지 시간 동안은 명함이 없어도
  /// 찍힌다.** 실기기에서야 드러나는 종류의 결함이라 여기서 갈라 둔다.
  Future<void> _runRectDetection(CameraImage image) async {
    final detection = await _rectDetector.detect(
      image,
      sensorOrientation: _sensorOrientation,
    );
    if (!mounted) return;

    final now = DateTime.now();
    final isCard = detection?.isCardLike ?? false;
    if (isCard) {
      _lastCardRectAt = now;
      _everFoundCardRect = true;
    }

    // 명함으로 판정된 것만 그린다 — 책상 모서리에 테두리가 붙으면 사용자는
    // 앱이 잘못 보고 있다고 읽는다.
    _rectHold.update(isCard ? detection : null, now);
    final visible = _rectHold.visibleAt(now);
    final verdict = detection?.verdict;
    // 디버그 줄의 숫자도 갱신돼야 한다 — 안 그러면 처음 값에서 멈춰
    // **화면을 보고 판정할 수 없다**(이 기기에서는 로그를 못 본다).
    final diagSummary = _rectDetector.lastDiagnostics?.summary;
    if (visible != _visibleDetection ||
        (!kReleaseMode &&
            (verdict != _lastRectVerdict || diagSummary != _lastDiagSummary))) {
      setState(() {
        _visibleDetection = visible;
        _lastRectVerdict = verdict;
        _lastDiagSummary = diagSummary;
      });
    }

    // ⚠️ **판정과 숫자를 함께 남긴다**(2026-08-17 측정 중 추가).
    //
    // 판정 이름만 있으면 *"얼마나 모자랐는지"*를 몰라 기준을 **또 짐작으로**
    // 고치게 된다 — 이 프로젝트가 두 번 그렇게 하다가 진짜 명함을 막았다.
    //
    // 안드로이드는 로그가 잡히므로 화면을 안 보고도 재는 값을 모을 수 있다
    // (아이폰은 로그가 안 올라와 화면으로만 본다).
    //
    // ⚠️ 초당 8번 찍으면 정작 볼 로그가 묻힌다 — **1초에 한 번**으로 줄인다.
    if (!kReleaseMode && detection != null) {
      final shownAt = _lastRectLogAt;
      if (shownAt == null ||
          now.difference(shownAt) >= const Duration(seconds: 1)) {
        _lastRectLogAt = now;
        debugPrint(
          '[CARDRECT] ${isCard ? "잡힘" : "떨어짐:${detection.verdict.name}"}'
          ' · ${diagSummary ?? ""}',
        );
      }
    }
  }

  /// 위 로그를 1초에 한 번으로 줄이기 위한 시각.
  DateTime? _lastRectLogAt;

  /// 프레임 전체를 다 볼 필요 없이 Y(밝기) 평면에서 격자 형태로 샘플링만
  /// 해서 가볍게 비교한다 — 매 프레임 호출되므로 연산량을 최소화해야 함.
  List<int> _sampleLuma(CameraImage image) {
    final plane = image.planes.first;
    final bytesPerRow = plane.bytesPerRow;
    final height = image.height;
    final width = image.width;
    final result = <int>[];
    for (var gy = 0; gy < _sampleGridSize; gy++) {
      final y = (gy * height ~/ _sampleGridSize).clamp(0, height - 1);
      for (var gx = 0; gx < _sampleGridSize; gx++) {
        final x = (gx * width ~/ _sampleGridSize).clamp(0, width - 1);
        final index = y * bytesPerRow + x;
        if (index >= 0 && index < plane.bytes.length) {
          result.add(plane.bytes[index]);
        }
      }
    }
    return result;
  }

  /// 촬영은 했지만 아직 인식(OCR)을 돌리지 않은 사진.
  ///
  /// 예전에는 셔터를 누르면 곧바로 인식까지 하고 화면을 닫았다. 그래서 **초점이
  /// 나간 사진도 그대로 인식**됐고(테스터 E-04), 사용자는 결과를 본 뒤에야
  /// 잘못 찍은 걸 알았다. 인식 전에 한 번 보여주고 [다시 찍기]/[확인]을 받는다.
  XFile? _pendingShot;

  /// 확인 화면에서 사용자가 [↻ 회전]으로 더 돌린 각도(F-03).
  ///
  /// 자동 크롭이 항상 **반시계 90도로 세워 주는데**, 명함을 가이드에 반대
  /// 방향으로 넣으면 그 고정 각도 때문에 **반드시 뒤집힌 채로 나온다.**
  /// 지금까지는 되돌릴 방법이 재촬영뿐이었다 — 명함 주인 앞에서 여러 번 다시
  /// 찍는 것은 실제 사용 맥락에서 부담이다.
  ///
  /// **파일이 아니라 각도만 들고 있는다.** 누를 때마다 다시 구우면 매번
  /// JPEG을 재압축해 화질이 깎인다. 굽는 것은 [_confirmPendingShot]에서
  /// 한 번뿐이고, 네 번 눌러 제자리로 온 경우에는 아예 굽지 않는다.
  int _pendingRotation = 0;

  /// 중간에 버려진 촬영이 남긴 임시 파일을 쓸어 담는다(2026-08-16).
  ///
  /// 등록하지 않고 화면을 닫으면 크롭·회전 결과가 남는다. **1시간이 지난
  /// 것만** 지운다 — 지금 쓰고 있는 파일을 건드리지 않기 위한 안전선이다.
  Future<void> _sweepOldScanTemp() async {
    await sweepScanTemp(Directory.systemTemp);
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isCapturing)
      return;

    // 스트림을 멈추면 검출도 멈춘다. **멈추기 전에** 지금 보고 있던 사각형을
    // 붙잡아 둔다 — 이 값으로 자른다.
    _detectionAtCapture = _rectHold.visibleAt(DateTime.now());

    // takePicture()는 이미지 스트림이 활성화된 상태에서 호출하면 실패하는
    // 기기가 있어서, 촬영 직전엔 항상 스트림을 먼저 멈춘다.
    await _stopAutoCaptureStream();

    setState(() {
      _isCapturing = true;
      _isFrameStable = false;
      _stableSince = null;
    });

    try {
      final rawFile = await controller.takePicture();
      if (!mounted) return;
      final screenSize = MediaQuery.of(context).size;
      // 검출된 테두리대로 자른다(B′). **실패하면 기존 고정 가이드 크롭으로
      // 되돌아간다** — 최악의 경우가 지금과 같아야 한다.
      _lastCropLongEdge = null;
      if (!kReleaseMode) _lastCropSummary = null;
      var croppedFile = await _cropByDetectedQuad(rawFile, screenSize);
      if (croppedFile == null) {
        // ⚠️ 어느 경로로 잘렸는지 화면에 남긴다 — 안 남기면 검출 크롭과
        // 폴백 크롭을 결과만 보고 구분할 수 없다.
        // ⚠️ 아래 `_cropToGuideFrame`이 자기 숫자를 채운다. 여기서는
        // **어느 경로로 갔는지만** 남긴다 — 그 구분이 없으면 결과만 보고
        // 검출 크롭과 폴백 크롭을 나눌 수 없다.
        final wasDetection =
            cardRectCropEnabled.value &&
            (_detectionAtCapture?.isCardLike ?? false);
        croppedFile = await _cropToGuideFrame(rawFile, screenSize);
        if (!kReleaseMode && wasDetection) {
          _lastCropSummary = '⚠️ 검출 크롭 실패 → ${_lastCropSummary ?? "가이드 폴백"}';
        }
      }

      // 촬영 원본은 크롭이 끝나면 쓰이지 않는다. **평문이므로 바로 지운다**
      // (2026-08-16). 실기기에서 이 파일들이 83장·198.5MB 쌓여 있었고,
      // 저장된 명함은 16장뿐이었다 — 등록하지 않고 버린 촬영분까지 전부
      // 남아 있었다는 뜻이다. 저장본을 암호화하는 이유가 무력해진다.
      //
      // ⚠️ 크롭이 실패하면 원본을 그대로 돌려주므로(같은 경로) 그때는
      // 지우지 않는다. 지우면 방금 찍은 사진이 사라진다.
      if (croppedFile.path != rawFile.path) {
        await deleteQuietly(rawFile.path);
      }

      if (!mounted) return;
      // 바로 인식하지 않고 먼저 보여준다 — 흐린 사진으로 인식을 돌리는 낭비와
      // "결과를 봐야 잘못 찍은 걸 아는" 문제를 없앤다.
      setState(() {
        _pendingShot = croppedFile;
        _isCapturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCapturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 명함 인식에 실패했습니다: $e'),
          backgroundColor: AppColors.destructive,
        ),
      );
      // 실패해서 다시 화면이 보이는 상태로 남으면, 재시도할 수 있게 안정성
      // 감지를 다시 시작한다.
      await _startAutoCaptureStream();
    }
  }

  /// 보여준 사진으로 인식을 진행한다.
  ///
  /// ⚠️ **화면에서 돌린 각도를 파일에 반영한 뒤 인식한다.** 미리보기만 돌리고
  /// 원본으로 인식하면 사용자가 본 것과 인식 결과가 어긋난다 — 이 저장소에서
  /// 반복된 "코드는 맞는데 실물이 틀린" 유형이 나는 자리다.
  Future<void> _confirmPendingShot() async {
    final shot = _pendingShot;
    if (shot == null) return;
    setState(() => _isCapturing = true);
    XFile? baked;
    try {
      baked = await _bakeRotation(shot, _pendingRotation);

      // ⚠️ **측정 전용 — 277이 끝나면 지운다.**
      //
      // 2단계 대조에 쓸 크롭본을 `card_samples`에 남긴다. 일괄 스캔이 그
      // 폴더를 읽는데, 크롭본은 임시 파일이라 여기를 지나면 지워진다 —
      // 그 한 칸을 잇는 것이다.
      //
      // ⚠️ release에서는 `kDebugMode` 때문에 **코드가 아예 안 돈다.**
      // 스위치가 켜져 있어도 마찬가지다.
      //
      // 어느 경로로 찍었는지를 파일 이름에 남긴다 — 그래야 경로별로 갈라
      // 채점할 수 있다.
      final keptPath = await keepCropForMeasurement(
        File(baked.path),
        pathLabel: cardRectCropEnabled.value ? 'on' : 'off',
      );
      if (keptPath != null && mounted) {
        // ⚠️ 저장 **경로**를 보여 준다. "저장했습니다"만으로는 정말 생겼는지
        // 알 수 없다 — 이 저장소가 여러 번 겪은 자리다.
        setState(() => _lastMeasureSavedName = keptPath.split('/').last);
      }

      final scanResult = await OcrScannerService.scanBusinessCard(baked);
      // ⚠️ 회전을 구우면 **평문 파일이 둘이 된다**(2026-08-16 실기기 확인).
      //
      //   크롭  card_scan_*.jpg  ← 여기서 지운다. 인식이 끝나면 아무도 안 쓴다
      //   회전  card_rot_*.jpg   ← 넘겨받은 쪽이 저장 후 지운다
      //
      // 저장 지점(ContactImageService)은 넘겨받은 경로 하나만 지우므로,
      // 회전을 누른 촬영마다 크롭본이 1MB씩 캐시에 남아 있었다. 저장본을
      // 암호화하는 이유 자체를 무력화한다.
      //
      // 인식이 **끝난 뒤에** 지운다 — 확인 화면이 이 파일을 그리는 중이라
      // 굽자마자 지우면 다시 그릴 때 빈 파일을 읽는다.
      if (baked.path != shot.path) await deleteQuietly(shot.path);
      if (!mounted) return;
      Navigator.pop(context, scanResult);
    } catch (e) {
      // 인식이 실패하면 이 사진은 버려진다(아래에서 `_pendingShot`을 비운다).
      // 둘 다 넘겨줄 곳이 없으므로 여기서 지운다 — 이 경로도 새고 있었다.
      await deleteQuietly(shot.path);
      if (baked != null && baked.path != shot.path) {
        await deleteQuietly(baked.path);
      }
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _pendingShot = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ 명함 인식에 실패했습니다: $e'),
          backgroundColor: AppColors.destructive,
        ),
      );
      await _startAutoCaptureStream();
    }
  }

  /// 방금 찍은 사진을 버리고 다시 촬영 상태로 돌아간다.
  Future<void> _retakePendingShot() async {
    // 버리는 사진은 확실히 안 쓰인다. 여기서 지운다(2026-08-16).
    await deleteQuietly(_pendingShot?.path);
    setState(() {
      _pendingShot = null;
      // 돌려 둔 각도도 함께 버린다 — 다시 찍은 사진에 앞 사진의 각도가
      // 따라붙으면 사용자가 돌린 적 없는 방향으로 나온다.
      _pendingRotation = 0;
      _isCapturing = false;
      _autoCaptureBlockedUntil = DateTime.now().add(_retakeCooldown);
    });
    await _startAutoCaptureStream();
  }

  /// 손으로 자르기(F-03, 추가 290).
  ///
  /// 자동 테두리 검출을 기본으로 쓰지 않기로 하면서, 자동이 잘못 잘랐을 때
  /// **사람이 고칠 길이 없었다.** 지금까지는 다시 찍는 것이 유일했다.
  ///
  /// ⚠️ **회전을 먼저 굽는다.** 화면에서 돌린 각도와 자르는 좌표를 함께
  /// 다루면 좌표계가 둘이 되고, 그건 실기기에서만 드러나는 종류의 어긋남이다
  /// (추가 273). 똑바로 선 사진을 넘기고, 돌아온 뒤에는 각도를 0으로 되돌린다.
  ///
  /// ⚠️ **자동 자르기가 쓰는 워프를 그대로 쓴다.** 새 자르기 코드를 만들지
  /// 않는다 — 만들면 두 코드가 서로 다르게 틀리기 시작한다.
  Future<void> _cropPendingShotByHand() async {
    final shot = _pendingShot;
    if (shot == null || _isCapturing) return;

    final upright = await _bakeRotation(shot, _pendingRotation);
    if (!mounted) return;

    final picked = await Navigator.of(context).push<ManualCropResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ManualCropView(imagePath: upright.path),
      ),
    );
    if (!mounted) return;

    if (picked == null || picked.corners.length != 4) {
      // 취소했다 — 구운 파일이 원본과 다르면 버린다.
      if (upright.path != shot.path) await deleteQuietly(upright.path);
      return;
    }

    setState(() => _isCapturing = true);
    try {
      final outPath =
          '${Directory.systemTemp.path}/card_scan_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await compute(
        warpCardToFile,
        CardWarpRequest(
          sourcePath: upright.path,
          // ⚠️ 화면 크기를 **사진 비율과 같게** 준다. 그러면 워프가 쓰는
          // "가시 영역"이 사진 전체가 되어, 정규 좌표가 그대로 통한다.
          // 새 좌표 변환을 만들지 않으려는 것이다.
          visibleCornersFlat: [
            for (final c in picked.corners) ...[c.dx, c.dy],
          ],
          screenWidth: picked.imageSize.width,
          screenHeight: picked.imageSize.height,
          outputPath: outPath,
          // 사람이 모서리를 직접 짚었으니 여백을 더하지 않는다.
          margin: 0,
        ),
      );
      if (!mounted) return;
      if (result == null) {
        _toastCropFailed();
        return;
      }
      // 자른 결과가 새 원본이 된다. 이전 것들은 버린다.
      final previous = shot.path;
      setState(() {
        _pendingShot = XFile(result.path);
        _pendingRotation = 0;
        _lastCropLongEdge = result.longEdge;
      });
      if (upright.path != previous) await deleteQuietly(upright.path);
      await deleteQuietly(previous);
    } catch (_) {
      if (mounted) _toastCropFailed();
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _toastCropFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('자르지 못했습니다. 다시 해 주세요.')));
  }

  /// 화면에서 돌린 각도를 실제 이미지에 굽는다(F-03).
  ///
  /// [degrees]가 0이면 **원본을 그대로 돌려준다** — 네 번 눌러 제자리로 온
  /// 것을 다시 인코딩하면 화질만 깎이고 결과는 같다.
  ///
  /// 실패하면 원본을 쓴다. 회전을 못 했다고 인식 자체를 막는 것보다, 방향이
  /// 어긋난 채로라도 인식을 진행하는 편이 낫다 — [_cropToGuideFrame]이
  /// 크롭 실패 시 원본을 쓰는 것과 같은 판단이다.
  ///
  /// ⚠️ **새 파일을 만들 때 원본을 지우지 않는다.** 확인 화면이 아직 원본을
  /// 그리고 있기 때문이다. 지우는 책임은 부르는 쪽([_confirmPendingShot])에
  /// 있다 — 돌려준 경로가 [source]와 다르면 원본은 버려진 것이다.
  Future<XFile> _bakeRotation(XFile source, int degrees) async {
    if (!needsRebake(degrees)) return source;
    try {
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return source;
      final rotated = img.copyRotate(decoded, angle: normalizeTurn(degrees));
      final jpgBytes = img.encodeJpg(rotated, quality: 100);
      final outPath =
          '${Directory.systemTemp.path}/card_rot_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(jpgBytes);
      return XFile(outPath);
    } catch (_) {
      return source;
    }
  }

  /// 가이드 박스의 실제 픽셀 크기를 현재 화면 크기 기준으로 계산한다.
  /// 명함의 긴 변(90mm)이 화면에서 차지하는 크기를 화면 "폭"의 86%로 고정
  /// 한다 — 가로 모드였을 때 긴 변(가로)을 이 기준으로 잡았던 것과 동일한
  /// 값이다. 세로 가이드로 바뀌면서 긴 변이 세로가 됐다고 화면 "높이"
  /// 기준(예: 0.62)으로 잡으면, 화면 높이가 폭보다 훨씬 크기 때문에 실제
  /// 화면에 표시되는 카드 이미지가 훨씬 커지고, 그만큼 사용자가 카메라를
  /// 명함에 더 가깝게 대야 한다 — 그 결과 카메라 렌즈의 최소 초점 거리보다
  /// 가까워져 초점이 영영 안 맞는 문제가 있었다(2026-08-06 실기기 확인,
  /// "가이드에 맞추려 가까이 가면서 초점을 못맞춤"). 촬영 거리를 가로
  /// 모드 때와 동일하게 유지하는 게 핵심이라, 긴 변 크기는 화면 폭 기준을
  /// 그대로 쓰고 짧은 변은 비율로 계산한다. 화면이 유난히 작아 긴 변이
  /// 세로 공간을 넘칠 때만 안전장치로 줄인다.
  /// 가이드 상자보다 **얼마나 넓게 자르는지**.
  ///
  /// ⚠️ **자르는 쪽과 그리는 쪽이 같은 값을 봐야 한다.** 예전에는 자르는 쪽에만
  /// 있어서, 화면의 흰 상자는 *"여기까지 나옵니다"*처럼 보이는데 실제로는 20%
  /// 더 나왔다 — 실기기에서 *"찍힌 결과가 가이드와 맞지 않는다"*로 나타났다
  /// (추가 293). 값은 그대로 두고 **보이게** 했다.
  ///
  /// 📌 이 값을 줄이면 안 된다. 0으로 만든 적이 있고 그때 **글자가 30~40%
  /// 잘렸다**(사용자 제보 2026-08-14). 자세한 내력은 쓰는 쪽 주석에 있다.
  static const kGuideCropMargin = 1.2;

  /// 가이드 상자의 **긴 변이 화면 폭에서 차지하는 비율**.
  ///
  /// ## ⚠️ 줄일 때는 반드시 실기기에서 **초점**을 확인할 것
  ///
  /// 이 값을 줄이면 사용자가 명함을 **더 가까이** 대게 된다. 예전에 가이드를
  /// 화면 **높이** 기준으로 잡았다가, 렌즈 최소 초점 거리보다 가까워져
  /// **초점이 영영 안 맞는** 문제가 있었다(2026-08-06 실기기,
  /// *"가이드에 맞추려 가까이 가면서 초점을 못맞춤"*).
  ///
  /// ## 왜 줄였나 (2026-08-17, 추가 293)
  ///
  /// 실기기에서 *"흰색 가이드가 너무 크네"* — 가이드가 화면을 거의 채워서
  /// 명함이 가운데 작게 놓이고, **찍힌 사진에 배경이 많이 들어갔다**
  /// (`가이드 크롭 1636x2934`).
  ///
  /// 📌 배경이 많이 들어가는 **근본 원인은 가이드가 큰 것**이지 자르기 여유가
  /// 아니다. 여유([kGuideCropMargin])는 글자 잘림을 막는 장치라 건드리지 않았다.
  ///
  /// 0.86 → 0.74로 **한 단계만** 줄였다. 이 저장소는 이런 값을 크게 바꿨다가
  /// 두 번 되돌린 적이 있다(자르기 여유 1.5 → 1.0 → 1.2).
  static const kGuideLongEdgeRatio = 0.74;

  Size _guideFrameSizeFor(Size screenSize) {
    var longEdge = screenSize.width * kGuideLongEdgeRatio;
    // 화면이 낮으면(가로 방향, 폴더블 펼침) 가이드가 세로로 넘친다. 위아래
    // 안내 문구와 촬영 버튼이 함께 들어가야 하므로 **높이의 0.72까지만** 쓴다.
    //
    // ⚠️ 예전 상한은 0.8이었는데, 그것만으로는 모자라 가로에서
    // `BOTTOM OVERFLOWED BY 52 PIXELS`가 떴다(사용자 제보 "핸드폰을 90도
    // 돌리니까 아래에 노란색이 보여"). 세로 고정(`setPreferredOrientations`)도
    // 함께 걸었지만 **Android는 큰 화면에서 앱의 방향 제한을 무시한다** —
    // 폴더블 펼친 화면에서는 여전히 가로가 되므로 크기 자체를 맞춰야 한다.
    final maxLongEdge = screenSize.height * 0.72;
    if (longEdge > maxLongEdge) longEdge = maxLongEdge;
    final shortEdge = longEdge * _cardAspectRatio;
    return Size(shortEdge, longEdge);
  }

  /// 화면에 보이는 가이드 프레임(카드 사각형) 위치를 실제 촬영본의 픽셀 좌표로
  /// 환산해 크롭한다. 프리뷰는 [_buildCameraPreview]에서 cover 방식(화면을
  /// 꽉 채우고 넘치는 부분은 잘림)으로 그리므로, 화면 중심 기준 비율을 그대로
  /// 이미지에 적용하면 동일한 영역이 나온다. 명함 주변 배경 글자/노이즈를
  /// 제거해 OCR 인식률을 높이는 게 목적이며, 실제 명함 규격이 제각각이라
  /// (표준 90x50mm 외에도 크고 작은 변형이 흔함) 계산이 살짝 어긋나거나
  /// 카드가 가이드보다 커도 잘리지 않도록 가이드 프레임보다 30% 여유를 두고
  /// 크롭 범위를 화면 안으로 clamp한다.
  /// 검출된 테두리대로 잘라서 편다(B′). 검출이 없거나 실패하면 **null**을
  /// 돌려주고, 부르는 쪽은 기존 [_cropToGuideFrame]으로 되돌아간다.
  ///
  /// ⚠️ **별도 isolate에서 돌린다.** 원근 보정은 결과 픽셀 하나마다 원본에서
  /// 네 점을 읽어 섞는 일이라, 200만 픽셀이면 그만큼 반복한다. 본 스레드에서
  /// 돌리면 촬영 직후 확인 화면으로 넘어가는 동안 화면이 멈춘 것처럼 보인다.
  ///
  /// ⚠️ **결과 크기를 로그로 남긴다.** 잘라낸 긴 변이 축소 임계(1,600px)를
  /// 넘는지가 이 작업의 갈림길이다 — 안 넘으면 `contact_image_service`가
  /// 축소를 건너뛰어 저장본이 커지고 **무료 200장 한도의 근거가 흔들린다.**
  Future<XFile?> _cropByDetectedQuad(XFile rawFile, Size screenSize) async {
    // ⚠️ **검출이 켜졌다고 자르기까지 바꾸지 않는다**(추가 293).
    //
    // 예전에는 스위치 하나가 둘을 같이 켰다. 검출을 "빈 화면 막기"에만 쓰기로
    // 하면서 갈랐다 — 자르기는 추가 277에서 **안 쓰기로 정한 것**이라
    // 기본 꺼짐이다. 이 줄이 없으면 검출을 켜는 순간 자르기까지 B′로 바뀐다.
    if (!cardRectCropEnabled.value) return null;
    final detection = _detectionAtCapture;
    if (detection == null || !detection.isCardLike) return null;

    try {
      // 표시 좌표 → 가시 좌표(화면에 보이는 영역 기준).
      final visibleQuad = displayQuadToVisibleQuad(
        detection.quad,
        detection.displaySize,
        screenSize,
      );

      final outPath =
          '${Directory.systemTemp.path}/card_scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await compute(
        warpCardToFile,
        CardWarpRequest(
          sourcePath: rawFile.path,
          visibleCornersFlat: cornersToFlat(visibleQuad.corners),
          screenWidth: screenSize.width,
          screenHeight: screenSize.height,
          outputPath: outPath,
        ),
      );
      if (result == null) return null;
      _lastCropLongEdge = result.longEdge;

      if (!kReleaseMode) {
        // ⚠️ 숫자만 남긴다. 명함 내용은 찍지 않는다(CLAUDE.md 4절).
        final over = result.longEdge > 1600;
        _lastCropSummary =
            '크롭 ${result.width}x${result.height} · 긴변 ${result.longEdge}'
            ' · 축소임계(1600) ${over ? "넘음 ✅" : "못넘음 ⚠️"}'
            ' · ${result.elapsedMs}ms';
        debugPrint('[CARDRECT] $_lastCropSummary');
      }
      return XFile(result.path);
    } catch (_) {
      // 원근 보정이 실패해도 촬영 자체를 버리지 않는다.
      return null;
    }
  }

  Future<XFile> _cropToGuideFrame(XFile rawFile, Size screenSize) async {
    try {
      final bytes = await rawFile.readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return rawFile;
      decoded = img.bakeOrientation(decoded);

      final imgW = decoded.width.toDouble();
      final imgH = decoded.height.toDouble();
      final screenAspect = screenSize.width / screenSize.height;
      final imageAspect = imgW / imgH;

      double visibleImgW, visibleImgH;
      if (imageAspect > screenAspect) {
        visibleImgH = imgH;
        visibleImgW = imgH * screenAspect;
      } else {
        visibleImgW = imgW;
        visibleImgH = imgW / screenAspect;
      }
      final offsetX = (imgW - visibleImgW) / 2;
      final offsetY = (imgH - visibleImgH) / 2;

      // 가이드 프레임보다 **넓게** 잘라낸다.
      //
      // ⚠️ 이 값은 한 번 되돌아간 적이 있다. `db605ef`가 **"명함 주변 텍스트
      // 잘림을 방지하기 위해"** 1.5로 넓혔는데, 뒤이은 스타일 커밋 `8fb5ff3`이
      // 배경 노이즈를 없애려고 **1.0(여유 없음)**으로 바꿨다. 그러자 1.5가
      // 막고 있던 결함이 그대로 돌아왔다 — 사용자 제보 "가이드에 맞춰 자동으로
      // 찍힌 명함의 양쪽 끝 글씨가 30~40% 잘린다"(2026-08-14).
      //
      // **잘린 글자는 되찾을 수 없고, 섞인 배경은 파서가 걸러낸다.** 어느
      // 쪽으로 틀릴지 골라야 한다면 넓게 자르는 쪽이다. 배경 글자가 필드를
      // 침범하던 문제는 그 뒤 파싱 규칙에서 많이 잡혔다(추가 199~201).
      //
      // **값은 실측으로 정했다.** 1.5로 자동 촬영한 실물 사진을 열어 보니 글자는
      // 온전했고 명함이 이미지의 약 74%를 차지했다(상하좌우 배경 각 ~13%).
      // 사용자가 그 여백을 줄이기로 결정해 1.3으로 좁혔고, 그 결과를 다시
      // 재보니 좌우 여백이 각 8~12%였다("아직 주변이 많이 보여"). 한 단계 더
      // 좁혀 1.2로 둔다 — 여백이 각 5~7% 정도가 된다.
      //
      // ⚠️ **이 값을 더 줄이려면 먼저 재라.** 0으로 만든 적이 있고(`8fb5ff3`)
      // 그때 글자가 30~40% 잘렸다. 줄이기 전에 **자동 촬영한 실물 사진을 열어
      // 네 귀퉁이가 온전한지** 확인할 것.
      const margin = kGuideCropMargin;
      final guideSize = _guideFrameSizeFor(screenSize);
      final guideW = guideSize.width * margin;
      final guideH = guideSize.height * margin;
      final scaleX = visibleImgW / screenSize.width;
      final scaleY = visibleImgH / screenSize.height;

      final cropW = (guideW * scaleX).clamp(1.0, imgW);
      final cropH = (guideH * scaleY).clamp(1.0, imgH);
      final rawCropX = offsetX + (visibleImgW - cropW) / 2;
      final rawCropY = offsetY + (visibleImgH - cropH) / 2;
      final cropX = rawCropX.clamp(0.0, imgW - cropW);
      final cropY = rawCropY.clamp(0.0, imgH - cropH);

      var cropped = img.copyCrop(
        decoded,
        x: cropX.round(),
        y: cropY.round(),
        width: cropW.round(),
        height: cropH.round(),
      );

      // ⚠️ **이 경로도 숫자를 남긴다**(2단계 대조). 검출 크롭만 크기를 찍고
      // 있어서 **비교 대상이 없었다** — 나란히 놓을 수 없으면 "나아졌다"를
      // 말할 수 없다.
      if (!kReleaseMode) {
        final long = cropW > cropH ? cropW.round() : cropH.round();
        final over = long > kCardPhotoMaxLongSide;
        _lastCropLongEdge = long;
        _lastCropSummary =
            '가이드 크롭 ${cropW.round()}x${cropH.round()} · 긴변 $long'
            ' · 축소임계($kCardPhotoMaxLongSide) ${over ? "넘음 ✅" : "못넘음 ⚠️"}';
        debugPrint('[CARDRECT] $_lastCropSummary');
      }

      // 가이드 프레임이 세로로 길어서 사용자가 명함을 시계 방향으로 90도
      // 돌려 넣었으므로, 크롭한 결과물은 항상 옆으로 누운 상태다. 기기
      // 자체는 회전하지 않았으니 EXIF가 아니라 고정 각도(반시계 90도)로
      // 되돌리면 된다 — 실제 촬영 영상에서 이 방향으로 확인함.
      cropped = img.copyRotate(cropped, angle: -90);

      final jpgBytes = img.encodeJpg(cropped, quality: 100);
      final outPath =
          '${Directory.systemTemp.path}/card_scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(outPath).writeAsBytes(jpgBytes);
      return XFile(outPath);
    } catch (_) {
      // 크롭 계산이 실패하면 원본을 그대로 사용 — 카드 일부가 잘리는 것보다
      // 배경이 좀 섞이는 게 낫다.
      return rawFile;
    }
  }

  Widget _buildCameraPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _controller != null && _controller!.value.isInitialized;
    final screenSize = MediaQuery.of(context).size;
    final guideSize = _guideFrameSizeFor(screenSize);

    // 검출된 테두리를 화면 좌표(가시 좌표)로 옮긴다(B′). null이면 예전처럼
    // 고정 가이드 상자만 보인다.
    // 자르기까지 검출로 하는가. **가이드 상자를 물릴지**가 여기 걸린다 —
    // 자르기가 꺼져 있으면 잘리는 자리는 여전히 고정 가이드다.
    final useDetectionCrop = cardRectCropEnabled.value;
    final detection = _visibleDetection;
    final detectedQuad = detection == null
        ? null
        : displayQuadToVisibleQuad(
            detection.quad,
            detection.displaySize,
            screenSize,
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Viewfinder — 실제 후면 카메라 실시간 프리뷰.
            Positioned.fill(
              child: Container(
                // ⚠️ 카메라 자리는 **검정**이어야 한다. 예전에는 밝은
                // `AppColors.bgBase`(0xFFF7F8FA)라, 카메라가 준비되는 동안
                // 화면이 통째로 하얬다 — 사용자 제보 "카메라가 하얀색이다가
                // 좀 늦게 화면이 보여". Android는 초기화가 더 느려서 그 흰
                // 화면이 더 오래 노출된다(통합본 E-01·E-06 관련).
                //
                // 아래 워터마크 아이콘이 `white.withValues(alpha: 0.04)`인
                // 것이 원래 어두운 배경을 전제했다는 증거다 — 흰 배경에서는
                // 보이지도 않았다.
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isReady) _buildCameraPreview(),
                    // 찾아낸 명함에 달라붙는 테두리(B′). 확인 화면에서는
                    // 프리뷰가 멈춰 있으므로 그리지 않는다.
                    if (isReady && detectedQuad != null && _pendingShot == null)
                      Positioned.fill(
                        child: CardRectOverlay(
                          quad: detectedQuad,
                          color: AppColors.accent,
                        ),
                      ),
                    if (!isReady && !_isInitializing && _initError == null)
                      Icon(
                        Icons.camera,
                        size: 180,
                        color: Colors.white.withValues(alpha: 0.04),
                      ),
                    // 기다리는 동안 "고장난 것"처럼 보이지 않게 무엇을 하는
                    // 중인지 알린다. 카메라 초기화는 기기에 따라 몇 초
                    // 걸리는데(Android가 더 느리다), 안내가 없으면 그 시간이
                    // 통째로 오류처럼 읽힌다.
                    if (_isInitializing)
                      const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 14),
                          Text(
                            '카메라를 준비하는 중이에요',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    if (_initError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _initError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 권한을 "다시 묻지 않음"으로 거부한 뒤에는 앱이
                                // 다시 권한 팝업을 띄울 수 없어, OS 설정 화면으로
                                // 직접 보내는 것이 유일한 복구 경로다(P2-6).
                                // geolocator의 openAppSettings는 위치 전용이
                                // 아니라 이 앱의 설정 페이지를 여는 범용 유틸이다.
                                OutlinedButton.icon(
                                  onPressed: () => Geolocator.openAppSettings(),
                                  icon: const Icon(Icons.settings, size: 18),
                                  label: const Text('설정 열기'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _initError = null;
                                      _isInitializing = true;
                                    });
                                    _initCamera();
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    if (_isCapturing)
                      Container(
                        color: Colors.black.withValues(alpha: 0.7),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: AppColors.accentText,
                              ),
                              SizedBox(height: 16),
                              Text(
                                '📸 촬영한 사진을 다듬는 중…',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Top Header Bar
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        '명함 카메라 스캔',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isFlashOn ? Icons.flash_on : Icons.flash_off,
                          color: _isFlashOn
                              ? AppColors.accentText
                              : Colors.white,
                          size: 24,
                        ),
                        onPressed: isReady ? _toggleFlash : null,
                      ),
                    ],
                  ),
                  if (!OcrScannerService.isSupportedOnThisPlatform)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.destructive.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '웹 브라우저에서는 OCR 인식이 지원되지 않습니다. 모바일 앱에서 테스트해 주세요.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),

            // Business Card Bounding Guide Frame Overlay
            // ⚠️ **넘치면 스크롤한다**(2026-08-17). 예전에는 `Center` 안에
            // `Column`만 있어서, 안내가 한 줄이라도 늘면 화면 아래로 넘쳤다 —
            // debug에서는 **노란 줄무늬**가 뜨고 **release에서는 경고 없이
            // 안내가 잘린다.** 보이지 않을 뿐 더 나쁘다(2026-08-14 제보
            // "핸드폰을 90도 돌리니까 아래에 노란색이 보여").
            //
            // 이 형태는 **내용이 들어가면 지금과 똑같이 가운데 정렬**되고,
            // 넘칠 때만 스크롤된다. 작은 화면·가로 화면·안내가 늘어난 경우를
            // 한꺼번에 막는다.
            //
            // ⚠️⚠️ **터치를 먹지 않게 감싼다**(추가 293, 실기기 지적).
            //
            // 이 스크롤 판은 Stack 안에서 **화면 전체를 덮는다.** 그러면 그
            // 아래 깔린 **X(닫기)와 셔터가 눌리지 않는다** — 넘침을 고치면서
            // 조용히 생긴 결함이고, 사용자에게는 *"X가 터치되지 않는다"*로만
            // 보였다.
            //
            // 📌 이 안에는 **누를 것이 하나도 없다**(가이드 틀·안내 문구·레이저).
            // 그래서 통째로 터치를 흘려보낸다.
            IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_isFrameStable)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.rotate_90_degrees_cw,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    '명함을 시계 방향으로 90° 돌려서 넣어주세요',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // ⭐ **실제로 잘리는 자리**(추가 293).
                          //
                          // 자르기는 가이드 상자보다 [kGuideCropMargin]배 넓다 —
                          // 명함 끝 글자가 잘리는 것을 막으려고 일부러 그렇게
                          // 뒀다. 그런데 화면에는 안쪽 상자만 보여서, 실기기에서
                          // *"찍힌 결과가 가이드와 맞지 않는다"*는 지적을 받았다.
                          //
                          // ⚠️ **여유를 줄이지 않고 보이게 한다.** 줄이면 글자가
                          // 잘린다(0으로 만든 적이 있고 30~40% 잘렸다). 안쪽
                          // 상자는 **명함을 놓는 자리**, 이 옅은 선은 **사진에
                          // 담기는 자리**다.
                          // ⚠️ **Stack으로 겹친다.** 처음에는 Column의 형제로
                          // 뒀다가 **감싸지 않고 아래에 따로 그려졌다** —
                          // 실기기에서 상자가 둘로 따로 보였다. 바깥 선은
                          // 안쪽 상자를 **둘러싸야** 뜻이 있다.
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              // ⚠️ **B′로 자를 때는 안 그린다.** 그때 자르는
                              // 자리는 **파란 테두리**이지 이 상자가 아니다 —
                              // 남겨 두면 "어느 것이 잘리는 자리냐"가 또 헷갈린다.
                              // ⚠️ **B′일 때는 아예 안 그린다**(사용자 지시).
                              // 그때 잘리는 자리는 **파란 테두리**라 이 선은
                              // 쓸모가 없고, 상자가 둘이면 헷갈리기만 한다.
                              // 고정 가이드로 자를 때만 뜻이 있다.
                              if (!useDetectionCrop)
                                Container(
                                  width: guideSize.width * kGuideCropMargin,
                                  height: guideSize.height * kGuideCropMargin,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.35,
                                      ),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: guideSize.width,
                                height: guideSize.height,
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    // ⚠️ **실제로 잘리는 자리를 흐리게 만들면 안 된다**
                                    // (추가 293, 실기기 지적).
                                    //
                                    // 예전에는 검출 테두리가 붙으면 이 상자를 물렸다.
                                    // 그런데 **자르기가 꺼져 있으면 잘리는 자리는
                                    // 여전히 이 상자**다 — 안 잘리는 테두리를 강조하고
                                    // 잘리는 상자를 가린 셈이라, 찍어 보면 테두리와
                                    // 결과가 어긋나 보인다.
                                    //
                                    // ⚠️ **B′로 자를 때는 이 상자를 가만히 둔다**
                                    // (실기기 지적: *"흰 가이드가 파란 테두리
                                    // 움직일 때 같이 움직이니 헷갈리네"*).
                                    //
                                    // 예전에는 검출 여부에 따라 밝기·굵기가
                                    // 바뀌었다. 검출은 붙었다 떨어졌다 하므로
                                    // **흰 상자가 파란 테두리를 따라 깜빡인다** —
                                    // 두 개가 함께 움직이는 것처럼 보인다.
                                    //
                                    // 📌 B′에서는 역할이 갈린다. **파란 테두리가
                                    // 움직이는 것**이고, **흰 상자는 "이쯤 두세요"
                                    // 라는 고정된 안내**다. 그러니 반응하지 않는
                                    // 것이 맞다.
                                    // 📌 B′에서는 **이 상자 하나만 남는다**
                                    // (바깥 선을 안 그리므로). 그래서 옅게 두면
                                    // 어디에 둘지 안 보인다 — 또렷하게 둔다.
                                    color: useDetectionCrop
                                        ? Colors.white.withValues(alpha: 0.75)
                                        : (_isFrameStable
                                              ? AppColors.accent
                                              : Colors.white),
                                    width: useDetectionCrop
                                        ? 1.5
                                        : (_isFrameStable ? 3 : 1.5),
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    // Animated Scanning Laser Line
                                    AnimatedBuilder(
                                      animation: _laserController,
                                      builder: (context, child) {
                                        return Positioned(
                                          top:
                                              _laserController.value *
                                              (guideSize.height - 10),
                                          left: 10,
                                          right: 10,
                                          child: Container(
                                            height: 2,
                                            color: AppColors.accentText,
                                          ),
                                        );
                                      },
                                    ),
                                    // Corner Guides
                                    const Positioned(
                                      top: 12,
                                      left: 12,
                                      child: Icon(
                                        Icons.crop_free,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                    ),
                                    const Positioned(
                                      bottom: 12,
                                      right: 12,
                                      child: Icon(
                                        Icons.crop_free,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _isFrameStable
                                      ? '고정됨 · 자동으로 촬영합니다'
                                      : '가이드 틀 안에 명함을 맞추고 잠시 멈춰 주세요',
                                  style: TextStyle(
                                    color: _isFrameStable
                                        ? AppColors.accent
                                        : AppColors.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                // ⚠️ **검출이 도는지 화면으로 판정할 수 있게 한다**(B′).
                                //
                                // 왜 로그가 아니라 화면인가: 이 기기에서는 앱 로그를
                                // 볼 방법이 없다 — `flutter run`이 앱에 못 붙고
                                // `idevicesyslog`에도 앱이 찍는 줄이 하나도 안 올라온다
                                // (2026-08-16 실측, iOS 26).
                                //
                                // 이 줄이 없으면 **아래 넷을 화면에서 구분할 수 없다** —
                                // 전부 "테두리가 안 보인다"로 똑같이 보인다.
                                //
                                //   채널 없음     ← 결함(네이티브 등록 누락)
                                //   이미지 실패   ← 결함(폭·행길이 어긋남)
                                //   Vision 미검출 ← 설계대로(조명·거리)
                                //   우리가 걸러냄 ← 판정 기준 문제
                                //
                                // ⚠️ 이 줄이 아예 안 보이면 **낡은 빌드가 깔린 것**이다.
                                // release 빌드에는 나오지 않는다.
                                if (!kReleaseMode &&
                                    CardRectDetector.isSupportedOnThisPlatform)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '검출 ${_rectDebugLabel()}',
                                      style: const TextStyle(
                                        color: Colors.lightGreenAccent,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                // 디버그 빌드에서만 보이는 실측값(대비 / 지배톤).
                                // 자동 촬영 임계값을 **추측으로 정했다가 진짜 명함을
                                // 막는 회귀**를 냈다. 실제 장면의 숫자를 읽을 수 있어야
                                // 제대로 정할 수 있다. release 빌드에는 안 나온다.
                                if (kDebugMode && _debugMetrics != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    // 누르면 범위를 지우고 다시 잰다 — 장면을 바꿔
                                    // 가며 값을 읽을 때 쓴다.
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _debugContrastMin = null;
                                        _debugContrastMax = null;
                                        _debugToneMin = null;
                                        _debugToneMax = null;
                                        _debugMetrics = null;
                                      }),
                                      child: Text(
                                        '$_debugMetrics '
                                        '(기준 $_minCenterContrast / '
                                        '$_minDominantToneRatio · '
                                        '${_contentGateEnabled ? "적용중" : "관찰만"}'
                                        ' · 눌러서 초기화)',
                                        style: const TextStyle(
                                          color: Colors.amberAccent,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 방금 찍은 사진 확인 — 인식 전에 [다시 찍기]/[확인]을 받는다.
            if (_pendingShot != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: Column(
                    children: [
                      // ⚠️ **확인 화면에도 닫기를 둔다**(추가 293, 실기기 지적).
                      //
                      // 이 판은 화면을 통째로 덮으므로 **머리말의 X가 가려지고
                      // 터치도 먹힌다.** 사용자에게는 *"X가 눌리지 않는다"*로만
                      // 보인다 — 확인 화면에서 나갈 길이 아예 없었다.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SafeArea(
                          bottom: false,
                          child: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                            // ⚠️ **닫기는 인식 중에도 눌려야 한다.** 막아 뒀더니
                            // "다시 찍기를 눌렀는데 곧바로 또 찍혀서 X가 안
                            // 눌린다"가 됐다 — 나갈 길이 다시 없어졌다.
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          // 파일을 다시 굽지 않고 화면에서만 돌린다 — 누르는
                          // 즉시 결과가 보여야 사용자가 판단할 수 있다(F-03).
                          child: RotatedBox(
                            quarterTurns: quarterTurnsFor(_pendingRotation),
                            child: Image.file(
                              File(_pendingShot!.path),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.sideLabel} · 글자가 또렷한가요?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // ⚠️ **작게 잡혔으면 알린다**(2026-08-16 실측).
                            //
                            // 멀리서 찍으면 크롭이 993px까지 내려간다(약
                            // 280dpi로 문서 스캔 표준 미달). 막지는 않는다 —
                            // 이 프로젝트는 자동 촬영 조건을 조였다가 **진짜
                            // 명함을 막는 회귀를 두 번** 냈다. 이미 있는
                            // *"글자가 또렷한가요?"* 관문에 근거를 한 줄
                            // 얹어, 다시 찍을지는 사용자가 고르게 한다.
                            if (_lastCropLongEdge != null &&
                                _lastCropLongEdge! < kCardPhotoMaxLongSide)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '명함이 작게 잡혔어요. 더 가까이서 다시 찍으면 글자가 또렷해집니다.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            // ⚠️ 측정 전용 — 남긴 파일 이름을 눈으로 확인하게
                            // 한다. 277이 끝나면 지운다.
                            if (kDebugMode && _lastMeasureSavedName != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '측정본 저장: $_lastMeasureSavedName',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.amberAccent,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            // ⚠️ 크롭 결과 픽셀 수(release 빌드 제외).
                            // 이 숫자가 축소 임계(1,600)를 넘는지가 저장
                            // 용량·무료 200장 한도와 직접 걸린다.
                            if (!kReleaseMode && _lastCropSummary != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _lastCropSummary!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.lightGreenAccent,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isCapturing
                                        ? null
                                        : _retakePendingShot,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Colors.white54,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    child: const Text('다시 찍기'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // F-03: 자동 크롭이 항상 반시계 90도로 세우기
                                // 때문에, 명함을 가이드에 반대로 넣으면 반드시
                                // 뒤집혀 나온다. 지금까지 되돌릴 방법이
                                // 재촬영뿐이었다.
                                OutlinedButton(
                                  onPressed: _isCapturing
                                      ? null
                                      : () => setState(() {
                                          _pendingRotation = nextClockwiseTurn(
                                            _pendingRotation,
                                          );
                                        }),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white54,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.rotate_right,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // F-03: 자동이 잘못 잘랐을 때 **사람이 고치는
                                // 유일한 길**이다(자동 검출을 기본으로 안 쓰기로
                                // 했으므로). 지금까지는 다시 찍는 것뿐이었다.
                                OutlinedButton(
                                  onPressed: _isCapturing
                                      ? null
                                      : _cropPendingShotByHand,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white54,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Icon(Icons.crop, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isCapturing
                                        ? null
                                        : _confirmPendingShot,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    child: Text(_isCapturing ? '인식 중…' : '확인'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 지금 찍는 면 — 셔터 위에 항상 보인다.
            if (_pendingShot == null)
              Positioned(
                bottom: 118,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      widget.sideLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom Shutter Controls
            if (_pendingShot == null)
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: (_isCapturing || !isReady) ? null : _capturePhoto,
                    child: Container(
                      width: 76,
                      height: 76,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isReady
                              ? AppColors.accent
                              : AppColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

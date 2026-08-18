import Flutter
import UIKit
import Vision

/// 명함 테두리(사각형) 검출 — 아이폰 쪽 구현.
///
/// ## 왜 이 파일이 있나
///
/// 2026-08-16에 애플의 기성 문서 스캐너(`VNDocumentCameraViewController`)를
/// 붙여 봤는데, **문서용이라 명함에 안 맞았다** — 여러 장을 한꺼번에 잡고
/// 안내가 영어로 떴다. 기성품은 **자기 화면을 통째로 들고 오고** 그 화면은
/// 우리가 고칠 수 없다.
///
/// 애플 Vision에는 둘이 따로 있다.
///
/// | | 무엇 | 우리 화면 |
/// |---|---|---|
/// | `VNDocumentCameraViewController` | 화면째 주는 문서 스캐너 | ❌ 못 씀 |
/// | **`VNDetectRectanglesRequest`** | **사각형 검출만** | ✅ 이 파일이 쓰는 것 |
///
/// 그래서 **화면은 Flutter 것 그대로 두고, "사각형 어디 있나"만 OS에 묻는다.**
///
/// ## ⚠️ 이 저장소의 첫 MethodChannel이다
///
/// 지금까지 네이티브 코드는 전부 pub 패키지가 대신 들고 있었다. 다음 사람이
/// 네이티브를 붙일 때 **본보기가 되므로 짧게 둔다.** 여기서 하는 일은 딱
/// 셋이다 — 밝기 바이트를 이미지로 만들고, Vision에 묻고, 좌표를 돌려준다.
/// **판단(명함처럼 생겼나)은 여기서 하지 않는다.** Dart 쪽
/// `card_quad_geometry.dart`가 한다 — 그쪽은 `flutter test`로 검사되고
/// 이쪽은 안 되기 때문이다.
///
/// ## 개인정보
///
/// ⚠️ 이 앱은 **제3자(명함 주인)의 개인정보**를 다룬다. 이 파일은 프레임을
/// **저장하지 않고 로그로도 남기지 않는다.** 받은 바이트는 검출이 끝나면
/// 그대로 버려진다. 돌려주는 것은 좌표 여덟 개(사각형 하나당)뿐이다.
public class CardRectDetectorPlugin: NSObject, FlutterPlugin {

  /// Dart 쪽 `CardRectDetector.channelName`과 **글자 그대로 같아야** 한다.
  private static let channelName = "connectionsense/card_rect"

  /// 검출은 UI 스레드에서 하지 않는다.
  ///
  /// ⚠️ 매 프레임 도는 일이라 여기서 막히면 **화면이 그대로 끊긴다.**
  /// Dart 쪽이 한 번에 한 프레임만 보내므로 큐가 쌓이지는 않는다.
  private let detectionQueue = DispatchQueue(
    label: "connectionsense.card_rect",
    qos: .userInitiated
  )

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(CardRectDetectorPlugin(), channel: channel)
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard call.method == "detect" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard
      let args = call.arguments as? [String: Any],
      let luma = args["luma"] as? FlutterStandardTypedData,
      let width = args["width"] as? Int,
      let height = args["height"] as? Int,
      let bytesPerRow = args["bytesPerRow"] as? Int,
      width > 0, height > 0, bytesPerRow >= width
    else {
      result(
        FlutterError(
          code: "bad_frame",
          message: "프레임 정보가 모자랍니다",
          details: nil
        )
      )
      return
    }

    let data = luma.data
    // 행 패딩까지 포함한 실제 필요량. 모자란 채로 CGImage를 만들면
    // 읽으면 안 되는 메모리를 읽는다.
    guard data.count >= bytesPerRow * height else {
      result(
        FlutterError(
          code: "short_frame",
          message: "밝기 평면이 잘려 있습니다",
          details: nil
        )
      )
      return
    }

    detectionQueue.async {
      let payload = CardRectDetectorPlugin.detectRectangles(
        luma: data,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow
      )
      DispatchQueue.main.async {
        result(payload)
      }
    }
  }

  /// 밝기(Y) 평면에서 사각형 후보를 찾아 **좌표와 진단값을 함께** 돌려준다.
  ///
  /// ```
  /// { "quads": [x0,y0,...],  // 사각형 하나당 8개, 여러 개가 이어 붙는다
  ///   "observations": 3,     // Vision이 내놓은 원본 개수(우리가 거르기 전)
  ///   "meanLuma": 118,       // 넘어온 이미지의 평균 밝기
  ///   "imageOk": true }      // 회색조 이미지를 만들 수 있었나
  /// ```
  ///
  /// 좌표는 **0~1 정규화, 원점은 왼쪽 위**다 — Vision은 원점이 왼쪽 **아래**라
  /// 여기서 뒤집어 준다. 이 변환을 Dart로 미루면 두 플랫폼이 각자 다른
  /// 규칙을 쓰게 된다.
  ///
  /// ## ⚠️ 왜 진단값을 로그가 아니라 **응답에 담나** (2026-08-16 실측)
  ///
  /// 실기기에서 *"채널OK · 후보없음"*이 나왔다 — 채널은 뚫렸는데 사각형이
  /// 하나도 안 잡히는 상태다. 원인 후보가 둘인데 **화면으로는 구분이 안 된다.**
  ///
  ///   ① 넘긴 밝기 이미지가 깨졌다(폭·행길이가 어긋남)
  ///   ② 이미지는 멀쩡한데 조건이 다 걸러낸다
  ///
  /// 로그로 가르려 했는데 **`idevicesyslog`에 앱 로그가 하나도 안 올라온다**
  /// (iOS 26, Flutter·Swift 양쪽 다 실측). `flutter run`도 앱에 못 붙는다.
  /// **그래서 이미 뚫려 있는 통로(채널)로 숫자를 돌려보낸다** — Dart가 그것을
  /// 디버그 화면에 띄운다.
  ///
  /// ⚠️ 숫자만 담는다. 명함 내용은 담지 않는다(CLAUDE.md 4절).
  private static func detectRectangles(
    luma: Data,
    width: Int,
    height: Int,
    bytesPerRow: Int
  ) -> [String: Any] {
    let mean = meanLuma(
      luma,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow
    )

    guard let cgImage = makeGrayImage(
      luma: luma,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow
    ) else {
      // ⚠️ 여기로 빠지면 **Vision은 아예 불리지도 않는다.** 예전에는 그냥
      // 빈 배열을 돌려줘서 "못 찾았다"와 구분이 안 됐다.
      return [
        "quads": [Double](),
        "observations": 0,
        "meanLuma": mean,
        "imageOk": false,
      ]
    }

    let request = VNDetectRectanglesRequest()
    // ⚠️ 여기서는 **느슨하게** 잡고, 명함인지 아닌지는 Dart가 조인다.
    //
    // 왜 나눴나: 이 값들을 여기서 조이면 왜 안 잡혔는지 알 방법이 실기기
    // 뿐이다. Dart 쪽 판정은 테스트로 고정돼 있어 규격을 바꿔도 회귀를
    // 바로 잡는다. 이 프로젝트는 자동 촬영 임계값을 짐작으로 정했다가
    // **진짜 명함을 막는 회귀를 두 번** 냈다.
    //
    // Vision의 aspect ratio는 **짧은 변 ÷ 긴 변**(0~1)이다. 0.4면 최대
    // 2.5:1까지 받는데, 명함(1.8:1)이 비스듬히 눌린 경우까지 들어온다.
    //
    // ⚠️ **지금은 일부러 가장 느슨하게 둔다.** 실기기에서 하나도 안 잡히는
    // 상태라, 조건을 조인 채로는 *"조건이 막은 것"*과 *"애초에 못 찾는 것"*을
    // 가를 수 없다. 먼저 **무엇이든 잡히는지** 보고, 그 다음에 조인다.
    request.minimumAspectRatio = 0.2
    request.maximumAspectRatio = 1.0
    // 직각에서 얼마나 벗어난 것까지 사각형으로 볼지(도). 최대가 45다.
    request.quadratureTolerance = 45
    // 화면에서 이보다 작으면 배경의 다른 물건으로 본다.
    request.minimumSize = 0.08
    request.minimumConfidence = 0.0
    // 후보를 여럿 넘긴다 — 책상 모서리와 명함이 함께 잡히는 일이 흔한데,
    // 하나만 넘기면 **엉뚱한 쪽이 뽑혀 명함을 놓친다.**
    request.maximumObservations = 12

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      // 실패해도 Dart 쪽은 기존 가이드 상자로 되돌아간다.
      return [
        "quads": [Double](),
        "observations": -1,
        "meanLuma": mean,
        "imageOk": true,
      ]
    }

    let observations = request.results ?? []

    var flat: [Double] = []
    flat.reserveCapacity(observations.count * 8)
    for observation in observations {
      // Vision은 원점이 왼쪽 아래다. y를 뒤집어 왼쪽 위 기준으로 맞춘다.
      let points = [
        observation.topLeft,
        observation.topRight,
        observation.bottomRight,
        observation.bottomLeft,
      ]
      for point in points {
        flat.append(Double(point.x))
        flat.append(Double(1.0 - point.y))
      }
    }
    return [
      "quads": flat,
      "observations": observations.count,
      "meanLuma": mean,
      "imageOk": true,
    ]
  }

  /// 넘어온 밝기 평면의 **평균값**(0~255).
  ///
  /// ⚠️ 이 값 하나로 *"이미지가 깨졌나"*를 가른다. 폭·행길이가 어긋나 있으면
  /// 0에 가깝거나 장면과 무관한 값이 나오고, 멀쩡하면 실제 밝기가 나온다.
  /// 사각형을 못 찾는 이유가 **이미지 문제인지 조건 문제인지**는 이걸 봐야
  /// 갈린다 — 안 재고 조건만 만지면 헛다리를 짚는다.
  ///
  /// 전부 훑지 않고 격자로 성기게 본다(매 프레임 도는 일이라).
  private static func meanLuma(
    _ luma: Data,
    width: Int,
    height: Int,
    bytesPerRow: Int
  ) -> Int {
    var total = 0
    var count = 0
    let stepY = max(1, height / 32)
    let stepX = max(1, width / 32)
    luma.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      let bytes = base.assumingMemoryBound(to: UInt8.self)
      var y = 0
      while y < height {
        var x = 0
        while x < width {
          let index = y * bytesPerRow + x
          if index < raw.count {
            total += Int(bytes[index])
            count += 1
          }
          x += stepX
        }
        y += stepY
      }
    }
    return count == 0 ? -1 : total / count
  }

  /// 밝기 바이트를 회색조 `CGImage`로 감싼다(복사 없이).
  ///
  /// 색은 쓰지 않는다 — 사각형 검출에 필요 없고, 색까지 옮기면 프레임마다
  /// 오가는 양이 세 배가 된다.
  private static func makeGrayImage(
    luma: Data,
    width: Int,
    height: Int,
    bytesPerRow: Int
  ) -> CGImage? {
    guard let provider = CGDataProvider(data: luma as CFData) else {
      return nil
    }
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }
}

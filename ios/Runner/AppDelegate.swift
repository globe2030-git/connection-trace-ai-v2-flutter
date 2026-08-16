import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 명함 테두리 검출(B′) — 이 저장소의 첫 MethodChannel이다.
    //
    // pub 패키지가 아니라 직접 등록하는 이유: 기성 문서 스캐너를 붙였더니
    // **애플의 화면이 통째로 딸려 왔고** 그 화면이 명함에 안 맞았다
    // (문서용이라 여러 장을 한꺼번에 잡음). 여기서는 화면 없이
    // `VNDetectRectanglesRequest`(검출만)를 부른다 —
    // `CardRectDetectorPlugin.swift` 머리말 참고.
    //
    // ⚠️ 등록을 빠뜨리면 앱은 그대로 뜨고 **검출만 조용히 안 된다.**
    // Dart 쪽이 `MissingPluginException`을 받아 기존 가이드 상자로
    // 되돌아가므로 화면상으로는 예전과 똑같이 보인다. 그래서 Dart 쪽에
    // `CardRectChannelState.missing`을 두어 그 경우를 갈라 남긴다.
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "CardRectDetectorPlugin"
    ) {
      CardRectDetectorPlugin.register(with: registrar)
    }
  }
}

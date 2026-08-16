package com.connectiontrace.connection_trace_ai_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var cardRectDetector: CardRectDetectorPlugin? = null

    /**
     * 명함 테두리 검출(B′)을 붙인다.
     *
     * 아이폰의 `AppDelegate.swift`와 **같은 자리**다 — 화면 없이
     * "사각형 어디 있나"만 묻는 통로를 연다. 안드로이드에는 아이폰의 Vision
     * 같은 OS 기본 검출이 없어 OpenCV를 쓴다(`CardRectDetectorPlugin.kt` 머리말).
     *
     * ⚠️ 등록을 빠뜨리면 앱은 그대로 뜨고 **검출만 조용히 안 된다.** Dart 쪽이
     * `MissingPluginException`을 받아 기존 가이드 상자로 되돌아가므로
     * 화면상으로는 예전과 똑같이 보인다 — 그래서 Dart에
     * `CardRectChannelState.missing`을 두어 그 경우를 갈라 남긴다.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cardRectDetector = CardRectDetectorPlugin(
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onDestroy() {
        cardRectDetector?.dispose()
        cardRectDetector = null
        super.onDestroy()
    }
}

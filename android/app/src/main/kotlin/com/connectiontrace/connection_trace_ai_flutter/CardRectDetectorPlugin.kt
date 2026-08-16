package com.connectiontrace.connection_trace_ai_flutter

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import org.opencv.android.OpenCVLoader
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.core.Size
import org.opencv.imgproc.Imgproc

/**
 * 명함 테두리(사각형) 검출 — 안드로이드 쪽 구현.
 *
 * ## 아이폰 쪽과 **같은 계약**을 쓴다
 *
 * 채널 이름·인자·응답 모양이 `ios/Runner/CardRectDetectorPlugin.swift`와 똑같다.
 * Dart는 어느 플랫폼인지 몰라도 된다.
 *
 * ```
 * 받는 것: { luma: ByteArray, width: Int, height: Int, bytesPerRow: Int }
 * 주는 것: { quads: [Double], observations: Int, meanLuma: Int, imageOk: Bool }
 * ```
 *
 * **판단은 여기서 하지 않는다.** 사각형 후보만 넘기고, 어느 것이 명함인지는
 * Dart(`card_quad_geometry.dart`)가 고른다 — 네이티브는 `flutter test`로 못
 * 돌리기 때문이다. 그 덕에 판정 규칙에 검사 98건이 붙어 있고, **두 플랫폼이
 * 똑같은 규칙**을 쓴다.
 *
 * ## ⚠️ 왜 `dartcv4`가 아니라 기성 OpenCV인가 (2026-08-16 실측)
 *
 * 처음에는 Dart에서 바로 부르는 `dartcv4`를 쓰려 했다. **빌드가 실패했다.**
 *
 * ```
 * /bin/sh: -c: line 0: syntax error near unexpected token `('
 * ```
 *
 * `dartcv4`는 **OpenCV 소스를 받아 우리 기계에서 컴파일**하는데, 그 과정이
 * 경로를 따옴표 없이 셸에 넘긴다. 저장소가 있는 볼륨 이름이 `X31(VM)` —
 * **괄호가 들어 있어** 셸이 문법 오류로 본다.
 *
 * 📌 **`dartcv4`가 우리 Flutter에서 안 되는 것이 아니다.** 괄호 없는 경로에
 * 복사해 빌드하니 정상으로 끝났고(APK 157.7MB, 기준선 125.0MB 대비
 * **arm64 네이티브 +10.5MB**), 그래서 **원인이 경로**라는 것이 확정됐다.
 *
 * 그래도 이쪽을 고른 이유(사용자 결정): **기성 OpenCV는 이미 컴파일된 것을
 * 받아 쓰므로 소스 컴파일 단계가 없다** — 경로 문제가 아예 생기지 않는다.
 * 저장소를 옮기면 다른 세션·서명 키 설정(`key.properties`는 git이 안 옮긴다)이
 * 함께 딸려 온다.
 *
 * ## 개인정보
 *
 * ⚠️ 이 앱은 **제3자(명함 주인)의 개인정보**를 다룬다. 이 파일은 프레임을
 * **저장하지 않고 로그로도 남기지 않는다.** 돌려주는 것은 좌표와 숫자뿐이다.
 */
class CardRectDetectorPlugin(messenger: BinaryMessenger) {

    companion object {
        /** Dart 쪽 `CardRectDetector.channelName`과 **글자 그대로 같아야** 한다. */
        private const val CHANNEL_NAME = "connectionsense/card_rect"

        /**
         * 캐니 경계 검출의 아래·위 문턱값.
         *
         * ⚠️ **아직 실측이 아니다.** 아이폰에서 최소 크기·가로세로비를 짐작으로
         * 정했다가 **두 번 틀렸다**(15% → 실측 6.7%, 1.3~1.7 → 실측 1.83).
         * 실기기에서 명함이 안 잡히면 **여기부터 의심하되, 고치기 전에 재라.**
         */
        private const val CANNY_LOW = 60.0
        private const val CANNY_HIGH = 180.0

        /**
         * 윤곽선을 네 점으로 근사할 때 쓰는 허용 오차(둘레 대비).
         *
         * 작으면 곡선을 그대로 따라가 점이 많아지고, 크면 명함이 삼각형으로
         * 뭉갠다.
         */
        private const val APPROX_EPSILON_RATIO = 0.02

        /**
         * 후보로 볼 최소 넓이(전체 대비).
         *
         * 여기서는 **아주 느슨하게만** 거른다 — 진짜 판정은 Dart의
         * `judgeCardShape`가 한다. 아이폰 쪽 Vision 설정과 같은 태도다.
         */
        private const val MIN_AREA_FRACTION = 0.01

        /** 한 프레임에서 넘길 후보 개수 상한. */
        private const val MAX_OBSERVATIONS = 12
    }

    /**
     * 검출은 UI 스레드에서 하지 않는다.
     *
     * ⚠️ 매 프레임 도는 일이라 여기서 막히면 **화면이 그대로 끊긴다.**
     * Dart 쪽이 한 번에 한 프레임만 보내므로 큐가 쌓이지는 않는다.
     */
    private val executor = Executors.newSingleThreadExecutor()

    /**
     * OpenCV 네이티브가 실제로 올라왔나.
     *
     * ⚠️ `initLocal()`은 **실패해도 예외를 던지지 않고 false를 준다.** 이 값을
     * 안 보면 *"검출이 안 되네"*로만 보이고 원인을 알 수 없다 — 아이폰에서
     * 겪은 *"채널은 뚫렸는데 왜 안 잡히지"*와 같은 함정이다.
     */
    private val openCvReady: Boolean by lazy { OpenCVLoader.initLocal() }

    private val channel = MethodChannel(messenger, CHANNEL_NAME).apply {
        setMethodCallHandler { call, result -> handle(call, result) }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "detect") {
            result.notImplemented()
            return
        }

        val luma = call.argument<ByteArray>("luma")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val bytesPerRow = call.argument<Int>("bytesPerRow") ?: 0

        if (luma == null || width <= 0 || height <= 0 || bytesPerRow < width) {
            result.error("bad_frame", "프레임 정보가 모자랍니다", null)
            return
        }
        // 행 패딩까지 포함한 실제 필요량. 모자란 채로 Mat을 만들면 읽으면
        // 안 되는 메모리를 읽는다.
        if (luma.size < bytesPerRow * height) {
            result.error("short_frame", "밝기 평면이 잘려 있습니다", null)
            return
        }

        executor.execute {
            val payload = detectRectangles(luma, width, height, bytesPerRow)
            // 채널 응답은 메인 스레드에서 돌려준다.
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.success(payload)
            }
        }
    }

    /**
     * 밝기(Y) 평면에서 사각형 후보를 찾아 **좌표와 진단값을 함께** 돌려준다.
     *
     * 좌표는 **0~1 정규화, 원점은 왼쪽 위**다. 아이폰 쪽(Vision)은 원점이 왼쪽
     * 아래라 그쪽에서 뒤집어 주고, 여기는 원래 왼쪽 위라 그대로 쓴다 —
     * **Dart에 도착할 때는 두 플랫폼이 같은 규칙**이다.
     *
     * ## ⚠️ 진단값을 응답에 담는 이유
     *
     * *"검출이 안 된다"*에는 서로 다른 것이 섞여 있는데, **화면으로는 전부
     * "테두리가 안 보인다"로 똑같이 보인다.**
     *
     * ```
     * 채널 없음 / OpenCV 미탑재 / 이미지 깨짐  ← 결함
     * 그냥 못 찾음                              ← 설계대로(조명·거리)
     * ```
     *
     * 아이폰에서 이 구분이 없어 한참 헤맸고, **로그를 볼 수 없는 기기**라는 것도
     * 그때 드러났다(iOS 26에서 `flutter run`도 `idevicesyslog`도 앱 로그를 못
     * 잡는다). 안드로이드는 로그가 잡히지만 **같은 계약을 유지한다** — 두
     * 플랫폼이 다르게 굴면 그 차이 자체가 다음 함정이 된다.
     */
    private fun detectRectangles(
        luma: ByteArray,
        width: Int,
        height: Int,
        bytesPerRow: Int,
    ): Map<String, Any> {
        val mean = meanLuma(luma, width, height, bytesPerRow)

        if (!openCvReady) {
            // ⚠️ 여기로 빠지면 검출은 **한 번도 시도되지 않는다.** 그냥 빈
            // 결과를 주면 "못 찾았다"와 구분이 안 된다.
            return mapOf(
                "quads" to DoubleArray(0).toList(),
                "observations" to 0,
                "meanLuma" to mean,
                "imageOk" to false,
            )
        }

        var gray: Mat? = null
        var blurred: Mat? = null
        var edges: Mat? = null
        val contours = ArrayList<MatOfPoint>()
        try {
            gray = Mat(height, width, CvType.CV_8UC1)
            if (bytesPerRow == width) {
                gray.put(0, 0, luma)
            } else {
                // 행 패딩이 있으면 한 줄씩 옮긴다 — 통째로 넣으면 이미지가
                // 비스듬히 밀린다.
                val row = ByteArray(width)
                for (y in 0 until height) {
                    System.arraycopy(luma, y * bytesPerRow, row, 0, width)
                    gray.put(y, 0, row)
                }
            }

            // 잡음을 눌러 준다 — 안 누르면 종이 결·책상 무늬가 전부 경계가 된다.
            blurred = Mat()
            Imgproc.GaussianBlur(gray, blurred, Size(5.0, 5.0), 0.0)

            edges = Mat()
            Imgproc.Canny(blurred, edges, CANNY_LOW, CANNY_HIGH)

            Imgproc.findContours(
                edges,
                contours,
                Mat(),
                Imgproc.RETR_LIST,
                Imgproc.CHAIN_APPROX_SIMPLE,
            )

            val totalArea = (width.toDouble() * height.toDouble())
            val quads = ArrayList<Double>()
            var observations = 0

            for (contour in contours) {
                if (observations >= MAX_OBSERVATIONS) break

                val area = Math.abs(Imgproc.contourArea(contour))
                if (area < totalArea * MIN_AREA_FRACTION) continue

                val curve = MatOfPoint2f(*contour.toArray())
                val perimeter = Imgproc.arcLength(curve, true)
                if (perimeter <= 0.0) {
                    curve.release()
                    continue
                }

                val approx = MatOfPoint2f()
                Imgproc.approxPolyDP(curve, approx, APPROX_EPSILON_RATIO * perimeter, true)
                curve.release()

                val points = approx.toArray()
                approx.release()
                if (points.size != 4) continue

                // 오목한 것은 명함이 아니다 — 그림자·글자 덩어리가 이렇게 잡힌다.
                val asContour = MatOfPoint(*points.map {
                    org.opencv.core.Point(it.x, it.y)
                }.toTypedArray())
                val convex = Imgproc.isContourConvex(asContour)
                asContour.release()
                if (!convex) continue

                observations++
                for (point in points) {
                    quads.add(point.x / width)
                    quads.add(point.y / height)
                }
            }

            return mapOf(
                "quads" to quads,
                "observations" to observations,
                "meanLuma" to mean,
                "imageOk" to true,
            )
        } catch (e: Throwable) {
            // 실패해도 촬영 자체는 막지 않는다 — Dart가 기존 가이드 상자로
            // 되돌아간다.
            return mapOf(
                "quads" to DoubleArray(0).toList(),
                "observations" to -1,
                "meanLuma" to mean,
                "imageOk" to true,
            )
        } finally {
            gray?.release()
            blurred?.release()
            edges?.release()
            for (contour in contours) contour.release()
        }
    }

    /**
     * 넘어온 평면의 평균 밝기(0~255).
     *
     * ⚠️ 이 값 하나로 *"이미지가 깨졌나"*를 가른다. 폭·행길이가 어긋나 있으면
     * 0에 가깝거나 장면과 무관한 값이 나온다. 매 프레임 도는 일이라 격자로
     * 성기게 본다.
     */
    private fun meanLuma(
        luma: ByteArray,
        width: Int,
        height: Int,
        bytesPerRow: Int,
    ): Int {
        var total = 0L
        var count = 0
        val stepY = maxOf(1, height / 32)
        val stepX = maxOf(1, width / 32)
        var y = 0
        while (y < height) {
            val rowStart = y * bytesPerRow
            var x = 0
            while (x < width) {
                val index = rowStart + x
                if (index < luma.size) {
                    // ByteArray는 부호가 있다 — 그대로 더하면 128 이상이
                    // 음수가 된다.
                    total += (luma[index].toInt() and 0xFF)
                    count++
                }
                x += stepX
            }
            y += stepY
        }
        return if (count == 0) -1 else (total / count).toInt()
    }
}

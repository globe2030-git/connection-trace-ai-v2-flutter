import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../utils/card_rect_opencv.dart';

/// 명함 사각형 검출을 **별도 isolate에서 계속 돌리는 일꾼**(안드로이드).
///
/// ## 왜 isolate인가
///
/// 검출은 **매 프레임(초당 8회) 도는 일**이다. 본 스레드에서 돌리면 그때마다
/// 화면이 멈칫한다 — 인계 문서가 이번 작업의 진짜 위험으로 짚은 자리다.
///
/// ## ⚠️ 왜 `compute()`가 아니라 계속 살아 있는 isolate인가
///
/// `compute()`는 **부를 때마다 isolate를 새로 띄우고 끝나면 버린다.** 한 번
/// 쓰는 무거운 일(촬영 뒤 원근 보정)에는 맞지만, **초당 여덟 번 띄웠다 버리는
/// 것**은 그 자체가 비용이다. 여기서는 화면을 여는 동안 하나를 띄워 두고
/// 프레임만 실어 보낸다.
///
/// ## 아이폰과의 관계
///
/// 아이폰은 네이티브 채널이 이 역할을 한다(Swift가 자기 큐에서 돈다).
/// **돌려주는 것은 양쪽이 똑같다** — 좌표와 진단값이 같은 모양으로 온다.
/// 그래야 화면의 진단 줄이 두 플랫폼에서 같게 보인다.
class CardRectWorker {
  CardRectWorker._(this._isolate, this._toWorker, this._fromWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;

  /// 보낸 프레임의 답을 기다리는 곳. 한 번에 하나만 오간다.
  Completer<OpenCvRectResult?>? _pending;
  bool _disposed = false;

  /// 일꾼을 띄운다. 실패하면 null — 부르는 쪽은 검출 없이 돈다.
  static Future<CardRectWorker?> spawn() async {
    try {
      final fromWorker = ReceivePort();
      final isolate = await Isolate.spawn(
        _workerMain,
        fromWorker.sendPort,
        errorsAreFatal: false,
        debugName: 'card_rect_worker',
      );

      // 일꾼이 자기 주소를 먼저 보내 준다.
      final stream = fromWorker.asBroadcastStream();
      final toWorker = await stream.first.timeout(
        const Duration(seconds: 5),
      );
      if (toWorker is! SendPort) {
        isolate.kill(priority: Isolate.immediate);
        fromWorker.close();
        return null;
      }

      final worker = CardRectWorker._(isolate, toWorker, fromWorker);
      stream.listen(worker._onMessage);
      return worker;
    } catch (_) {
      return null;
    }
  }

  void _onMessage(Object? message) {
    final pending = _pending;
    _pending = null;
    if (pending == null || pending.isCompleted) return;
    pending.complete(message is OpenCvRectResult ? message : null);
  }

  /// 프레임 한 장을 보내 결과를 받는다.
  ///
  /// ⚠️ **앞의 것이 안 끝났으면 null을 돌려주고 이 프레임은 버린다.** 큐가
  /// 쌓이면 테두리가 손을 따라오지 못하고 뒤늦게 따라붙는다 — 아이폰 쪽
  /// `CardRectDetector`가 하는 것과 같은 판단이다.
  Future<OpenCvRectResult?> detect(
    Uint8List luma, {
    required int width,
    required int height,
    Duration timeout = const Duration(milliseconds: 800),
  }) async {
    if (_disposed || _pending != null) return null;

    final completer = Completer<OpenCvRectResult?>();
    _pending = completer;
    try {
      _toWorker.send(_WorkerRequest(luma, width, height));
      return await completer.future.timeout(timeout);
    } catch (_) {
      _pending = null;
      return null;
    }
  }

  /// 화면을 닫을 때 부른다. **안 부르면 isolate가 남는다.**
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending?.complete(null);
    _pending = null;
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

/// isolate로 넘기는 프레임 한 장.
class _WorkerRequest {
  const _WorkerRequest(this.luma, this.width, this.height);
  final Uint8List luma;
  final int width;
  final int height;
}

/// 일꾼 isolate의 본체.
///
/// ⚠️ **최상위 함수여야 한다** — isolate에 넘기려면 클로저나 인스턴스 메서드는
/// 안 된다.
void _workerMain(SendPort toMain) {
  final fromMain = ReceivePort();
  toMain.send(fromMain.sendPort);

  fromMain.listen((message) {
    if (message is! _WorkerRequest) return;
    try {
      toMain.send(
        detectCardQuadsWithOpenCv(
          message.luma,
          width: message.width,
          height: message.height,
        ),
      );
    } catch (_) {
      // 한 프레임이 실패해도 일꾼은 계속 산다 — 여기서 죽으면 그 뒤로
      // 검출이 통째로 멈추는데, 화면상으로는 "잘 안 잡힌다"로만 보인다.
      toMain.send(null);
    }
  });
}

import 'package:flutter/material.dart';

/// 스캔한 명함을 **전체 화면으로 크게** 본다.
///
/// **왜 필요한가**: 명함 등록·수정 화면의 미리보기는 높이가 180px로 묶여 있다.
/// 목록에서 여러 장을 훑기엔 그 크기가 맞지만, **인식 결과가 맞는지 확인하려면
/// 명함의 글자를 읽을 수 있어야 한다.** 특히 명함을 눕혀 찍은 사진은 가로가
/// 남고 세로가 눌려서 글씨가 거의 안 보인다(실제 표본 `card_134` 삼성SDI가
/// 그렇게 찍혀 있다).
///
/// 그래서 **확대·이동·회전**을 준다.
/// - 확대·이동: 두 손가락으로. 두 번 누르면 2배/원래대로 오간다.
/// - 회전: 눕혀 찍은 명함을 세워 읽기 위한 것이라 90° 단위로만 돌린다.
///   ⚠️ **회전은 보기 전용이다** — 저장된 이미지를 바꾸지 않는다. 원본을
///   건드리면 되돌릴 수 없고, 여기서 필요한 것은 읽는 동안만 돌려 보는 것이다.
Future<void> showCardImageViewer(
  BuildContext context, {
  required ImageProvider image,
  String title = '스캔한 명함',
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) =>
          _CardImageViewer(image: image, title: title),
    ),
  );
}

class _CardImageViewer extends StatefulWidget {
  final ImageProvider image;
  final String title;

  const _CardImageViewer({required this.image, required this.title});

  @override
  State<_CardImageViewer> createState() => _CardImageViewerState();
}

class _CardImageViewerState extends State<_CardImageViewer> {
  final _controller = TransformationController();
  int _quarterTurns = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 두 번 눌러 확대/축소. 누른 지점을 중심으로 키운다 — 화면 한가운데를
  /// 기준으로 키우면 보려던 글자가 화면 밖으로 밀려난다.
  void _toggleZoom(TapDownDetails details) {
    if (_controller.value != Matrix4.identity()) {
      _controller.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final position = details.localPosition;
    _controller.value = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (scale - 1),
        -position.dy * (scale - 1),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '왼쪽으로 돌리기',
                  onPressed: () =>
                      setState(() => _quarterTurns = (_quarterTurns + 3) % 4),
                  icon: const Icon(Icons.rotate_left, color: Colors.white),
                ),
                IconButton(
                  tooltip: '오른쪽으로 돌리기',
                  onPressed: () =>
                      setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
                  icon: const Icon(Icons.rotate_right, color: Colors.white),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
            Expanded(
              child: GestureDetector(
                onDoubleTapDown: _toggleZoom,
                onDoubleTap: () {},
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 1,
                  maxScale: 6,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: _quarterTurns,
                      child: Image(image: widget.image, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                '두 손가락으로 확대·이동 · 두 번 눌러 확대 · 돌리기는 보기 전용이라 저장된 이미지는 그대로예요',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 미리보기 자리에 놓는 이미지. **누르면 전체 화면으로 크게 열린다.**
///
/// 누를 수 있다는 것을 알 수 있게 오른쪽 아래에 돋보기 배지를 얹는다 — 예전에는
/// 아무 표시가 없어서 크게 볼 방법 자체가 없는 것처럼 보였다(사용자 제보,
/// 2026-08-14).
class ZoomableCardImage extends StatelessWidget {
  final ImageProvider image;
  final String title;

  const ZoomableCardImage({
    super.key,
    required this.image,
    this.title = '스캔한 명함',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showCardImageViewer(context, image: image, title: title),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Image(image: image, fit: BoxFit.contain),
          Positioned(
            right: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in, size: 15, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      '크게 보기',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

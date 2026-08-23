import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// 명함 한 면(앞면·뒷면 등)의 이미지 한 장과 그 라벨.
///
/// [image]는 항상 **이미 메모리에 올라온** `ImageProvider`다 — 새로 스캔한
/// 면은 `FileImage`(평문 임시 파일), 이미 저장된 면은 `MemoryImage`
/// (`ContactImageService`로 복호화한 바이트)를 넘긴다. 이 위젯 자신은 파일을
/// 새로 만들지 않는다.
class CardFaceImage {
  final ImageProvider image;
  final String label;

  const CardFaceImage({required this.image, required this.label});
}

/// 스캔한 명함을 **전체 화면으로 크게** 본다(추가 133, 확장: 추가 426).
///
/// **왜 필요한가**: 명함 등록·수정 화면과 상세 화면의 미리보기는 작게 묶여
/// 있다. 목록에서 훑기엔 그 크기가 맞지만, **인식 결과가 맞는지 확인하려면
/// 명함의 글자를 읽을 수 있어야 한다.** 특히 명함을 눕혀 찍은 사진은 가로가
/// 남고 세로가 눌려서 글씨가 거의 안 보인다(실제 표본 `card_134` 삼성SDI가
/// 그렇게 찍혀 있다).
///
/// 그래서 **확대·이동·회전**을 준다.
/// - 확대·이동: 두 손가락으로. 두 번 누르면 2배/원래대로 오간다.
/// - 회전: 눕혀 찍은 명함을 세워 읽기 위한 것이라 90° 단위로만 돌린다.
///   ⚠️ **회전은 보기 전용이다** — 저장된 이미지를 바꾸지 않는다. 원본을
///   건드리면 되돌릴 수 없고, 여기서 필요한 것은 읽는 동안만 돌려 보는 것이다.
///
/// [faces]가 2장 이상이면(앞면+뒷면) **좌우로 스와이프해 넘길 수 있다** —
/// 편집·상세 화면이 **같은 위젯 하나를 공유**한다(스펙 지시: "뷰어는 공용
/// 위젯 하나로"). 1장뿐이면 페이지 점·배지가 자동으로 사라진다.
Future<void> showCardImageViewer(
  BuildContext context, {
  required List<CardFaceImage> faces,
  int initialIndex = 0,
  String title = '스캔한 명함',
}) {
  if (faces.isEmpty) return Future<void>.value();
  final start = initialIndex.clamp(0, faces.length - 1);
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) =>
          _CardImageViewer(faces: faces, title: title, initialIndex: start),
    ),
  );
}

class _CardImageViewer extends StatefulWidget {
  final List<CardFaceImage> faces;
  final String title;
  final int initialIndex;

  const _CardImageViewer({
    required this.faces,
    required this.title,
    required this.initialIndex,
  });

  @override
  State<_CardImageViewer> createState() => _CardImageViewerState();
}

class _CardImageViewerState extends State<_CardImageViewer> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _pageIndex = widget.initialIndex;

  // 면(페이지)마다 확대·회전 상태를 따로 둔다 — 앞면을 확대한 채로 뒷면으로
  // 넘기면 뒷면까지 확대된 채로 열리는 것을 막기 위함.
  late final List<TransformationController> _zoomControllers = List.generate(
    widget.faces.length,
    (_) => TransformationController(),
  );
  late final List<int> _quarterTurns = List.filled(widget.faces.length, 0);

  bool get _hasMultipleFaces => widget.faces.length > 1;

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _zoomControllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// 두 번 눌러 확대/축소. 누른 지점을 중심으로 키운다 — 화면 한가운데를
  /// 기준으로 키우면 보려던 글자가 화면 밖으로 밀려난다.
  void _toggleZoom(int index, TapDownDetails details) {
    final controller = _zoomControllers[index];
    if (controller.value != Matrix4.identity()) {
      controller.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final position = details.localPosition;
    controller.value = Matrix4.identity()
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
    final face = widget.faces[_pageIndex];
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
                    // 여러 면이면 "앞면 1/2"처럼 지금 보는 면을 알려 준다 —
                    // 스와이프만으로는 몇 번째 면인지 알기 어렵다.
                    _hasMultipleFaces
                        ? '${face.label} ${_pageIndex + 1}/${widget.faces.length}'
                        : widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '왼쪽으로 돌리기',
                  onPressed: () => setState(
                    () => _quarterTurns[_pageIndex] =
                        (_quarterTurns[_pageIndex] + 3) % 4,
                  ),
                  icon: const Icon(Icons.rotate_left, color: Colors.white),
                ),
                IconButton(
                  tooltip: '오른쪽으로 돌리기',
                  onPressed: () => setState(
                    () => _quarterTurns[_pageIndex] =
                        (_quarterTurns[_pageIndex] + 1) % 4,
                  ),
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
              child: PageView.builder(
                controller: _pageController,
                itemCount: widget.faces.length,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                itemBuilder: (context, index) {
                  final f = widget.faces[index];
                  return GestureDetector(
                    onDoubleTapDown: (d) => _toggleZoom(index, d),
                    onDoubleTap: () {},
                    child: InteractiveViewer(
                      transformationController: _zoomControllers[index],
                      minScale: 1,
                      maxScale: 6,
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: _quarterTurns[index],
                          child: Image(image: f.image, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_hasMultipleFaces) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.faces.length, (i) {
                  final active = i == _pageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 4),
            ],
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

/// 편집·상세 화면 상단에 놓는 **명함 사진 큰 미리보기**(추가 426).
///
/// - 사진을 누르면(또는 우하단 돋보기를 누르면) [showCardImageViewer]로 크게
///   연다.
/// - [faces]가 2장 이상이면 좌하단에 앞/뒤 세그먼트가 뜬다. **1장이면 아예
///   그리지 않는다** — 세그먼트가 있는데 눌러도 아무 일이 안 일어나는 것보다,
///   없는 편이 "여긴 고를 게 없다"를 정확히 말해 준다.
class CardPhotoPreview extends StatelessWidget {
  final List<CardFaceImage> faces;
  final int selectedIndex;

  /// 세그먼트에서 다른 면을 골랐을 때. 넘기지 않으면(예: 상세 화면의 읽기
  /// 전용 미리보기) 세그먼트를 눌러도 선택이 바뀌지 않는다 — 어차피 대부분
  /// 이 자리는 [faces]가 1장이라 세그먼트 자체가 안 뜬다.
  final ValueChanged<int>? onSelectFace;

  final double height;

  /// 미리보기 아래 안내 한 줄. null이면 표시하지 않는다.
  final String? caption;

  const CardPhotoPreview({
    super.key,
    required this.faces,
    required this.selectedIndex,
    this.onSelectFace,
    this.height = 196,
    this.caption = '사진을 누르면 크게 볼 수 있어요.',
  });

  @override
  Widget build(BuildContext context) {
    if (faces.isEmpty) return const SizedBox.shrink();
    final index = selectedIndex.clamp(0, faces.length - 1);
    final hasMultiple = faces.length > 1;

    void openViewer() =>
        showCardImageViewer(context, faces: faces, initialIndex: index);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.borderSubtle.withValues(alpha: 0.8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: openViewer,
                    child: ColoredBox(
                      color: AppColors.bgBase,
                      child: Image(
                        image: faces[index].image,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  if (hasMultiple)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _FaceSegmentControl(
                        faces: faces,
                        selectedIndex: index,
                        onSelect: onSelectFace,
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _MagnifyButton(onTap: openViewer),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

class _FaceSegmentControl extends StatelessWidget {
  final List<CardFaceImage> faces;
  final int selectedIndex;
  final ValueChanged<int>? onSelect;

  const _FaceSegmentControl({
    required this.faces,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(faces.length, (i) {
            final active = i == selectedIndex;
            return Semantics(
              button: true,
              selected: active,
              label: faces[i].label,
              child: GestureDetector(
                onTap: onSelect == null ? null : () => onSelect!(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    faces[i].label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? Colors.black87 : Colors.white,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _MagnifyButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MagnifyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '크게 보기',
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.zoom_in, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

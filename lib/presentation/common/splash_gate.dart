import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../../core/theme/app_colors.dart';

// 네이티브 스플래시(flutter_native_splash)가 엔진 초기화 동안 보여주던 로고를
// Flutter 첫 프레임에서 똑같은 배경색/이미지로 그대로 이어받아 화면 위에 덮어
// 두었다가, 실제 앱 화면이 완전히 그려진 뒤 네이티브 스플래시를 제거하고 이
// 오버레이 자체를 부드럽게 페이드아웃시킨다. 실제 앱은 이 오버레이 밑에서
// 이미 렌더링되어 있으므로 전환 시 색이 바뀌거나 화면이 깜빡이는 느낌이 없다.
class SplashGate extends StatefulWidget {
  final Widget child;

  const SplashGate({super.key, required this.child});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeOut;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeOut = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      FlutterNativeSplash.remove();
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _fadeOut,
          builder: (context, _) {
            if (_fadeOut.value >= 1) return const SizedBox.shrink();
            return IgnorePointer(
              child: Opacity(
                opacity: 1 - _fadeOut.value,
                child: Container(
                  color: AppColors.bgDarkSlate,
                  alignment: Alignment.center,
                  child: Image.asset('assets/CI.png', width: 260),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

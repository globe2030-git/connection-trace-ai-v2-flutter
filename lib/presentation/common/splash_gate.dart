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
      duration: const Duration(seconds: 2),
    );
    // 애니메이션 시작과 동시에 서서히 옅어지면 2초를 다 채우기 전에 뒤에
    // 있는 첫 화면이 비쳐 보인다. 대부분(85%)은 완전 불투명을 유지하다가
    // 마지막 15%(0.3초) 구간에서만 빠르게 페이드아웃해서, "2초간 로딩 화면이
    // 온전히 떠 있다가 첫 화면으로 전환"되는 것처럼 보이게 한다.
    _fadeOut = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.85, 1.0, curve: Curves.easeOut),
    );

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
                  color: AppColors.bgBase,
                  alignment: Alignment.center,
                  // ⚠️ 여기가 **옛 라벤더 레이더 마크**를 쓰고 있었다
                  // (사용자 보고, 2026-08-10). 2026-08-05 리브랜딩에서 네이티브
                  // 스플래시와 런처 아이콘은 위치핀+명함 마크로 바꿨는데,
                  // 앱 안에서 한 번 더 덮어 그리는 이 화면만 남았다.
                  //
                  // 네이티브 스플래시가 사라진 직후 이 화면이 이어서 뜨므로,
                  // 사용자 눈에는 "로딩 중에 옛 아이콘이 보인다"로 나타난다 —
                  // 리소스를 아무리 다시 생성해도 고쳐지지 않던 이유다.
                  child: Image.asset(
                    'assets/icons3d/pin_card_blue_splash.png',
                    width: 220,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

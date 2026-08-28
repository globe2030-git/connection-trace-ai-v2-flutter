/// 앱 잠금 화면 — 켜져 있으면 본인 확인을 통과해야 명함첩이 보인다(추가 570).
///
/// ## 어디에 두나
///
/// `AuthGate` **안쪽**이다. 로그인 전에는 지킬 것이 없고, 로그인 흐름 위에
/// 인증 창을 겹치면 **어느 것을 하라는 건지 알 수 없는 화면**이 된다.
///
/// ## 🚨 「돌아올 때마다 잠근다」로 하지 않았다
///
/// 명함 촬영·갤러리 선택·주소 검색은 **잠깐 나갔다 오는 흐름**이다. 그때마다
/// 잠그면 **명함 한 장 등록하는 데 인증을 세 번** 하게 된다. 그래서
/// [shouldLockOnResume]이 **떠나 있던 시간**으로 판단한다(기본 30초).
///
/// ⚠️ `inactive`가 아니라 `paused`만 본다 — 긴급재난문자나 알림 배너로도
/// `inactive`가 되는데, 그걸로 잠그면 **쓰는 도중에 잠긴다.**
library;

import 'package:flutter/material.dart';

import '../../core/services/app_lock_service.dart';
import '../../core/theme/app_colors.dart';

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child, this.service});

  final Widget child;

  /// 검사에서 가짜를 넣기 위한 자리. 실제 앱에서는 비워 둔다.
  final AppLockService? service;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late final AppLockService _service = widget.service ?? AppLockService();

  /// 잠겨 있나. **처음에는 잠근 채로 시작한다** — 설정을 읽기 전에 내용이
  /// 한 프레임이라도 보이면 잠금의 뜻이 없다.
  bool _locked = true;
  bool _enabled = false;
  bool _prompting = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _start() async {
    final enabled = await _service.isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _locked = enabled;
    });
    if (enabled) await _unlock();
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    final ok = await _service.authenticate();
    _prompting = false;
    if (!mounted) return;
    if (ok) setState(() => _locked = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final at = _pausedAt;
    _pausedAt = null;
    if (at == null) return;
    if (!shouldLockOnResume(
      enabled: _enabled,
      awayFor: DateTime.now().difference(at),
    )) {
      return;
    }
    setState(() => _locked = true);
    _unlock();
  }

  @override
  Widget build(BuildContext context) {
    if (!_locked) return widget.child;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 44, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            const Text(
              '앱이 잠겨 있습니다',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '본인 확인을 하면 명함첩이 열립니다',
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            // 🚨 인증 창을 취소했을 때 **다시 부를 길**이 있어야 한다.
            //    없으면 앱을 껐다 켜는 수밖에 없다.
            FilledButton(onPressed: _unlock, child: const Text('잠금 해제')),
          ],
        ),
      ),
    );
  }
}

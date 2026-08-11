import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/app_update_service.dart';
import '../../core/theme/app_colors.dart';

/// 앱 시작 시 버전을 확인해(P1-45):
/// - **강제**(최소 지원 미만): [child] 대신 닫을 수 없는 업데이트 화면을 띄운다.
/// - **권장**(새 버전 있음): [child]는 그대로 두고 1회 안내 다이얼로그를 띄운다.
/// - **없음/확인 실패**: [child]를 그대로 보여준다(오프라인에 앱을 잠그지 않음).
class VersionGate extends StatefulWidget {
  final Widget child;

  const VersionGate({super.key, required this.child});

  @override
  State<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<VersionGate> {
  final AppUpdateService _service = AppUpdateService();
  AppUpdateStatus _status = AppUpdateStatus.none;
  bool _recommendedHandled = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final status = await _service.check();
    if (!mounted) return;
    setState(() => _status = status);
    if (status.level == AppUpdateLevel.recommended && !_recommendedHandled) {
      _recommendedHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRecommendedDialog(status);
      });
    }
  }

  Future<void> _openStore(String? url) async {
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _showRecommendedDialog(AppUpdateStatus status) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('업데이트가 있어요'),
        content: Text(
          status.message?.isNotEmpty == true
              ? status.message!
              : '새 버전이 나왔어요. 지금 업데이트하면 최신 기능으로 이용할 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openStore(status.storeUrl);
            },
            child: const Text('업데이트'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_status.level == AppUpdateLevel.forced) {
      return _UpdateRequiredScreen(
        status: _status,
        onUpdate: () => _openStore(_status.storeUrl),
      );
    }
    return widget.child;
  }
}

/// 강제 업데이트 화면 — 닫을 수 없다(뒤로가기·바깥 탭 없음). 업데이트만 남긴다.
class _UpdateRequiredScreen extends StatelessWidget {
  final AppUpdateStatus status;
  final VoidCallback onUpdate;

  const _UpdateRequiredScreen({required this.status, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update,
                  size: 56,
                  color: AppColors.accentText,
                ),
                const SizedBox(height: 20),
                const Text(
                  '업데이트가 필요해요',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  status.message?.isNotEmpty == true
                      ? status.message!
                      : '현재 버전은 더 이상 지원되지 않아요. 계속 사용하려면 '
                            '최신 버전으로 업데이트해 주세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onUpdate,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('업데이트하기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

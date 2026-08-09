import 'package:flutter/material.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';

Future<bool?> showLocationConsentSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _LocationConsentSheet(),
  );
}

Future<void> showLocationUsePolicy(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.cardSurface,
      title: const Row(
        children: [
          AppIcon(AppIconId.locationInfo, color: AppColors.accentText),
          SizedBox(width: 10),
          Expanded(child: Text('위치정보 이용 안내')),
        ],
      ),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PolicySection(
              title: '이용 목적',
              body: '현재 위치와 명함에 등록된 회사 주소 사이의 거리를 계산하고, 가까운 인맥을 거리순으로 보여줍니다.',
            ),
            _PolicySection(
              title: '이용 범위',
              body:
                  '앱을 열거나 사용자가 내 위치 갱신을 요청할 때 현재 위치를 한 번 조회합니다. 백그라운드에서 계속 추적하지 않습니다.',
            ),
            _PolicySection(
              title: '저장 및 전송',
              body:
                  '현재 위치와 위치 이력은 저장하지 않으며 개발사 서버로 전송하지 않습니다. 거리 계산은 이 기기 안에서 처리됩니다.',
            ),
            _PolicySection(
              title: '동의 거부 및 철회',
              body:
                  '동의하지 않아도 명함 등록과 조회 기능은 사용할 수 있습니다. 주변 거리 기능만 제한되며 설정에서 언제든 동의를 철회할 수 있습니다.',
              isLast: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

class _LocationConsentSheet extends StatelessWidget {
  const _LocationConsentSheet();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + bottomInset),
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: AppColors.borderFunctional)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Semantics(
                label: '위치 사용 안내',
                child: const CircleAvatar(
                  radius: 30,
                  backgroundColor: Color(0x332B76C5),
                  child: AppIcon(
                    AppIconId.pinActive,
                    size: 32,
                    color: AppColors.accentText,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '주변 인맥을 찾기 위해\n현재 위치가 필요해요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '현재 위치와 명함에 등록된 회사 주소를 비교해 가까운 인맥과 거리를 보여드립니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              const _ConsentPoint(
                icon: Icons.phone_android_outlined,
                title: '기기 안에서 거리 계산',
                body: '현재 위치는 개발사 서버로 전송하지 않습니다.',
              ),
              const _ConsentPoint(
                icon: Icons.history_toggle_off_outlined,
                title: '위치 이력은 저장하지 않음',
                body: '앱 사용 중 필요한 순간에만 위치를 조회합니다.',
              ),
              const _ConsentPoint(
                icon: Icons.layers_outlined,
                title: '명함 기능은 계속 사용 가능',
                body: '동의하지 않아도 명함 등록과 조회는 이용할 수 있습니다.',
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => showLocationUsePolicy(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('위치정보 이용 내용 자세히 보기'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const AppIcon(AppIconId.locationInfo),
                label: const Text(
                  '동의하고 위치 사용',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: AppColors.borderFunctional),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('위치 없이 둘러보기'),
              ),
              const SizedBox(height: 10),
              const Text(
                '동의한 경우에만 운영체제 위치 권한 요청 화면이 이어서 표시됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _ConsentPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentText.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.accentText, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  final String title;
  final String body;
  final bool isLast;

  const _PolicySection({
    required this.title,
    required this.body,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.55,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

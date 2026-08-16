import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// 한 칸에서 부딪힌 두 값. `key`는 폼의 필드 키(`mobile`·`email` …)다.
class ScanFieldConflict {
  final String key;
  final String label;

  /// 지금 폼에 들어 있는 값(보통 앞면에서 읽었거나 사용자가 직접 쓴 값).
  final String currentValue;

  /// 방금 스캔에서 읽은 값.
  final String scannedValue;

  const ScanFieldConflict({
    required this.key,
    required this.label,
    required this.currentValue,
    required this.scannedValue,
  });
}

/// 뒷면을 이어 찍었을 때 **이미 채워진 칸에 다른 값이 들어온 경우** 어느 쪽을
/// 쓸지 칸마다 고르게 한다(F-01).
///
/// 왜 필요한가 — 예전에는 이 상황에서 새로 읽은 값이 **조용히 버려졌다.**
/// 빈 칸만 채우는 규칙(`_fillIfEmpty`)이라 이미 값이 있으면 아무 일도 일어나지
/// 않았고, 사용자는 뒷면에 다른 값이 있었다는 사실조차 몰랐다. 흔한 경우가
/// 앞면 휴대폰 / 뒷면 회사 대표번호, 앞면 국문 주소 / 뒷면 영문 주소다.
///
/// **기본은 언제나 "지금 값 유지"다.** 스캔 한 번으로 이미 입력한 값이 저절로
/// 바뀌면 안 된다 — 고르는 것은 사용자다.
///
/// 고른 결과를 `{필드키: 새로 쓸 값}`으로 돌려준다. 아무것도 안 바꿨거나
/// 닫았으면 `null`.
Future<Map<String, String>?> showScanFieldConflictSheet(
  BuildContext context, {
  required List<ScanFieldConflict> conflicts,
}) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // 값을 고르지 않고 바깥을 눌러 닫으면 지금 값이 그대로 남는다(= 예전 동작).
    builder: (_) => _ScanFieldConflictSheet(conflicts: conflicts),
  );
}

class _ScanFieldConflictSheet extends StatefulWidget {
  final List<ScanFieldConflict> conflicts;

  const _ScanFieldConflictSheet({required this.conflicts});

  @override
  State<_ScanFieldConflictSheet> createState() =>
      _ScanFieldConflictSheetState();
}

class _ScanFieldConflictSheetState extends State<_ScanFieldConflictSheet> {
  /// 칸마다 "새로 읽은 값을 쓸지". 기본은 전부 `false`(지금 값 유지).
  final Set<String> _useScanned = {};

  @override
  Widget build(BuildContext context) {
    final count = widget.conflicts.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '뒷면에서 다른 값을 읽었습니다 ($count개)',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '어느 쪽을 쓸지 골라 주세요. 고르지 않으면 지금 값을 그대로 둡니다.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            // 칸이 많으면(양면이 국·영문으로 전부 갈린 명함) 목록이 길어지므로
            // 시트 안에서만 스크롤한다.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in widget.conflicts) ...[
                      Text(
                        c.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      _ValueOption(
                        value: c.currentValue,
                        badge: '지금 값',
                        selected: !_useScanned.contains(c.key),
                        onTap: () =>
                            setState(() => _useScanned.remove(c.key)),
                      ),
                      _ValueOption(
                        value: c.scannedValue,
                        badge: '뒷면',
                        selected: _useScanned.contains(c.key),
                        onTap: () => setState(() => _useScanned.add(c.key)),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '취소',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    final picked = <String, String>{};
                    for (final c in widget.conflicts) {
                      if (_useScanned.contains(c.key)) {
                        picked[c.key] = c.scannedValue;
                      }
                    }
                    Navigator.of(context).pop(picked);
                  },
                  child: const Text(
                    '적용',
                    style: TextStyle(
                      color: AppColors.accentText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueOption extends StatelessWidget {
  final String value;
  final String badge;
  final bool selected;
  final VoidCallback onTap;

  const _ValueOption({
    required this.value,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: '$badge $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                badge,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

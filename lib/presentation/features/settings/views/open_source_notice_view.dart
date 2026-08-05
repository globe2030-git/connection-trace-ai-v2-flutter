import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../common/glass_card.dart';

/// "오픈소스 라이선스" 진입 전에 거치는 한글 안내 화면.
///
/// Flutter의 [showLicensePage]가 보여주는 실제 라이선스 전문은 각 패키지가
/// 원 저작자 이름으로 배포한 원문(대부분 영문)이다. MIT/BSD/Apache 같은
/// 라이선스는 그 원문 자체가 법적 효력을 갖는 텍스트라 번역하면 의미가
/// 미묘하게 달라질 위험이 있고, 수백 개 패키지를 전부 번역할 실익도 없다.
/// 대신 이 화면에서 "왜 영문인지"를 먼저 한글로 설명해, 사용자가 갑자기
/// 영문 텍스트 화면으로 넘어가도 당황하지 않게 한다.
class OpenSourceNoticeView extends StatelessWidget {
  final String applicationName;
  final String applicationVersion;
  final String applicationLegalese;

  const OpenSourceNoticeView({
    super.key,
    required this.applicationName,
    required this.applicationVersion,
    required this.applicationLegalese,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDarkSlate,
      appBar: AppBar(
        title: const Text('오픈소스 라이선스'),
        backgroundColor: AppColors.bgDarkSlate,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.code, size: 36, color: AppColors.accentText),
              const SizedBox(height: 16),
              Text(
                '$applicationName은 여러 오픈소스 라이브러리를 사용해 만들어졌습니다.',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '아래에서 확인하실 수 있는 라이선스 전문은 각 라이브러리 저작자가 '
                '배포한 원문이며, 국제 관례에 따라 대부분 영문으로 표기되어 있습니다. '
                'MIT·BSD·Apache 등 오픈소스 라이선스는 원문 자체가 법적 효력을 갖는 '
                '텍스트라, 의미가 달라질 수 있는 번역 대신 원문을 그대로 보여드립니다.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 24),
              GlassCard(
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: applicationName,
                  applicationVersion: applicationVersion,
                  applicationLegalese: applicationLegalese,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '라이선스 전문 보기 (영문)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

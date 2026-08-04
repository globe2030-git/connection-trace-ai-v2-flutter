import 'package:flutter/material.dart';

import '../../../../core/services/weather_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/ai_provider.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/models/my_profile_model.dart';

class AiBriefingSelection {
  final List<CommunicationLogModel> communicationLogs;
  // 동의 화면에서 미리 조회해 보여준 오늘 날씨 요약. 상대방 위치 정보가
  // 없거나 조회에 실패했으면 null — AiBriefingService.buildPrompt에서
  // 조용히 생략된다.
  final String? weatherSummary;

  const AiBriefingSelection({
    required this.communicationLogs,
    this.weatherSummary,
  });
}

/// AI 요청 직전에 실제 전송 항목을 보여 주고 요청마다 동의를 받는 화면.
/// 이 화면을 통과하지 않은 정보는 AI 서비스 경계로 전달하지 않는다.
class AiDataReviewSheet extends StatefulWidget {
  final AiProvider provider;
  final ContactModel contact;
  final MyProfileModel myProfile;

  const AiDataReviewSheet({
    super.key,
    required this.provider,
    required this.contact,
    required this.myProfile,
  });

  @override
  State<AiDataReviewSheet> createState() => _AiDataReviewSheetState();
}

class _AiDataReviewSheetState extends State<AiDataReviewSheet> {
  late final List<CommunicationLogModel> _availableLogs;
  final Set<String> _selectedIds = {};
  bool _consented = false;

  // 상대방 위치(geo)가 있으면 동의 화면을 여는 시점에 미리 조회해서 "AI에
  // 실제로 전송될 정보"에 날씨도 포함해서 보여준다 — 나중에 조용히 끼워
  // 넣지 않고 동의 화면에서부터 확인할 수 있게.
  String? _weatherSummary;
  bool _isLoadingWeather = false;

  @override
  void initState() {
    super.initState();
    _availableLogs = [...widget.contact.commLogs]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _availableLogs.removeRange(
      _availableLogs.length > 10 ? 10 : _availableLogs.length,
      _availableLogs.length,
    );
    _selectedIds.addAll(_availableLogs.take(5).map((log) => log.id));

    if (widget.contact.geo != null) {
      _isLoadingWeather = true;
      WeatherService.getTodayWeatherSummary(widget.contact.geo).then((
        summary,
      ) {
        if (!mounted) return;
        setState(() {
          _weatherSummary = summary;
          _isLoadingWeather = false;
        });
      });
    }
  }

  String _channelLabel(String type) => switch (type) {
    'call' => '통화 메모',
    'sms' => '문자',
    'email' => '이메일',
    'kakao' => '카카오톡',
    _ => '소통 기록',
  };

  void _submit() {
    if (!_consented) return;
    Navigator.pop(
      context,
      AiBriefingSelection(
        communicationLogs: _availableLogs
            .where((log) => _selectedIds.contains(log.id))
            .toList(),
        weatherSummary: _weatherSummary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: AppColors.accentText,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'AI에 보낼 정보 확인',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '선택한 정보만 ${widget.provider.displayName}로 전송합니다. 앱이 백그라운드에서 자동 전송하지 않습니다.',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '항상 포함되는 기본 정보',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _InfoCard(
                        lines: [
                          '내 정보: ${widget.myProfile.name}, ${widget.myProfile.title}, ${widget.myProfile.company}',
                          '상대방: ${widget.contact.name}, ${widget.contact.title}, ${widget.contact.company}',
                          if (widget.contact.tags.isNotEmpty)
                            '태그: ${widget.contact.tags.join(', ')}',
                          if (widget.contact.interests.isNotEmpty)
                            '관심사: ${widget.contact.interests.join(', ')}',
                          if ((widget.contact.memo ?? '').trim().isNotEmpty)
                            '메모: ${widget.contact.memo}',
                          if (_isLoadingWeather) '오늘 날씨: 조회 중…',
                          if (_weatherSummary != null)
                            '오늘 상대방 지역 날씨: $_weatherSummary',
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '포함할 소통 기록',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${_selectedIds.length}개 선택',
                            style: const TextStyle(
                              color: AppColors.accentText,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_availableLogs.isEmpty)
                        const _InfoCard(lines: ['소통 기록 없이 기본 정보만 전송합니다.'])
                      else
                        ..._availableLogs.map(
                          (log) => Semantics(
                            label: '${_channelLabel(log.type)} ${log.summary}',
                            checked: _selectedIds.contains(log.id),
                            child: Material(
                              color: Colors.transparent,
                              child: CheckboxListTile(
                                value: _selectedIds.contains(log.id),
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected ?? false) {
                                      _selectedIds.add(log.id);
                                    } else {
                                      _selectedIds.remove(log.id);
                                    }
                                  });
                                },
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                activeColor: AppColors.accent,
                                title: Text(
                                  _channelLabel(log.type),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  log.summary,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.bgDarkSlate,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.borderFunctional),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: CheckboxListTile(
                            value: _consented,
                            onChanged: (value) {
                              setState(() => _consented = value ?? false);
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.accent,
                            title: Text(
                              '위 정보가 ${widget.provider.displayName}로 전송되는 데 동의합니다.',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                            subtitle: const Text(
                              '전송 후 처리는 선택한 AI 제공사의 개인정보 처리방침을 따릅니다. 동의는 이번 요청에만 적용됩니다.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _consented ? _submit : null,
                    icon: const Icon(Icons.auto_awesome, color: Colors.white),
                    label: const Text(
                      '동의하고 AI 가이드 만들기',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      disabledBackgroundColor: AppColors.borderDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<String> lines;

  const _InfoCard({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgDarkSlate,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderFunctional),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines
            .map(
              (line) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

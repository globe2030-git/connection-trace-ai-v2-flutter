import 'package:flutter/material.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/ai_usage_service.dart';
import '../../../../core/services/weather_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/models/my_profile_model.dart';

class AiBriefingSelection {
  final List<CommunicationLogModel> communicationLogs;
  // 동의 화면에서 미리 조회해 보여준 오늘 날씨 요약. 상대방 위치 정보가
  // 없거나 조회에 실패했으면 null — AiBriefingService.buildPrompt에서
  // 조용히 생략된다.
  final String? weatherSummary;
  // 2026-08-07: 전화/문자/카카오톡이 플랫폼 정책상 자동 연동이 안 되다 보니
  // (통화 버튼을 누르면 대화 포인트가 안 보이게 되는 문제와 별개로) 사용자가
  // "최근에 이런 얘기를 나눴다" 같은 맥락을 AI에 직접 전달할 방법이 아예
  // 없었다(사용자 피드백). 소통 기록 선택과 별도로 자유롭게 몇 줄 적어 넣을
  // 수 있게 한다 — null/빈 문자열이면 프롬프트에서 조용히 생략된다.
  final String? extraNote;

  const AiBriefingSelection({
    required this.communicationLogs,
    this.weatherSummary,
    this.extraNote,
  });
}

/// AI 요청 직전에 실제 전송 항목을 보여 주고 요청마다 동의를 받는 화면.
/// 이 화면을 통과하지 않은 정보는 회사 서버(커넥션센스 AI 프록시) 경계로
/// 전달하지 않는다.
class AiDataReviewSheet extends StatefulWidget {
  final ContactModel contact;
  final MyProfileModel myProfile;

  const AiDataReviewSheet({
    super.key,
    required this.contact,
    required this.myProfile,
  });

  @override
  State<AiDataReviewSheet> createState() => _AiDataReviewSheetState();
}

class _AiDataReviewSheetState extends State<AiDataReviewSheet> {
  late final List<CommunicationLogModel> _availableLogs;
  final Set<String> _selectedIds = {};
  final _extraNoteController = TextEditingController();
  bool _consented = false;

  // 상대방 위치(geo)가 있으면 동의 화면을 여는 시점에 미리 조회해서 "AI에
  // 실제로 전송될 정보"에 날씨도 포함해서 보여준다 — 나중에 조용히 끼워
  // 넣지 않고 동의 화면에서부터 확인할 수 있게.
  String? _weatherSummary;
  bool _isLoadingWeather = false;

  // 오늘 몇 번 더 쓸 수 있는지. 사용자가 "쓸까 말까"를 정하는 바로 이 화면에
  // 보여줘야 의미가 있다 — 눌러본 뒤 "한도 초과"를 만나면 이미 늦다.
  // 못 읽었으면 null이고, 그 경우 아무것도 표시하지 않는다(추정치를 보여주면
  // 서버 판정과 어긋나 오히려 혼란스럽다).
  AiUsage? _usage;

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

    // 남은 횟수는 서버 카운터가 유일한 진실이라 매번 새로 읽는다.
    AiUsageService.fetch().then((usage) {
      if (mounted) setState(() => _usage = usage);
    });

    if (widget.contact.geo != null) {
      _isLoadingWeather = true;
      WeatherService.getTodayWeatherSummary(widget.contact.geo).then((summary) {
        if (!mounted) return;
        setState(() {
          _weatherSummary = summary;
          _isLoadingWeather = false;
        });
      });
    }
  }

  @override
  void dispose() {
    _extraNoteController.dispose();
    super.dispose();
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
    final note = _extraNoteController.text.trim();
    Navigator.pop(
      context,
      AiBriefingSelection(
        communicationLogs: _availableLogs
            .where((log) => _selectedIds.contains(log.id))
            .toList(),
        weatherSummary: _weatherSummary,
        extraNote: note.isEmpty ? null : note,
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
                    const AppIcon(
                      AppIconId.aiDataInfo,
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
                      const Text(
                        '선택한 정보만 회사 서버를 거쳐 AI로 전송합니다. 앱이 백그라운드에서 자동 전송하지 않습니다.',
                        style: TextStyle(
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
                      const SizedBox(height: 18),
                      const Text(
                        '직접 남길 메모 (선택)',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '통화·문자·카카오톡이 자동으로 연동되지 않는 경우, 최근 나눈 대화나'
                        ' 참고할 내용을 몇 줄 적어두면 AI가 반영합니다.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _extraNoteController,
                        maxLines: 3,
                        maxLength: 300,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: '예: 지난주에 신제품 출시 준비로 바쁘다고 하셨음',
                          hintStyle: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                          ),
                          filled: true,
                          fillColor: AppColors.bgDarkSlate,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.borderFunctional,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.borderFunctional,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.accent,
                            ),
                          ),
                          counterStyle: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
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
                            title: const Text(
                              '위 정보가 회사 서버를 거쳐 AI로 전송되는 데 동의합니다.',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                            subtitle: const Text(
                              '동의는 이 화면을 여는 동안(다시 시도 포함) 유지되며, 화면을 닫으면 사라집니다.',
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_usage != null) ...[
                      _UsageRemainingLine(usage: _usage!),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _consented ? _submit : null,
                        icon: const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                        ),
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

/// 동의 버튼 바로 위에 "몇 번 더 쓸 수 있는지"를 보여준다.
///
/// 여기에 두는 이유: 사용자가 쓸지 말지를 정하는 지점이 여기다. 눌러본 뒤에
/// "오늘 한도를 다 썼어요"를 만나면 이미 늦고, 왜 안 되는지도 알기 어렵다
/// (실사용 피드백 — 잔여 횟수를 확인할 방법이 없어 불편하다).
class _UsageRemainingLine extends StatelessWidget {
  final AiUsage usage;

  const _UsageRemainingLine({required this.usage});

  @override
  Widget build(BuildContext context) {
    final exhausted = usage.exhausted;
    // 오늘 한도와 이번 달 한도 중 먼저 걸리는 쪽을 보여준다. 둘 다 적으면
    // 사용자는 "어느 게 나를 막는 건지" 헷갈린다.
    final scope = usage.isMonthlyBinding ? '이번 달' : '오늘';
    final text = exhausted
        ? '$scope 사용 가능한 횟수를 모두 썼어요'
        : '$scope ${usage.remaining}회 더 쓸 수 있어요';
    final color = exhausted ? AppColors.destructive : AppColors.textSecondary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          exhausted ? Icons.error_outline : Icons.bolt_outlined,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            color: color,
            fontWeight: exhausted ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
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

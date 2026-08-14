import 'package:flutter/material.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/ai_usage_service.dart';
import '../../../../core/services/weather_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/models/my_profile_model.dart';
import '../../../common/legal_document_view.dart';

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
  /// 인맥별 **직전에 고른 소통 기록**. 매번 처음부터 다시 고르지 않도록
  /// 기억한다(사용자 요청, 2026-08-10).
  ///
  /// 기기에 저장하지 않고 앱이 켜져 있는 동안만 들고 있는다 — 남는 것은
  /// 기록 식별자뿐이지만, 굳이 디스크에 늘릴 이유가 없다. 앱을 다시 켜면
  /// 아무것도 선택되지 않은 상태(기본 제외, opt-in)로 시작한다.
  static final Map<String, Set<String>> _lastSelectionByContact = {};

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
    // 기본 선택 없음(opt-in) — 소통 기록은 사용자가 직접 골라야만 전송된다
    // (사용자 결정 2026-08-11: 개인정보라 기본 포함이 아니라 기본 제외로).
    // 단 같은 인맥을 다시 열면 **직전에 사용자가 고른 것**은 되살린다 — 그건
    // 사용자가 명시적으로 선택한 값이라 opt-in 원칙에 어긋나지 않고, 매번
    // 처음부터 다시 고르는 번거로움만 던다. 직전 선택 중 이미 삭제된 기록은
    // 걸러낸다(없는 항목이 선택된 것처럼 보이면 "무엇이 전송되는가"가 어긋남).
    final remembered = _lastSelectionByContact[widget.contact.id];
    final availableIds = _availableLogs.map((log) => log.id).toSet();
    if (remembered != null && remembered.any(availableIds.contains)) {
      _selectedIds.addAll(remembered.where(availableIds.contains));
    }

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
    // 이번에 고른 것을 기억해 다음에 기본값으로 쓴다(사용자 요청, 2026-08-10).
    // 동의까지 마친 선택만 기억한다 — 화면을 그냥 닫은 경우는 "고른 것"이
    // 아니므로 다음번 기본값이 되어서는 안 된다.
    _lastSelectionByContact[widget.contact.id] = {..._selectedIds};
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
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          // 빈 곳을 눌러도 키보드가 닫히게 한다. 멀티라인 입력칸은 키보드에
          // 완료 키가 없어서, 스크롤 말고도 빠져나올 길을 하나 더 둔다
          // (통합본 E-10). `translucent`라 아래 버튼들의 터치는 그대로 간다.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
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
                  // 여러 줄 메모 칸이 있는 화면이다. Android에서 멀티라인 입력칸은
                  // 키보드에 완료 키 대신 **줄바꿈 키**가 떠서 키보드를 닫을 방법이
                  // 없다 — 그대로 두면 위쪽이 키보드에 가린 채 스크롤도 막힌다
                  // (통합본 E-10). 끌어서 스크롤하면 키보드를 내린다.
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 설명은 한 줄로 줄이고 상세는 방침으로 넘긴다(사용자
                        // 요청, 2026-08-10). 이 화면의 본체는 설명이 아니라
                        // **무엇이 나가는지 보여 주고 고르게 하는 것**이라,
                        // 긴 문단이 목록을 밀어내면 오히려 확인을 방해한다.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Expanded(
                              child: Text(
                                '아래 항목만 전송됩니다. 자동 전송은 없습니다.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => showLegalDocument(
                                context,
                                LegalDocument.privacy,
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                '자세히',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accentText,
                                ),
                              ),
                            ),
                          ],
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
                              label:
                                  '${_channelLabel(log.type)} ${log.summary}',
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
                            fillColor: AppColors.bgBase,
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
                            color: AppColors.bgBase,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.borderFunctional,
                            ),
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
                            disabledBackgroundColor: AppColors.borderSubtle,
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
    // "오늘"/"이번 달" 같은 스코프 접두사는 붙이지 않는다 — 보너스 회차가
    // 섞이면 무료 한도의 스코프(일/월)가 더 이상 정확한 설명이 아니다.
    final text = exhausted
        ? '사용 가능한 횟수를 모두 썼어요'
        : '${usage.totalRemaining}회 더 쓸 수 있어요';
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
        color: AppColors.bgBase,
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

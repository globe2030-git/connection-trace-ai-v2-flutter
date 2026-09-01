import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../radar/view_models/radar_view_model.dart';

/// 통화/문자/카카오톡 소통 기록을 사용자가 직접 입력하는 화면.
/// 기기 자동 연동이 안 되는 상황(iOS 전체, 안드로이드의 카카오톡, 또는 그냥
/// 사용자가 직접 요약해서 남기고 싶은 경우) 어디서나 쓸 수 있는 기본 입력
/// 경로 — 소통 이력 기능의 "항상 되는" 기반이 되는 화면이다. v1에서는 이것이
/// 유일한 입력 경로다(Gmail 가져오기 제거, 추가 136).
class ManualCommLogModalView extends StatefulWidget {
  final ContactModel contact;
  final String initialType;

  /// "전한 대화 포인트를 소통 기록에 저장" 흐름에서 [수정 후 저장]을 눌렀을
  /// 때 채널·내용을 미리 채워 넣는 값(2026-08-11). 사용자가 직접 손볼 수
  /// 있도록 이 화면을 그대로 재사용한다.
  final String? initialSummary;

  const ManualCommLogModalView({
    super.key,
    required this.contact,
    this.initialType = 'call',
    this.initialSummary,
  });

  @override
  State<ManualCommLogModalView> createState() => _ManualCommLogModalViewState();
}

class _ManualCommLogModalViewState extends State<ManualCommLogModalView> {
  late String _selectedType;
  DateTime _selectedDateTime = DateTime.now();
  final _summaryController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    final initialSummary = widget.initialSummary;
    if (initialSummary != null && initialSummary.isNotEmpty) {
      _summaryController.text = initialSummary;
    }
  }

  /// 선택 가능한 채널. **소통 기록 추가 시트의 항목과 1:1로 맞춘다** —
  /// 시트에 없는 채널을 여기서만 고를 수 있으면 두 화면이 어긋난다.
  /// 이메일은 추가 136에서 시트의 Gmail 항목을 뺄 때 함께 제거했다(추가 138).
  ///
  /// 채널별 색(`AppColors.channelCall` 등)은 여기서 쓰지 않는다. 칩 4개가
  /// 각각 파랑·초록·주황·노랑이라 화면이 산만했고, 특히 카카오 브랜드
  /// 옐로우(#FEE500) 위의 흰 글자는 대비가 1.3:1로 읽히지 않았다. 선택 상태를
  /// 색 종류가 아니라 **채움 여부**로 구분한다(추가 138).
  static const _channelOptions = [
    {'type': 'call', 'label': '통화', 'icon': AppIconId.call},
    {'type': 'sms', 'label': '문자', 'icon': AppIconId.message},
    {'type': 'kakao', 'label': '카카오톡', 'icon': AppIconId.chatSend},
  ];

  /// 실제로 화면에 그릴 채널 목록. 기본은 위 3종이지만, 브리핑의 "더보기 →
  /// 이메일"에서 [수정 후 저장]으로 넘어온 경우(initialType == 'email')에는
  /// 이메일 칩을 함께 보여준다 — 안 그러면 어느 칩도 선택돼 있지 않은
  /// 상태로 보여, 무슨 채널로 저장되는지 화면이 설명하지 못한다(2026-08-11).
  /// 직접 "추가"로 들어온 경우에는 여전히 3종만 보인다(추가 138의 결정 유지).
  List<Map<String, Object>> get _visibleChannelOptions => [
    ..._channelOptions,
    if (widget.initialType == 'email')
      {'type': 'email', 'label': '이메일', 'icon': AppIconId.mailSend},
  ];

  @override
  void dispose() {
    _summaryController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (time == null || !mounted) return;

    setState(() {
      _selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final newLog = CommunicationLogModel(
      type: _selectedType,
      summary: _summaryController.text.trim(),
      timestamp: _selectedDateTime,
      isAutoSynced: false,
      source: 'manual',
    );

    final updatedContact = widget.contact.copyWith(
      commLogs: [newLog, ...widget.contact.commLogs],
    );

    final viewModel = context.read<RadarViewModel>();
    viewModel.updateContact(updatedContact);
    // 브리핑 화면이 들고 있는 contact 스냅샷도 새로 갱신해서 방금 추가한
    // 기록이 화면에 바로 반영되게 한다.
    viewModel.openBriefing(updatedContact);

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.contact.name} 님의 소통 기록을 추가했습니다.'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  String get _title => switch (_selectedType) {
    'call' => '통화 후 메모',
    'sms' => '문자 내용 추가',
    'kakao' => '카카오톡 내용 추가',
    'email' => '이메일 내용 추가',
    _ => '소통 기록 추가',
  };

  String get _description => switch (_selectedType) {
    'call' => '통화기록을 읽지 않습니다. 통화 후 기억할 내용만 직접 적어 주세요.',
    'sms' => '문자 앱에서 필요한 대화만 복사해 붙여넣어 주세요.',
    'kakao' => '카카오톡에서 필요한 대화만 복사해 붙여넣어 주세요.',
    'email' => '보낸 이메일에서 기억할 내용만 직접 적어 주세요.',
    _ => '필요한 내용만 직접 입력해 주세요.',
  };

  String get _hint => switch (_selectedType) {
    'call' => '예: 신규 프로젝트를 다음 주에 다시 논의하기로 함',
    'sms' => '문자 앱에서 복사한 필요한 대화를 붙여넣으세요.',
    'kakao' => '카카오톡에서 복사한 필요한 대화를 붙여넣으세요.',
    'email' => '예: 견적서 회신 — 다음 주 미팅에서 조건 확정하기로 함',
    _ => '기억할 내용을 입력하세요.',
  };

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    setState(() {
      _summaryController.text = text.length > 2000
          ? text.substring(0, 2000)
          : text;
      _summaryController.selection = TextSelection.collapsed(
        offset: _summaryController.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          // 여러 줄 메모 칸이 있는 화면이다. Android에서 멀티라인 입력칸은
          // 키보드에 완료 키 대신 **줄바꿈 키**가 떠서 키보드를 닫을 방법이
          // 없다 — 그대로 두면 위쪽이 키보드에 가린 채 스크롤도 막힌다
          // (통합본 E-10). 끌어서 스크롤하면 키보드를 내린다.
          child: SingleChildScrollView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 채널을 바꾸면 안내문 길이가 달라져 모달 전체 높이가 출렁인다
                  // (사용자 보고, 2026-08-10). 두 줄 자리를 미리 잡아 두면
                  // 한 줄짜리 안내문에서도 높이가 그대로다. 최소 높이라서
                  // 시스템 글자 크기를 키운 기기에서는 자연히 늘어난다 —
                  // 고정 높이로 잡으면 그런 기기에서 글자가 잘린다.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Text(
                      '${widget.contact.name} 님 · $_description',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    '채널',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 칩을 균등 폭(Expanded)으로 깔고 내용은 각 칩의 가운데에
                  // 둔다(사용자 요청, 2026-08-10). `Wrap` + `ChoiceChip`은 칩
                  // 폭이 글자 수를 따라가서 "통화"와 "카카오톡"의 폭이 두 배
                  // 넘게 차이 났고, 그 상태에서는 안쪽 글자를 가운데로 옮겨도
                  // 줄 전체가 들쭉날쭉해 보인다. 폭을 먼저 맞춰야 정렬이 산다.
                  Row(
                    children: [
                      for (final opt in _visibleChannelOptions) ...[
                        if (opt != _visibleChannelOptions.first)
                          const SizedBox(width: 8),
                        Expanded(
                          child: _ChannelChip(
                            icon: opt['icon'] as AppIconId,
                            label: opt['label'] as String,
                            isSelected: _selectedType == opt['type'],
                            onTap: () => setState(
                              () => _selectedType = opt['type'] as String,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),

                  const Text(
                    '날짜 / 시간',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickDateTime,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bgBase,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderFunctional),
                      ),
                      // 날짜 글자를 박스 가로 한가운데에 둔다(사용자 요청,
                      // 2026-08-10). 양옆 아이콘 슬롯 너비를 24로 똑같이 잡아야
                      // 실제로 가운데에 온다 — 아이콘 크기가 18과 16으로 달라
                      // 그냥 Spacer로 밀면 한쪽으로 치우친다.
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 24,
                            child: Icon(
                              Icons.event,
                              size: 18,
                              color: AppColors.accentText,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${_selectedDateTime.year}.${_selectedDateTime.month.toString().padLeft(2, '0')}.${_selectedDateTime.day.toString().padLeft(2, '0')} '
                              '${_selectedDateTime.hour.toString().padLeft(2, '0')}:${_selectedDateTime.minute.toString().padLeft(2, '0')}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 24,
                            child: Icon(
                              Icons.edit_calendar_outlined,
                              size: 16,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 이 줄이 모달 높이가 출렁이던 가장 큰 원인이었다. "붙여넣기"
                  // 버튼은 문자·카카오톡에서만 나오는데, 버튼이 있는 줄과 글자만
                  // 있는 줄은 높이가 20px 넘게 차이 난다. 채널을 바꿀 때마다
                  // 화면이 튀어 보였다 — 버튼 유무와 무관하게 줄 높이를 40으로
                  // 고정한다(사용자 보고, 2026-08-10).
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '내용 *',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accentText,
                            ),
                          ),
                        ),
                        if (_selectedType == 'sms' || _selectedType == 'kakao')
                          TextButton.icon(
                            onPressed: _pasteFromClipboard,
                            icon: const Icon(Icons.content_paste, size: 16),
                            label: const Text('붙여넣기'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _summaryController,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 2000,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: _hint,
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: AppColors.bgBase,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.borderFunctional,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.borderFunctional,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.accentText,
                          width: 1.5,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.destructive,
                          width: 1.5,
                        ),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '내용을 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text(
                        '기록 저장하기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 채널 선택 칩 하나. `Expanded`로 감싸 쓰는 것을 전제로 하며, 안쪽 내용을
/// 가운데 정렬한다.
///
/// `ChoiceChip`을 쓰지 않는 이유는 두 가지다.
/// 1. 칩 폭이 글자 수를 따라가 "통화"와 "카카오톡"이 두 배 넘게 차이 났다.
///    균등 폭으로 깔아야 줄이 정돈돼 보인다.
/// 2. 선택 시 기본 체크 표시가 채널 아이콘 위에 겹쳐 그려져 무슨 채널인지
///    알아볼 수 없었다.
class _ChannelChip extends StatelessWidget {
  final AppIconId icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChannelChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 선택 시 accent(#2563EB) 채움 + 흰 글자 = 대비 5.17:1로 WCAG AA 통과.
    final foreground = isSelected ? Colors.white : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Material(
        color: isSelected ? AppColors.accent : AppColors.bgBase,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected
                    ? AppColors.accent
                    : AppColors.borderFunctional,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
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

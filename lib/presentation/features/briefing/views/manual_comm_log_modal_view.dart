import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';
import '../../radar/view_models/radar_view_model.dart';

/// 통화/문자/이메일/카카오톡 등 소통 기록을 사용자가 직접 입력하는 화면.
/// 실제 기기 자동 연동이 안 되는 상황(iOS 전체, 안드로이드의 카카오톡/이메일,
/// 또는 그냥 사용자가 직접 요약해서 남기고 싶은 경우) 어디서나 쓸 수 있는
/// 기본 입력 경로 — 소통 이력 연동 기능의 "항상 되는" 기반이 되는 화면이다.
class ManualCommLogModalView extends StatefulWidget {
  final ContactModel contact;
  final String initialType;

  const ManualCommLogModalView({
    super.key,
    required this.contact,
    this.initialType = 'call',
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
  }

  static const _channelOptions = [
    {
      'type': 'call',
      'label': '통화',
      'icon': AppIconId.call,
      'color': AppColors.channelCall,
    },
    {
      'type': 'sms',
      'label': '문자',
      'icon': AppIconId.message,
      'color': AppColors.channelSms,
    },
    {
      'type': 'email',
      'label': '이메일',
      'icon': AppIconId.mailSend,
      'color': AppColors.channelEmail,
    },
    {
      'type': 'kakao',
      'label': '카카오톡',
      'icon': AppIconId.chatSend,
      'color': AppColors.channelKakao,
    },
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
    'email' => '이메일 내용 추가',
    'kakao' => '카카오톡 내용 추가',
    _ => '소통 기록 추가',
  };

  String get _description => switch (_selectedType) {
    'call' => '통화기록을 읽지 않습니다. 통화 후 기억할 내용만 직접 적어 주세요.',
    'sms' => '문자 앱에서 필요한 대화만 복사해 붙여넣어 주세요.',
    'email' => '직접 기록할 이메일 내용을 입력해 주세요. Gmail은 별도 가져오기도 지원합니다.',
    'kakao' => '카카오톡에서 필요한 대화만 복사해 붙여넣어 주세요.',
    _ => '필요한 내용만 직접 입력해 주세요.',
  };

  String get _hint => switch (_selectedType) {
    'call' => '예: 신규 프로젝트를 다음 주에 다시 논의하기로 함',
    'sms' => '문자 앱에서 복사한 필요한 대화를 붙여넣으세요.',
    'email' => '예: 견적서 검토 후 금요일까지 회신 예정',
    'kakao' => '카카오톡에서 복사한 필요한 대화를 붙여넣으세요.',
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
          child: SingleChildScrollView(
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
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.contact.name} 님 · $_description',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.4,
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _channelOptions.map((opt) {
                      final type = opt['type'] as String;
                      final color = opt['color'] as Color;
                      final isSelected = _selectedType == type;
                      return ChoiceChip(
                        selected: isSelected,
                        onSelected: (_) => setState(() => _selectedType = type),
                        avatar: AppIcon(
                          opt['icon'] as AppIconId,
                          size: 16,
                          color: isSelected ? Colors.white : color,
                        ),
                        label: Text(opt['label'] as String),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                        selectedColor: color,
                        backgroundColor: AppColors.bgBase,
                        side: BorderSide(color: color.withValues(alpha: 0.4)),
                      );
                    }).toList(),
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
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event,
                            size: 18,
                            color: AppColors.accentText,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_selectedDateTime.year}.${_selectedDateTime.month.toString().padLeft(2, '0')}.${_selectedDateTime.day.toString().padLeft(2, '0')} '
                            '${_selectedDateTime.hour.toString().padLeft(2, '0')}:${_selectedDateTime.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.edit_calendar_outlined,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  Row(
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

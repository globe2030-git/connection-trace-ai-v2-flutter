import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/utils/korean_phone_formatter.dart';
import '../../../../core/utils/web_tab_guard.dart';
import '../../../../core/services/address_geocoding_service.dart';
import '../../../../core/services/ocr_scanner_service.dart';
import '../../../../data/models/contact_model.dart';
import '../view_models/wallet_view_model.dart';
import 'camera_scan_modal_view.dart';
import 'file_picker_modal_view.dart';

class AddCardModalView extends StatefulWidget {
  final ContactModel? contactToEdit;
  // QR 스캔 등으로 미리 채워 넣을 값 — contactToEdit과 달리 "새 명함"으로
  // 저장된다(기존 id를 덮어쓰지 않음). 필드 초기값 채우는 용도로만 쓰임.
  final ContactModel? prefillData;

  const AddCardModalView({super.key, this.contactToEdit, this.prefillData});

  @override
  State<AddCardModalView> createState() => _AddCardModalViewState();
}

class _AddCardModalViewState extends State<AddCardModalView> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  late TextEditingController _nameController;
  late TextEditingController _companyController;
  late TextEditingController _titleController;
  late TextEditingController _addressController;
  late TextEditingController _addressDetailController;
  late TextEditingController _phoneController;
  late TextEditingController _officePhoneController;
  late TextEditingController _emailController;
  late TextEditingController _tagsController;
  late TextEditingController _memoController;

  // Strict Contiguous Sequential Focus Nodes to prevent Tab/Enter key jumping
  final _nameFocusNode = FocusNode();
  final _companyFocusNode = FocusNode();
  final _titleFocusNode = FocusNode();
  final _addressFocusNode = FocusNode();
  final _addressDetailFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _officePhoneFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _tagsFocusNode = FocusNode();
  final _memoFocusNode = FocusNode();

  // [버그 수정] Tab 키가 필드를 건너뛰던 문제 — FocusTraversalOrder, 필드별
  // Focus.onKeyEvent, 폼 전체 Shortcuts+Actions(NextFocusIntent 재정의)까지 Dart
  // 레벨에서 세 가지를 시도했지만 전부 재현 계속됨. 디버그 로그로 확인해보니 Dart
  // 쪽 currentIndex 자체는 Tab마다 정확히 1씩 증가하는데, 그 직후 "브라우저의 기본
  // Tab 동작"이 별도로 한 번 더 끼어들어 실제 화면 포커스를 그 다음 칸으로 밀어버려
  // 결과적으로 한 칸 더 건너뛰는 것으로 나타남 — 즉 Dart 레벨 어떤 방식으로도 브라우저
  // 자체의 네이티브 Tab 기본 동작을 완전히 못 막았던 것. 그래서 web_tab_guard.dart에서
  // document keydown을 capture 단계에서 직접 가로채 preventDefault로 브라우저 기본
  // 동작 자체를 원천 차단하고, 포커스 이동은 오직 이 리스트 순서 기준 _moveFocus만
  // 담당한다(initState에서 WebTabGuard.install로 연결).
  late final List<FocusNode> _fieldFocusOrder;

  // Profile Picture Avatar URL State & OCR Raw Text State
  String? _selectedAvatarUrl;
  String? _scannedRawText;
  bool _isScanningOcr = false;
  bool _showRawTextCard = false;
  bool _isSavingCard = false;

  final List<String> _avatarPresets = const [
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
    'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=150',
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150',
  ];

  bool get _isEditing => widget.contactToEdit != null;

  @override
  void initState() {
    super.initState();
    final c = widget.contactToEdit ?? widget.prefillData;
    _selectedAvatarUrl = c?.avatarUrl;
    _nameController = TextEditingController(text: c?.name ?? '');
    _companyController = TextEditingController(text: c?.company ?? '');
    _titleController = TextEditingController(text: c?.title ?? '');
    _addressController = TextEditingController(text: c?.address ?? '');
    _addressDetailController = TextEditingController(text: c?.addressDetail ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _officePhoneController = TextEditingController(text: c?.officePhone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _tagsController = TextEditingController(text: c != null ? c.tags.join(', ') : 'AI, IT');
    _memoController = TextEditingController(text: c?.memo ?? '');
    _fieldFocusOrder = [
      _nameFocusNode,
      _companyFocusNode,
      _titleFocusNode,
      _addressFocusNode,
      _addressDetailFocusNode,
      _phoneFocusNode,
      _officePhoneFocusNode,
      _emailFocusNode,
      _tagsFocusNode,
      _memoFocusNode,
    ];
    WebTabGuard.install(onTab: (shiftKey) => _moveFocus(shiftKey ? -1 : 1));
  }

  @override
  void dispose() {
    WebTabGuard.uninstall();
    _nameController.dispose();
    _companyController.dispose();
    _titleController.dispose();
    _addressController.dispose();
    _addressDetailController.dispose();
    _phoneController.dispose();
    _officePhoneController.dispose();
    _emailController.dispose();
    _tagsController.dispose();
    _memoController.dispose();

    _nameFocusNode.dispose();
    _companyFocusNode.dispose();
    _titleFocusNode.dispose();
    _addressFocusNode.dispose();
    _addressDetailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _officePhoneFocusNode.dispose();
    _emailFocusNode.dispose();
    _tagsFocusNode.dispose();
    _memoFocusNode.dispose();
    super.dispose();
  }

  // _fieldFocusOrder 리스트 기준으로 현재 포커스된 필드를 찾아 delta칸 이동한다
  // (+1 = 정방향 Tab, -1 = Shift+Tab). 위젯 트리 순서나 브라우저 네이티브 DOM
  // 탭 순서와 무관하게 오직 이 리스트만이 이동 순서를 결정한다.
  void _moveFocus(int delta) {
    final currentIndex = _fieldFocusOrder.indexWhere((n) => n.hasFocus);
    if (currentIndex == -1) return;
    final nextIndex = currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= _fieldFocusOrder.length) {
      FocusScope.of(context).unfocus();
      return;
    }
    _fieldFocusOrder[nextIndex].requestFocus();
  }

  /// AI OCR Business Card Scanner (Camera / Image Gallery)
  Future<void> _performOcrScan({required bool isFromCamera}) async {
    OcrScanResult? result;

    if (isFromCamera) {
      // Open camera scanner view with viewfinder shutter
      result = await Navigator.push<OcrScanResult>(
        context,
        MaterialPageRoute(builder: (_) => const CameraScanModalView()),
      );
    } else {
      // Open interactive gallery / file explorer picker view
      result = await showModalBottomSheet<OcrScanResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const FilePickerModalView(),
      );
    }

    if (result == null || !mounted) return;

    setState(() {
      _isScanningOcr = false;
      _scannedRawText = result!.rawText;
      _showRawTextCard = true;
      _nameController.text = result.name;
      _companyController.text = result.company;
      _titleController.text = result.title;
      _addressController.text = result.address;
      _phoneController.text = result.phone;
      _officePhoneController.text = '02-555-1234';
      _emailController.text = result.email;
      _tagsController.text = result.tags.join(', ');
      _memoController.text = 'AI OCR 스캔으로 자동 추출된 명함 텍스트 정보입니다.';
      if (result.avatarUrl != null) {
        _selectedAvatarUrl = result.avatarUrl;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isFromCamera ? '📸 명함 촬영 스캔이 완료되었습니다!' : '🖼️ 선택한 파일의 명함 텍스트가 스캔되었습니다!'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  Future<void> _saveCard() async {
    // 1. Basic required validations
    if (_nameController.text.trim().isEmpty) {
      _focusAndShowError(_nameFocusNode, '⚠️ 이름을 입력해 주세요.');
      return;
    }
    if (_companyController.text.trim().isEmpty) {
      _focusAndShowError(_companyFocusNode, '⚠️ 회사명을 입력해 주세요.');
      return;
    }

    final rawAddress = _addressController.text.trim();
    if (rawAddress.isEmpty) {
      _focusAndShowError(_addressFocusNode, '⚠️ 회사 주소를 입력해 주세요.');
      return;
    }

    final phoneVal = _phoneController.text.trim();
    final phoneRegExp = RegExp(r'^\d{2,3}-\d{3,4}-\d{4}$');
    if (phoneVal.isEmpty) {
      _focusAndShowError(_phoneFocusNode, '⚠️ 휴대폰 번호를 입력해 주세요.');
      return;
    } else if (!phoneRegExp.hasMatch(phoneVal)) {
      _focusAndShowError(_phoneFocusNode, '⚠️ 올바른 전화번호 형식(예: 010-1234-5678)으로 입력해 주세요.');
      return;
    }

    final emailVal = _emailController.text.trim();
    if (emailVal.isEmpty) {
      _focusAndShowError(_emailFocusNode, '⚠️ 이메일을 입력해 주세요.');
      return;
    } else if (!emailVal.contains('@') || !emailVal.contains('.')) {
      _focusAndShowError(_emailFocusNode, '⚠️ 올바른 이메일 형식을 입력해 주세요.');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 2. Address Geocoding & Road Name Address Conversion Dialog
    setState(() => _isSavingCard = true);
    final addressResult = await AddressGeocodingService.validateAndConvert(rawAddress);
    if (!mounted) return;
    setState(() => _isSavingCard = false);

    if (!addressResult.isValid) {
      // Unresolvable address prompt
      _showUnresolvableAddressDialog(rawAddress);
      return;
    }

    // Check if Road Name Address conversion prompt is needed
    if (addressResult.roadNameAddress != null &&
        addressResult.roadNameAddress != rawAddress &&
        !rawAddress.contains('(도로명')) {
      _showRoadNameConversionDialog(addressResult);
    } else {
      _executeFinalSave(addressResult.roadNameAddress ?? rawAddress, addressResult.geoPosition);
    }
  }

  void _showUnresolvableAddressDialog(String rawAddress) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('📍 주소 위치 확인 필요', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '입력하신 주소 ("$rawAddress")의 GPS 위치를 정밀하게 찾을 수 없습니다.',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 12),
            if (_scannedRawText != null) ...[
              const Text(
                '💡 명함 RAW 스캔 텍스트:',
                style: TextStyle(color: AppColors.accentText, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgDarkSlate,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _scannedRawText!,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              '건물명이나 도로명 주소(예: 테헤란로 123)로 직접 수정하여 입력해 주세요.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addressFocusNode.requestFocus();
            },
            child: const Text('주소 수정하기', style: TextStyle(color: AppColors.accentText, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showRoadNameConversionDialog(AddressValidationResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('🛣️ 도로명 주소 자동 변환', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '입력하신 주소를 표준 정밀 도로명 주소로 자동 변환하시겠습니까?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgDarkSlate,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• 기존 입력 주소: ${result.originalAddress}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• 변경 도로명 주소: ${result.roadNameAddress}',
                    style: const TextStyle(color: AppColors.accentText, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeFinalSave(result.originalAddress, result.geoPosition);
            },
            child: const Text('기존 입력 유지', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addressController.text = result.roadNameAddress!;
              _executeFinalSave(result.roadNameAddress!, result.geoPosition);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('네, 도로명으로 변경', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _executeFinalSave(String finalAddress, GeoPosition? resolvedGeo) {
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final contact = ContactModel(
      id: _isEditing ? widget.contactToEdit!.id : DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      company: _companyController.text.trim(),
      title: _titleController.text.trim().isEmpty ? '담당자' : _titleController.text.trim(),
      address: finalAddress,
      addressDetail: _addressDetailController.text.trim().isEmpty ? null : _addressDetailController.text.trim(),
      phone: _phoneController.text.trim(),
      officePhone: _officePhoneController.text.trim().isEmpty ? null : _officePhoneController.text.trim(),
      email: _emailController.text.trim(),
      avatarUrl: _selectedAvatarUrl,
      tags: tags.isEmpty ? ['신규'] : tags,
      geo: resolvedGeo ?? (_isEditing ? widget.contactToEdit!.geo : const GeoPosition(lat: 37.4979, lng: 127.0276)),
      talkingPoints: _isEditing ? widget.contactToEdit!.talkingPoints : [
        '최근 프로젝트 진행 상황 공유하기',
        '다음 비즈니스 미팅 일정 제안하기',
      ],
      commLogs: _isEditing ? widget.contactToEdit!.commLogs : [],
      isPriority: _isEditing ? widget.contactToEdit!.isPriority : false,
      memo: _memoController.text.trim().isEmpty ? null : _memoController.text.trim(),
    );

    if (_isEditing) {
      context.read<WalletViewModel>().updateContact(contact);
    } else {
      context.read<WalletViewModel>().addContact(contact);
    }
    
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isEditing ? '🎉 ${contact.name} 님의 명함 정보가 수정되었습니다!' : '🎉 ${contact.name} 님의 명함이 등록되었습니다!'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  void _focusAndShowError(FocusNode focusNode, String message) {
    focusNode.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.destructive,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderDark,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _isEditing ? '🎴 명함 정보 수정' : '🎴 새 명함 직접 등록',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.textSecondary),
                        tooltip: '입력 취소',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '* 필수 입력 항목',
                      style: TextStyle(fontSize: 12, color: AppColors.destructive, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 📸 OCR Camera & Gallery Scan Action Buttons
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgDarkSlate,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📷 명함 자동 스캔 (OCR)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.accentText),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isScanningOcr ? null : () => _performOcrScan(isFromCamera: true),
                                icon: _isScanningOcr
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                label: const Text('명함 촬영 스캔', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isScanningOcr ? null : () => _performOcrScan(isFromCamera: false),
                                icon: const Icon(Icons.photo_library, size: 16, color: AppColors.accentText),
                                label: const Text('이미지 업로드', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.accentText)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.accentText),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 📸 Profile Photo Selector Widget
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            final nextIdx = _selectedAvatarUrl == null
                                ? 0
                                : (_avatarPresets.indexOf(_selectedAvatarUrl!) + 1) % (_avatarPresets.length + 1);
                            setState(() {
                              _selectedAvatarUrl = nextIdx < _avatarPresets.length ? _avatarPresets[nextIdx] : null;
                            });
                          },
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                                backgroundImage: _selectedAvatarUrl != null ? NetworkImage(_selectedAvatarUrl!) : null,
                                child: _selectedAvatarUrl == null
                                    ? const Icon(Icons.person, size: 36, color: AppColors.accentText)
                                    : null,
                              ),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: AppColors.accentText,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '프로필 사진 선택 (터치하여 변경)',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Collapsible RAW Scanned Text Card
                  if (_scannedRawText != null) ...[
                    GestureDetector(
                      onTap: () => setState(() => _showRawTextCard = !_showRawTextCard),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.accentText.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.accentText.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '📄 OCR 스캔 RAW 텍스트 확인 / 복원',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accentText),
                            ),
                            Icon(_showRawTextCard ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.accentText, size: 18),
                          ],
                        ),
                      ),
                    ),
                    if (_showRawTextCard) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.bgDarkSlate,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderDark),
                        ),
                        child: Text(
                          _scannedRawText!,
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontFamily: 'monospace'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  // 1. 이름 (필수)
                  _buildFormField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    order: 1,
                    nextFocusNode: _companyFocusNode,
                    autofocus: true,
                    label: '이름 *',
                    hint: '예: 홍길동',
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '이름을 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // 2. 회사명 (필수)
                  _buildFormField(
                    controller: _companyController,
                    focusNode: _companyFocusNode,
                    order: 2,
                    nextFocusNode: _titleFocusNode,
                    label: '회사명 *',
                    hint: '예: 카카오 / 삼성전자',
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '회사명을 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // 3. 직함 / 부서 (선택)
                  _buildFormField(
                    controller: _titleController,
                    focusNode: _titleFocusNode,
                    order: 3,
                    nextFocusNode: _addressFocusNode,
                    label: '직함 / 부서',
                    hint: '예: 팀장 / R&D 센터',
                  ),
                  const SizedBox(height: 12),

                  // 4. 회사 주소 — 도로명까지(위치 정보/지오코딩의 기준이 되는 부분)
                  _buildFormField(
                    controller: _addressController,
                    focusNode: _addressFocusNode,
                    order: 4,
                    nextFocusNode: _addressDetailFocusNode,
                    label: '회사 주소 (도로명) *',
                    hint: '예: 서울특별시 강남구 테헤란로 123',
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '회사 주소를 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // 4-1. 상세주소(선택) — 건물명/층/호수 등. 위치 정보에는 안 쓰이고
                  // 표시용으로만 별도 보관.
                  _buildFormField(
                    controller: _addressDetailController,
                    focusNode: _addressDetailFocusNode,
                    order: 4.5,
                    nextFocusNode: _phoneFocusNode,
                    label: '상세주소 (선택)',
                    hint: '예: 5층 501호',
                  ),
                  const SizedBox(height: 12),

                  // 5. 휴대폰 번호 (필수 + 실시간 형식 감시)
                  _buildFormField(
                    controller: _phoneController,
                    focusNode: _phoneFocusNode,
                    order: 5,
                    nextFocusNode: _officePhoneFocusNode,
                    label: '휴대폰 번호 *',
                    hint: '예: 010-1234-5678',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '휴대폰 번호를 입력해 주세요.';
                      }
                      final phoneRegExp = RegExp(r'^\d{2,3}-\d{3,4}-\d{4}$');
                      if (!phoneRegExp.hasMatch(val.trim())) {
                        return '올바른 전화번호 형식(예: 010-1234-5678)으로 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // 6. 사무실 전화번호 (선택)
                  _buildFormField(
                    controller: _officePhoneController,
                    focusNode: _officePhoneFocusNode,
                    order: 6,
                    nextFocusNode: _emailFocusNode,
                    label: '사무실 전화번호 (선택)',
                    hint: '예: 02-123-4567',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 12),

                  // 7. 이메일 (필수!)
                  _buildFormField(
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    order: 7,
                    nextFocusNode: _tagsFocusNode,
                    label: '이메일 *',
                    hint: '예: example@company.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '이메일을 입력해 주세요.';
                      }
                      if (!val.contains('@') || !val.contains('.')) {
                        return '올바른 이메일 형식을 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // 8. 태그 키워드
                  _buildFormField(
                    controller: _tagsController,
                    focusNode: _tagsFocusNode,
                    order: 8,
                    nextFocusNode: _memoFocusNode,
                    label: '태그 키워드 (쉼표 구분)',
                    hint: '예: AI, 바이오, C-Level',
                  ),
                  const SizedBox(height: 12),

                  // 9. Memo Summary (메모 및 특징 요약)
                  _buildFormField(
                    controller: _memoController,
                    focusNode: _memoFocusNode,
                    order: 9,
                    isLast: true,
                    maxLines: 3,
                    label: 'Memo Summary (메모 및 특징 요약)',
                    hint: '인맥에 대한 주요 특징, 비즈니스 연관성, 미팅 메모 등을 자유롭게 입력하세요.',
                  ),
                  const SizedBox(height: 22),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSavingCard ? null : _saveCard,
                      icon: _isSavingCard
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(_isEditing ? Icons.edit : Icons.check, color: Colors.white),
                      label: Text(
                        _isSavingCard ? '주소 확인 중...' : (_isEditing ? '명함 수정 완료' : '명함 저장하기'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required double order,
    FocusNode? nextFocusNode,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool isLast = false,
    int maxLines = 1,
    bool autofocus = false,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: label.contains('*') ? AppColors.accentText : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          textInputAction: maxLines > 1
              ? TextInputAction.newline
              : (isLast ? TextInputAction.done : TextInputAction.next),
          onEditingComplete: () {
            if (nextFocusNode != null) {
              nextFocusNode.requestFocus();
            } else {
              FocusScope.of(context).unfocus();
            }
          },
          onFieldSubmitted: (_) {
            if (nextFocusNode != null) {
              FocusScope.of(context).requestFocus(nextFocusNode);
            }
          },
          validator: validator,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.bgDarkSlate,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            errorStyle: const TextStyle(color: AppColors.destructive, fontSize: 11.5, fontWeight: FontWeight.bold),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderFunctional),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderFunctional),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accentText, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.destructive, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

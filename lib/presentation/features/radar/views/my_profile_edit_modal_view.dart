import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/korean_phone_formatter.dart';
import '../../../../core/services/ocr_scanner_service.dart';
import '../../../../data/models/my_profile_model.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../common/address_search_view.dart';
import '../../wallet/views/camera_scan_modal_view.dart';
import '../../wallet/views/file_picker_modal_view.dart';

class MyProfileEditModalView extends StatefulWidget {
  const MyProfileEditModalView({super.key});

  @override
  State<MyProfileEditModalView> createState() => _MyProfileEditModalViewState();
}

class _MyProfileEditModalViewState extends State<MyProfileEditModalView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _titleController;
  late final TextEditingController _companyController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _addressDetailController;

  // 이 화면은 자체 Scaffold 없이 showModalBottomSheet의 콘텐츠로만 쓰여서
  // ScaffoldMessenger.of(context)를 쓰면 스낵바가 모달 뒤 페이지로 가서 안 보이고,
  // Scaffold로 감싸면 시트 높이 계산과 충돌해 레이아웃이 깨진다(add_card_modal_view.dart
  // 에서 실기기로 확인된 문제) — 폼 안에 직접 그리는 배너로 우회한다.
  String? _inlineNoticeText;

  String? _avatarPath;
  bool _avatarCleared = false;
  bool _isPickingAvatar = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<MyProfileRepository>().profile;
    _nameController = TextEditingController(text: profile.name);
    _titleController = TextEditingController(text: profile.title);
    _companyController = TextEditingController(text: profile.company);
    _phoneController = TextEditingController(text: profile.phone);
    _emailController = TextEditingController(text: profile.email);
    _addressController = TextEditingController(text: profile.address);
    _addressDetailController = TextEditingController(text: profile.addressDetail ?? '');
    _avatarPath = profile.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _addressDetailController.dispose();
    super.dispose();
  }

  Future<void> _openAddressSearch() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const AddressSearchView()),
    );
    if (result != null && result.trim().isNotEmpty && mounted) {
      setState(() => _addressController.text = result.trim());
    }
  }

  /// 내 명함도 실물 명함을 스캔해서 채울 수 있어야 한다는 요청으로 추가 —
  /// 명함 등록 화면과 동일한 카메라/파일 스캔을 재사용한다. 이 화면은 "이미
  /// 채워진 프로필을 고치는" 폼이라 명함 등록 때처럼 빈 칸만 채우는 방식이
  /// 아니라, 스캔으로 실제 읽힌 값만(빈 문자열은 무시) 기존 값 위에 덮어써
  /// "실물 명함으로 프로필을 최신화"하는 의도에 맞춘다.
  Future<void> _performOcrScan({required bool isFromCamera}) async {
    OcrScanResult? result;
    if (isFromCamera) {
      result = await Navigator.push<OcrScanResult>(
        context,
        MaterialPageRoute(builder: (_) => const CameraScanModalView()),
      );
    } else {
      result = await showModalBottomSheet<OcrScanResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const FilePickerModalView(),
      );
    }
    if (result == null || !mounted) return;

    setState(() {
      if (result!.name.trim().isNotEmpty) _nameController.text = result.name.trim();
      if (result.title.trim().isNotEmpty) _titleController.text = result.title.trim();
      if (result.company.trim().isNotEmpty) _companyController.text = result.company.trim();
      if (result.phone.trim().isNotEmpty) _phoneController.text = result.phone.trim();
      if (result.email.trim().isNotEmpty) _emailController.text = result.email.trim();
      if (result.address.trim().isNotEmpty) _addressController.text = result.address.trim();
      _inlineNoticeText = '📸 스캔한 명함 정보로 채웠습니다. 내용을 확인하고 저장해 주세요.';
    });
  }

  /// 갤러리에서 고른 사진을 앱 문서 디렉터리에 고정된 파일명으로 복사해 둔다.
  /// image_picker가 주는 경로는 임시 캐시라 앱 재시작 시 사라질 수 있어서,
  /// 영구 보관하려면 직접 복사해야 한다. 매번 같은 파일명으로 덮어써서
  /// 이전 사진 파일이 버려지지 않게 한다.
  Future<void> _pickAvatarPhoto() async {
    setState(() => _isPickingAvatar = true);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked == null || !mounted) return;
      final docsDir = await getApplicationDocumentsDirectory();
      final savedPath = '${docsDir.path}/my_profile_avatar.jpg';
      await File(picked.path).copy(savedPath);
      if (!mounted) return;
      setState(() {
        _avatarPath = savedPath;
        _avatarCleared = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _inlineNoticeText = '⚠️ 사진을 불러오지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _isPickingAvatar = false);
    }
  }

  void _removeAvatarPhoto() {
    setState(() {
      _avatarPath = null;
      _avatarCleared = true;
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final updated = MyProfileModel(
      name: _nameController.text.trim(),
      title: _titleController.text.trim(),
      company: _companyController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
      addressDetail: _addressDetailController.text.trim().isEmpty ? null : _addressDetailController.text.trim(),
      avatarPath: _avatarCleared ? null : _avatarPath,
    );

    context.read<MyProfileRepository>().updateProfile(updated);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('👤 내 디지털 명함 정보를 저장했습니다.'), backgroundColor: AppColors.accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
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
                      decoration: BoxDecoration(color: AppColors.borderDark, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '✏️ 내 디지털 명함 수정',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Center(child: _buildAvatarPicker()),
                  const SizedBox(height: 16),

                  if (OcrScannerService.isSupportedOnThisPlatform) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _performOcrScan(isFromCamera: true),
                            icon: const Icon(Icons.camera_alt_outlined, size: 18, color: AppColors.accentText),
                            label: const Text('내 명함 카메라 스캔', style: TextStyle(fontSize: 12.5, color: AppColors.accentText, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.accentText),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _performOcrScan(isFromCamera: false),
                            icon: const Icon(Icons.folder_open, size: 18, color: AppColors.textSecondary),
                            label: const Text('파일에서 스캔', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.borderDark),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_inlineNoticeText != null) ...[
                    _buildInlineNotice(),
                    const SizedBox(height: 12),
                  ],

                  _buildField(controller: _nameController, label: '이름 / 직책 *', hint: '예: 홍길동 대표', required: true),
                  const SizedBox(height: 12),
                  _buildField(controller: _titleController, label: '직함', hint: '예: C-Level'),
                  const SizedBox(height: 12),
                  _buildField(controller: _companyController, label: '회사명 *', hint: '예: 커넥션 트레이스 AI', required: true),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _phoneController,
                    label: '휴대폰 번호 *',
                    hint: '예: 010-1234-5678',
                    keyboardType: TextInputType.phone,
                    required: true,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _emailController,
                    label: '이메일 *',
                    hint: '예: example@company.com',
                    keyboardType: TextInputType.emailAddress,
                    required: true,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return '이메일을 입력해 주세요.';
                      if (!val.contains('@') || !val.contains('.')) return '올바른 이메일 형식을 입력해 주세요.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _addressController,
                    label: '주소 (도로명) *',
                    hint: '예: 서울특별시 강남구 테헤란로 123',
                    required: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, color: AppColors.accentText),
                      tooltip: '도로명주소 검색',
                      onPressed: _openAddressSearch,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildField(controller: _addressDetailController, label: '상세주소 (선택)', hint: '예: 5층 501호'),

                  const SizedBox(height: 22),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('저장하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

  Widget _buildInlineNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _inlineNoticeText!,
              style: const TextStyle(fontSize: 12.5, color: AppColors.accentText, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.close, size: 16, color: AppColors.accentText),
            onPressed: () => setState(() => _inlineNoticeText = null),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPicker() {
    return Column(
      children: [
        Stack(
          children: [
            GestureDetector(
              onTap: _isPickingAvatar ? null : _pickAvatarPhoto,
              child: CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                backgroundImage: _avatarPath != null ? FileImage(File(_avatarPath!)) : null,
                child: _isPickingAvatar
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentText))
                    : (_avatarPath == null
                        ? Text(
                            _nameController.text.trim().isNotEmpty ? _nameController.text.trim().substring(0, 1) : '?',
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.accentText),
                          )
                        : null),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _isPickingAvatar ? null : _pickAvatarPhoto,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        if (_avatarPath != null) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: _removeAvatarPhoto,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('사진 삭제', style: TextStyle(fontSize: 12, color: AppColors.destructive, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool required = false,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: label.contains('*') ? AppColors.accentText : AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.bgDarkSlate,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderFunctional)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.borderFunctional)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accentText, width: 1.5)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.destructive, width: 1.5)),
            suffixIcon: suffixIcon,
          ),
          validator: validator ?? (required ? (val) => (val == null || val.trim().isEmpty) ? '${label.replaceAll(' *', '')}을(를) 입력해 주세요.' : null : null),
        ),
      ],
    );
  }
}

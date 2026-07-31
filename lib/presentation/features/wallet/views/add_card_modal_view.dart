import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../data/models/contact_model.dart';
import '../view_models/wallet_view_model.dart';

class AddCardModalView extends StatefulWidget {
  const AddCardModalView({super.key});

  @override
  State<AddCardModalView> createState() => _AddCardModalViewState();
}

class _AddCardModalViewState extends State<AddCardModalView> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _officePhoneController = TextEditingController();
  final _titleController = TextEditingController();
  final _emailController = TextEditingController();
  final _tagsController = TextEditingController(text: 'AI, IT');

  // Sequential Focus Nodes to prevent cursor jumping
  final _nameFocusNode = FocusNode();
  final _companyFocusNode = FocusNode();
  final _addressFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _officePhoneFocusNode = FocusNode();
  final _titleFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _tagsFocusNode = FocusNode();

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _officePhoneController.dispose();
    _titleController.dispose();
    _emailController.dispose();
    _tagsController.dispose();

    _nameFocusNode.dispose();
    _companyFocusNode.dispose();
    _addressFocusNode.dispose();
    _phoneFocusNode.dispose();
    _officePhoneFocusNode.dispose();
    _titleFocusNode.dispose();
    _emailFocusNode.dispose();
    _tagsFocusNode.dispose();
    super.dispose();
  }

  void _saveCard() {
    // Check validation and automatically jump/focus to the first invalid field
    if (_nameController.text.trim().isEmpty) {
      _focusAndShowError(_nameFocusNode, '⚠️ 이름을 입력해 주세요.');
      return;
    }
    if (_companyController.text.trim().isEmpty) {
      _focusAndShowError(_companyFocusNode, '⚠️ 회사명을 입력해 주세요.');
      return;
    }
    if (_addressController.text.trim().isEmpty) {
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
      _focusAndShowError(_emailFocusNode, '⚠️ 올바른 이메일 형식(예: example@company.com)으로 입력해 주세요.');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final newContact = ContactModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      company: _companyController.text.trim(),
      title: _titleController.text.trim().isEmpty ? '담당자' : _titleController.text.trim(),
      address: _addressController.text.trim(),
      phone: phoneVal,
      officePhone: _officePhoneController.text.trim().isEmpty ? null : _officePhoneController.text.trim(),
      email: emailVal,
      tags: tags.isEmpty ? ['신규'] : tags,
      geo: const GeoPosition(lat: 37.4979, lng: 127.0276),
      talkingPoints: [
        '최근 프로젝트 진행 상황 공유하기',
        '다음 비즈니스 미팅 일정 제안하기',
      ],
      isPriority: false,
    );

    context.read<WalletViewModel>().addContact(newContact);
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🎉 ${newContact.name} 님의 명함이 성공적으로 저장되었습니다!'),
        backgroundColor: AppColors.accentSky,
      ),
    );
  }

  void _focusAndShowError(FocusNode focusNode, String message) {
    focusNode.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
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
                  children: const [
                    Text(
                      '🎴 새 명함 직접 등록',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    Text(
                      '* 필수 입력 항목',
                      style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600),
                    )
                  ],
                ),
                const SizedBox(height: 16),

                // 1. 이름 (필수)
                _buildFormField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  nextFocusNode: _companyFocusNode,
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
                  nextFocusNode: _addressFocusNode,
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

                // 3. 회사 주소 (필수)
                _buildFormField(
                  controller: _addressController,
                  focusNode: _addressFocusNode,
                  nextFocusNode: _phoneFocusNode,
                  label: '회사 주소 / 위치 *',
                  hint: '예: 서울특별시 강남구 테헤란로 123',
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return '회사 주소를 입력해 주세요.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // 4. 휴대폰 번호 (필수 + 실시간 형식 감시)
                _buildFormField(
                  controller: _phoneController,
                  focusNode: _phoneFocusNode,
                  nextFocusNode: _officePhoneFocusNode,
                  label: '휴대폰 번호 *',
                  hint: '예: 010-1234-5678',
                  keyboardType: TextInputType.phone,
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

                // 5. 사무실 전화번호 (선택)
                _buildFormField(
                  controller: _officePhoneController,
                  focusNode: _officePhoneFocusNode,
                  nextFocusNode: _titleFocusNode,
                  label: '사무실 전화번호 (선택)',
                  hint: '예: 02-123-4567',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),

                // 6. 직함 / 부서 (선택)
                _buildFormField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  nextFocusNode: _emailFocusNode,
                  label: '직함 / 부서',
                  hint: '예: 팀장 / R&D 센터',
                ),
                const SizedBox(height: 12),

                // 7. 이메일 (필수!)
                _buildFormField(
                  controller: _emailController,
                  focusNode: _emailFocusNode,
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
                  isLast: true,
                  label: '태그 키워드 (쉼표 구분)',
                  hint: '예: AI, 바이오, C-Level',
                ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saveCard,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('명함 저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentSky,
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
    FocusNode? nextFocusNode,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool isLast = false,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: label.contains('*') ? AppColors.accentSky : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
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
            errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderDark),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderDark),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accentSky, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

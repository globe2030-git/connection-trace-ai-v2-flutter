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
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _titleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _tagsController = TextEditingController(text: 'AI, IT');

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _titleController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _saveCard() {
    if (_nameController.text.trim().isEmpty || _companyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이름과 회사명을 입력해주세요.')),
      );
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
      phone: _phoneController.text.trim().isEmpty ? '010-0000-0000' : _phoneController.text.trim(),
      email: _emailController.text.trim(),
      tags: tags.isEmpty ? ['신규'] : tags,
      geo: const GeoPosition(lat: 37.4979, lng: 127.0276), // Default location
      talkingPoints: [
        '최근 프로젝트 진행 상황 공유하기',
        '다음 비즈니스 미팅 일정 제안하기',
      ],
      isPriority: false,
    );

    context.read<WalletViewModel>().addContact(newContact);
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${newContact.name} 님의 명함이 등록되었습니다!')),
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

              const Text(
                '🎴 새 명함 직접 등록',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),

              _buildTextField(_nameController, '이름 *', '예: 김철수'),
              const SizedBox(height: 10),
              _buildTextField(_companyController, '회사명 *', '예: 카카오 / 삼성전자'),
              const SizedBox(height: 10),
              _buildTextField(_titleController, '직함 / 부서', '예: 팀장 / R&D 센터'),
              const SizedBox(height: 10),
              _buildTextField(_phoneController, '전화번호', '예: 010-1234-5678', keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              _buildTextField(_emailController, '이메일', '예: example@company.com', keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              _buildTextField(_tagsController, '태그 키워드 (쉼표 구분)', '예: AI, 바이오, C-Level'),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
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
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.bgDarkSlate,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderDark),
            ),
          ),
        ),
      ],
    );
  }
}

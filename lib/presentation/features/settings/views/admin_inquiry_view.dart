import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/inquiry_model.dart';
import '../../../../data/repositories/inquiry_repository.dart';
import '../../../common/glass_card.dart';

enum _AdminFilterStatus { all, pending, answered }

/// 관리자 전용 1:1 문의 조회 및 검색 관리 화면.
///
/// 사용자의 성명(userName) 및 이메일(userEmail)로 실시간 검색할 수 있으며,
/// 문의 상세 확인 및 관리자 답변 작성이 가능하다.
class AdminInquiryManagementView extends StatefulWidget {
  const AdminInquiryManagementView({super.key});

  @override
  State<AdminInquiryManagementView> createState() =>
      _AdminInquiryManagementViewState();
}

class _AdminInquiryManagementViewState
    extends State<AdminInquiryManagementView> {
  final _repo = InquiryRepository();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _AdminFilterStatus _filterStatus = _AdminFilterStatus.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('관리자 1:1 문의 관리'),
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 1. 검색 및 필터 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                // 이름/이메일 검색창
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.textMuted.withValues(alpha: 0.2),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      icon: const Icon(Icons.search, color: AppColors.textMuted),
                      hintText: '사용자 이름 또는 이메일로 검색',
                      hintStyle: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.6),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              color: AppColors.textMuted,
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 상태 필터 칩 (전체 / 답변대기 / 답변완료)
                Row(
                  children: [
                    _filterChip('전체', _AdminFilterStatus.all),
                    const SizedBox(width: 8),
                    _filterChip('답변대기', _AdminFilterStatus.pending),
                    const SizedBox(width: 8),
                    _filterChip('답변완료', _AdminFilterStatus.answered),
                  ],
                ),
              ],
            ),
          ),

          // 2. 문의 내역 리스트 (StreamBuilder)
          Expanded(
            child: StreamBuilder<List<InquiryModel>>(
              stream: _repo.watchAllInquiriesForAdmin(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      '문의 목록을 불러오지 못했습니다.\n(관리자 권한을 확인해 주세요)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  );
                }

                final inquiries = snapshot.data ?? const [];
                final query = _searchQuery.trim().toLowerCase();

                // 이름 및 이메일 실시간 필터링
                final filtered = inquiries.where((item) {
                  if (_filterStatus == _AdminFilterStatus.pending &&
                      item.status != InquiryStatus.pending) {
                    return false;
                  }
                  if (_filterStatus == _AdminFilterStatus.answered &&
                      item.status != InquiryStatus.answered) {
                    return false;
                  }

                  if (query.isEmpty) return true;
                  final nameMatches = item.userName.toLowerCase().contains(query);
                  final emailMatches = item.userEmail.toLowerCase().contains(query);
                  final subjectMatches = item.subject.toLowerCase().contains(query);
                  return nameMatches || emailMatches || subjectMatches;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      query.isEmpty
                          ? '접수된 문의 내역이 없습니다.'
                          : "'$query' 검색 결과가 없습니다.",
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _AdminInquiryCard(
                      inquiry: item,
                      onTap: () => _openAdminDetail(context, item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _AdminFilterStatus status) {
    final selected = _filterStatus == status;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppColors.textPrimary,
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: selected,
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.cardSurface,
      onSelected: (_) => setState(() => _filterStatus = status),
    );
  }

  void _openAdminDetail(BuildContext context, InquiryModel inquiry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminInquiryReplySheet(repo: _repo, inquiry: inquiry),
    );
  }
}

class _AdminInquiryCard extends StatelessWidget {
  final InquiryModel inquiry;
  final VoidCallback onTap;

  const _AdminInquiryCard({required this.inquiry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final answered = inquiry.status == InquiryStatus.answered;
    final displayName = inquiry.userName.isNotEmpty
        ? inquiry.userName
        : (inquiry.userEmail.isNotEmpty ? inquiry.userEmail : '익명 사용자');

    return GlassCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 이름 & 이메일
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (inquiry.userEmail.isNotEmpty &&
                            inquiry.userName.isNotEmpty)
                          Text(
                            inquiry.userEmail,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 상태 배지
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (answered ? AppColors.accentText : AppColors.textMuted)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      answered ? '답변완료' : '답변대기',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: answered
                            ? AppColors.accentText
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                inquiry.subject,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                inquiry.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminInquiryReplySheet extends StatefulWidget {
  final InquiryRepository repo;
  final InquiryModel inquiry;

  const _AdminInquiryReplySheet({
    required this.repo,
    required this.inquiry,
  });

  @override
  State<_AdminInquiryReplySheet> createState() =>
      _AdminInquiryReplySheetState();
}

class _AdminInquiryReplySheetState extends State<_AdminInquiryReplySheet> {
  final _replyController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _submitReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.repo.addAdminReply(
        inquiryId: widget.inquiry.id,
        message: text,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.inquiry.userName.isNotEmpty
        ? widget.inquiry.userName
        : widget.inquiry.userEmail;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '[$displayName] 문의 답변 작성',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '제목: ${widget.inquiry.subject}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '내용: ${widget.inquiry.message}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _replyController,
                maxLines: 4,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '답변할 내용을 입력하세요...',
                  hintStyle: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: AppColors.bgBase,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submitReply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '답변 전송하기',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
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

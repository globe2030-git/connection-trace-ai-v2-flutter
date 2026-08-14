import 'package:flutter/material.dart';
import '../../../../core/services/ai_usage_service.dart';
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

  /// 사용량 조회는 서버 함수 호출이라 **한 번만** 쏜다. `build` 안에서
  /// `FutureBuilder(future: ...)`를 만들면 답변을 입력할 때마다(리빌드마다)
  /// 서버를 다시 부른다.
  late final Future<AdminUserUsage> _usageFuture;

  @override
  void initState() {
    super.initState();
    _usageFuture = AiUsageService.fetchForAdmin(widget.inquiry.userEmail);
  }

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
    final inquiry = widget.inquiry;
    final answered = inquiry.status == InquiryStatus.answered;
    final displayName = inquiry.userName.isNotEmpty
        ? inquiry.userName
        : (inquiry.userEmail.isNotEmpty ? inquiry.userEmail : '익명 사용자');
    final formattedDate =
        '${inquiry.createdAt.year}-${inquiry.createdAt.month.toString().padLeft(2, '0')}-${inquiry.createdAt.day.toString().padLeft(2, '0')} ${inquiry.createdAt.hour.toString().padLeft(2, '0')}:${inquiry.createdAt.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더: 타이틀 & 닫기 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '고객 문의 응대 및 상세 정보',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. 고객 프로필 정보 카드
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgBase,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.textMuted.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.accent,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (inquiry.userEmail.isNotEmpty)
                                        Text(
                                          inquiry.userEmail,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (answered
                                            ? AppColors.accentText
                                            : AppColors.textMuted)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    answered ? '답변완료' : '답변대기',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: answered
                                          ? AppColors.accentText
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24, color: Colors.white12),
                            _infoRow('접수 시각', formattedDate),
                            const SizedBox(height: 4),
                            _infoRow(
                              '사용자 UID',
                              inquiry.userId.isNotEmpty
                                  ? inquiry.userId
                                  : '비회원/익명',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 1-2. 고객 AI 이용 현황 카드
                      //
                      // 값은 서버 함수(getUserUsage)가 준 것만 그린다. 예전에는
                      // 클라이언트가 users/{uid}를 직접 읽었는데, 그 문서는 본인만
                      // 읽을 수 있어(명함 복호화 키가 함께 들어 있다) 관리자에게는
                      // 항상 권한 거부가 났고, 그 실패를 삼켜 0을 그렸다.
                      // "유료 충전 잔여"·"무료 잔여"는 서버에 그런 필드 자체가
                      // 없어 언제나 0이었으므로 화면에서 뺐다 — 근거 없는 숫자를
                      // 관리자에게 보여주면 응대가 틀어진다(backlog 추가 178).
                      FutureBuilder<AdminUserUsage>(
                          future: _usageFuture,
                          builder: (context, usageSnapshot) {
                            if (usageSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return _usageMessageBox('사용량을 불러오는 중…');
                            }
                            if (usageSnapshot.hasError) {
                              final e = usageSnapshot.error;
                              return _usageMessageBox(
                                e is AdminUsageException
                                    ? e.message
                                    : '사용량을 불러오지 못했습니다.',
                                isError: true,
                              );
                            }
                            final usage = usageSnapshot.data!;

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.accent.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet_outlined,
                                        color: AppColors.accentText,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        '고객 AI 이용 현황',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.accentText,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _usageStatBox(
                                          '오늘 사용',
                                          '${usage.dailyCount}회 / ${usage.dailyLimit}회',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _usageStatBox(
                                          '이번 달 사용',
                                          '${usage.monthlyCount}회 / ${usage.monthlyLimit}회',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: _usageStatBox(
                                          '보너스 회차',
                                          '${usage.bonusCredits}회',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 16),

                      // 2. 문의 본문 내용 카드
                      const Text(
                        '문의 내용',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgBase.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              inquiry.subject,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              inquiry.message,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 3. 대화 / 답변 이력 타임라인 Stream
                      const Text(
                        '답변 & 대화 이력',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<List<InquiryReplyModel>>(
                        stream: widget.repo.watchReplies(inquiry.id),
                        builder: (context, snapshot) {
                          final replies = snapshot.data ?? const [];
                          if (replies.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                '등록된 답변 이력이 없습니다. 아래에서 답변을 작성해 주세요.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: replies.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final r = replies[index];
                              final isAdmin = r.from == 'admin';
                              return Align(
                                alignment: isAdmin
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.75,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isAdmin
                                        ? AppColors.accent
                                            .withValues(alpha: 0.2)
                                        : AppColors.cardSurface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isAdmin
                                          ? AppColors.accent
                                          : AppColors.textMuted
                                              .withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isAdmin ? '관리자 답변' : '고객 추가 문의',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isAdmin
                                              ? AppColors.accentText
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        r.message,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // 4. 관리자 답변 작성 및 응대 전송 하단 입력 폼
              const Divider(height: 1, color: Colors.white12),
              const SizedBox(height: 12),
              TextField(
                controller: _replyController,
                maxLines: 3,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: '고객에게 전달할 응대 답변을 작성하세요...',
                  hintStyle: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppColors.bgBase,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                          '답변 등록 및 응대 완료',
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

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// 사용량을 아직 못 읽었거나(로딩) 못 읽은(오류) 상태를 **숫자 대신 문장으로**
  /// 보여준다. 숫자 자리에 0을 그리면 관리자가 "이 고객은 한 번도 안 썼다"로
  /// 읽어 응대가 틀어진다.
  Widget _usageMessageBox(String message, {bool isError = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.textMuted.withValues(alpha: 0.08)
            : AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isError
              ? AppColors.textMuted.withValues(alpha: 0.25)
              : AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.info_outline : Icons.hourglass_empty,
            size: 18,
            color: isError ? AppColors.textMuted : AppColors.accentText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _usageStatBox(String title, String val) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            val,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

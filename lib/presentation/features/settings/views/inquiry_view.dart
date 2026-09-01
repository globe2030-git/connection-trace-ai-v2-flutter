import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/inquiry_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/inquiry_repository.dart';
import '../../../common/glass_card.dart';

class InquiryView extends StatefulWidget {
  const InquiryView({super.key});

  @override
  State<InquiryView> createState() => _InquiryViewState();
}

class _InquiryViewState extends State<InquiryView> {
  final _repo = InquiryRepository();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    final uid = auth.firebaseUid;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('1:1 문의'),
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              onPressed: () => _openCompose(
                context,
                uid,
                auth.displayName ?? '',
                auth.email ?? '',
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                '새 문의',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
      body: uid == null
          ? const _LoginRequired()
          : StreamBuilder<List<InquiryModel>>(
              stream: _repo.watchMyInquiries(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                final inquiries = snapshot.data ?? const [];
                if (inquiries.isEmpty) {
                  return const _InquiryEmpty();
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  itemCount: inquiries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final inquiry = inquiries[index];
                    return GlassCard(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => InquiryDetailView(inquiry: inquiry),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inquiry.subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  inquiry.message,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusBadge(status: inquiry.status),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _openCompose(
    BuildContext context,
    String uid,
    String userName,
    String email,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InquiryComposeSheet(
        repo: _repo,
        uid: uid,
        userName: userName,
        email: email,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final InquiryStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final answered = status == InquiryStatus.answered;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          color: answered ? AppColors.accentText : AppColors.textMuted,
        ),
      ),
    );
  }
}

class _InquiryComposeSheet extends StatefulWidget {
  final InquiryRepository repo;
  final String uid;
  final String userName;
  final String email;

  const _InquiryComposeSheet({
    required this.repo,
    required this.uid,
    required this.userName,
    required this.email,
  });

  @override
  State<_InquiryComposeSheet> createState() => _InquiryComposeSheetState();
}

class _InquiryComposeSheetState extends State<_InquiryComposeSheet> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty || message.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.repo.submitInquiry(
        userId: widget.uid,
        userName: widget.userName,
        userEmail: widget.email,
        subject: subject,
        message: message,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '새 문의 작성',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _subjectController,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(hintText: '제목'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _messageController,
                maxLines: 5,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(hintText: '문의 내용을 입력해 주세요'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _submitting ? '보내는 중...' : '보내기',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
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

class InquiryDetailView extends StatefulWidget {
  final InquiryModel inquiry;

  const InquiryDetailView({super.key, required this.inquiry});

  @override
  State<InquiryDetailView> createState() => _InquiryDetailViewState();
}

class _InquiryDetailViewState extends State<InquiryDetailView> {
  final _repo = InquiryRepository();
  final _replyController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _repo.addUserReply(inquiryId: widget.inquiry.id, message: text);
      _replyController.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: Text(widget.inquiry.subject),
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<InquiryReplyModel>>(
              stream: _repo.watchReplies(widget.inquiry.id),
              builder: (context, snapshot) {
                final replies = snapshot.data ?? const [];
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _MessageBubble(
                      message: widget.inquiry.message,
                      isMe: true,
                    ),
                    const SizedBox(height: 10),
                    for (final reply in replies) ...[
                      _MessageBubble(
                        message: reply.message,
                        isMe: !reply.isFromAdmin,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(hintText: '추가로 남길 말씀이 있다면 입력해 주세요'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '답장 보내기',
                    onPressed: _sending ? null : _sendReply,
                    icon: const Icon(Icons.send, color: AppColors.accentText),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String message;
  final bool isMe;

  const _MessageBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.accentSoft : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: isMe ? null : Border.all(color: AppColors.borderSubtle),
        ),
        child: Text(
          message,
          style: TextStyle(
            fontSize: 13,
            color: isMe ? AppColors.accentText : AppColors.textPrimary,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _LoginRequired extends StatelessWidget {
  const _LoginRequired();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '로그인 후 문의를 남길 수 있습니다.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _InquiryEmpty extends StatelessWidget {
  const _InquiryEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '아직 남긴 문의가 없습니다. 오른쪽 아래 버튼으로 문의해 보세요.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
      ),
    );
  }
}

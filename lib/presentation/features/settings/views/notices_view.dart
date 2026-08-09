import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/notice_model.dart';
import '../../../../data/repositories/notice_repository.dart';
import '../../../common/glass_card.dart';

class NoticesView extends StatefulWidget {
  const NoticesView({super.key});

  @override
  State<NoticesView> createState() => _NoticesViewState();
}

class _NoticesViewState extends State<NoticesView> {
  final _repo = NoticeRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('공지사항'),
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: StreamBuilder<List<NoticeModel>>(
        stream: _repo.watchPublishedNotices(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          if (snapshot.hasError) {
            return const _NoticesError();
          }
          final notices = snapshot.data ?? const [];
          if (notices.isEmpty) {
            return const _NoticesEmpty();
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: notices.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final notice = notices[index];
              return GlassCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoticeDetailView(notice: notice),
                  ),
                ),
                child: Row(
                  children: [
                    if (notice.pinned)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.push_pin,
                          size: 16,
                          color: AppColors.accentText,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notice.title,
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
                            _formatDate(notice.createdAt),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

String _formatDate(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

class NoticeDetailView extends StatelessWidget {
  final NoticeModel notice;

  const NoticeDetailView({super.key, required this.notice});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('공지사항'),
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notice.title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatDate(notice.createdAt),
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 18),
            MarkdownBody(
              data: notice.bodyMarkdown,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
                strong: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticesEmpty extends StatelessWidget {
  const _NoticesEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '등록된 공지사항이 없습니다.',
        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
      ),
    );
  }
}

class _NoticesError extends StatelessWidget {
  const _NoticesError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '공지사항을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

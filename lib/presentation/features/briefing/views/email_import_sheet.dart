import 'package:flutter/material.dart';

import '../../../../core/icons/app_icons.dart';
import '../../../../core/services/email_sync_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/contact_model.dart';

/// ⚠️ **현재 앱 어디에서도 열리지 않는 화면이다.** Gmail 가져오기 항목을 소통
/// 기록 추가 목록에서 뺐기 때문이다(2026-08-10, `CommunicationSourceAction`
/// 주석 참고). 나중에 되살릴 때를 위해 코드만 남겨 둔 것이므로, 이 파일을
/// 고쳐도 실행 화면에는 아무 변화가 없다.
class EmailImportSheet extends StatefulWidget {
  final ContactModel contact;

  const EmailImportSheet({super.key, required this.contact});

  @override
  State<EmailImportSheet> createState() => _EmailImportSheetState();
}

class _EmailImportSheetState extends State<EmailImportSheet> {
  List<CommunicationLogModel>? _messages;
  final Set<String> _selectedIds = {};
  bool _loading = false;
  String? _error;

  Future<void> _connectAndLoad() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (!EmailSyncService.isSignedIn) {
        await EmailSyncService.signIn();
      }
      final messages = await EmailSyncService.syncEmails(widget.contact.email);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _selectedIds
          ..clear()
          ..addAll(messages.map((message) => message.id));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '');
    if (raw.contains('client') || raw.contains('configuration')) {
      return 'Google 로그인을 사용할 수 없습니다. 앱의 Google OAuth 설정을 확인해 주세요.';
    }
    return raw;
  }

  Future<void> _switchAccount() async {
    if (_loading) return;
    await EmailSyncService.signOut();
    if (!mounted) return;
    setState(() {
      _messages = null;
      _selectedIds.clear();
      _error = null;
    });
    await _connectAndLoad();
  }

  void _import() {
    final selected = (_messages ?? const <CommunicationLogModel>[])
        .where((message) => _selectedIds.contains(message.id))
        .toList();
    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 6),
              child: Row(
                children: [
                  const AppIcon(
                    AppIconId.emailLink,
                    color: AppColors.accentText,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Gmail에서 가져오기',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              // 여러 줄 메모 칸이 있는 화면이다. Android에서 멀티라인 입력칸은
              // 키보드에 완료 키 대신 **줄바꿈 키**가 떠서 키보드를 닫을 방법이
              // 없다 — 그대로 두면 위쪽이 키보드에 가린 채 스크롤도 막힌다
              // (통합본 E-10). 끌어서 스크롤하면 키보드를 내린다.
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.contact.email}과 주고받은 최근 메일의 제목과 짧은 미리보기만 조회합니다. 선택한 항목만 이 기기에 저장됩니다.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                    if (EmailSyncService.isSignedIn) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '연결 계정: ${EmailSyncService.signedInEmail}',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _loading ? null : _switchAccount,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              '다른 계정으로 로그인',
                              style: TextStyle(
                                color: AppColors.accentText,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 36),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(
                                color: AppColors.accentText,
                              ),
                              SizedBox(height: 12),
                              Text(
                                '메일 목록을 불러오는 중입니다.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (messages == null)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _connectAndLoad,
                          icon: const Icon(Icons.login, color: Colors.white),
                          label: Text(
                            EmailSyncService.isSignedIn
                                ? '메일 목록 불러오기'
                                : 'Google 계정 연결하기',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      )
                    else if (messages.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgBase,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          '이 주소와 주고받은 최근 메일을 찾지 못했습니다.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '저장할 메일 선택',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${_selectedIds.length}개',
                            style: const TextStyle(
                              color: AppColors.accentText,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...messages.map(
                        (message) => Material(
                          color: Colors.transparent,
                          child: CheckboxListTile(
                            value: _selectedIds.contains(message.id),
                            onChanged: (value) {
                              setState(() {
                                if (value ?? false) {
                                  _selectedIds.add(message.id);
                                } else {
                                  _selectedIds.remove(message.id);
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            activeColor: AppColors.accent,
                            title: Text(
                              message.summary,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                            subtitle: Text(
                              '${message.timestamp.year}.${message.timestamp.month.toString().padLeft(2, '0')}.${message.timestamp.day.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.destructive,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.destructive,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: _connectAndLoad,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (messages != null && messages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _selectedIds.isEmpty ? null : _import,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      disabledBackgroundColor: AppColors.borderSubtle,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '선택한 메일 저장하기',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

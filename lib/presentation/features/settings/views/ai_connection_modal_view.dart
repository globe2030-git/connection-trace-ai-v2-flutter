import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/ai_provider.dart';
import '../../../../data/repositories/ai_credentials_repository.dart';
import '../../../common/glass_card.dart';

/// AI 대화 브리핑에 쓸 AI 제공사를 연동하는 화면. 여러 제공사 중 이미 갖고
/// 있는 것을 골라 본인의 API 키로 직접 연동하는 방식 — 앱이 AI를 대신
/// 제공하는 게 아니라, 사용자 본인의 AI 계정(API 키)을 통해 도움을 받는
/// 컨셉이라 아이디/비밀번호가 아니라 API 키를 입력받는다.
class AiConnectionModalView extends StatefulWidget {
  const AiConnectionModalView({super.key});

  @override
  State<AiConnectionModalView> createState() => _AiConnectionModalViewState();
}

class _AiConnectionModalViewState extends State<AiConnectionModalView> {
  final Map<AiProvider, TextEditingController> _keyControllers = {
    for (final p in AiProvider.values) p: TextEditingController(),
  };
  final Map<AiProvider, bool> _obscure = {
    for (final p in AiProvider.values) p: true,
  };

  // 이 화면도 자체 Scaffold 없는 bottom sheet라(add_card_modal_view.dart에서
  // 검증된 패턴) ScaffoldMessenger 대신 폼 안에 직접 그리는 배너로 안내한다.
  String? _inlineNoticeText;

  @override
  void dispose() {
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _showNotice(String text) {
    setState(() => _inlineNoticeText = text);
  }

  Future<void> _connect(AiProvider provider) async {
    final key = _keyControllers[provider]!.text.trim();
    if (key.isEmpty) {
      _showNotice('⚠️ API 키를 입력해 주세요.');
      return;
    }
    await context.read<AiCredentialsRepository>().setApiKey(provider, key);
    _keyControllers[provider]!.clear();
    if (!mounted) return;
    _showNotice(
      '✅ ${provider.displayName} 연동 완료. 이제 대화 브리핑에서 실제 AI 응답을 받을 수 있어요.',
    );
  }

  Future<void> _openConsole(AiProvider provider) async {
    final uri = Uri.parse(provider.consoleUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      _showNotice(
        '⚠️ 발급 페이지를 열지 못했습니다. 브라우저에서 ${provider.consoleUrl}로 직접 접속해 주세요.',
      );
    }
  }

  Future<void> _disconnect(AiProvider provider) async {
    await context.read<AiCredentialsRepository>().removeApiKey(provider);
    if (!mounted) return;
    _showNotice('${provider.displayName} 연동을 해제했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AiCredentialsRepository>();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
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

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🤖 AI 연동',
                      style: TextStyle(
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
                const SizedBox(height: 6),
                const Text(
                  '이미 갖고 계신 AI 서비스의 API 키를 연동하면, "30초 AI 대화 브리핑"이 실제 AI가 생성한 맞춤 대화 포인트를 보여줍니다. API 키는 이 기기에만 안전하게 저장되고 서버로 전송되지 않습니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),

                if (_inlineNoticeText != null) ...[
                  _buildInlineNotice(),
                  const SizedBox(height: 12),
                ],

                ...AiProvider.values.map(
                  (provider) => _buildProviderCard(context, repo, provider),
                ),
              ],
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
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.accentText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: const Icon(
              Icons.close,
              size: 16,
              color: AppColors.accentText,
            ),
            onPressed: () => setState(() => _inlineNoticeText = null),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(
    BuildContext context,
    AiCredentialsRepository repo,
    AiProvider provider,
  ) {
    final isConnected = repo.hasKey(provider);
    final isActive = repo.activeProvider == provider;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderColor: isActive ? AppColors.accentText : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    provider.displayName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentText.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '사용 중',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.accentText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              provider.consoleHint,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            if (isConnected) ...[
              Row(
                children: [
                  const Icon(
                    Icons.vpn_key,
                    size: 14,
                    color: AppColors.accentText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    repo.maskedKeyPreview(provider) ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (!isActive)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => repo.setActiveProvider(provider),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.accentText),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '이걸로 사용',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.accentText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (!isActive) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _disconnect(provider),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.destructive),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        '연동 해제',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.destructive,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: () => _openConsole(provider),
                icon: const Icon(
                  Icons.open_in_new,
                  size: 16,
                  color: AppColors.accentText,
                ),
                label: const Text(
                  '발급 페이지 열기',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.accentText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accentText),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  minimumSize: const Size(double.infinity, 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ...provider.setupSteps.asMap().entries.map((entry) {
                final stepNum = entry.key + 1;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: const BoxDecoration(
                          color: AppColors.accentText,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$stepNum',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
              TextField(
                controller: _keyControllers[provider],
                obscureText: _obscure[provider]!,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'API 키 붙여넣기',
                  hintStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppColors.bgDarkSlate,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.borderFunctional,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.borderFunctional,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.accentText,
                      width: 1.5,
                    ),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure[provider]!
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                    onPressed: () => setState(
                      () => _obscure[provider] = !_obscure[provider]!,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _connect(provider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '연동',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

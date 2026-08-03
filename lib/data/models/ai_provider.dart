/// AI 대화 브리핑에 연동할 수 있는 AI 제공사. 사용자가 이미 갖고 있는
/// 제공사 중 하나를 골라 자신의 API 키로 연동하는 방식이라, 앱이 하나의
/// 제공사만 강제하지 않고 여러 개 중 선택할 수 있게 한다.
enum AiProvider {
  anthropic,
  openai,
  gemini;

  String get displayName => switch (this) {
        AiProvider.anthropic => 'Claude (Anthropic)',
        AiProvider.openai => 'ChatGPT (OpenAI)',
        AiProvider.gemini => 'Gemini (Google)',
      };

  /// API 키 발급 페이지 안내용 — 설정 화면에 표시만 하고 자동으로 열지는 않는다.
  String get consoleHint => switch (this) {
        AiProvider.anthropic => 'console.anthropic.com에서 API 키를 발급받으세요.',
        AiProvider.openai => 'platform.openai.com에서 API 키를 발급받으세요.',
        AiProvider.gemini => 'aistudio.google.com에서 API 키를 발급받으세요.',
      };

  /// 기본 모델 — 제공사마다 계속 바뀌므로, 설정 화면에서 사용자가 직접
  /// 덮어쓸 수 있게 하고 이 값은 초기값으로만 쓴다.
  String get defaultModel => switch (this) {
        AiProvider.anthropic => 'claude-opus-5',
        AiProvider.openai => 'gpt-4o-mini',
        AiProvider.gemini => 'gemini-2.0-flash',
      };
}

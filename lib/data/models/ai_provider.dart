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

  /// "발급 페이지 열기" 버튼에서 바로 여는 URL.
  String get consoleUrl => switch (this) {
        AiProvider.anthropic => 'https://console.anthropic.com/settings/keys',
        AiProvider.openai => 'https://platform.openai.com/api-keys',
        AiProvider.gemini => 'https://aistudio.google.com/apikey',
      };

  /// 설정 화면에서 순서대로 보여줄 발급 안내 — claude.ai/chatgpt.com 같은
  /// 소비자 구독 계정과는 별개로, 사용량만큼 과금되는 개발자용 키를
  /// 새로 발급받아야 한다는 점을 각 단계에서 자연스럽게 알 수 있게 구성.
  List<String> get setupSteps => switch (this) {
        AiProvider.anthropic => const [
            '위 "발급 페이지 열기" 버튼으로 console.anthropic.com에 접속',
            'claude.ai 로그인과 같은 계정으로 로그인(계정이 없으면 새로 만들기)',
            '왼쪽 메뉴 "API Keys" 클릭 → "Create Key" 클릭',
            '생성된 키(sk-ant-로 시작) 전체를 복사',
            '아래 입력칸에 붙여넣고 "연동" 버튼 클릭',
          ],
        AiProvider.openai => const [
            '위 "발급 페이지 열기" 버튼으로 platform.openai.com에 접속',
            'chatgpt.com 로그인과 같은 계정으로 로그인(계정이 없으면 새로 만들기)',
            '"Create new secret key" 클릭 → 이름 입력 후 생성',
            '생성된 키(sk-로 시작, 한 번만 보여줌) 전체를 복사',
            '아래 입력칸에 붙여넣고 "연동" 버튼 클릭',
          ],
        AiProvider.gemini => const [
            '위 "발급 페이지 열기" 버튼으로 aistudio.google.com에 접속',
            '구글 계정으로 로그인(계정이 없으면 새로 만들기)',
            '"Create API key" 클릭',
            '생성된 키(AIza로 시작) 전체를 복사',
            '아래 입력칸에 붙여넣고 "연동" 버튼 클릭',
          ],
      };

  /// 기본 모델 — 제공사마다 계속 바뀌므로, 설정 화면에서 사용자가 직접
  /// 덮어쓸 수 있게 하고 이 값은 초기값으로만 쓴다.
  String get defaultModel => switch (this) {
        AiProvider.anthropic => 'claude-opus-5',
        AiProvider.openai => 'gpt-4o-mini',
        AiProvider.gemini => 'gemini-2.0-flash',
      };
}

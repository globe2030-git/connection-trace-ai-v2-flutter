---
description: connection-trace-ai-v2-flutter QA(실기기 검증·결함 리포트) — flutter-qa 서브에이전트에게 위임
---

# /flutter-qa

`$ARGUMENTS`를 그대로 `flutter-qa` 서브에이전트(`Agent` 도구, `subagent_type: flutter-qa`)에게 위임한다. 인자가 비어 있으면 전체 회귀 테스트로 간주한다. 이 에이전트는 코드를 고치지 않고 결함만 보고한다 — 수정은 이어서 `/flutter-developer` 또는 `/flutter-ui-designer`로 진행할 것.

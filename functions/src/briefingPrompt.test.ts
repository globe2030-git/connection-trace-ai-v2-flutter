/**
 * briefingPrompt.ts 자동 테스트. Node 22 내장 러너(`node:test`) — chunk.test.ts,
 * usageReset.test.ts와 같은 패턴. 실행:
 * `npm run build && node --test lib/briefingPrompt.test.js`
 *
 * ⚠️ **이 테스트가 확인하는 것은 "프롬프트가 의도대로 조립되는가"뿐이다.**
 * "AI 답이 좋아졌는가"는 여기서 못 잡는다 — 그건 서버에 배포해야 잴 수 있고,
 * 배포는 사용자 결정이다. 이 저장소의 CLAUDE.md가 말하는 그대로다:
 * **자동 테스트는 규칙을 보고 사람은 화면을 본다.**
 */
import {test} from "node:test";
import assert from "node:assert/strict";
import {buildPrompt, GenerateBriefingRequest} from "./briefingPrompt";

function req(
  over: Partial<GenerateBriefingRequest> = {},
): GenerateBriefingRequest {
  return {
    contactSummary: "홍길동 / 예시상사 / 과장",
    myProfileSummary: "김철수 / 커넥션센스",
    communicationLogs: [],
    ...over,
  };
}

test("필수 정보는 프롬프트에 그대로 들어간다", () => {
  const p = buildPrompt(req());
  assert.match(p, /홍길동 \/ 예시상사 \/ 과장/);
  assert.match(p, /김철수 \/ 커넥션센스/);
  assert.match(p, /정확히 3개 작성하세요/);
});

test("소통 기록이 없으면 '최근 소통 기록 없음'으로 적는다", () => {
  assert.match(buildPrompt(req()), /최근 소통 기록 없음/);
});

test("소통 기록이 있으면 불릿으로 나열한다", () => {
  const p = buildPrompt(req({communicationLogs: ["3월 통화", "5월 문자"]}));
  assert.match(p, /- 3월 통화\n- 5월 문자/);
  assert.doesNotMatch(p, /최근 소통 기록 없음/);
});

test("관심사가 비어 있으면 '없음'으로 적는다", () => {
  assert.match(buildPrompt(req()), /관심사: 없음/);
  assert.match(buildPrompt(req({interests: "   "})), /관심사: 없음/);
});

test("관심사가 있으면 그대로 적는다", () => {
  assert.match(buildPrompt(req({interests: "등산, 커피"})), /관심사: 등산, 커피/);
});

test("날씨는 있을 때만 절이 생긴다", () => {
  assert.doesNotMatch(buildPrompt(req()), /오늘 상대방 지역 날씨/);
  assert.match(
    buildPrompt(req({weatherSummary: "맑음, 24°C"})),
    /오늘 상대방 지역 날씨: 맑음, 24°C/,
  );
});

test("메모는 있을 때만 절이 생긴다", () => {
  assert.doesNotMatch(buildPrompt(req()), /사용자가 직접 남긴 메모/);
  assert.match(
    buildPrompt(req({extraNote: "지난주 이직했다고 함"})),
    /\[사용자가 직접 남긴 메모\]\n지난주 이직했다고 함/,
  );
});

test("공백뿐인 메모는 절을 만들지 않는다", () => {
  assert.doesNotMatch(buildPrompt(req({extraNote: "  \n "})), /직접 남긴 메모/);
});

// F-07(재생성 다양성)
test("직전 포인트가 있으면 회피 지시가 붙는다", () => {
  const p = buildPrompt(req({previousPoints: ["요즘 어떠세요?", "  ", ""]}));
  assert.match(p, /직전에 제안했던 대화 포인트 — 반드시 피할 것/);
  assert.match(p, /- 요즘 어떠세요\?/);
  // 빈 문자열/공백은 걸러져서 불릿이 하나만 생긴다
  assert.equal((p.match(/^- /gm) ?? []).length, 1);
});

test("직전 포인트가 없거나 전부 공백이면 회피 절을 생략한다", () => {
  assert.doesNotMatch(buildPrompt(req()), /반드시 피할 것/);
  assert.doesNotMatch(
    buildPrompt(req({previousPoints: ["", "   "]})),
    /반드시 피할 것/,
  );
});

test("시드는 넘겼을 때만 붙고, 답변에 넣지 말라고 명시한다", () => {
  assert.doesNotMatch(buildPrompt(req()), /생성 다양성 시드/);
  const p = buildPrompt(req(), "a1b2c3");
  assert.match(p, /생성 다양성 시드: a1b2c3/);
  assert.match(p, /이 식별자는 답변에 포함하지 말고/);
});

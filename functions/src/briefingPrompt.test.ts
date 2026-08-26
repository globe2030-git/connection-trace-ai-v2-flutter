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
import {
  buildPrompt,
  resolveFieldLabel,
  FIELD_LABELS,
  GenerateBriefingRequest,
} from "./briefingPrompt";

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

// ── 분야 축(2026-08-26, 추가 499) ──────────────────────────────────────────

// 이 문자열은 **분야 기능을 넣기 전(origin/main)의 마지막 지시 절 원문**이다.
// 분야를 안 고른 사용자의 프롬프트는 이번 변경 뒤에도 여기서 한 글자도
// 달라지면 안 된다. 달라지면 나중에 "분야를 넣어서 답이 나아진 것"인지
// "지시문을 건드려서 달라진 것"인지 가릴 수 없다.
const 분야_없을_때_원문 = `각 대화 포인트는 한 문장, 한국어로, 실제로 그대로 말할 수 있는 구체적인 문장으로
작성하세요. 날씨 정보가 있다면 그중 한 문장 정도에 자연스럽게 녹여도 좋습니다.
단, 날씨는 사실만 담백하게 언급하고 "상쾌하다", "완벽한 날씨" 같은 주관적 단정은
피하세요. 상대방의 관심사나 직함/업종과 관련된 일반적인 화제(업계 동향, 최근 이슈 등 당신이
알고 있는 상식 수준의 내용)를 자연스럽게 언급하는 문장을 하나 포함해도 좋습니다 —
단, 확인되지 않은 구체적 사실·사건을 지어내지 마세요. 번호/불릿/설명 없이 대화
포인트 문장만 줄바꿈으로 구분해서 정확히 3개 작성하세요.`;

test("분야가 없으면 지시 절이 이전과 한 글자도 다르지 않다", () => {
  assert.ok(buildPrompt(req()).endsWith(분야_없을_때_원문));
});

test("모르는 키·빈 키는 분야 없음으로 떨어진다(이전 동작 유지)", () => {
  for (const k of ["", "   ", "없는분야", "IT", "toString", "__proto__"]) {
    const p = buildPrompt(req({fieldKey: k}));
    assert.ok(p.endsWith(분야_없을_때_원문), `키 ${JSON.stringify(k)}`);
    assert.doesNotMatch(p, /분야\(사용자가 직접 고름\)/, `키 ${JSON.stringify(k)}`);
  }
});

test("resolveFieldLabel: 목록에 있는 키만 이름을 준다", () => {
  assert.equal(resolveFieldLabel("legal"), "법률·회계");
  assert.equal(resolveFieldLabel(" legal "), "법률·회계");
  assert.equal(resolveFieldLabel("없는키"), null);
  assert.equal(resolveFieldLabel(undefined), null);
  // Object.prototype에서 상속된 이름이 분야로 새어 들어오면 안 된다
  assert.equal(resolveFieldLabel("constructor"), null);
});

test("분야 목록은 설계 보드의 열 개와 같다", () => {
  assert.deepEqual(Object.values(FIELD_LABELS), [
    "금융·경제", "IT·기술", "산업·제조", "건설·부동산", "의료·바이오",
    "법률·회계", "교육", "공공·행정", "미디어·콘텐츠", "유통·소비재",
  ]);
});

test("분야를 고르면 상대방 정보에 한 줄이 들어간다", () => {
  assert.match(
    buildPrompt(req({fieldKey: "medical"})),
    /분야\(사용자가 직접 고름\): 의료·바이오/,
  );
});

test("분야를 고르면 세 문장을 서로 다른 축으로 뽑으라고 지시한다", () => {
  const p = buildPrompt(req({fieldKey: "finance"}));
  assert.match(p, /서로 다른 축에서 하나씩 뽑아/);
  assert.match(p, /- 분야 화제: 「금융·경제」/);
  assert.match(p, /- 관계·근황:/);
  assert.match(p, /- 가벼운 안부:/);
  assert.match(p, /정확히 3개\n작성하세요/);
});

// 🚨 이 작업에서 가장 중요한 검사. 분야를 주면 모델이 "그 분야 뉴스처럼
// 들리는 문장"을 만들 유인이 커지는데, 모델은 최신 동향을 모르면서 아는 것처럼
// 쓴다. 금지 지시가 프롬프트에서 통째로 빠지는 회귀를 여기서 막는다.
test("분야를 고르면 지어내기 금지가 구체적으로 걸린다", () => {
  const p = buildPrompt(req({fieldKey: "it"}));
  assert.match(p, /「IT·기술」 분야 문장에서 반드시 지킬 것:/);
  for (const 금지 of [
    "사건", "뉴스", "정책", "법령", "수치", "통계", "기업명", "제품명", "인물명",
  ]) {
    assert.match(p, new RegExp(금지), `금지 목록에 ${금지}가 없다`);
  }
  assert.match(p, /당신은 최신 동향을 알지 못합니다/);
  // 무엇을 쓰지 말라고만 하지 않고, 무엇을 대신 쓰라고까지 지정한다
  assert.match(p, /상대에게 묻는 형태로 쓰세요/);
  assert.match(p, /무슨 일을 하는지 단정하지 마세요/);
  // 나머지 두 문장에도 기존 금지가 남아 있어야 한다
  assert.match(p, /나머지 두 문장에서도 확인되지 않은 구체적 사실·사건을 지어내지 마세요/);
});

test("프롬프트 본문에 굵게(**) 서식을 쓰지 않는다", () => {
  // 모델이 서식을 따라 쓰면 parseTalkingPoints가 못 걸러 화면에 그대로 나온다
  for (const k of [undefined, "finance", "public"]) {
    assert.doesNotMatch(buildPrompt(req({fieldKey: k}), "seed"), /\*\*/);
  }
});

test("분야는 다른 절(날씨·메모·직전 포인트)과 함께 써도 다 살아 있다", () => {
  const p = buildPrompt(req({
    fieldKey: "education",
    weatherSummary: "흐림, 18°C",
    extraNote: "학회 준비 중",
    previousPoints: ["지난번 그 이야기"],
    interests: "독서",
  }), "z9");
  assert.match(p, /분야\(사용자가 직접 고름\): 교육/);
  assert.match(p, /오늘 상대방 지역 날씨: 흐림, 18°C/);
  assert.match(p, /학회 준비 중/);
  assert.match(p, /- 지난번 그 이야기/);
  assert.match(p, /관심사: 독서/);
  assert.match(p, /생성 다양성 시드: z9/);
});

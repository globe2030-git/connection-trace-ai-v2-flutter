# Vertex AI 서울 리전(asia-northeast3) 이전 가능성 조사

조사일: 2026-08-24 · 배정: 추가 447 · **조사만 했고 코드는 한 줄도 고치지 않았다.**

> ## 한 줄 결론 — **기술적으로 가능하다. 그런데 유통기한이 두 달이다.**
>
> 서울 리전에서 **ML 처리까지 국내 보장되는 Gemini 모델은
> `gemini-2.5-flash`(128k) 하나뿐**이고, 그 모델의 **은퇴일이 2026-10-20**이다
> (공식 모델 문서, 이 세션이 직접 확인). **후속 모델은 서울에 하나도 없다** —
> 3.5·3.6·3.7 전부 미국·EU 멀티리전 아니면 global뿐이다.
>
> 그러므로 이 건의 진짜 질문은 *"서울로 갈 수 있나"*가 아니라
> **"두 달 뒤에도 갈 수 있나"**다. 이 문서는 그 답을 갖고 있지 않다 —
> Google이 후속 모델을 서울에 열지 여부는 우리가 통제할 수 없다.

---

## 0. 이 문서가 앞선 문서들과 어떻게 다른가 — 먼저 밝힌다

이 주제는 **처음이 아니다.** 겹치는 것을 숨기면 다음 사람이 같은 조사를 또 한다.

| 문서 | 언제 | 무엇을 말했나 |
|---|---|---|
| [`server-ocr-legal-research-2026-08-23.md`](./server-ocr-legal-research-2026-08-23.md) | 08-23 | 갱신 주석에서 "서울 + 2.5-flash면 §28조의8 논점 소멸" |
| [`server-ocr-adoption-plan-2026-08-23.md`](./server-ocr-adoption-plan-2026-08-23.md) | 08-23 | 3-1절 같은 취지 + **서울 리전 429 혼잡 실측** |
| 법무 검토(assets, 08-24) | 08-24 | *"일정을 앞당기고 싶다면 손댈 곳은 하나 — Vertex AI 서울 리전"* |

**이 문서가 새로 넣는 것은 넷이다.**

1. ⭐⭐ **은퇴일 2026-10-20.** 앞선 문서 어디에도 없다. 08-23 판독은 가용성·상주
   표만 봤고 **모델 페이지의 Versions 절은 안 봤다.** 3절.
2. ⭐ **앞의 문서들은 전부 "서버 명함 인식"(미착수·보류) 이야기다. 그런데
   AI 브리핑은 이미 돌고 있고, 이미 국외로 나가고 있다.** 앞선 문서 어디에도
   *"지금 도는 브리핑을 어떻게 할 것인가"*가 없다. 5절.
3. **근거 PDF를 사람이 아니라 좌표로 다시 읽었고, 웹 원문으로 2차 대조했다.**
   08-23 판독은 PM이 눈으로 본 것이고, `pdftotext -layout`의 열 정렬은 실제로
   **한 칸 어긋나 있었다**(2-3절 ⚠️).
4. **전환 비용·단가를 코드와 원문 기준으로 짚었다.** 6·7절. **단가는 오히려
   내려간다**(원문 확인).

---

## 1. ⚠️ 지금 우리가 무엇을 쓰고 있는지부터 — 코드 실측

**추측하지 않고 파일을 열어 확인했다.** (`origin/main` = `ee69ae0` 기준)

### 1-1. AI 브리핑 — **Google AI Studio(Gemini Developer API)다. Vertex가 아니다.**

```
functions/src/index.ts:84    const geminiApiKey = defineSecret("GEMINI_API_KEY");
functions/src/index.ts:180   const GEMINI_MODEL = "gemini-3.6-flash";
functions/src/index.ts:357   const url =
  `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
```

`generativelanguage.googleapis.com`은 **Gemini Developer API(구 AI Studio)**의
호스트다. `aiplatform.googleapis.com`(Vertex AI)이 **아니다.** 저장소 전체에서
`aiplatform`·`vertex` 문자열은 **코드에 단 한 건도 없다**(있는 것은
`tool/ocr_review/*.py`가 읽는 08-23 실측 TSV 파일명뿐).

📌 **이 제품 구분이 이 조사의 출발점이다.** 두 제품은 이름만 비슷하고
**데이터 처리 위치 보장이 다르다.** Developer API에는 **리전을 고를 수단
자체가 없다**(6-1절, 공식 비교표 원문).

| 항목 | 실측값 | 어디서 |
|---|---|---|
| 제품 | Gemini Developer API (AI Studio) | `index.ts:357` |
| 인증 | **API 키**(`GEMINI_API_KEY` 시크릿, URL 쿼리스트링) | `index.ts:84`, `357` |
| 모델 | `gemini-3.6-flash` | `index.ts:180` |
| 호출 리전 지정 | **없음**(지정할 방법 자체가 없다) | — |
| 입력 형태 | **텍스트 전용** — `contents:[{parts:[{text: prompt}]}]` | `index.ts:362` |
| 함수 리전 | `asia-northeast3` | `index.ts:783` 외 11곳 전부 |
| 호출 지점 | `generateBriefing` **한 곳뿐** | `index.ts:780` |

### 1-2. 명함 인식(OCR) — **서버로 아무것도 안 나간다. 전부 기기 안이다.**

```
pubspec.yaml:54   google_mlkit_text_recognition: ^0.15.0
```

`functions/src/index.ts`에 이미지·OCR 호출부가 **없다.** 서버에 있는 것은
`ocrStats/{uid}` **카운터 문서**(`index.ts:1507`, `1549`)뿐이다.

⭐ **그러므로 "무엇이 이미 외부로 나가고 있나"의 답은 명확하다.**

```
명함 사진·명함 이미지   → 나가지 않는다 (ML Kit 온디바이스)
AI 브리핑 프롬프트     → 나간다 (미국, Gemini Developer API)
```

### 1-3. ⚠️ 그런데 그 프롬프트에는 **제3자(명함 주인) 개인정보가 들어 있다**

`buildPrompt()`(`index.ts:257~325`)가 실제로 합치는 것:

| 프롬프트 조각 | 필드 | 누구의 정보인가 |
|---|---|---|
| `[상대방 정보]` | `contactSummary` | **명함 주인**(이름·직함·회사 등) |
| `관심사:` | `interests` | **명함 주인** |
| `오늘 상대방 지역 날씨` | `weatherSummary` | 명함 주인 **주소에서 나온** 좌표 기반 |
| `[최근 소통 기록]` | `communicationLogs` | 이용자–명함 주인 사이의 접촉 이력 |
| `[사용자가 직접 남긴 메모]` | `extraNote` | 이용자가 명함 주인에 대해 적은 것 |
| `[나(사용자) 정보]` | `myProfileSummary` | 이용자 본인 |

게시된 방침도 이 경로를 그대로 적어 두었다.

```
privacy-policy.html:565
  이용자의 기기 → 커넥션센스 서버(Google Cloud Functions, 서울 리전)
                → Google Gemini API(미국)
```

즉 **서버 명함 인식이 아직 미착수여도, 제3자 개인정보의 국외 이전은 이미
진행 중이다.** 법무 검토가 지목한 위험(§28조의8, 매출 3%/20억)이 겨누는 구조는
**미래의 사진 전송에만 있는 것이 아니다.**

> ⚠️ **다만 이 문서는 "지금 브리핑이 위법이다"라고 판정하지 않는다.**
> 브리핑은 국외 이전 표(7번)에 **행이 있고**, 전송 확인 화면(`AiDataReviewSheet`)도
> 있다. 사진 전송과 달리 *고지 자체가 없는* 상태는 아니다. 다만 법무 메모가
> 짚은 **"동의의 주체가 명함 주인이 아니라 이용자"**라는 구조적 문제와
> **"근거 열 자체가 표에 없다"**(시행령 §31①2호)는 흠결은 브리핑에도 그대로
> 걸린다. **판단은 법무·변호사 몫이고, 이 문서는 사실관계만 댄다.**

---

## 2. 근거와 그 한계 — 무엇을 어떻게 확인했나

### 2-1. ⭐ 제품이 개명됐다 — 이것부터 확인했다

`cloud.google.com/vertex-ai/generative-ai/docs/...` 경로는 **301 Moved
Permanently**로 `docs.cloud.google.com/gemini-enterprise-agent-platform/...`로
옮겨져 있다. 표시명도 **"Generative AI on Vertex AI" → "Gemini Enterprise
Agent Platform"**으로 바뀌었다.

📌 **그래서 08-23 PDF의 제목이 "Vertex AI"가 아니었던 것이다.** 08-23 시점에는
*"제품이 다르면 표가 무효 아닌가"*가 미해결 의문이었는데, **원 URL이 직접
리디렉션하는 목적지**라는 것으로 해소됐다. 본문도 `aiplatform.googleapis.com`,
`vertexai.init()`, `google-cloud-aiplatform` SDK를 그대로 가리킨다.

### 2-2. 무엇을 근거로 삼았나

| 근거 | 확인 주체 | 확인일 |
|---|---|---|
| 사용자 저장 PDF 4건(데이터 상주·배포 및 엔드포인트) | 이 세션이 좌표+이미지로 판독 | 문서 갱신 **2026-08-07**, 저장 08-23 |
| `…/models/gemini/2-5-flash` 원문 HTML | ⭐ **이 세션이 직접 `curl`로 받아 파싱** | **2026-08-24** |
| `…/models/gemini/3-6-flash`, `3-5-flash`, `3-7-flash` 원문 HTML | ⭐ **이 세션이 직접** | **2026-08-24** |
| `ai.google.dev/gemini-api/docs/pricing` 원문 HTML | ⭐ **이 세션이 직접** | **2026-08-24** |
| `locations` / `data-residency` / `supported-capabilities` / `migrate-google-ai` / Service Terms | **조사 에이전트**가 원문에서 인용 | 2026-08-24 |

⚠️ **마지막 줄은 이 세션이 직접 열지 않았다.** 아래에서 그 출처의 사실은
**"에이전트 확인"**으로 표시해 구분한다.

⚠️ **PDF는 한국어 기계 번역본**이다(문서 머리에 *"AI 번역에는 오류가 있을 수
있습니다"*). 법적 문언으로 인용하려면 영문 원본 대조가 필요하다. 다만 이
문서의 **결론은 전부 영문 원문(`curl`)으로 교차 확인된 것**이다.

### 2-3. ⚠️ 표를 읽는 데 실제로 한 번 틀릴 뻔했다 — 절차를 남긴다

```
1) pdftotext -layout      → 열이 어긋났다. 이것만 믿었으면 틀렸다
2) pdftotext -bbox-layout → 낱말 x좌표로 열 경계를 확정
3) pdftoppm -png          → 해당 페이지를 이미지로 렌더링해 눈으로 대조
4) curl + HTML 파싱        → 웹 원문으로 2차 대조
```

> ⚠️ `-layout` 출력에서 `Gemini 3.5 Flash` 행은 체크가 **마지막 칸(대한민국)까지
> 있는 것처럼** 보였다. x좌표로 재니 마지막 체크는 **x=674(싱가포르)**였고,
> 대한민국 열은 **x=732**로 비어 있었다. 렌더링 이미지와 웹 원문
> (`3-5-flash` 페이지 ML processing = `asia-northeast1, asia-south1,
> asia-southeast1`)이 모두 일치했다.
>
> **자릿수가 맞아 보인다고 확인이 아니다.**

확정한 열 x좌표(데이터 상주 PDF):

```
153 미국멀티  178 EU멀티  203 브라질  276 캐나다  350 프랑스  393 독일
435 네덜란드  477 영국  520 호주  580 인도  618 일본  674 싱가포르  732 대한민국
```

---

## 3. ⭐⭐ 가장 중요한 발견 — 서울에서 쓸 수 있는 그 모델이 두 달 뒤 은퇴한다

이 세션이 `docs.cloud.google.com` 모델 페이지 HTML을 직접 받아 확인한
**Versions 절 원문**이다.

| 모델 | Launch stage | Release date | **Retirement date** | ML processing 리전 |
|---|---|---|---|---|
| ⭐ **`gemini-2.5-flash`** | GA | June 17, 2025 | ⚠️ **October 20, 2026** | US multi · Canada · Brazil · EU multi · europe-west2/3/9 · **APAC: `asia-northeast1`, `asia-northeast3`, `asia-south1`, `asia-southeast1`, `australia-southeast1`** |
| `gemini-3.5-flash` | GA | May 19, 2026 | May 19, 2027 **or later** | us · eu multi · northamerica-northeast1 · europe-west2/3 · APAC: `asia-northeast1`, `asia-south1`, `asia-southeast1` — **서울 없음** |
| `gemini-3.6-flash` ← **지금 우리 모델** | GA | July 21, 2026 | (기재 없음) | **`us`, `eu` 멀티리전뿐** — 아시아 전무 |
| `gemini-3.7-flash` | GA | August 13, 2026 | (기재 없음) | **`us`, `eu` 멀티리전뿐** — 아시아 전무 |

📌 **여기서 읽어야 할 것은 날짜 하나가 아니라 방향이다.**

```
2.5 세대 (2025-06)  →  서울 포함 12개 리전에서 국내 처리 보장
3.5 세대 (2026-05)  →  아시아 3곳, 서울 빠짐
3.6 세대 (2026-07)  →  us/eu 멀티리전만
3.7 세대 (2026-08)  →  us/eu 멀티리전만
```

**세대가 올라갈수록 리전이 줄어들고 있다.** 그리고 `supported-capabilities`
문서는 이 방향을 명시적으로 확인해 준다(에이전트 확인, 원문):

> *"Jurisdictional multi-region endpoints: These are designed **exclusively for
> the Gemini 3 family and future versions**. Older models (like Gemini 2.5 and
> earlier) are not supported on these endpoints."*
>
> | Model family | Standard regional endpoints (US and EU) | Jurisdictional multi-region |
> |---|---|---|
> | Gemini 3.x | ❌ | ✅ |
> | Gemini 2.x | ✅ | ❌ |

즉 Google은 **3.x 계열을 "리전별"이 아니라 "관할권 멀티리전(us/eu)"으로만
내놓는 방향**이다. 한국은 그 관할권 목록에 없고, `aiplatform.<region>.rep.
googleapis.com` 호스트도 **`us`·`eu` 둘뿐**이다(에이전트 확인).

⚠️ **그러므로 "지금은 되니까 가자"는 결정은 두 달짜리다.** 그렇다고 "가지
말자"도 아니다 — 아래 4절에서 갈라 본다.

⚠️ **이 문서는 Google이 후속 모델을 서울에 열지 여부를 알지 못한다.**
`2.5-flash-lite`·`2.5-pro`도 같은 2026-10-20 은퇴이므로 **2.5 세대 통째로
정리되는 것**으로 보이지만, **그것이 "서울이 닫힌다"는 뜻인지는 문서에 없다.**
추정하지 않는다.

### 3-1. ⚠️ 두 개의 표는 서로 다른 것을 말한다 — 섞으면 안 된다

Google 문서 스스로 못을 박아 두었다(에이전트 확인, `locations` 페이지 원문):

> **"Important: Endpoints don't guarantee data residency or in-region ML
> processing. For information about data residency, see Data residency."**

| 표 | 무엇을 말하나 | 국외 이전 판단에 쓸 수 있나 |
|---|---|---|
| `locations`(배포 및 엔드포인트) | 그 리전 **엔드포인트로 부를 수 있다** | ❌ **안 된다** |
| `data-residency` / 모델 페이지 `ML processing` | 그 리전 안에서 **처리가 이뤄진다** | ✅ **이것이 근거다** |

**둘이 실제로 어긋나는 예가 있다.** `gemini-embedding-001`·텍스트용 임베딩·
멀티모달 임베딩은 `locations`에서 **서울 ✓**인데 `data-residency`에서는
**대한민국 열이 비어 있다**(미국·EU 멀티리전만). **서울 엔드포인트로 부를 수는
있지만 처리가 국내에 머문다는 약속은 없다.** (렌더링 이미지로 확인)

### 3-2. ⚠️ 같은 `gemini-2.5-flash`인데 128k와 1M이 갈린다

데이터 상주 표는 같은 모델 ID를 **컨텍스트 크기로 두 행**으로 나눠 놨다.

| 행 | 대한민국 ML 처리 |
|---|---|
| **Gemini 2.5 Flash, 128k** | ✅ |
| Gemini 2.5 Flash, **1M** | ❌ (미국·EU·캐나다·싱가포르) |

📌 **모델 ID만 적으면 안 된다.** 문서·설정 어디서든 **"128k"를 함께 명시**해야
한다. 브리핑 프롬프트는 수천 토큰이라 128k로 충분하다.

### 3-3. 전역(global) 엔드포인트는 쓰면 안 된다

에이전트 확인, 원문:

> *"**Don't use the global endpoint if you have ML processing requirements**,
> because you can't control or know which region your ML processing requests
> are sent to when a request is made."*
>
> *"Global endpoints route and process data anywhere globally … **they don't
> provide regional isolation or data residency guarantees.**"*

반대로 리전 엔드포인트는:

> *"**Locational endpoints**: These endpoints (like `us-central1`,
> `europe-west1`) **ensure that ML processing remains entirely within the
> broader multi-regional or country jurisdiction associated with that region**."*

### 3-4. ⚠️ 문서는 보장하는데 **계약 문언은 다르다** — 법무가 봐야 할 자리

에이전트가 `cloud.google.com/terms/service-terms`에서 찾은 것:

| 조항 | 원문 | 단위 |
|---|---|---|
| General Terms 1. **Data Location**(저장) | *"Customer may select a specific **Region or Multi-Region** … Google will store Customer Data … at rest only within the selected Region or Multi-Region."* | **Region 또는 Multi-Region** |
| Service Terms 16. **AI/ML Data Location**(처리) | *"…(b) perform machine learning processing of Customer Data by the Service, in each case **in a specific Multi-Region**, and Google will perform (a) and (b) only in that Multi-Region."* | ⚠️ **Multi-Region만** |

⭐ **저장 조항은 "Region 또는 Multi-Region"인데 ML 처리 조항은 "Multi-Region"만
쓴다.** 그리고 Multi-Region은 **`us`와 `eu` 둘뿐**이다.

즉 **서울 단일 리전 처리는 문서(docs) 표에는 있지만, 계약 문언에는 그 단위가
없다.** 이것이 단순한 문언 정리인지, 아니면 **약정 수준의 차이**인지는
**이 문서가 판단할 수 없다.**

⚠️ **법무 검토가 "국외 이전 위험이 0이 된다"고 할 때 그 근거는 문서 표다.
계약 문언까지 대조한 것은 아니다.** 감독기관에 *"무슨 근거로 국내 처리라고
했나"*를 답해야 하는 자리라면 **이 차이를 변호사에게 반드시 보여야 한다.**
Google에 서면 확인을 요청할 수도 있다. **미확인 항목으로 남긴다.**

### 3-5. 그래서 우리 용도별 판정

| 용도 | 서울에서 되나 | 근거 |
|---|---|---|
| **AI 대화 브리핑**(텍스트 생성) | ⭕ **된다** — `gemini-2.5-flash`로 내려야 함 | 3절 |
| **명함 인식**(이미지 입력) | ⭕ **된다** | 아래 |
| 임베딩(향후 검색용) | ❌ **상주 보장 없음** | 3-1 |

⭕ **명함 인식이 되는 근거는 둘이고, 서로를 보강한다.**

1. **문서**(에이전트 확인, `2-5-flash` 페이지 Modalities 표 원문):
   `Text: Input and output` · **`Image: Input only`** · Audio/Video: Input only.
   이미지 최대 3,000장/프롬프트, 인라인 7MB, MIME `image/png|jpeg|webp|heic|heif`.
2. **실측**: 08-23에 명함 96장을 실제로 서울에서 돌려 12칸 **94%**를 얻었다
   (추가 415~419). 결과 TSV 4건이
   `connection-sense-assets/명함데이터/server_ocr_vertex25_*.tsv`에 남아 있다.

📌 **문서와 실측이 같은 방향을 가리키는 드문 경우다.** 이 저장소가 겪어 온
사고는 대개 둘이 갈릴 때 났다.

---

## 4. 서울로 가는 것이 여전히 옳은가 — 은퇴일을 넣고 다시 본다

3절의 발견은 결론을 뒤집지 않는다. **선택지를 셋으로 벌린다.**

| 안 | 무엇 | 국외 이전 | 두 달 뒤 |
|---|---|---|---|
| **A. 그대로 둔다** | Developer API + 3.6-flash(미국) | **있다** — 지금 상태 | 그대로 |
| **B. 서울로 간다** | Vertex 서울 + 2.5-flash(128k) | **없다**(AI분) | ⚠️ **10-20에 재결정** |
| **C. Vertex로 가되 리전은 나중에** | Vertex us/eu 멀티리전 + 3.x | 있다(단, **관할권 고정**) | 안정적 |

📌 **B가 두 달짜리라고 해서 무의미하지 않다.** 이유 셋.

1. **가장 큰 공사는 리전이 아니라 제품 이전이다**(6절). Developer API →
   Vertex 전환을 해 두면 **리전·모델을 바꾸는 것은 문자열 두 개**다. B로 갔다가
   10월에 막혀도 **C로 내려오는 비용이 거의 없다.**
2. **10-20까지도 시간은 시간이다.** 그사이 스토어 출시가 걸린다면 **출시
   시점의 상태**가 중요하다.
3. **은퇴가 곧 "서울이 닫힘"은 아니다.** 후속 모델이 서울에 열릴 수도 있다 —
   **모르는 것이지 나쁜 것이 아니다.**

⚠️ **그러나 이것만은 분명히 적어 둔다.**

> **방침에 *"AI 처리는 국내에서만 이뤄집니다"*라고 쓰는 것과, 서울에서 도는
> 모델을 쓰는 것은 다른 무게다.** 방침은 **되돌리기 어렵고**(한 번 쓴 단언을
> 지우려면 또 개정해야 한다 — 08-23 도입계획 5-4절), 모델 은퇴는
> **우리가 통제하지 못한다.** 10-20에 대체 모델이 없으면 **방침이 먼저
> 거짓이 된다.**
>
> 📌 그래서 **방침 문안은 "서울 리전"으로 못 박기보다, 후속 대응 여지를 남기는
> 쪽이 안전하다.** 문안 설계는 법무·변호사 몫이다 — 이 문서는 위험만 짚는다.

---

## 5. ⭐ 앞선 문서들이 빠뜨린 것 — **브리핑과 OCR은 서로 다른 일이다**

법무 검토도, 08-23 두 문서도 전부 **"서버 명함 인식"** 맥락에서 서울을
말한다. 그런데 이전 대상은 사실 **둘**이고, 상태가 정반대다.

| | AI 대화 브리핑 | 서버 명함 인식 |
|---|---|---|
| 지금 상태 | ⭐ **가동 중** | **미착수**(사용자 결정으로 보류) |
| 지금 국외로 나가나 | ⭐ **나간다**(미국) | 안 나간다 |
| 방침에 적혀 있나 | 있다(7번 표 Gemini 행) | 없다(신설 필요) |
| 서울로 옮기면 | 국외 이전 **행 하나가 사라진다** | 국외 이전이 **애초에 생기지 않는다** |
| 옮기는 데 드는 것 | **제품 이전 + 모델 교체**(3.6→2.5) | 없음(어차피 새로 만든다) |
| 위험 성격 | **되돌리기** — 이미 나간 것은 못 되돌린다 | **예방** — 아직 안 나갔다 |

📌 **두 가지 실무적 함의.**

1. **서버 인식은 "서울로 시작하면 그만"이다.** 보류 중이므로 지금 **결정만**
   해 두면 추가 작업이 없다. 법무가 말한 *"손댈 곳 하나"*는 여기서는
   **결정**이지 **공사**가 아니다.
2. ⚠️ **브리핑은 다르다. 여기가 실제 공사다.** 그리고 **모델을 한 세대
   내려야 한다.** 브리핑 품질이 어떻게 달라지는지는 **아무도 재지 않았다**(8절).

### 5-1. 서울로 옮겨도 **국외 이전 표는 사라지지 않는다** — 정확히 적는다

법무 검토의 *"개정 범위가 절반으로 준다"*는 **서버 인식 개정분** 이야기다.
현재 방침 7번 표를 실제로 열어 보면 행이 **넷**이다.

| 이전받는 자 | 국가 | 서울 이전 후 |
|---|---|---|
| Google LLC (Firebase Authentication) | 미국 | **남는다** |
| Google LLC (**Gemini API**) | 미국 | ⭐ **빠진다** |
| Apple Inc. (주소→좌표) | 미국 | **남는다** |
| OpenMeteo GmbH (날씨) | 스위스 | **남는다** |

⚠️ **그러므로 "국외 이전이 0이 된다"고 쓰면 사실과 다르다.** 0이 되는 것은
**AI 처리로 인한 국외 이전**이고, 회원 인증·주소 변환·날씨는 그대로다.
(오늘자 법무 검토 본문도 540행에서 같은 점을 인정하고 있다.)

---

## 6. 전환에 무엇이 필요한가 — 코드 기준

### 6-1. 인증이 근본적으로 바뀐다

공식 마이그레이션 문서 비교표 원문(에이전트 확인):

| Feature | Gemini API | Gemini Enterprise Agent Platform |
|---|---|---|
| Endpoint | `generativelanguage.googleapis.com` | `aiplatform.googleapis.com` |
| **Authentication** | **API Key or OAuth** | **Google Cloud service account** |
| Infrastructure | **Global endpoint.** | Global endpoint **and regional endpoints.** |
| Model improvement | Free tier: 사용될 수 있음 / Paid: 안 씀 | **never used** |
| Compliance | *"No compliance certifications … Regulated customers should use Gemini Enterprise Agent Platform instead."* | *"**Provides data residency**, CMEK, Access Transparency"* |
| Quota (RPM) | 모델·요금제에 따라 | 모델 **및 리전**에 따라 |

⚠️ **Vertex도 API 키를 쓸 수 있지만 그러면 리전을 잃는다.** Express mode의
엔드포인트는 `https://aiplatform.googleapis.com/v1/publishers/google/models/…?key=…`
로 **호스트에 리전이 없고 경로에 `locations/`도 없다** — 3-3절의 global
endpoint에 해당한다. **데이터 상주가 목적이면 API 키는 선택지가 아니다.**

| | 지금 | 바뀜 |
|---|---|---|
| 방식 | API 키(URL 쿼리) | **서비스 계정 / ADC** → `Authorization: Bearer` |
| 보관 | `defineSecret("GEMINI_API_KEY")` | 시크릿 불필요 |
| 사전 작업 | 없음 | `aiplatform.googleapis.com` 사용 설정 + 함수 SA에 `roles/aiplatform.user` |

📌 **Cloud Functions가 이미 `asia-northeast3`에 있다는 점이 유리하다.** 함수와
모델 리전이 같아 리전 간 왕복이 없고 ADC가 그대로 잡힌다.

⚠️ **`GEMINI_API_KEY` 시크릿을 지우는 것은 이전이 검증된 뒤다.**

### 6-2. 엔드포인트 — 형식 확인됨

> 🚨 **[2026-08-31 추가 경고] 이 절의 URL 형식은 서울(지역 엔드포인트) 전용이다
> — us/eu 관할권 멀티리전에는 쓰면 안 된다.** 이 절 바로 아래 형식
> (`${LOCATION}-aiplatform.googleapis.com`)은 서울행을 전제로 적은
> **지역(locational) 엔드포인트** 형식이다. 리전 결정이 서울 → us 관할권
> 멀티리전으로 바뀐 뒤 이 절을 그대로 코드에 옮기면서 실제로 결함이 났다
> (PR #747 병합 후 발견·수정, backlog 추가 623). **us/eu로 갈 때 맞는 형식은
> 3절(약 216줄)의 `aiplatform.<region>.rep.googleapis.com` — 관할권 멀티리전은
> 그쪽 절을 볼 것.** 같은 문서 안에 서로 다른 전제로 쓰인 두 절이 있으니,
> 리전 결정이 바뀌면 **참조할 절도 함께 바뀌어야 한다는 것**을 이 사고가
> 보여준다.

에이전트가 `locations` REST 예제 원문에서 확인(⚠️ 아래는 **서울 등 지역
엔드포인트** 형식이다 — us/eu 관할권 멀티리전 형식은 3절 참고):

```
https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/${LOCATION}/publishers/google/models/${MODEL_ID}:generateContent
```

서울 대입:

```
지금:  https://generativelanguage.googleapis.com/v1beta/models/
         gemini-3.6-flash:generateContent?key=API_KEY

바뀜:  https://asia-northeast3-aiplatform.googleapis.com/v1/projects/<PROJECT>/
         locations/asia-northeast3/publishers/google/models/
         gemini-2.5-flash:generateContent
       + Authorization: Bearer <ACCESS_TOKEN>
```

모델 ID 문자열은 **양쪽이 같다**(`gemini-2.5-flash`). 다른 것은 경로다 —
AI Studio는 `models/…`, Vertex는 `publishers/google/models/…`.

### 6-3. SDK — 갈아엎을 필요가 없다

공식 SDK 문서 원문(에이전트 확인):

> *"The Google Gen AI SDK provides a unified interface … **With a few
> exceptions, code that runs on one platform will run on both.** … you can
> migrate the application to Gemini Enterprise Agent Platform **without
> rewriting your code.**"*

```js
// @google/genai
new GoogleGenAI({vertexai: false, apiKey: GEMINI_API_KEY});                  // 지금
new GoogleGenAI({vertexai: true, project: PROJECT, location: LOCATION});     // 바뀜
```

⚠️ 단 우리 코드는 **SDK를 안 쓰고 `fetch`로 REST를 직접 부른다**
(`index.ts:352~373`). 선택지는 둘이다.

| 선택 | 장점 | 단점 |
|---|---|---|
| **REST 유지** + `google-auth-library`로 토큰만 | 의존성 1개, 지금 구조 유지 | 6-2 URL·6-4 파라미터를 우리가 관리 |
| **`@google/genai` SDK 도입** | 두 제품 차이를 SDK가 흡수 | 의존성 큼, 기존 파싱·재시도 로직 재작성 |

📌 **지금 코드는 응답 파싱(`parseTalkingPoints`)·사고 파트 필터·400 폴백까지
직접 짜 놓았다.** SDK로 갈아엎으면 **그 세 가지를 다시 검증해야 한다.**
**REST 유지 쪽을 권한다** — 다만 이는 권고이고 결정 사항이 아니다.

### 6-4. 요청 본문 — 걱정했던 자리는 **괜찮다**

```
index.ts:365   thinkingConfig: { thinkingLevel: THINKING_LEVEL }
```

`supported-capabilities` 표에서 **`Thinking budget`은 미·EU 밖 리전 엔드포인트에서
✅**다(에이전트 확인). 즉 **서울에서도 사고량 제어는 된다.**

⚠️ **다만 파라미터 *이름*이 세대별로 다를 수 있다.** `thinkingLevel`은
**Gemini 3 세대 디스커버리 문서에서 확인한 필드**다(`index.ts:172~180` 주석).
2.5 세대가 같은 이름을 받는지는 **확인하지 못했다.**

📌 **다행히 코드가 이미 이 사고에 대비돼 있다.** `callGemini()`가 400을 받으면
`thinkingLevel`을 빼고 한 번 더 보낸다(`index.ts:381~397`). **기능이 죽지는
않지만 사고 토큰이 통제되지 않아 요금이 오를 수 있다** — 08-08에 사고 토큰이
과금 출력의 91%였던 전례가 있다.

⚠️ **이 자리에서 이미 두 번 틀린 전례가 있다**(`thinkingBudget` 거부 →
필드 위치 오독). **짐작하지 말고 v1 디스커버리 문서로 확인할 것.**

### 6-5. 코드 변경 규모 — **작다. 한 파일, 대여섯 자리.**

| 자리 | 무엇 |
|---|---|
| `index.ts:357` | URL |
| `index.ts:352~373` | 액세스 토큰 획득 + `Authorization` 헤더 |
| `index.ts:180` | 모델 ID (`gemini-3.6-flash` → `gemini-2.5-flash`) |
| `index.ts:365` | thinking 파라미터명(6-4) |
| `index.ts:782` | `secrets: [geminiApiKey]` 제거(검증 후) |
| `functions/package.json` | `google-auth-library` 추가 |

응답 파싱(`candidates[].content.parts[].text`, `usageMetadata`)은 **양쪽이 같은
모양**이라 그대로 쓸 수 있을 것으로 보인다 — ⚠️ **실물로 확인하지 못했다.**

📌 **어려운 것은 코드가 아니라 그 뒤다.** ① 모델이 바뀌므로 브리핑 품질 재확인,
② 방침 개정, ③ `firebase deploy --only functions`는 **사용자 결정**이고 지금은
**지갑 코드까지 함께 올라간다**(CLAUDE.md 6절).

---

## 7. 비용과 제약

### 7-1. ⭐ 단가는 **오히려 내려간다** — 이 세션이 원문에서 직접 확인

`ai.google.dev/gemini-api/docs/pricing` 원문 HTML(2026-08-24, 직접 `curl`):

| 모델 | 입력 / 1M | 출력(사고 포함) / 1M |
|---|---|---|
| `gemini-3.6-flash` ← **지금** | **$0.75** (2026-12-31까지) → **$1.50** (2027-01-01~) | **$3.75** → **$7.50** |
| ⭐ `gemini-2.5-flash` | **$0.30** | **$2.50** |

**즉 2.5-flash로 내려가면 입력 60% ↓, 출력 33% ↓** (지금 프로모션가 대비).
2027년 정가 대비로는 **입력 80% ↓, 출력 67% ↓**.

📌 **부수 발견 — 코드 주석이 낡았다.** `index.ts:172`는 단가를 *"입력
$1.50/1M · 출력 $7.50/1M"*로 적어 두었는데, 이는 **2027-01-01부터의 정가**이고
**지금 실제 단가는 그 절반**이다. 손익 계산에 이 주석을 인용한 곳이 있다면
같이 봐야 한다. ⚠️ **이 문서는 그 주석을 고치지 않았다**(조사만 하기로 한 범위).

**Vertex와 AI Studio 단가는 같고, 서울 프리미엄은 문서상 없다**(에이전트 확인
— Gemini 요금표에는 Region 열 자체가 없고, 리전별 단가 구분은 Anthropic 등
파트너 모델에만 있으며 그 목록에 `asia-northeast3`는 아예 없다).

⚠️ **Vertex에는 상시 무료 등급이 없다**(신규 $300 크레딧, 또는 Express
mode 90일 — 후자는 API 키 방식이라 리전을 잃는다).

⚠️ **건당 실제 원가는 여전히 안 쟀다.** 08-23 도입계획 6절이 같은 지적을 했다.
단가를 알아도 **토큰 수를 모르면 원가를 모른다.**

### 7-2. ⚠️ 서울 리전 혼잡(429) — **이미 실측된 제약이 있다**

08-23에 명함 95장을 서울에서 돌린 기록([도입계획](./server-ocr-adoption-plan-2026-08-23.md) 5-2절):

```
1회차   첫 시도 95건 전멸
2회차   재실행 중반 33건 밀림
3회차   1차 50건만 성공, 45건 밀림
```

세 번 다 재시도해서 결국 성공했다. **재시도 설계 없이 온디맨드로 부르면
사용자 요청이 통째로 실패한다.**

⭐ **이것은 브리핑에도 그대로 걸린다.** 지금 브리핑에는
**`thinkingLevel` 거부(400)용 재시도 하나뿐**이고 **혼잡 재시도가 없다**
(`index.ts:400~412` — `!response.ok`면 바로 `unavailable`을 던진다).
서울로 옮기면 **지금 없는 재시도·백오프가 새로 필요할 수 있다.**

📌 **global endpoint를 쓰면 429가 준다고 문서가 말하지만**(3-3절 인용),
**그 순간 리전 보장이 사라진다.** 가용성과 상주가 정면으로 맞바꿈 관계다.

⚠️ 위 숫자는 **그날 하루·일괄 배치 부하**의 값이다. 브리핑은 건당 1회
호출이라 부하 형태가 다르다 — **그대로 옮겨 읽지 말 것.**

### 7-3. 서울에서 못 쓰게 되는 것

`supported-capabilities` 문서 "Standard regional endpoints (outside US and EU)"
열(에이전트 확인). 이 표는 *"기능이 없다"*가 아니라 **"그 리전 안에서 처리된다는
보장이 없다"**는 뜻이다 — 문서가 명시한다:

> *"**Non-Listed capabilities**: If a capability is not explicitly listed,
> ML processing is not guaranteed to occur in a specific location."*

| 서울에서 ✅ | 서울에서 ❌ |
|---|---|
| Chat completions · Function calling · Structured output · System instructions · **Context caching** · **Long context** · **Thinking budget** · Code execution · **Batch inference** · Private Google Access · Security controls | **Count tokens** · **Thought summaries** · **Model tuning** · **Provisioned Throughput** · Grounding(Agent Platform Search) · Standard PayGo without usage tiers |

우리 영향:

| 잃는 것 | 영향 |
|---|---|
| Gemini 3.x 계열 전부 | ⚠️ **브리핑 모델이 한 세대 내려간다** |
| **Count tokens** | 사전 토큰 계산 API를 못 쓴다 — 다만 **우리는 응답의 `usageMetadata`로 사후 집계**하므로(`index.ts:428`) 영향 없다 |
| Thought summaries | 지금 안 쓴다 |
| Model tuning / Provisioned Throughput | 지금 안 쓴다 |
| 이미지 **생성** 모델 전부 | 지금 안 쓴다 |
| 1M 컨텍스트 | 브리핑은 수천 토큰 — 영향 없다 |
| 임베딩 상주 보장 | 향후 의미 검색을 국내 상주로 하려면 막힌다 |
| 전역 엔드포인트의 가용성 이점 | 429가 늘 수 있다(7-2) |

### 7-4. 보관·학습 정책 — 방침 문안에 직결된다

에이전트가 원문에서 확인한 것.

| | Vertex(Agent Platform) | AI Studio 유료 ← **지금 우리** |
|---|---|---|
| 학습 사용 | *"Google won't use your data to train or fine-tune any AI/ML models without your prior permission"* | *"Google doesn't use your prompts … to improve our products"* |
| 남용 모니터링 로깅 | **최대 90일**, ⭐ *"stored securely … **in the same region or multi-region selected by the customer**"* · **opt-out 신청 가능** | *"logs prompts and responses **for a limited period of time**"* · ⚠️ *"**may be stored transiently or cached in any country** in which Google or its agents maintain facilities"* |
| 인메모리 캐시 | 기본 켜짐, **24시간 TTL**, 프로젝트 격리, *"adheres to all Data Residency requirements"*, **끌 수 있음**(`cacheConfig.disableCache`) | (해당 문구 없음) |
| 요청·응답 로깅 | *"disabled by default"* | — |

⭐ **이것이 리전 이전의 숨은 이득이다.** 지금은 남용 모니터링 로그가
**"어느 나라든"** 캐시될 수 있다고 약관이 명시한다. Vertex 서울로 가면
**그 90일 로그까지 선택한 리전에 남는다.**

⚠️ **반대로 이것은 방침 문안의 함정이기도 하다.** 방침 7번 표의 Gemini 행은
보유 기간을 **"요청 처리 후 미보관"**이라고 적고 있는데, **남용 모니터링 90일과
인메모리 캐시 24시간이 있으므로 엄밀히는 부정확하다.** 08-23 법무 메모도
같은 지적을 했다(129행). **서울로 가든 안 가든 이 문구는 손봐야 한다.**

---

## 8. ⚠️ 확인하지 못한 것 — 착수 전 채울 것

**규약대로 확인한 것과 못 한 것을 가른다.**

| # | 확인 못 한 것 | 왜 중요한가 | 어떻게 채우나 |
|---|---|---|---|
| 1 | ⭐ **2.5-flash 은퇴 후 서울에 후속 모델이 열리는가** | **B안 전체의 수명** | Google에 문의 / 10월까지 문서 재확인 |
| 2 | ⭐ **Service Terms 16조가 단일 리전 처리를 약정하는가**(3-4) | 감독기관에 댈 **계약 근거** | 변호사 검토 + Google 서면 확인 |
| 3 | ⭐ **2.5-flash로 바꿨을 때 브리핑 품질** | **아무도 안 쟀다.** OCR 94%는 12칸 인식이지 대화 문장 생성이 아니다 | 같은 명함으로 3.6 vs 2.5 대화 포인트 비교 |
| 4 | **2.5 세대의 thinking 파라미터 이름**(6-4) | 틀리면 요금이 오른다 | v1 디스커버리 문서(`index.ts:194` 주석과 같은 방법) |
| 5 | **Vertex 응답 스키마가 정말 같은지** | `parseTalkingPoints` 재검증 필요 여부 | 실제 호출 1회 |
| 6 | **건당 토큰·원가** | 손익·충전 티어 전제(08-23 도입계획 6절과 같은 지적) | 실측 |
| 7 | **지연시간** | 서울 왕복이 체감에 얼마나 붙는지 | 실측 |
| 8 | **서울 리전 할당량(RPM/TPM)** | 7-2의 429와 직결. 문서상 quota가 **"모델 및 리전"**에 따라 다르다 | 콘솔 할당량 페이지 |
| 9 | **Firebase 프로젝트가 Vertex를 쓸 수 있는 상태인지** | Blaze는 맞으나 API 사용 설정·IAM 미확인 | 콘솔 실물 |
| 10 | **Vertex 요금표 원문 재확인** | 이 세션은 JS 렌더링 때문에 못 열었다(AI Studio 쪽만 직접 확인) | 브라우저로 열기 |
| 11 | **영문 원본 vs 한국어 PDF 대조** | PDF는 기계 번역본 | Switch to English |
| 12 | **`GOOGLE_GENAI_USE_VERTEXAI` vs `GOOGLE_GENAI_USE_ENTERPRISE`** | SDK 경로를 택할 경우만 | 실제 SDK 버전 |

⚠️ **특히 3번을 "OCR 94%가 증명한다"로 읽지 말 것.** 그 실측은 **12칸을
뽑아내는 일**이고, 브리핑은 **한국어 대화 문장 3개를 자연스럽게 만드는 일**이다.
`index.ts:165~180`·`321~335`의 주석이 보여주듯 **이 프로젝트는 3.6-flash의
버릇(영문 초안·사고 파편) 때문에 파서까지 따로 만들어 두었다.** 모델이 바뀌면
**그 버릇도 바뀌고, 맞춰 둔 파서·프롬프트가 어긋날 수 있다.**

---

## 9. 정리 — 결정에 필요한 것만

### 9-1. 세 질문에 대한 답

| 질문 | 답 |
|---|---|
| **① 서울에서 우리 용도가 가능한가** | 🔶 **조건부 가능.** 조건 둘 — (a) 모델을 `gemini-2.5-flash`(**128k**)로 내릴 것, (b) ⚠️ **2026-10-20 은퇴** 이후는 미정 |
| 브리핑(텍스트 생성) | ⭕ 가능 |
| 명함 인식(이미지 입력) | ⭕ 가능 — 문서(Modalities: Image = Input only) + 실측 96장 94% 양쪽 확인 |
| **② 지금 쓰는 것 / 바꿀 것** | **지금**: AI Studio(Developer API) · API 키 · `gemini-3.6-flash` · 리전 지정 불가 · 텍스트 전용 · 미국 처리 |
| | **바꿀 것**: 제품(→Vertex) · 인증(키→서비스 계정) · 엔드포인트(리전 고정) · **모델 세대(3.6→2.5)** |
| | **코드**: `functions/src/index.ts` 한 파일, 대여섯 자리 + 의존성 1개 |
| **③ 확인 못 한 것** | 8절 12건. 그중 무거운 셋 — **은퇴 후 대안 / 계약 문언 / 브리핑 품질** |

### 9-2. 부수 소득 — 서울로 가면 같이 좋아지는 것

| | 지금 | Vertex 서울 |
|---|---|---|
| 단가(입력/출력 per 1M) | $0.75 / $3.75 (2027년 $1.50/$7.50) | **$0.30 / $2.50** |
| 남용 모니터링 로그 위치 | *"any country"* | **선택 리전 내**, opt-out 가능 |
| 컴플라이언스 | *"No compliance certifications"* | 데이터 상주·CMEK·VPC-SC·Access Transparency |
| 시크릿 관리 | `GEMINI_API_KEY` 보관 필요 | 불필요(ADC) |

### 9-3. 순서 — 코드가 첫 단계가 아니다

```
1. 8절 1·2번(은퇴 후 대안 · 계약 문언)  ← ⭐ 이게 안 풀리면 나머지가 무의미
2. 8절 3번(브리핑 품질)                 ← 모델을 내리는 것이므로 필수
3. 8절 4~9번(파라미터·스키마·원가·할당량·콘솔)
4. 그다음 코드                          ← 여기까지 오면 반나절 일이다
5. firebase deploy                      ← ⚠️ 사용자 결정. 지갑 코드가 함께 올라간다
6. 방침 개정                            ← ⚠️ 사용자 결정(게시). 4절 경고 참고
```

### 9-4. 사용자 결정이 필요한 것

| 결정 | 왜 사용자인가 |
|---|---|
| Vertex 채택 여부, 그리고 **리전을 서울로 할지 us/eu 멀티리전으로 할지**(4절 A/B/C) | 법무 검토가 "일정을 당길 단 하나"로 지목 |
| 브리핑 모델을 한 세대 내리는 것을 받아들일지 | **품질 저하 가능성** — 아직 안 쟀다 |
| 방침에 "국내 처리"를 **단언할지** | ⚠️ **되돌리기 어렵고 모델 은퇴는 통제 밖**(4절) |
| `firebase deploy --only functions` | CLAUDE.md 6절 |

---

## 10. 이 문서를 읽고 하지 말아야 할 것

- ❌ **"서울로 가면 국외 이전이 0이 된다"** — 아니다. **AI로 인한 것만** 0이다.
  회원 인증·주소 변환·날씨 3행은 남는다(5-1).
- ❌ **"서울로 가면 끝"** — **2026-10-20 은퇴**가 있다(3절). 결정에 이 날짜를
  넣지 않으면 두 달 뒤 같은 자리에 다시 선다.
- ❌ **`locations` 표의 서울 ✓를 국외 이전 근거로 쓰는 것** — 문서가 스스로
  *"엔드포인트는 상주를 보장하지 않는다"*고 못 박았다(3-1).
- ❌ **`gemini-2.5-flash`라고만 쓰고 넘어가는 것** — **1M판은 한국 보장이
  없다**(3-2). **128k**를 명시해야 한다.
- ❌ **API 키로 Vertex를 부르는 것**(Express mode) — global endpoint가 되어
  **리전 보장이 사라진다**(6-1).
- ❌ **OCR 94%를 브리핑 품질 근거로 쓰는 것**(8절 3번).
- ❌ **문서 표를 계약 근거로 그대로 쓰는 것** — Service Terms 16조는
  **Multi-Region만** 약정한다(3-4). 변호사 확인이 필요하다.
- ❌ **이 문서의 표를 시간이 지난 뒤 그대로 인용하는 것** — 모델 가용성표와
  은퇴일은 자주 바뀐다. **가장 빨리 낡는 것은 정확도가 아니라 단가와 리전
  목록이다**(08-23 도입계획 7절과 같은 경고).

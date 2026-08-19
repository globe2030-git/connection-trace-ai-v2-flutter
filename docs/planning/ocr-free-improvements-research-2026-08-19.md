# OCR 무료 개선안 조사 — 엔진 교체 불필요, 병목은 파싱 (2026-08-19)

> 배경: 사용자 요청 — *"기존 작업 말고 OCR 추출과 파싱에 관한 자료를 찾아서
> 적용할 만한 무료 내용을 먼저 찾아서 알려줘. 정확도가 생명인데 원하는 수준이
> 나오지 않는다."* 이에 따라 기존 계획(정답지 정리 → R-05)과 별개로 **외부
> 기술·라이브러리를 웹 조사**해 적용 가능성을 평가했다. backlog **추가 329**.
>
> 전제가 되는 진단은 [`ocr-misread-triage-2026-08-19.md`](./ocr-misread-triage-2026-08-19.md)
> (추가 320·322): 전체 오류 127건 중 **진짜 오독은 21건(16%)**, 나머지
> **106건(83%)은 "읽었는데 파서가 자리를 못 고른 것"**이다.

⚠️ 이 문서의 성격: **현재 스택 확인은 실물**(코드·Podfile.lock·pub cache를
직접 열었다), **대안 평가는 조사**(출처 문서 기반)다. 어느 것도 아직 우리
명함 82~103장으로 **실측하지 않았다** — 도입 전 반드시 재생 하네스로 잰다.

---

## 1. 현재 스택 (실물 확인)

| 항목 | 실물 |
|---|---|
| OCR 엔진 | `google_mlkit_text_recognition: ^0.15.0`(설치는 0.15.1) — ML Kit 온디바이스 v2 |
| 인식 모델 | `TextRecognizer(script: TextRecognitionScript.korean)` **한 종류만** (`lib/core/services/ocr_scanner_service.dart:270`) |
| iOS | `GoogleMLKit/TextRecognitionKorean`(`ios/Podfile:43`)의 전이 의존성으로 **라틴 기본 모델(`GoogleMLKit/TextRecognition`)도 이미 링크돼 있음**(`Podfile.lock:1361,1372`) |
| Android | `build.gradle.kts:120`은 `text-recognition-korean:16.0.1`만 명시하지만, 플러그인 자체 `android/build.gradle`(pub cache 실물)이 라틴 기본 `text-recognition:16.0.1`을 이미 `implementation`으로 포함 |
| 전처리 | dartcv4(OpenCV)는 **테두리 검출·크롭에만** 사용. 이진화·대비·기울기 보정 없음 |
| 파싱 | 순수 규칙 기반(`ocr_scanner_service.dart` 2,757줄). 줄 좌표는 실어 나르나(추가 317) **좌표로 줄/열을 재배정하는 로직은 없음** |

📌 **가장 큰 수확**: 라틴 인식기가 **두 플랫폼 모두 이미 들어 있다.** 새 팟도
새 gradle 의존성도 필요 없다 — 호출 코드만 없다.

## 2. 조사한 대안 (무료·온디바이스 기준 평가)

| 이름 | 겨냥 | 무료 | 온디바이스 | Flutter 난이도 | 앱 크기 | 판정 |
|---|---|---|---|---|---|---|
| **ML Kit 라틴 2차 패스** | 오독(이메일·주소) | ✅ | ✅ | **낮음**(코드만) | **+0** | ✅ 권장 |
| **좌표 기반 줄/열 재배정** | **파싱 106건** | ✅ | ✅ | 중간~높음(규칙 설계) | +0 | ✅ 권장(=R-05) |
| **전처리 보강**(이진화·대비, dartcv4 재사용) | 오독 일부 | ✅ | ✅ | 중간 | +0 | ✅ 조건부(실측 후) |
| Tesseract 5(kor) | 오독 | ✅ | ✅ | 높음 | **+12~15MB** | ❌ 커뮤니티가 "명함엔 잘 안 됐다" 보고 |
| PaddleOCR PP-OCRv5(한국어) | 오독 | ✅ | △(ONNX/ncnn 이식) | **높음**(Flutter 바인딩 없음) | ~17MB+런타임 | ❌ 한국어 모델이 v3에서 끊겼다 v5에 재개 — 불안정 |
| EasyOCR | 오독 | ✅ | ❌(사실상 서버용) | 매우 높음 | 불명 | ❌ 모바일 이식 사례 못 찾음 |
| Apple Vision | 오독(iOS만) | ✅ | ✅ | 높음(플랫폼 이원화) | +0 | ❌ ML Kit 대비 한글 정량 비교 자료 없음 |
| Donut/LayoutLM 계열 | 파싱(레이아웃) | ✅ | ❌(서버급) | 매우 높음 | 수백MB급 추정 | ❌ 온디바이스 경량화 사례 못 찾음 |
| 온디바이스 소형 LLM(Gemma 등) | 파싱(구조화) | ✅ | △(Android 위주) | 높음 | **모델 1~4GB** | ❌ 규모 과도 |
| 유료 클라우드 OCR | — | ❌ | ❌ | — | — | ❌ 무료 조건 + 제3자 개인정보 외부 전송(방침 수정 필요) |

비권장의 공통 이유: **병목이 인식이 아니라 파싱(83%)이라, 엔진을 바꿔도 그대로
남는다.** 이번 조사는 새 기술 도입보다 **기존 방향(R-05)이 업계 표준 패턴과
일치한다는 확인**에 가깝다.

## 3. 권장 순위와 적용 스케치

**① 정답지 오류 정리 (선행 조건, 추가 323에서 이미 합의)** — 회사 칸 28건 중
최소 3건은 정답지 자체가 잘려 있거나 오기입. 이걸 먼저 고쳐야 아래 둘의 효과를
정확히 잴 수 있다. 재촬영 불필요.

**② 이메일 칸 전용 라틴 2차 패스 (R-03 축소판)** — 스캔 후 이메일 칸이 비었거나
정규식에 안 맞을 때**만**, 같은 이미지를 `TextRecognitionScript.latin`으로 한 번
더 읽는다. 라틴 결과가 정규식을 통과하면 채택, 아니면 버림 — **합치기 로직이
필요 없어** 전면 다중 패스(기각됨)와 다르다. 모델이 이미 양쪽에 있어 비용
사실상 0. 주소 칸(`길`→`킬` 오독 3건)에도 같은 패턴 확장 가능.

**③ 좌표 기반 줄/열 재배정 (R-05)** — 이미 갖고 있는 줄 좌표로 y클러스터링
(논리적 줄 묶음) + x정렬(좌/우 열)을 하고, 그 위에 기존 정규식·키워드 규칙을
얹어 "값의 모양 + 자리"로 칸을 판단한다. `card_13`처럼 회사 칸에 사람 이름이
들어가는 유형이 이 층에서 잡힌다. 가장 큰 파이(83%)를 겨냥.

**(선택) 전처리 보강** — 크롭 직후 그레이스케일 + adaptive threshold(또는
CLAHE)를 한 단계 추가. 일반 문서 기준 최대 15% 개선 사례가 있으나 **명함 특화
근거는 아니다.** 103장 재생 하네스로 오독 21건 중 몇 건이 주는지 **먼저 재고**,
효과가 작으면 접는다.

## 4. 못 찾은 것 (없다고 단정하는 게 아니라 검색으로 확인 못 한 것)

- 한국어 **명함 전용** 공개 정답 데이터셋(AI Hub에는 일반 문자·문서 OCR만 있음)
- Apple Vision vs ML Kit **한글 정량** 비교 벤치마크
- EasyOCR의 모바일/Flutter 이식 사례
- Donut·LayoutLM의 온디바이스 경량화 실사례

## 5. 출처

- <https://pub.dev/packages/google_mlkit_text_recognition> — 두 인식기 병용 패턴
- <https://developers.google.com/ml-kit/vision/text-recognition/v2/languages>
- <https://flutterexperts.com/how-to-add-text-recognition-ocr-in-flutter-apps/> — Tesseract vs ML Kit 코멘트
- <https://tesseract-ocr.github.io/tessdoc/Data-Files.html> — 언어팩 크기
- <https://huggingface.co/PaddlePaddle/korean_PP-OCRv5_mobile_rec>
- <https://github.com/nihui/ncnn-android-ppocrv5>
- <https://fritz.ai/comparing-apples-and-google-s-on-device-ocr-technologies/>
- <https://docparser.com/blog/improve-ocr-accuracy/> — 전처리 개선 사례
- <https://arxiv.org/pdf/1002.4006> — 명함 기울기 보정 논문
- <https://www.ijprems.com/ijprems-paper/aidriven-business-card-ocr-and-natural-language-custom-report-generation-for-sales-crm-systems> — 좌표+휴리스틱 필드 분류
- <https://invoicedataextraction.com/blog/python-ocr-library-comparison-invoices> — 열/행 재구성 기법
- <https://github.com/clovaai/donut>
- <https://aihub.or.kr/> — 명함 특화 데이터셋 없음 확인

## 6. 미결 (사용자 결정 대기)

착수 순서. 권장은 **① 정답지 정리 → ② 라틴 2차 패스 → ③ 좌표 재배정**이나,
사용자 확정 전이다. ⚠️ 다른 세션들은 이 논의가 대기 중임을 사용자에게
리마인드할 것(사용자 요청, 2026-08-19).

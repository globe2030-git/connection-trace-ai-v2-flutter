# 개인정보 취급 — 코드가 무엇을 흘릴 수 있는가 (2026-09-06)

> **재는 문서다. 코드는 한 줄도 안 고쳤다.**
>
> ⭐ **이번엔 실물 조회가 안 된다** — 오늘 서버 자료를 전부 지웠다. 그래서
> *"지금 무엇이 새어 있나"* 가 아니라 **「코드가 무엇을 흘릴 수 있는가」**를 본다.
>
> **잰 커밋**: `e316599c` · 워크트리 `ct-fn-coverage` · 2026-09-06
> 🚫 **실제 개인정보 값은 이 문서에 하나도 옮기지 않았다** — 자리와 조건만 적는다.

---

## 0. 한 줄

**넷 중 둘은 깨끗했고, 둘에서 나왔다.**

```
① 로그          🟡 개인정보 필드 직접 노출 **0건**. 다만 **한 자리**에서 조건부로 샌다
② 안전하지 않은 저장소  ✅ **위반 0건**
③ 방침 ↔ 코드     🚨 **게시본에 알리고가 없다** — 배포 순서가 걸려 있다
④ 과장           🚨 **같은 저장소가 자기와 모순된다** — 두 자리
```

---

## 1. ① 로그에 개인정보가 나가는가 — **직접 노출 0건, 조건부 한 자리**

### 1-1. 먼저 세는 법과 그 한계

```
앱 lib          debugPrint(  **188건**   (print( 은 0건)
서버 functions   logger.      **67건**
```

⚠️ **`grep` 이 못 보는 것을 먼저 물었다**: 문자열 보간 안의 객체(`$obj`) ·
암묵 `toString()` · **예외 객체를 그대로 찍는 것**. 그래서 필드명만 찾지 않고
**보간 형태**로 갈랐다.

📌 **처음 센 것이 틀렸다** — `debugPrint(` 를 `grep -E` 로 세니 **0건**이 나왔고
`--include=*.dart` 는 zsh 가 먹었다. **고정 문자열(`grep -F`)로 다시 세서 188건**을
얻었다. *"세는 도구가 무엇을 못 보는가"* 를 이 문서 안에서 한 번 겪었다.

### 1-2. ✅ 직접 노출은 없다

```
이름·전화·이메일·주소 필드를 보간한 debugPrint   **0건**
  grep -rniE "debugPrint\(.*\$\{?[a-z]*\.?(name|phone|email|address|mobile|company)" lib
```

⭐ **모범 사례가 서버에 있다** — `functions/src/index.ts:2807`

```ts
function otpLogFields(phoneHashValue: string) {
  return {phonePrefix: phoneHashValue.slice(0, 8)};
}
```

**번호도 인증번호도 안 넣고 해시 앞 8자만** 찍는다. 규약의 *"값이 있는지 없는지만
찍는다"* 를 실제로 지킨 자리다.

### 1-3. 🚨 그런데 예외 객체가 61건 그대로 나간다 — 그중 **한 자리는 실재한다**

```
${e.runtimeType} 형태 (안전)   71건
맨 $e  (toString 전체가 나감)   **61건**
```

⚠️ **61건을 전부 결함으로 세지 않는다.** 대부분은 `FirebaseException` ·
`PlatformException` 처럼 **메시지가 일반 문구**라 개인정보가 안 실린다.
**개발A 가 오늘 허수를 다섯 만든 자리**라, 하나씩 「진짜 나가는가」를 봤다.

#### 🚨 실재하는 것 — `lib/presentation/common/address_search_view.dart:166`

```dart
try {
  final data = jsonDecode(raw) as Map<String, dynamic>;   // ← raw = 주소 payload
  ...
} catch (e) {
  debugPrint('[AddressSearch] 파싱 실패, 결과 없이 닫음: $e');
}
```

**왜 실재하는가** — Dart 의 **`FormatException.toString()` 은 문제가 된 원본
문자열의 일부를 함께 낸다.** `jsonDecode` 가 던지는 것이 바로 `FormatException`
이고, 그 `source` 가 여기서는 **주소 payload**(`fullAddress` · `roadAddress` ·
`jibunAddress` · `buildingName`)다.

```
조건    주소 검색 결과 JSON 이 깨졌을 때 (WebView 가 비정상 응답을 준 경우)
결과    **주소 문자열 일부가 로그로 나간다**
성격    이용자 본인의 주소가 아니라 **명함 주인(제3자)의 주소**일 수 있다
```

⚠️ **터진 것이 아니라 「터질 수 있는 자리」다.** 평소 경로에서는 JSON 이 정상이라
안 걸린다. **그래서 자동 테스트로도 안 잡힌다.**

📌 **고치는 법은 이미 이 저장소 안에 있다** — 같은 파일의 다른 자리들과
`ocr_scanner_service` 등이 `${e.runtimeType}` 만 찍는다. **한 글자 차이다.**

#### 🟡 봐 둘 것 — `auth_repository.dart` (18건)

`이메일 가입 예외: $e` · `이메일 로그인 예외: $e` 처럼 **인증 예외**를 그대로
찍는다.

⚠️ **확인 못 했다.** `FirebaseAuthException.toString()` 이 **이메일 주소를 싣는지**는
플러그인 버전·플랫폼에 따라 다르고, **실기기 로그로 재야 안다.** 코드만 봐서는
못 가른다 — **모른다고 적는다.**

⭐ 같은 파일 `:635` 는 `${e.code}` 만 찍는다. **이미 옳은 방식이 옆줄에 있다.**

---

## 2. ② 암호화 안 되는 저장소에 원문이 들어가는가 — ✅ **위반 0건**

`prefs.setString` **22건**을 전부 봤다. 개인정보 의심 후보 넷을 열었다.

| 자리 | 무엇을 넣나 | 판정 |
|---|---|---|
| `terms_consent_service.dart:199·206` | `{uid: 동의시각 ISO8601}` | ✅ 계정 식별자 + 시각 |
| `geo_backfill_service.dart:409·591` | `{단계이름: 건수}` | ✅ 숫자만 |

**이름·전화·이메일·주소 원문은 한 건도 없다.** 규약의 *"해시나 플래그만 쓴다"* 가
지켜지고 있다.

---

## 3. ③ 방침과 코드가 어긋나는가 — 🚨 **하나. 그리고 「빠뜨림」이 아니라 「순서」다**

### 3-1. 바깥으로 나가는 곳 전수

```
앱(lib)          api.open-meteo.com · tile.openstreetmap.org · api.vworld.kr
                 business.juso.go.kr · dapi(카카오) · www.googleapis.com
서버(functions)   generativelanguage.googleapis.com · aiplatform(Vertex)
                 **kakaoapi.aligo.in** · kapi/kauth.kakao.com
                 nid/openapi.naver.com · appleid.apple.com · www.googleapis.com
```

⚠️ **`connectionsense.web.app.evil.com` 은 수신처가 아니다** — `social_oauth.dart:152`
의 **방어 주석**이다(*"`startsWith` 로 느슨하게 보면 안 된다"*). **허수를 하나
지웠다.**

### 3-2. 게시본(v2.6)의 수탁자·이전받는 자

```
OpenMeteo GmbH · Google LLC(셋) · Apple Inc./Google LLC · 카카오 주식회사 · 수사기관
```

날씨·지도·주소 변환·주소 검색·AI(Vertex)·알림은 **전부 방침이 말하고 있다.**
📌 기관명이 아니라 **기능으로** 서술한 자리가 많아 `grep` 으로는 「없다」로
보이기 쉽다 — **표를 직접 열어야 보인다.**

### 3-3. 🚨 딱 하나 — **알리고가 게시본에 없다**

```
코드   functions/src 가 **kakaoapi.aligo.in** 으로 간다
       보내는 것: **전화번호**(인증번호 발송)
게시본 v2.6 위탁 표에 **알리고 없음**  (`grep -ci "알리고|aligo"` → **0**)
v2.7 초안 ✅ 있다 — **주식회사 알리는사람들**(서비스명 「알리고」),
       **재위탁: 주식회사 카카오** 까지 적혀 있다 (`:829` `:835`)
```

⭐ **즉 방침이 빠뜨린 것이 아니라, 고친 방침이 아직 안 게시된 것이다.**

🚨 **그래서 이것은 「문서 결함」이 아니라 「배포 순서」다.**

```
지금    번호 인증이 #873(고정 IP) 때문에 막혀 있다 — **아직 아무 번호도 안 나간다**
그날    #873 이 배포되면 번호가 알리고로 나가기 시작한다
전제    **그 전에 v2.7 이 게시돼 있어야 한다**
```

⚠️ **순서가 뒤집히면 「고지 없는 위탁」이 된다** — 규약이 *"방침과 구현이 어긋나는
것 자체가 법적 리스크"* 라고 못 박은 자리이고, 이 저장소가 **BYOK 서술 불일치로
이미 한 번 겪은** 종류다.

📌 **막혀 있는 것이 오히려 안전망이 됐다.** #873 이 먼저 나갔으면 순서가 뒤집혔을
수 있다.

---

## 4. ④ 과장이 있는가 — 🚨 **같은 저장소가 자기와 모순된다**

### 4-1. ✅ 옳게 쓴 자리 셋

```
encryption_key_service.dart:21   "함께 있으므로 완전한 제로-지식/이중격리 암호화는 아니다"
data_crypto_service.dart:31      "…로부터의 완전한 제로-지식 [은 아니다]"
data_backup_service.dart:27      "이 설계는 완전한 제로-지식 암호화는 아니다"
```

**규약을 정확히 지켰다** — 키가 서버에 함께 있다는 사실을 숨기지 않는다.

### 4-2. 🚨 그런데 두 자리가 정반대를 말한다

```
card_photo_backup_service.dart:20
  "서버(회사 포함)는 사진을 **열어볼 수 없다.** 키는 계정별로 따로 있다"

contact_image_service.dart:30
  "복호화하지 않고 암호문 그대로 올리므로 **서버는 사진을 열어볼 수 없다.**"
```

**왜 틀렸나** — 올라가는 것이 암호문인 것은 맞지만, **그 키도 서버에 있다**
(`users/{uid}.encryptionKeyB64`). 바로 그 사실 때문에 위 세 자리가 *"제로-지식이
아니다"* 라고 적은 것이다.

> **한 저장소가 같은 사실을 두고 정반대로 말하고 있다.**
> 세 곳은 *"키가 서버에 있어 제로-지식이 아니다"*,
> 두 곳은 *"서버는 열어볼 수 없다"*.

⚠️ **주석이라 이용자에게 안 보인다** — 그래서 급하지는 않다. 🚨 **그런데
`card_photo_backup_service.dart:20` 은 방침 문안을 쓸 때 참고되는 자리다.**
여기서 *"회사도 못 본다"* 를 읽고 방침에 옮기면 **이용자에게 보이는 거짓**이 된다.

📌 **[추가 687]에서 겪은 것과 같은 모양이다** — 그때도 코드 주석이 *"이 기기에만
있다"* 라고 말했고, **그 문장이 화면 문구로 이어져 있었다.**

---

## 5. 🚨 이 점검이 못 본 것

```
① **실기기·서버 실물을 못 봤다**
   서버 자료가 오늘 전부 지워져 실물 조회로는 아무것도 안 나온다.
   ⚠️ 그러니 이 문서는 **「코드가 흘릴 수 있는가」**이지 **「샜는가」가 아니다.**

② **`FirebaseAuthException` 이 이메일을 싣는지 못 가렸다** (1-3 의 🟡)
   플러그인 버전·플랫폼에 따라 다르다. **실기기 로그로 재야 안다.**

③ **맨 `$e` 61건을 하나씩 다 열지 못했다**
   가장 위험해 보이는 둘(주소·인증)만 호출부까지 갔다. **나머지 59건은
   「가능성」이지 확인된 것이 아니다** — 결함 수로 세지 말 것.

④ **네이티브 로그(Android Logcat·iOS os_log)는 안 봤다**
   플러그인이 자체적으로 찍는 것은 이 grep 에 안 걸린다.

⑥ **「`try` 없이 파싱하는 자리」를 못 셌다**
   안 잡힌 예외는 Crashlytics 로 **회사 밖에** 나간다(아래 실측). 그 전수는
   별건이다 — **다음에 잴 것.**

⑤ ~~release 빌드에서 debugPrint 가 나가는지 안 쟀다~~ → **쟀다. 아래 참조**
```

### ⭐ ⑤는 그 자리에서 쟀다 — **눌러 두지 않았다**

```
grep -rn "debugPrint = " lib   →  **0건** (재정의 없음)
lib/main.dart 에 kReleaseMode 로 로그를 끄는 코드  →  **없음**
kReleaseMode 를 쓰는 파일 넷은 전부 **로그가 아니라 기능 분기**다
  (app_check_service · card_rect_detector · camera_scan · add_card_modal)
```

🚨 **Flutter 는 release 에서 `debugPrint` 를 지우지 않는다.** 눌러 두지도 않았으므로
**위 188건이 release 빌드에서도 그대로 나간다.**

⚠️ **그래서 1절의 무게가 올라간다.** `address_search_view.dart:166` 의 주소 유출은
**개발 빌드에만 있는 일이 아니다** — 테스터 기기의 로그에도 남는다.

### ⭐ 「어디로 나가는가」도 이어서 쟀다 — **debugPrint 는 기기에만 남는다**

Crashlytics 는 붙어 있다(`firebase_crashlytics: ^5.0.0`). **그런데 무엇을 받는지가
갈린다.**

```
main.dart:48   FlutterError.onError = …recordFlutterFatalError
main.dart:50   PlatformDispatcher.instance.onError = …recordError(error, stack, fatal: true)

FirebaseCrashlytics.log(...) 호출   앱 전체에서 **0건**
                                   (main.dart 밖에서 crashlytics 를 부르는 곳 없음)
```

✅ **그러므로 `debugPrint` 188건은 Crashlytics 로 안 올라간다.** 기기 로그
(logcat / os_log)에만 남는다 — **회사 밖으로는 안 나간다.**

⭐ **그래서 1절의 주소 유출은 「기기 안」에 머문다.** `address_search_view.dart:166`
은 `try/catch` 안이라 **잡힌 예외**이고, 잡힌 예외는 Crashlytics 로 안 간다.

🚨 **대신 다른 것이 나간다 — 「안 잡힌 예외」다.**

```
잡힌 예외    → debugPrint → 기기 로그만
안 잡힌 예외  → recordError(error, …) → **Crashlytics = 회사 밖**
```

⚠️ **예외 객체가 통째로 올라가므로, 메시지에 개인정보가 실린 예외가 어디선가
안 잡히면 그것은 밖으로 나간다.** 예를 들어 `jsonDecode` 를 `try` 없이 부르는
자리가 있으면 `FormatException` 이 원본을 안고 올라간다.

📌 **이 문서는 그 전수를 못 셌다** — 「`try` 없이 파싱하는 자리」를 세는 것은
별건이다. **⑥으로 남긴다.**

---

## 6. 요약

```
잰 것   e316599c · 2026-09-06 · 코드만(실물 조회 불가)

✅ 깨끗   ② 안전하지 않은 저장소 — 위반 0건
          ① 개인정보 필드 직접 로그 — 0건 (otpLogFields 는 모범)

🚨 나온 것
   1  address_search_view.dart:166   FormatException 이 **주소 원본 조각**을 로그로
                                     낸다 (JSON 이 깨질 때). 한 글자 고치면 닫힌다
   2  게시본 방침에 **알리고 없음**      v2.7 초안엔 있다 → **「배포 순서」 문제**
                                     🚨 #873 배포 **전에** v2.7 게시가 필요
   3  주석 두 자리가 *"서버는 열어볼 수 없다"*  — 같은 저장소 세 자리와 **정반대**

🟡 못 가린 것   FirebaseAuthException 이 이메일을 싣는지 (실기기 필요)
🚨 **release 에서도 debugPrint 가 그대로 나간다** — 눌러 둔 곳이 없다(실측)
             → 1절은 **개발 빌드만의 이야기가 아니다**
✅ **Crashlytics 는 `debugPrint` 를 안 받는다**(실측) — 로그는 **기기 안**에 머문다
🚨 **대신 「안 잡힌 예외」는 통째로 Crashlytics 로 간다** = 회사 밖
⭐ 다음에 잴 것  **`try` 없이 파싱하는 자리** — 거기서 난 예외는 원본을 안고 밖으로 나간다
```

# 법적 고지를 대표 도메인 아래로 — 준비 문서 (추가 651)

작성일: 2026-09-01
지시: globe2030님 — *"대표 도메인 아래 나머지 붙이는 거 아닌가"* → *"2번 준비해줘"*
상태: **준비만 한다. 실행은 globe2030님 결정.**

---

## 0. 왜 하나

지금 우리 주소가 넷으로 흩어져 있다.

```
connectionsense.co.kr             대표 — 마케팅 홈페이지        (사이트 `connectionsense`)
connectionsense.web.app           위와 같은 사이트
connection-sense.web.app          법적 고지 4종                 (사이트 `connection-sense`)
connection-sense.firebaseapp.com  인증 메일 링크                (기본값)
```

이용자가 보는 법적 고지 주소가 **대표 도메인이 아니다.** 스토어·카카오·네이버
콘솔에 넣는 주소도 그것이라, **회사 주소와 방침 주소의 도메인이 다르다.**

---

## 1. 🚨 먼저 — 건드리면 안 되는 것

`connection-sense.web.app` 은 **두 가지 서로 다른 일**에 쓰인다. 이름이 같아서
한꺼번에 바꾸기 쉬운데, **하나는 바꾸면 기능이 깨진다.**

| 자리 | 쓰임 | 바꿔도 되나 |
|---|---|---|
| `legal_document_view.dart:30` | 앱이 여는 **법적 고지 주소** | ✅ 바꾼다 |
| `address_search_view.dart:192` | 주소검색 **웹뷰의 origin** | 🚨 **절대 안 된다** |

🚨 **`address_search_view.dart` 는 법적 고지와 아무 상관이 없다.** 그 값은
주소검색 웹뷰가 어느 origin 으로 뜰지를 정하고, 그 origin 이 **행안부·카카오에
등록돼 있어야** 검색이 돌아간다(같은 파일 396줄 주석: *"등록해야 켜진다"*).

📌 이 저장소는 이미 그 자리에서 한 번 데었다 — `file://` origin 때문에
`ERR_UNKNOWN_URL_SCHEME` 이 떴고, **화면에 뜬 것은 증상이고 원인은 origin**
이었다(CLAUDE.md 2절). **문자열 일괄 치환을 하면 정확히 그 사고가 재현된다.**

> **같은 문자열이라고 같은 뜻이 아니다. 바꾸기 전에 무엇에 쓰이는지 본다.**

---

## 2. 무엇을 옮기나 — 파일은 부딪히지 않는다 (실측)

```
docs/legal/                     docs/site/
  account-deletion.html           index.html      ← 🚨 유일한 충돌
  app-permissions.html            site.css
  privacy-policy.html             fonts/…         ← 이름은 같고 내용도 같다
  terms-of-service.html           README.md
  legal.css
  index.html                    ← 🚨 유일한 충돌
  fonts/…                       ← sha256 네 개 모두 일치. 그냥 site 쪽을 쓴다
```

**슬러그 넷은 마케팅 사이트와 안 겹친다** — `/privacy-policy`,
`/terms-of-service`, `/app-permissions`, `/account-deletion`.

### `index.html` 충돌을 어떻게 하나

`docs/legal/index.html` 은 **법적 고지 목차**다. 옮기면 마케팅 홈페이지의
`index.html` 과 부딪힌다. 셋 중 하나를 고른다.

| 안 | 어떻게 | 대가 |
|---|---|---|
| **A** | 목차를 **버린다**. 홈페이지 푸터가 이미 넷을 다 링크한다 | 목차 페이지를 직접 열던 사람은 홈으로 간다 |
| B | `/legal` 로 옮긴다 | 지금 `legal` 사이트에 `/legal → /` 리다이렉트가 있어 서로 어긋난다 |
| C | 옮기지 않고 옛 사이트에 남긴다 | 원본이 둘로 갈린다 — 이 저장소가 제일 조심하는 것 |

⭐ **A 를 권한다.** 목차는 어디에서도 링크되지 않고, 홈페이지 푸터가 그 일을
이미 하고 있다.

---

## 3. 바꿔야 할 곳 — 빠짐없이 (실측)

### 저장소 안

```
lib/presentation/common/legal_document_view.dart:30   _baseUrl              ✅ 바꾼다
docs/site/index.html:227~230                          푸터 링크 4개          ✅ 바꾼다
docs/site/README.md:73                                설명                  ✅ 바꾼다
docs/admin/README.md:75,104,114                       관리자 매뉴얼 3곳      ✅ 바꾼다
lib/core/services/social_oauth.dart:47                주석 한 줄            ✅ 바꾼다
firebase.json                                         legal 타깃을 리다이렉트 전용으로

lib/presentation/common/address_search_view.dart:192,396   🚨 건드리지 않는다 (1절)
functions/src/socialAuth.test.ts:286                       🚨 건드리지 않는다 — OAuth 테스트 고정값
```

### 저장소 밖 — 🚨 **여기가 진짜 위험한 곳이다**

```
⬜ Google Play Console      개인정보처리방침 URL
⬜ App Store Connect        개인정보처리방침 URL
⬜ 카카오 개발자 콘솔        개인정보처리방침 URL
⬜ 네이버 개발자 콘솔        개인정보처리방침 URL (검수 신청서에도 들어간다)
⬜ 방침 문서 본문            자기 주소를 참조하는 곳이 있는지
```

🚨 **하나라도 빠지면 「방침을 못 보는 상태」가 된다.** 개인정보처리방침 30조 2항이
요구하는 **지속적 게재**를 못 지키게 된다.

---

## 4. 그래서 **옮기지 말고 더한 뒤 리다이렉트한다**

```
❌ 옮긴다   옛 주소가 404  →  게시된 법적 고지가 사라진다
✅ 더한다   새 주소를 만들고, 옛 주소는 301 로 새 주소를 가리킨다
```

**옛 주소가 영구히 살아 있어야 한다.** 스토어 심사·콘솔·이미 발송된 메일·
검색 결과가 그 주소를 들고 있다. 301 을 걸면 **원본은 하나**이면서 **옛 주소도
안 죽는다.**

`firebase.json` 의 `legal` 타깃은 이렇게 바뀐다.

```
public      docs/legal-redirect   (빈 디렉터리 + index.html 하나)
redirects   /**  →  https://connectionsense.co.kr/:splat   type 301
```

⚠️ 기존 리다이렉트 다섯(`/privacy` → `/privacy-policy` 등)은 **새 사이트로 옮겨
간다.** 안 옮기면 그 짧은 주소들이 죽는다.

---

## 5. 순서 — 이 순서가 아니면 방침이 잠깐 사라진다

```
1. docs/site 에 법적 고지 넷을 넣고 배포           새 주소가 살아난다
2. 새 주소 넷이 200 인지 확인                      ← 여기서 멈출 수 있다
3. 앱·문서의 주소를 새 주소로 고치고 빌드           앱이 새 주소를 연다
4. 저장소 밖 넷(스토어·카카오·네이버)을 고친다       ← 사람이 하는 일
5. legal 타깃을 리다이렉트 전용으로 바꾸고 배포      옛 주소가 새 주소로 넘어간다
```

🚨 **5 를 1보다 먼저 하면 그 사이 방침이 404 다.** 법적 고지가 잠깐이라도
사라지면 안 된다.

📌 **2에서 멈출 수 있는 것이 이 순서의 값이다** — 새 주소가 안 뜨면 아직
아무것도 안 바꾼 상태다.

---

## 6. 함께 처리할 것 — `authorizedDomains`

인증 메일 링크를 대표 도메인으로 옮기려면 **먼저 승인된 도메인에 넣어야 한다.**
2026-09-01 실측 기준 목록에 대표 도메인이 **없다.**

```
있음   localhost · connection-sense.firebaseapp.com
       connection-sense.web.app · connection-sense-admin.web.app
없음   🚨 connectionsense.co.kr · connectionsense.web.app
```

⭐ **핸들러 자체는 이미 살아 있다** — 세 도메인 모두 같은 441바이트 Firebase
인증 핸들러를 준다(실측). **새로 만들 것은 없고 콘솔에 등록만 하면 된다.**

```
1. Authentication → 설정 → 승인된 도메인 → connectionsense.co.kr 추가
2. 템플릿 → 작업 URL → https://connectionsense.co.kr/__/auth/action
```

⚠️ **이미 발송된 메일 속 링크는 옛 도메인을 가리킨다.** `connection-sense.firebaseapp.com`
을 승인 목록에서 **빼면 안 된다** — 유효기간 안의 링크가 죽는다.

---

## 7. 하지 않기로 한 것 — OAuth 리다이렉트

```
connectionsense.web.app/oauth/kakao   → 404      그런데 로그인은 된다
```

📌 **앱이 그 주소로 이동하는 순간을 가로채기 때문에 페이지가 없어도 된다.**
이용자가 볼 일이 없는 문자열이다.

⚠️ 반면 바꾸면 **카카오·네이버 콘솔에 재등록**해야 하고, 2026-09-01 에 그
자리에서 `KOE006` 으로 한 번 막혔다. **눈에 안 보이는 것을 위해 그 위험을
다시 질 이유가 없다.**

---

## 8. 결정이 필요한 것

```
⬜ ①  실행할 것인가                      globe2030님
⬜ ②  index.html 충돌 — A안(목차 버림)   globe2030님, 2절
⬜ ③  언제 할 것인가                      9/2 테스터 배포 앞뒤
```

📌 **③에 걸리는 것이 있다.** 3단계가 **앱 빌드**를 요구하므로, 9/2 배포에 태우면
한 번에 끝나고 놓치면 **다음 빌드까지 기다려야** 한다. 반대로 지금 넣으면
**9/2 앞에서 만질 것이 하나 늘어난다.**

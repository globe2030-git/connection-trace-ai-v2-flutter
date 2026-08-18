# B안(패키지명까지 개명) 실행 비용·위험 — 실측 (2026-08-16)

> **이 문서는 착수 계획이 아니다.** "B안을 하면 무슨 일이 벌어지는가"를 재서
> 적은 것이다. 개명 여부·이름·A안/B안은 **사용자가 결정한다.**
> 이름 후보 조사는 [`../marketing/app-name-research-2026-08-16.md`](../marketing/app-name-research-2026-08-16.md).

**표기 규칙**: **실측** = 코드·설정 파일을 직접 열어 확인한 것.
**확인 필요** = 재보지 못해 단정할 수 없는 것. 추정은 쓰지 않았다.

---

## 먼저 — 전제 셋이 실물과 달랐다

이 조사에서 가장 중요한 부분이다. **B안이 비싸다는 근거로 쓰이던 것 셋이
사실과 달랐다.**

### ① "패키지명을 바꾸면 Firebase 프로젝트를 새로 만들어야 한다" → **아니다**

**실측** — 지금 이 앱은 **Android와 iOS의 식별자가 이미 서로 다르다.**

| | 값 |
|---|---|
| Android 패키지명 | `com.connectiontrace.connection_trace_ai_flutter` ← 옛 이름 "Connection Trace" 잔재 |
| iOS 번들 ID | `com.creamhouse.connectionsense` |

**그런데 둘 다 같은 Firebase 프로젝트 `connection-sense`에 등록돼 있다.**
`firebase.json`에 android·ios `appId`가 각각 잡혀 있다.

```
android  1:79345379389:android:24e13cbaadaf82ac182254
ios      1:79345379389:ios:534c871d9bfd7d78182254
```

**즉 "한 프로젝트 = 한 패키지명"이 아니라는 것이 이 저장소에서 이미
증명돼 있다.** 새 패키지명의 앱을 **추가 등록**하면 되고, Firestore 데이터·
사용자 계정·Storage는 **그대로 쓴다.** 프로젝트를 갈아엎을 일이 아니다.

⚠️ **확인 필요**: 이 맥에 Firebase CLI가 없다(`firebase not found`). 위는
저장소의 설정 파일로 확인한 것이고, **콘솔에서 앱 목록을 직접 봐야 확정**된다.

### ② "테스터의 명함이 날아간다" → **대부분 돌아온다**

**실측** — `lib/data/services/data_backup_service.dart`

명함·프로필은 **로컬(`shared_preferences`)이 원본이고 Firestore에 암호화
백업**된다(AES-256-GCM). **새 기기에서 로그인했는데 로컬이 비어 있으면
서버에서 통째로 내려받는다.**

패키지명을 바꾼 앱은 OS가 보기에 **다른 앱**이라 데이터 폴더가 새것이다 =
로컬이 비어 있다 = **로그인하면 복원 경로가 그대로 작동한다.**

⚠️ **단, 사진 중 일부는 못 돌아온다.** 사진 백업(`CardPhotoBackupService`,
Cloud Storage)은 **2026-08-16에 들어갔다.** `card_photo_backup_state.dart`가
스스로 적어 둔 대로, 서버에 없는 사진이 셋 있다.

| 왜 서버에 없나 |
|---|
| 백업 기능을 켜기 전에 등록했다 |
| 한도(무료 300·충전 2,000)를 넘었다 |
| 업로드가 조용히 실패했다(네트워크 끊김 등) |

**이 사진들은 기존 앱에만 있고, 새 앱으로 넘어가지 않는다.**

### ③ "Android가 debug 키로 서명돼 있다(P1-19)" → **이미 해결돼 있다**

**실측**

```
android/key.properties                        존재 (권한 600)
/Users/globe2030/keys/connectionsense-upload.jks   실재 (저장소 밖 — 원칙대로)
저장소 안 *.jks / *.keystore                  없음
```

`android/app/build.gradle.kts`는 **key.properties가 있으면 업로드 키로
서명**하고, 없으면 debug로 폴백한다.

⚠️ **정정 (PM 실측, 추가 255).** 처음 이 문서에 *"이 맥에서 빌드하면 정식
서명된다"*고 적었는데 **틀렸다.** 정확히는 **"본체 워크트리에서 빌드하면"**
이다. `key.properties`는 `.gitignore` 대상이라 **git이 워크트리 사이로
옮겨 주지 않는다.**

| 워크트리 | key.properties |
|---|---|
| `…-flutter` (본체) | ✅ 있음 → 업로드 키 서명 |
| `…-docs` · `…-feature` · `sharp-chebyshev-…` | ⚠️ **없음 → debug 폴백** |

**본 것은 맞았는데 본 범위를 결론의 범위로 넓힌 것**이 오류였다. 본체
하나만 열어 보고 "이 맥"이라고 썼다.

⚠️ **폴백이 조용하다.** key.properties가 없는 워크트리·CI·다른 맥에서
릴리스를 빌드하면 **경고 없이 debug 키로 서명된 결과물이 나온다.** 그것을
스토어에 올리면 이후 업데이트를 영영 못 올린다. **개명과 무관하게** 빌드가
실패하도록 막는 편이 안전하다 — 코드 변경이므로 별건이고 **착수는 사용자
승인 사항**이다.

**→ 그러므로 "개명하는 김에 정식 키도 도입하자"는 이유는 성립하지 않는다.
키는 이미 있다.** CLAUDE.md의 P1-19 서술은 낡았다(추가 255에서 정정됨).

---

## 진짜 비용은 여기 있다

전제 셋이 무너진 대신, **재보니 실제로 비싼 것이 따로 있었다.**

### ⚠️ 호스팅 도메인은 법적 문서만 쓰는 게 아니다 — 기능이 걸려 있다

**실측**

| 코드 | 쓰는 곳 | 무엇이 걸리나 |
|---|---|---|
| `lib/presentation/common/legal_document_view.dart:30` | `https://connection-sense.web.app` | 방침·약관 화면 |
| `lib/presentation/common/address_search_view.dart:92` | `https://connection-sense.web.app/` | **주소 검색 기능** |

**주소 검색이 이 도메인을 쓴다.** 예전에 `file://` origin 때문에 주소 검색이
안 됐던 그 문제를 호스팅 페이지로 푼 흔적이다. **도메인을 바꾸면 법적 고지
재게시가 아니라 기능이 깨진다.**

`.firebaserc`에 호스팅 대상이 둘이다 — `legal`(`connection-sense`) ·
`admin`(`connection-sense-admin`). `firebase.json`의 admin CSP에도
`asia-northeast3-connection-sense.cloudfunctions.net`,
`connection-sense.firebaseapp.com`이 **하드코딩**돼 있다.

📌 **다행히 이것은 B안의 필수 항목이 아니다.** 패키지명을 바꾸면서 **호스팅
도메인은 그대로 둘 수 있다.** 도메인까지 바꾸는 것은 **C안**으로 따로 봐야
하고, 그 값이 B안보다 크다.

### 로그인·App Check를 새 식별자로 다시 등록해야 한다

**실측**

- `google-services.json`에 **인증서 지문 1개, OAuth 클라이언트 4개**. Google
  로그인은 **패키지명 + SHA 지문 조합**으로 등록된다 → 새 패키지명으로
  **재등록 필요**
- Apple 로그인(`signInWithApple`)은 **번들 ID 기반** → App ID·Service ID·
  키 재설정 필요
- **App Check가 켜져 있고 서버가 `enforceAppCheck: true`로 토큰을 요구한다**
  (`app_check_service.dart`, 2026-08-08부터). **새 앱을 App Check에 등록하지
  않으면 서버 호출이 전부 거부된다** — 앱은 켜지는데 아무것도 안 되는 상태가
  된다. 개명 작업에서 가장 빠뜨리기 쉬운 항목이다

---

## 되돌릴 수 있나 / 시한이 언제인가

**사용자가 볼 표는 이것이다.**

| 항목 | 스토어 등록 **전** | 스토어 등록 **후** |
|---|---|---|
| **표시 이름**(아이콘 아래 이름) | 가능 | ✅ **가능** — 언제든 |
| 스토어 제목·설명 | 가능 | ✅ 가능 |
| 문서·마케팅 문구 68개 파일 | 가능 | ✅ 가능 |
| 상표 출원 | 가능 | ✅ 가능(빠를수록 안전) |
| **Android 패키지명** | 가능 | ❌ **영원히 불가** |
| **iOS 번들 ID** | 가능 | ❌ **영원히 불가** |
| Firebase 프로젝트 ID | 가능 | ❌ 불가(데이터 이관 필요) |
| Storage 버킷 이름 | 가능 | ❌ 불가 |
| 호스팅 도메인 `connection-sense.web.app` | 가능 | ⚠️ 가능하나 **구 URL 리다이렉트 유지 필요** |

**빨간 칸은 넷뿐이고, 그중 이용자 눈에 보이는 것은 없다.**

---

## 그래서 얼마인가

### A안 (표시 이름만)

**작업**: `Info.plist` 1줄 + `AndroidManifest.xml` 1줄 + 문서 68개 파일의
문자열 + 법적 문서 재게시(`firebase deploy --only hosting`, **사용자 승인
사항**).

**위험**: 낮음. 되돌릴 수 있다. 서버·로그인·데이터에 손대지 않는다.

**시한**: 없음. 출시 후에도 가능하다.

### B안 (패키지명까지)

**A안에 더해**:

1. Android `applicationId` · iOS `PRODUCT_BUNDLE_IDENTIFIER` 변경
2. Firebase 콘솔에 **새 앱 2개 추가 등록** → `google-services.json` ·
   `GoogleService-Info.plist` · `firebase_options.dart` 재생성
3. **Google 로그인 OAuth 재등록**(SHA 지문 포함)
4. **Apple 로그인 App ID·Service ID·키 재설정**
5. **App Check에 새 앱 등록** ← 빠뜨리면 서버 호출 전부 거부
6. **테스터 재설치 안내** — 업데이트가 아니라 새 설치다. 기존 앱은 기기에
   남는다. 로그인하면 명함은 복원되나 **백업 안 된 사진은 유실**된다

**위험**: 중간. 되돌릴 수는 있으나(패키지명을 되돌리면 됨) **테스터가 한 번
겪는 혼란은 되돌릴 수 없다.**

**시한**: ⚠️ **스토어 등록 전까지.** 이후에는 불가능하다.

### C안 (호스팅 도메인까지) — 권하지 않음

주소 검색 기능과 admin CSP가 도메인에 묶여 있다. **B안에 포함시키지 말 것.**

---

## 판단 재료

**B안을 할 이유**는 하나다 — Android 패키지명이 **옛 이름
`connectiontrace`**를 그대로 달고 있다. 개발자 눈에만 보이지만, 앞으로
계속 남는다.

**B안을 안 할 이유**는 셋이다.

1. 이용자에게 보이지 않는다
2. 테스터가 재설치해야 하고, **백업 안 된 사진이 유실된다**
3. 로그인·App Check 재등록에서 하나만 빠뜨려도 **앱이 조용히 죽는다**

📌 **다만 "Firebase 프로젝트를 새로 만들어야 한다"와 "명함이 날아간다"는
근거는 이 조사로 사라졌다.** B안이 처음 알려진 것만큼 비싸지는 않다.
남은 실질 비용은 **테스터 재설치 1회 + 재등록 5종 + 미백업 사진 유실**이다.

---

## 다음에 재야 할 것 (내가 못 잰 것)

⚠️ **아래는 확인하지 못했다. 결정 전에 사용자 또는 콘솔 접근이 되는 세션이
확인해야 한다.**

| 무엇 | 어디서 | 왜 필요한가 |
|---|---|---|
| Firebase에 등록된 앱 목록 | Firebase 콘솔 | ①의 확정 근거 |
| 테스터 수와 설치 기기 수 | App Distribution | 재설치 안내 대상 규모 |
| 백업 안 된 사진이 실제로 몇 장인지 | Firestore/Storage 실물 | 유실 규모 |
| Play Console 등록 여부 | Play Console | 시한이 이미 지났는지 |
| Apple App ID 등록 상태 | Apple Developer | 5번 항목 작업량 |

이 맥에는 **Firebase CLI가 없다**(`firebase not found`). 설치는 환경을
바꾸는 일이라 하지 않았다.

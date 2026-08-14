# 커넥션센스 관리자 콘솔

공지사항 · 1:1 문의 · 법적 문서를 관리자가 코드 배포 없이 직접 수정할 수 있는
경량 정적 웹페이지. 빌드 도구 없이 순수 HTML/JS + Firebase JS SDK(CDN)로
동작한다.

## 접속

**https://connection-sense-admin.web.app**

**로그인: `connectionsense@creamhouse.net` 또는 `globe@creamhouse.net`으로
"Google 계정 로그인" 버튼을 쓴다.** 둘 다 인증 완료 상태다(2026-08-08 확인).

> **이메일/비밀번호 입력란이 아니라 "Google 계정 로그인" 버튼이다.** 두 계정
> 모두 제공사가 `google.com`이라 비밀번호 로그인은 동작하지 않는다.
>
> (경위) `connectionsense@creamhouse.net`은 원래 Workspace **그룹메일**이라
> 게시 권한 설정 탓에 Firebase 인증 메일을 받지 못해 `emailVerified=false`로
> 막혀 있었다(2026-08-06). 2026-08-08에 **사용자 메일함으로 다시 만들어**
> 해소됐다. 개인 메일(`globe@creamhouse.net`)은 그때 우회용으로 넣은 것이라,
> 정리하고 싶으면 `firestore.rules`의 허용목록에서 빼도 된다.

## 관리자 판별 방식

`firestore.rules`의 `isAdmin()`이 **이메일 화이트리스트 + 이메일 인증 여부**로
판별한다.

```
request.auth.token.email_verified == true &&
request.auth.token.email in ['connectionsense@creamhouse.net', 'globe@creamhouse.net']
```

이메일 인증을 요구하는 이유: 가입 시점에는 이메일 소유 확인이 없어서 이메일
자체가 사실상 비밀번호 역할을 한다. 인증 메일을 실제로 받을 수 있는 사람만
관리자가 되도록 막는 마지막 방어선이다.

> **낡은 정보 주의**: 예전 설계는 `admins/{uid}` 화이트리스트 문서였다.
> 2026-08-06에 위 방식으로 바뀌었고, **`admins` 컬렉션은 비어 있으며 더 이상
> 쓰지 않는다.**

### ⚠️ "Rules만 고치면 된다"는 더 이상 사실이 아니다 (2026-08-14)

`getUserUsage`·`grantSupportCredits`(2026-08-14 개명 — 舊 grantBonusCredits) 같은 관리자 전용 Cloud Functions는
Firestore Rules를 거치지 않고 Admin SDK로 직접 접근하기 때문에, **Rules의
`isAdmin()` 배열만 바꾸고 Functions 쪽을 빠뜨리면 해제된 관리자가 Callable을
계속 호출할 수 있다**(ADMIN-VULN-001). 그래서 관리자 이메일은 이제 두 곳에
따로 있고 **반드시 함께** 고쳐야 한다.

- `firestore.rules`의 `isAdmin()` 배열
- `functions/src/adminEmails.ts`의 `ADMIN_EMAILS`

**관리자를 추가/제거하는 절차:**

1. 위 두 곳을 **둘 다** 고친다.
2. `python3 tool/check_admin_sync.py`로 두 목록이 정확히 같은지 확인한다
   (다르면 비영 종료코드로 실패하고 어느 쪽에만 있는지 알려준다).
3. `firebase deploy --only firestore:rules,functions`로 **동시에** 배포한다
   (한쪽만 배포하면 그 사이 두 원본이 어긋난 상태로 운영된다).
4. 즉시 완전 차단이 필요하면(계정 탈취 의심 등) 위 절차만으로는 부족하다 —
   Firebase 콘솔에서 해당 계정의 refresh token도 함께 폐기(revoke)해서
   이미 발급된 로그인 세션 자체를 끊어야 한다.

⚠️ **이 방식은 임시 조치다.** 진짜 단일 원본(`config/admins` Firestore
문서 + Rules `get()`으로 그 문서를 조회)으로 전환하는 것이 후속 과제로
남아 있다 — 이번 세션은 운영 Firestore에 그 문서를 실제로 만들어 검증할
수 없어 "공유 상수 + 동기화 검사"로 드리프트만 막는 수준에서 멈췄다
(ADMIN-VULN-001, `docs/planning/admin-security-vulnerability-assessment-2026-08-13.md`).

## 배포

Hosting 타겟 두 개로 분리돼 있다(`.firebaserc` 참고).

| 타겟 | 사이트 | 내용 |
|---|---|---|
| `legal` | https://connection-sense.web.app | `docs/legal` — 법적 고지 4종 |
| `admin` | https://connection-sense-admin.web.app | `docs/admin` — 이 콘솔 |

```bash
firebase deploy --only hosting:admin    # 이 콘솔만
firebase deploy --only hosting:legal    # 법적 고지만
```

Firebase 웹 앱은 이미 등록돼 있고(`1:79345379389:web:483f3096c5d7d484182254`)
`admin.js`의 `firebaseConfig`도 실제 값으로 채워져 있다. **추가 설정 없이
그대로 배포된다.**

## 데이터 구조

- `notices/{id}`: `{ title, bodyMarkdown, pinned, published, createdAt, updatedAt }`
  — 앱은 `published == true`인 것만 읽는다.
- `inquiries/{id}`: `{ userId, userEmail, subject, message, status, createdAt }`
  + 서브컬렉션 `replies/{id}`: `{ from: 'admin'|'user', message, createdAt }`
- `legalDocs/{slug}`: `{ title, bodyHtml, updatedAt }` — slug는
  `privacy-policy` / `terms-of-service` / `app-permissions` /
  `account-deletion`. **이 컬렉션은 실제로 쓰이지 않는다** — 아래 항목 참고.

## ⚠️ 법적 문서 편집기는 비활성화돼 있다 (2026-08-14)

**"법적 문서" 탭에서 문서를 열어도 저장/삭제 버튼이 없다.** 읽기 전용으로
Firestore `legalDocs/{slug}`에 남아 있는 옛 내용을 참고용으로만 보여준다.

과거에는 이 콘솔에서 `legalDocs/{slug}`를 고치면 "앱 재배포 없이 바로
반영"된다고 안내했는데, **이건 사실이 아니었다.** Flutter 앱은 Firestore
`legalDocs`를 전혀 읽지 않고 항상 `https://connection-sense.web.app/{slug}`의
정적 Hosting HTML을 연다(`lib/presentation/common/legal_document_view.dart`).
그래서 관리자가 콘솔에서 문서를 바꿨다고 믿어도 사용자와 스토어 심사는 옛
HTML을 계속 보는 사고가 가능했다(`docs/planning/admin-code-privacy-audit-2026-08-13.md`
P0-1). 진짜 게시 경로를 다시 만들기 전까지는 편집 자체를 막아 둔다.

**법적 문서를 실제로 바꾸려면:**

1. 저장소의 `docs/legal/{slug}.html`을 고친다.
2. `firebase deploy --only hosting:legal`로 배포한다.
3. `https://connection-sense.web.app/{slug}`를 열어 반영을 확인한다.

콘솔의 `legalDocs/{slug}` Firestore 문서를 고치거나 지워도 이 경로에는
아무 영향이 없다.

## 관리자 콘솔 CSP 근거 (2026-08-14, ADMIN-VULN-011)

- script-src: admin.js가 import하는 유일한 외부 origin은 www.gstatic.com(Firebase SDK 모듈). script-src는 잠겨 있다(unsafe-inline 없음).
- style-src: cdn.jsdelivr.net(Pretendard CSS) + 'unsafe-inline' — admin.js가 innerHTML로 인라인 style 속성을 61곳 쓰고 index.html에도 인라인 <style> 블록이 있어 불가피. 61곳을 CSS 클래스로 리팩터하면 제거 가능(후속 과제).
- connect-src: https://*.googleapis.com(Firestore/Auth REST — 정확한 서브도메인이 SDK 내부 구현이라 와일드카드로 안전 마진 확보) + asia-northeast3-connection-sense.cloudfunctions.net(Callable Functions, 리전 확인됨).
- frame-src: connection-sense.firebaseapp.com(Firebase Auth 내부 relay iframe) + accounts.google.com(Google 로그인).
- ⚠️ 잔여 리스크: 이 CSP는 코드 조사 기반 최선 추정이다. 배포 후 실브라우저로 로그인·Firestore 조회·Functions 호출·Google 로그인이 CSP 위반 없이 도는지 반드시 확인할 것(devtools 콘솔의 CSP violation 로그로 확인). 문제 생기면 connect-src/frame-src를 좁히지 말고 필요한 origin만 추가.

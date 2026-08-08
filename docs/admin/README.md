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
판별한다. 관리자를 추가/제거하려면 그 배열에 이메일만 넣고 규칙을 배포하면
된다 — Firebase 콘솔 작업이 필요 없다.

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
  `account-deletion`. **네 문서 모두 실제 문안이 들어 있다**(2026-08-06 기준).

## ⚠️ 법적 문서를 고칠 때 — 두 곳이 따로 논다

같은 문서가 **두 군데**에 있고 자동으로 동기화되지 않는다.

| 어디 | 무엇이 보나 |
|---|---|
| `legalDocs/{slug}` (Firestore) | 이 콘솔에서 편집하는 대상. 앱 안에서 보이는 문서 |
| `docs/legal/*.html` (저장소) | Hosting으로 서비스되는 공개 웹페이지. **스토어 콘솔에 등록하는 URL이 이쪽** |

**콘솔에서만 고치면 공개 웹페이지는 옛 문안 그대로 남는다.** 개인정보처리방침
같이 스토어 심사와 직결되는 문서는 반드시 양쪽을 함께 고칠 것 — 방침과 실제
고지가 어긋나는 것 자체가 법적 리스크다(BYOK 서술 불일치로 이미 한 번 겪었다,
`CLAUDE.md` 4번 항목 참고).

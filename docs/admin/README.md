# 커넥션센스 관리자 콘솔

공지사항 · 1:1 문의 · 법적 문서를 관리자가 코드 배포 없이 직접 수정할 수 있는
경량 정적 웹페이지. 빌드 도구 없이 순수 HTML/JS + Firebase JS SDK(CDN)로
동작한다.

## 배포 전 반드시 해야 할 일 (한 번만)

1. **Firebase 웹 앱 등록** — 이 프로젝트(`connection-sense`)에는 아직 웹 앱이
   등록된 적이 없다(Android/iOS만 있음). Firebase 콘솔 > 프로젝트 설정 >
   "앱 추가" > 웹(</>) 아이콘으로 새 웹 앱을 등록하면 `firebaseConfig` 값이
   발급된다. 그 값을 `admin.js` 상단의 `firebaseConfig` 객체에 채워 넣는다
   (`apiKey`, `appId`는 지금 `"REPLACE_ME"`로 비워둔 상태).

2. **관리자 계정 생성** — Firebase 콘솔 > Authentication > Users에서
   이메일/비밀번호 계정을 하나 만든다(관리자 본인 계정).

3. **관리자 권한 부여** — Firestore에 `admins` 컬렉션을 만들고, 2번에서 만든
   계정의 uid를 문서 ID로 하는 빈 문서를 하나 추가한다(필드는 없어도 됨).
   이 컬렉션은 `firestore.rules`에서 클라이언트가 직접 읽거나 쓰지 못하게
   막아뒀기 때문에 Firebase 콘솔에서 수동으로만 추가할 수 있다 — 그래야
   공격자가 자기 uid로 문서를 만들어 스스로 관리자가 되는 걸 막을 수 있다.

4. **배포** — 이 폴더를 Firebase Hosting에 올린다. 지금 `docs/legal`이
   이미 하나의 Hosting 사이트로 배포되어 있는데, `docs/admin`을 같은
   사이트의 다른 경로(`/admin`)로 둘지, 별도 Hosting 사이트로 분리할지는
   운영 판단이 필요해 `firebase.json`은 아직 건드리지 않았다. 결정되면
   `firebase.json`의 `hosting` 설정에 반영하고 `firebase deploy`로 배포한다.

## 데이터 구조

- `notices/{id}`: `{ title, bodyMarkdown, pinned, published, createdAt, updatedAt }`
  — 앱은 `published == true`인 것만 읽는다.
- `inquiries/{id}`: `{ userId, userEmail, subject, message, status, createdAt }`
  + 서브컬렉션 `replies/{id}`: `{ from: 'admin'|'user', message, createdAt }`
- `legalDocs/{slug}`: `{ title, bodyHtml, updatedAt }` — slug는
  `privacy-policy` / `terms-of-service` / `app-permissions` /
  `account-deletion`. **주의**: 이 문서는 아직 실제 정책 문안을 옮기지
  않은 빈 상태다 — `docs/legal/*.html`의 개인정보처리방침은 오늘
  (2026-08-05) 다른 작업에서 좌표 저장 정책을 실시간으로 수정 중이라,
  그 작업이 커밋된 뒤에 최종 문안을 옮기는 게 안전하다.

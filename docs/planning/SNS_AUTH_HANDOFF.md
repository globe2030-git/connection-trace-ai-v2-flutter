# SNS 본인인증(카카오/네이버/구글/애플) & authProfile DB 및 관리자 인수인계서

**작성일**: 2026년 8월 13일  
**작성 목적**: 기존 구글/애플 로그인 구조에서 카카오/네이버 SNS 인증 추가, `authProfile` DB 본인인증 원천 데이터 보관 및 관리자 사용자 검증 기능 개발을 위한 차기 Claude/개발자 인수인계 문서.

---

## 1. 지금까지 완료된 작업 현황 Summary

1. **1:1 문의 사용자 성명(`userName`) 연동**
   - `InquiryModel`, `inquiry_repository.dart`, `inquiry_view.dart` 수정 완료.
   - 문의 제출 시 `userId`, `userEmail`뿐만 아니라 `userName` (사용자 성명)이 함께 Firestore `inquiries` 컬렉션에 백업 및 저장됨.

2. **관리자 1:1 문의 실시간 검색 및 응대 UI 구현 완료 (`admin_inquiry_view.dart`)**
   - `InquiryRepository`에 `watchAllInquiriesForAdmin()`, `addAdminReply()`, `fetchUserAiUsage()` 추가.
   - `AdminInquiryManagementView`: 이름 및 이메일 실시간 검색창, 상태 필터(전체/답변대기/답변완료) 지원.
   - 고객 응대 모달(`_AdminInquiryReplySheet`): 고객 프로필(이름, 이메일, UID, 접수일시), **고객 AI 크레딧 & 충전/이용 현황 카드**, 실시간 대화 이력 타임라인, 관리자 답변 폼 통합 완료.

---

## 2. SNS 본인인증(Kakao/Naver) 추가 및 `authProfile` DB 아키텍처 사양

### 2-1. Firestore DB `users/{uid}` 데이터 구조 사양

로그인 성공 시점에 `users/{uid}` 문서에 **`authProfile` (SNS 본인인증 원본 데이터)**을 저장하여 사용자가 앱 내에서 프로필 이름을 수동 변경하더라도 원본 인증 정보를 보존합니다.

```json
// Firestore: users/{uid} 문서
{
  "authProfile": {
    "provider": "kakao.com",          // google.com | apple.com | kakao.com | naver.com
    "displayName": "홍길동",          // SNS 최초 수신 실명/닉네임
    "email": "hong@kakao.com",       // SNS 수신 이메일
    "photoUrl": "http://...",        // 프로필 사진 URL
    "mobile": "010-1234-5678",       // 전화번호 (네이버 등 제공 시)
    "firstSignedInAt": "2026-08-13T18:50:00Z"
  },
  "profile": {
    "name": "길동이",                 // 사용자가 앱 내에서 수동 편집한 표시용 이름
    "company": "(주)크림",
    "phone": "010-1234-5678"
  },
  "encryptionKeyB64": "...",
  "updatedAt": "ServerTimestamp"
}
```

---

### 2-2. `firestore.rules` 보안 규칙 보완 사항

`clientWritableUserFields()` 함수에 `authProfile`을 포함하되, 원본 데이터 위변조 방지를 위해 **최초 1회 생성 시만 허용 (`!exists(resource)`)** 조치 권장:

```cel
function isInitialAuthProfileWrite() {
  return !('authProfile' in resource.data) && ('authProfile' in request.resource.data);
}
```

---

### 2-3. 프로필 사진(아바타) 내 명함 자동 매핑 메커니즘 (`login_view.dart`)

- **구글/카카오/네이버 프로필 사진 자동 적용**:
  - `login_view.dart`의 `_prefillAvatarFromGoogle(auth.photoUrl)`이 이미 구현되어 있음.
  - 로그인 성공 시 SNS에서 프로필 사진 URL(`photoUrl`)을 내려받아, 사용자의 내 명함 프로필 사진(`profile.avatarPath`)이 비어있는 경우 자동으로 다운로드하여 `my_profile_avatar.jpg`에 보관하고 프로필 사진으로 자동 설정됨.
  - 카카오/네이버 연동 시 `_prefillAvatarFromSns(auth.photoUrl)`로 공통화하여 호출하면 동일하게 자동 적용됨.

---

## 3. 카카오 vs 네이버 연동 비교 및 사전 준비 사항

### 🥇 1) 카카오 (Kakao) — 추천 (속도 빠름 ⭐⭐⭐⭐⭐)
- **추천 패키지**: `kakao_flutter_sdk_user` (공식 패키지, iOS/Android/Web 지원 완벽)
- **개발 사전 준비 (developers.kakao.com)**:
  1. 카카오 디벨로퍼스 앱 생성 후 **네이티브 앱 키** 및 **JavaScript 키** 발급.
  2. **Android Key Hash (키 해시)** 등록 (디버그/릴리즈).
  3. **iOS URL Scheme** 추가: `Info.plist`에 `kakao{NATIVE_APP_KEY}` 등록.
  4. **동의 항목 설정**: 닉네임, 프로필 사진, 카카오계정 이메일(`account_email`) 설정.
- **Firebase Auth 연동**:
  - 카카오 토큰 수신 후 Firebase Cloud Functions (`createCustomToken`)를 이용해 Firebase Auth 로그인 또는 Firebase OAuthProvider 연동.

### 🥈 2) 네이버 (Naver) — (속도 보통 ⭐⭐⭐⭐)
- **추천 패키지**: `flutter_naver_login` (커뮤니티 패키지)
- **개발 사전 준비 (developers.naver.com)**:
  1. 네이버 개발자 센터 앱 등록 (서비스 URL, CallBack URL).
  2. **Client ID** & **Client Secret** 발급.
  3. iOS Bundle ID & Scheme 이름 (영문 소문자/숫자) 설정.
  4. Android Package Name 설정 및 `strings.xml` 설정.
  5. **제공 항목 설정**: 회원이름, 이메일, 별명, 프로필 사진, 휴대전화번호.

---

### 📋 3-3. 네이버 로그인 수신 가능 전체 항목 명세

| 수신 항목 (API 필드) | 설명 | 내 명함 자동 매핑 및 활용 |
| :--- | :--- | :--- |
| `id` | 네이버 회원 고유 식별자 | 계정 고유 UID 식별 |
| `name` | 네이버 회원 실명 (예: "홍길동") | 명함 이름 & `authProfile.displayName` |
| `nickname` | 별명/닉네임 | 닉네임 기본값 |
| `email` | 계정 이메일 (예: "user@naver.com") | 명함 이메일 & `authProfile.email` |
| `profile_image` | 프로필 사진 URL | 내 명함 프로필 아바타 이미지 자동다운로드 |
| `mobile` | 휴대전화번호 (예: "010-1234-5678") | 내 명함 연락처 자동 채움 |
| `mobile_e164` | E.164 국제 표준 전화번호 | 국가 코드 포함 번호 |
| `gender` | 성별 (`M`/`F`/`U`) | 성별 정보 |
| `birthday` / `birthyear`| 생일(`MM-DD`) 및 출생년도(`YYYY`) | 생년월일 / 연령 정보 |

---

## 4. 차기 Claude/개발자 작업 체크리스트 (Next Action Items)

- [ ] `kakao_flutter_sdk_user` 및 `flutter_naver_login` 패키지 `pubspec.yaml` 추가
- [ ] `SnsAuthProvider` Enum에 `kakao`, `naver` 추가
- [ ] `AuthRepository` 내 `signInWithKakao()`, `signInWithNaver()` 구현
- [ ] `login_view.dart` 내 `_prefillAvatarFromSns()` 카카오/네이버 프로필 사진 자동다운로드 확장
- [ ] 로그인 성공 시 `users/{uid}.authProfile` (실명, 이메일, 프로필사진, 전화번호) 기록 로직 추가
- [ ] `AdminInquiryManagementView`에서 `authProfile`과 `inquiry.userName` 대조 표시 UI 연결

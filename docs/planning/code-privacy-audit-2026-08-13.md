# 코드 품질·개인정보·계정 격리 점검 보고서

- 점검일: 2026-08-13 (Asia/Seoul)
- 기준 브랜치/커밋: `main` / `50fcc25b62800db6b8565a0009a2f2f15b7c83b2`
- 점검 대상: Flutter 앱, Firebase Functions, Firestore 규칙, 개인정보처리방침, 테스트, 빈 데이터 UI
- 점검 방식: 소스·설정·테스트 정적 검토 및 독립 교차 검증
- 실행하지 않은 것: Flutter/Functions/Firestore 실테스트, 실기기 검증, 운영 Firestore 데이터 조회
- 결론: **출시 전 수정 필요**. 특히 계정 전환과 인증 상태 분리는 다른 계정의 개인정보가 섞이는 실제 경로이므로 최우선으로 막아야 한다.

## 1. 핵심 판정

| 영역 | 판정 | 요약 |
|---|---|---|
| 코드 품질 | 수정 필요 | 실패와 빈 결과를 구분하지 않는 API, 비동기 저장 실패 삼킴, 비원자적 계정 삭제가 있다. |
| 로그 개인정보 | 수정 필요 | 주소가 포함될 수 있는 딥링크 URL을 그대로 출력하고, 연락처 ID·예외 원문도 여러 경로에서 출력한다. |
| 로컬/Firestore 암호화 | 부분 충족 | 명함·프로필 JSON과 최종 명함 원본은 AES-256-GCM이지만, 프로필/연락처 아바타와 스캔 임시 JPG는 평문이다. 키 동기화 실패 시 키 분기 가능성도 있다. |
| 계정 변경·로그아웃 | **중대 결함** | 이전 계정 메모리를 유지한 채 새 UID를 먼저 적용해 이전 계정 명함을 새 계정 Firestore에 재백업할 수 있다. |
| 탈퇴·재설치 | 수정 필요 | 탈퇴 후 문의·OCR 통계·삭제표식이 남고, 재설치 정리 실패를 성공으로 확정한다. |
| 외부 API/방침 일치 | 수정 필요 | AI 주요 전송 항목은 대체로 일치하지만, 동의 전 날씨 조회와 로그인 시 자동 주소 지오코딩, AI 재시도 동의 재사용이 방침과 다르다. |
| 테스트 결함 재현력 | 부족 | 일부 순수 로직 테스트는 좋지만, 계정 A→B·탈퇴 전체 삭제·동의 전 네트워크를 재현하지 않으며 한 테스트는 결함 동작을 성공 기준으로 고정한다. |
| 빈 데이터 UI | 현재 정상 | 운영 가짜 연락처 주입은 없고 주요 화면에 빈 상태가 있다. 다만 이를 고정하는 위젯 테스트가 부족하다. |

## 2. 반드시 먼저 고칠 결함

### P0-1. 계정 A의 명함이 계정 B 화면과 Firestore에 결합될 수 있음

**근거**

- `lib/presentation/common/auth_gate.dart:42-60`은 계정 전환 판단보다 먼저 `setCurrentUid(uid)`를 호출한다.
- `lib/data/repositories/contacts_repository.dart:83-103`은 새 UID만 설정하고 기존 `_contacts`를 유지한 채 `_stripGeoFromServerBackupsOnce(uid)`를 시작한다.
- `lib/data/repositories/contacts_repository.dart:357-373`은 현재 메모리의 명함 전체를 전달받은 UID 경로로 재백업한다.
- `lib/presentation/common/auth_gate.dart:83-95`의 `유지하고 계속 쓰기`는 이전 계정 데이터를 지우지 않은 채 마지막 UID를 새 계정으로 확정한다.
- `lib/data/repositories/contacts_repository.dart:499-547`과 `lib/data/repositories/my_profile_repository.dart:164-170`은 이후 변경을 현재 UID로 백업한다.
- Firestore 규칙은 B로 정상 인증된 앱이 `users/B/...`에 쓰는 요청을 허용하므로 이 의미적 오염을 막지 못한다.

**재현 시나리오**

1. A 로그인 후 이름·전화·주소·메모가 있는 명함을 저장한다.
2. 로그아웃한다. 현재 로그아웃은 저장소 메모리를 비우지 않는다.
3. 같은 설치본에서 B로 로그인한다.
4. 계정 전환 대화상자가 뜨기 전 또는 `유지하고 계속 쓰기` 선택 후 `users/B/contacts`를 확인한다.
5. A의 명함이 B 화면에 보이거나 B 키로 암호화되어 B 경로에 올라갈 수 있다.

**수정 원칙**

- 로컬 키·SharedPreferences 키·이미지 디렉터리·메모리 상태를 UID별로 분리한다.
- 새 UID를 리포지토리에 적용하기 전에 기존 UID 상태를 격리한다.
- `setCurrentUid`에서 백업·마이그레이션·지오코딩을 자동 시작하지 않는다. 소유권 확정 후 명시적으로 실행한다.
- `유지하고 계속 쓰기`는 제거한다. 꼭 필요하면 새 계정에 자동 동기화되지 않는 명시적 내보내기/가져오기 절차로 만든다.

**완료 기준**

- A→로그아웃→B, A→B 직접 전환, 앱 재시작 후 B 로그인 모두에서 A의 명함·프로필·사진이 B에게 보이지 않는다.
- B 경로에 A 데이터가 한 건도 쓰이지 않는다.
- 이 조건을 Firestore Emulator 또는 주입형 가짜 백업 서비스로 자동 테스트한다.

### P0-2. Google 로그인 성공과 Firebase 인증 실패가 분리되어 이전 Firebase UID를 사용할 수 있음

**근거**

- `lib/data/repositories/auth_repository.dart:92-123`은 Firebase 자격 증명 로그인이 실패해도 Google 로컬 세션을 로그인 성공으로 확정한다.
- `lib/data/repositories/auth_repository.dart:254-278`은 Firebase 로그아웃 실패도 삼킨 뒤 로컬 상태를 로그아웃으로 바꾼다.
- `lib/presentation/common/auth_gate.dart:137-148`은 로컬 `isSignedIn`만으로 본 화면을 열고, 별도로 남아 있는 `FirebaseAuth.currentUser.uid`를 저장소 소유자로 넘긴다.

**영향**

- Google 사용자 B가 로그인했지만 Firebase에는 A 세션이 남은 분리 상태에서 A UID의 키·백업을 읽거나 수정할 수 있다.
- Firebase UID가 없으면 로그인 상태에서 명함·프로필을 SharedPreferences 평문으로 저장하는 경로도 열린다 (`contacts_repository.dart:457-465`, `my_profile_repository.dart:145-151`).

**수정 원칙/완료 기준**

- 운영 로그인은 Firebase 인증 성공을 필수 조건으로 한다. 실패하면 이전 Firebase/로컬 세션을 정리하고 로그인 화면에 머문다.
- Google/Apple 주체, Firebase UID, 리포지토리 UID, 암호화 키 UID가 일치하는지 앱 진입 전에 단일 검증한다.
- Firebase 로그인·로그아웃 실패를 강제로 주입한 테스트에서 다른 UID의 데이터 화면/백업 접근이 불가능해야 한다.

### P1-1. Firestore 키 조회 실패가 새 키 발급으로 이어져 키 분기와 복구 불능을 만들 수 있음

**근거**

- `lib/core/services/encryption_key_service.dart:107-125`은 원격 문서 조회 실패를 기록한 뒤 계속 진행한다.
- `lib/core/services/encryption_key_service.dart:127-151`은 새 키를 로컬에 저장하고 서버 저장 실패를 삼킨 뒤 메모리에 캐시한다.
- 기존 서버 키 변경은 `firestore.rules`의 키 불변 규칙에 막히므로, 새 로컬 키와 기존 서버 키가 자동으로 다시 합쳐지지 않는다.

**수정/테스트**

- `키 없음`과 `조회 실패`를 다른 결과 타입으로 만든다. 조회 실패에서는 새 키를 만들거나 암호문을 쓰지 않는다.
- 최초 키 생성은 트랜잭션/create-if-absent로 원자화하고 충돌 시 서버 키를 다시 읽는다.
- 두 기기 동시 최초 로그인, 원격 조회 실패, 서버 키 쓰기 실패를 주입해 모든 기기가 동일 키에 합의하는지 검사한다.

### P1-2. 계정 삭제가 재인증보다 먼저 서버 데이터와 복구 키를 삭제함

**근거**

- `lib/presentation/features/settings/views/settings_view.dart:954-983`은 `deleteAllUserData`를 먼저 실행한 뒤 Firebase 계정을 삭제한다.
- 최근 로그인 요건은 계정 삭제 시점에야 확인된다. `settings_view.dart:987-1017`에서 사용자가 재인증을 취소하면 계정은 살아 있지만 서버 명함·프로필·키는 이미 삭제된 상태다.

**수정/테스트**

- 파괴적 삭제 전에 재인증을 완료한다.
- 더 안전한 구조는 인증된 서버 측 삭제 작업/계정 삭제 트리거가 모든 데이터를 멱등적으로 정리하는 방식이다.
- 재인증 필요·취소·네트워크 실패 각 경우에 `계정이 남으면 데이터도 남고`, `삭제 완료면 모든 데이터가 사라지는` 원자성 테스트를 추가한다.

### P1-3. 탈퇴 후 문의 원문·OCR 통계·삭제표식이 서버에 남음

**근거**

- `lib/data/services/data_backup_service.dart:246-258`은 `users/{uid}/contacts`와 부모 문서만 삭제한다. Firestore 부모 삭제는 하위 컬렉션을 연쇄 삭제하지 않는다.
- `users/{uid}/deletedContacts/*`는 `data_backup_service.dart:118-125`에서 생성되지만 탈퇴 시 삭제되지 않는다.
- `lib/core/services/ocr_stats_service.dart:112-129`의 `ocrStats/{uid}`도 삭제 경로가 없다.
- `lib/data/repositories/inquiry_repository.dart:32-67`과 `lib/data/models/inquiry_model.dart:13-54`는 UID·이메일·제목·문의 원문·답변을 `inquiries`에 저장하지만 탈퇴 정리에서 제외된다.
- `functions/src/index.ts:735-770`의 삭제 트리거는 Apple 토큰과 AI 감사 로그만 정리한다.
- 개인정보처리방침 `docs/legal/privacy-policy.html:170,187-200,433-440`은 탈퇴 시 관련 정보를 즉시 파기한다고 적고, 문의 수집 항목·보유 기간·관리자 열람 범위는 명확히 적지 않는다.

**수정/테스트**

- 서버 측 멱등 삭제 작업에서 모든 UID 하위 컬렉션과 전역 UID 연결 컬렉션을 재귀 삭제한다.
- 문의는 법적 보존 필요 여부를 결정하고, 보존한다면 항목·목적·기간·근거·관리자 열람을 방침에 고지하며 계정 식별정보를 분리/가명화한다.
- 삭제 완료 후 `users`, `contacts`, `deletedContacts`, `ocrStats`, `inquiries/replies`, `aiAuditLogs`, `appleAuth`에 UID 또는 이메일 연결 자료가 0건인지 자동 검사한다.
- `tool/verify_server_privacy.py`도 현재 users/contacts만 보므로 위 컬렉션을 포함하도록 확장한다.

### P1-4. 재설치 정리 실패를 성공으로 기록해 다시 시도하지 않음

**근거**

- `lib/core/services/fresh_install_service.dart:71-89`은 보안 저장소 삭제나 Firebase 로그아웃 실패를 모두 삼킨 뒤 `install_marker_v1=true`를 기록한다.
- 다음 시작부터는 `fresh_install_service.dart:55`에서 즉시 반환해 정리를 다시 시도하지 않는다.
- `test/fresh_install_test.dart:129-153`은 이 결함 동작을 오히려 성공 기준으로 고정한다.

**수정/테스트**

- 인증 세션과 키 정리가 모두 성공한 뒤에만 완료 표식을 기록한다.
- 실패하면 비민감한 `정리 필요` 상태를 남기고 다음 실행에 재시도하며, 완료 전에는 계정 데이터 화면 진입을 막는다.
- 기존 두 테스트는 `실패 시 완료 표식 없음 + 다음 시작 재시도 + 계정 화면 차단`을 검증하도록 바꾼다.

## 3. 개인정보 저장·로그·외부 전송 결함

### P1-5. 평문 이미지와 임시 스캔 파일이 남음

**확인된 경로**

- `camera_scan_modal_view.dart:365-420`: 명함 크롭 결과를 `Directory.systemTemp/card_scan_*.jpg`에 평문 저장한다.
- `contact_image_service.dart:86-105`: 최종 `.enc`는 암호화하지만 원본 JPG를 삭제하지 않는다.
- `add_card_modal_view.dart:618-632`: 연락처 아바타를 `contact_avatar_*.jpg`로 평문 복사한다.
- `my_profile_edit_modal_view.dart:209-223`, `login_view.dart:63-84`: 내 사진을 계정 공용 `my_profile_avatar.jpg`로 평문 저장한다.
- `contacts_repository.dart:525-540`: 연락처 삭제 시 `cardImagePath`만 지우고 연락처 아바타 파일은 지우지 않는다.
- `settings_view.dart:844-857`: 탈퇴 정리도 명함 암호문과 내 프로필 JPG만 대상으로 하며 연락처 아바타/임시 스캔 파일은 빠진다.
- 방침 `privacy-policy.html:447`은 명함·프로필 데이터가 기기/서버 모두 AES-256-GCM이라고 표현해 실제와 다르다.

**수정/완료 기준**

- 모든 사용자·연락처 이미지를 UID별 디렉터리의 인증 암호문으로 저장하고 모델에는 계정 상대 식별자만 둔다.
- 가능하면 평문 스캔을 디스크에 쓰지 않고 메모리에서 OCR·암호화한다. 불가하면 성공·실패·취소·화면 종료 모두의 `finally`에서 삭제한다.
- 연락처 삭제·계정 전환·탈퇴 후 관련 UID의 평문 JPG가 0개인지 검사한다.
- Android 백업 제외 규칙도 추가한다.

### P1-6. 주소·위치가 사용자의 전송 동의 전에 외부 사업자에게 전달됨

두 경로가 있다.

1. `contacts_repository.dart:83-103,110-125`는 로그인/복원 때 `backfillMissingGeo()`를 자동 시작한다. `geo_backfill_service.dart:129-147`과 `address_geocoding_service.dart:64-67`은 저장된 제3자 주소를 Apple/Google 지오코더로 보낸다.
2. `ai_data_review_sheet.dart:74-109`는 동의 시트를 여는 즉시 Open-Meteo에 좌표를 보낸다. 동의 체크는 나중에 `ai_data_review_sheet.dart:126-141`에서 AI 호출만 막는다.

방침 `privacy-policy.html:82`는 외부 전송 항목을 먼저 보여주고 동의한 경우에만 동작한다고 적고, `privacy-policy.html:319`는 주소 변환·날씨 조회 기능을 사용하지 않으면 국외 이전을 거부할 수 있다고 설명한다. 현재 자동 로그인 지오코딩과 동의 전 날씨 조회는 이 설명과 맞지 않는다.

**수정/완료 기준**

- 주소 변환과 날씨 조회의 전송 대상·목적·항목을 표시한 뒤 별도 동의를 얻는다.
- 동의 전 화면 열기, 로그인, 서버 복원만으로 네트워크 요청이 발생하지 않아야 한다.
- HTTP/지오코더 가짜 구현으로 `동의 전 0회`, `동의 후 선택된 항목만 1회`를 테스트한다.

### P1-7. 오프라인 연락처 삭제가 재시도되지 않아 서버 개인정보가 부활할 수 있음

- `contacts_repository.dart:525-540`은 서버 삭제와 tombstone 작성을 기다리지 않는다.
- `data_backup_service.dart:105-125`은 실패를 삼키고 재시도 큐를 남기지 않는다.
- 다음 동기화에서 서버에만 남은 연락처와 tombstone 없음 조합은 `mergeSync`에 의해 다시 살아난다.

로컬 암호화 저장소에 pending tombstone을 먼저 영속화하고, 서버 삭제+tombstone을 batch/transaction으로 완료할 때까지 재시도해야 한다. 오프라인 삭제→앱 재시작→온라인 동기화에서도 삭제한 연락처가 다시 나타나지 않는 테스트가 필요하다.

### P1-8. 진단 로그에 주소 URL·연락처 식별자·예외 원문이 남음

- `lib/presentation/common/address_search_view.dart:137-151`은 `kakaomap://search?q=<주소>` 형태가 될 수 있는 `request.url` 전체를 `debugPrint`한다.
- `data_backup_service.dart:62,109,124,189,204`, `geo_backfill_service.dart:146`, `encryption_key_service.dart:80,104,118,123,135,147` 등은 연락처/문서 ID, 전체 UID, 예외 문자열을 출력한다.
- `functions/src/index.ts:254-270`은 외부 API 오류 본문을 최대 500자 또는 전체로 기록한다. 현재 소스만으로 프롬프트 반사 여부는 입증되지 않았지만 외부 응답 본문을 안전하다고 가정하면 안 된다.

**수정/완료 기준**

- 중앙 비식별 로거를 만들고 URL은 고정 이벤트 코드와 scheme만, 예외는 허용된 오류 분류/runtimeType만 기록한다.
- 이름·전화·이메일·주소·쿼리·path·UID 전체·연락처 ID·외부 응답 본문을 기록하지 않는다.
- 민감 필드가 로그 호출 인자에 들어가는지 정적 회귀 테스트를 추가한다.

### P2-1. AI 재시도가 개인정보처리방침의 요청별 동의와 다름

- `briefing_overlay_view.dart:52-57,101-128,581-584`는 최초 선택을 `_consentedSelection`에 보관해 재시도 때 확인 시트를 생략한다.
- 앱 문구 `ai_data_review_sheet.dart:419-420`은 화면을 여는 동안 재시도까지 동의가 유지된다고 하지만, 방침 `privacy-policy.html:384-385`는 동의가 요청 1건에만 적용된다고 적는다.

요청마다 다시 확인하거나, 법률 검토 후 세션 동의를 채택한다면 UI와 방침을 같은 범위·기간·철회 방법으로 고쳐야 한다.

### P2-2. 서버 입력 크기·스키마 제한이 없어 비용·안정성 결함을 만들 수 있음

- `functions/src/index.ts:536-561`은 두 필수 문자열 존재 여부만 확인하고 문자열 길이, 배열 개수, 각 항목 크기·타입을 제한하지 않는다.
- 클라이언트의 글자 수 제한은 변조 클라이언트가 우회할 수 있다.

Callable 경계에서 허용 필드, 타입, 문자열 byte/문자 수, 배열 개수, 총 프롬프트 크기를 검증하고 한도 차감·Gemini 호출 전에 `invalid-argument`로 거절해야 한다. 경계값·초과값 테스트를 Functions CI에 넣는다.

## 4. 테스트 품질 판정

### 잘 된 부분

- `test/data_encryption_test.dart`: 정상 복호화, 잘못된 키, 위변조, 평문 마이그레이션을 확인한다.
- `test/contacts_repository_wiring_test.dart`: LWW 병합과 tombstone 순수 로직을 검증한다.
- `test/location_access_flow_test.dart`: 두 번째 호출에도 동의 UI가 중복되지 않는 실제 불변조건을 확인한다.
- `test/fresh_install_test.dart`: 최초 설치/업데이트 구분 등 분기 자체는 폭넓게 다룬다.

### 현재 테스트가 놓치거나 잘못 고정한 부분

| 결함 | 현재 상태 | 반드시 추가할 회귀 테스트 |
|---|---|---|
| 계정 A→B 오염 | `last_signed_in_uid`와 전환 대화상자 전체 흐름 테스트 없음 | B 로그인 전/후 A 데이터 화면·로컬·Firestore 0건 |
| Firebase/Google 분리 인증 | Firebase 실패를 주입한 진입 테스트 없음 | Firebase 실패 시 로그인 실패 및 stale UID 제거 |
| 탈퇴 전체 삭제 | 검증 도구가 users/contacts만 확인 | 모든 UID 연결 컬렉션 0건 |
| 재설치 정리 실패 | 실패해도 marker=true를 성공으로 기대 | marker 미설정, 재시도, 화면 차단 |
| 동의 전 외부 전송 | 실제 HTTP/지오코더 호출 횟수 미검증 | 동의 전 0회, 동의 후 1회 |
| 오프라인 삭제 | fire-and-forget 실패/재시작 테스트 없음 | 온라인 복귀 후 부활하지 않음 |
| 로그 비식별화 | 자동 검사 없음 | 민감 샘플이 로그 sink에 도달하지 않음 |
| 빈 데이터 UI | 주요 화면 위젯 테스트 없음 | 빈 저장소에서 가짜 이름/카드 없음, 정확한 CTA 표시 |

### CI 누락

`.github/workflows/ci.yml:24-54`는 Flutter analyze/test만 실행한다. 아래를 별도 job으로 추가해야 한다.

- `functions`: `npm test` 또는 최소 `npm run build && npm test`
- Firestore Emulator 기반 보안 규칙 테스트
- 서버 개인정보 삭제 검증 테스트
- 로그 비식별화/개인정보처리방침-코드 상수 정합성 검사
- 현재 방침은 AI 일 10회(`privacy-policy.html:394`), 앱/Functions는 20회(`ai_briefing_service.dart:78`, `functions/src/index.ts:65`)이므로 문서-상수 검사로 드리프트를 막는다.

## 5. 빈 데이터 UI와 가짜 자료 점검

정적 검토 기준으로 운영 화면에 가짜 연락처를 주입하는 코드는 찾지 못했다.

- `ContactsRepository`는 빈 목록으로 시작하며 과거 하드코딩 연락처 3명은 제거되어 있다 (`contacts_repository.dart:15-20`).
- 내 프로필 기본값은 실제 입력 전 빈 값이며, SNS 사진을 제외한 이름·직함을 꾸며내지 않는다.
- 지갑 화면은 연락처 없음과 검색 결과 없음을 구분하고 첫 명함 등록 CTA를 보여준다.
- 레이더 화면은 위치 미설정, 검색 결과 없음, 주변 인맥 없음, 좌표 준비 중을 구분한다.
- 공지·문의·OCR 통계·알림 화면도 빈 상태 문구를 사용한다.
- `홍길동` 같은 폼 예시는 placeholder일 뿐 저장된 운영 자료로 표시되지 않는다.

**남은 위험**: 이 상태를 고정하는 위젯 테스트가 부족하다. 빈 저장소를 주입한 테스트에서 알려진 가짜 이름·카드·통계가 보이지 않고, 각 화면의 실제 빈 상태 문구/CTA만 보이는지 검증해야 한다.

## 6. 외부 서비스와 개인정보처리방침 대조표

| 외부 서비스/경로 | 실제 전송 | 방침 대조 | 조치 |
|---|---|---|---|
| Firebase Auth/Firestore | 계정 식별정보, 암호화된 명함·프로필, 키 | 항목 고지는 대체로 일치 | 인증 분리 상태와 탈퇴 잔존 자료 수정 |
| Google Gemini | 확인 화면의 명함/프로필 요약, 선택 소통기록, 날씨, 추가 메모 | 전송 항목은 대체로 일치 | 요청별 동의 범위와 서버 입력 제한 수정 |
| Open-Meteo | 명함 좌표, 접속 IP | 고지됨 | 동의 시트 열기만 해도 전송되는 순서 수정 |
| Apple/Google 지오코더 | 명함 주소 문자열 | 고지됨 | 로그인·복원 자동 전송을 동의 뒤로 이동 |
| Kakao 우편번호 | 주소 검색어 | 고지됨 | 주소 포함 딥링크 로그 제거 |
| VWorld/OpenStreetMap | 지도 타일 요청·접속 IP | 대체로 일치 | 현재 별도 결함 없음 |
| Crashlytics | 미처리 예외·스택 | 고지됨, 명시적 PII custom key는 없음 | 전체 예외 문자열 로깅 원칙은 중앙 통제 |
| Gmail 코드 | UI 진입점이 없어 현재 비활성 | 현재 미제공 설명과 일치 | 배포 코드에서 제거하거나 기능 플래그/테스트로 비활성 보장 |
| 1:1 문의 Firestore | UID, 이메일, 제목, 원문, 답변 | 수집 항목·보유기간·관리자 열람 고지가 부족 | 방침 보완 및 탈퇴 삭제/가명화 |

## 7. 추가로 확인된 범위 인접 보안 문제

이번 요청의 중심은 개인정보와 계정 격리지만 다음도 출시 전에 처리할 가치가 크다.

- `firebase.json:79-88`은 `docs/admin` 전체를 정적 공개하며 `docs/admin/reports/pnl-analysis-freemium.html` 내부 경영 보고서가 직접 URL로 열릴 수 있다. 공개 호스팅 밖으로 이동하고 서버 인증을 적용한다.
- `android/app/build.gradle.kts:60-68`은 릴리스 키가 없으면 debug 서명으로 폴백한다. release 빌드는 키가 없으면 실패하도록 바꾼다.
- `firestore.rules:111-116`은 문의 소유자가 `from: admin` 답변을 직접 만들 수 있게 필드를 검증하지 않는다. 사용자 작성은 `from == user`, 허용 필드, 길이, 타임스탬프를 강제한다.

## 8. 권장 수정 순서

1. P0-1 계정 UID 경계와 계정별 로컬 저장 구조를 먼저 고친다.
2. P0-2 인증 주체를 Firebase UID 하나로 통합하고 실패 시 fail-closed 한다.
3. 키 생성/동기화와 계정 삭제 순서를 원자적 서버 흐름으로 재설계한다.
4. 탈퇴 전체 삭제 목록과 문의 보유 정책을 확정한다.
5. 이미지·임시 파일 암호화/삭제와 재설치 재시도를 구현한다.
6. 외부 지오코딩·날씨·AI 재시도 동의를 실제 전송 시점과 맞춘다.
7. 오프라인 삭제 큐, 로그 비식별화, 서버 입력 검증을 추가한다.
8. 결함을 먼저 실패시키는 회귀 테스트를 작성한 뒤 수정하고, CI에 Functions/Rules/privacy 검사를 연결한다.
9. 빈 데이터 위젯 테스트와 문서-상수 정합성 검사를 추가한다.

## 9. 원 개발 AI 작업 규칙

- 이 문서를 수정 명세로 사용하되, 한 번에 전부 고치지 말고 위 순서대로 작은 브랜치/작업 단위로 나눈다.
- 각 항목은 **재현 테스트가 먼저 실패하는지 확인한 뒤** 구현하고, 통과만을 위한 mock/지연시간 의존 테스트를 만들지 않는다.
- 사용자 승인 없이 개인정보처리방침 문구만 코드에 맞춰 느슨하게 바꾸지 않는다. 실제 전송을 동의 뒤로 옮기는 방안을 우선한다.
- 운영 자료에 가짜 연락처·가짜 통계·가짜 알림을 넣지 않는다.
- 이름·전화·이메일·주소·전체 UID·연락처 ID·URL query·외부 오류 본문을 로그에 남기지 않는다.
- 수정 후 `HANDOFF.md`와 backlog에 결정, 남은 위험, 실제 실행한 테스트를 기록한다.
- 테스트 실행 전 저장소 `AGENTS.md`가 요구하는 테스트 범위 선택을 사용자에게 제시한다.

## 10. 검토 한계

- 이번 검토에서는 저장소 규칙에 따라 테스트 실행 전 사용자 선택을 받지 않았으므로 테스트를 실제 실행하지 않았다.
- 운영 Firestore/Cloud Logging/Crashlytics/기기 파일시스템의 현재 잔존 자료는 조회하지 않았다.
- 외부 서비스가 오류 응답에 요청 원문을 반사하는지는 소스만으로 입증하지 않았으므로, 외부 오류 본문 로깅은 예방 조치로 분류했다.
- 개인정보처리방침 변경은 법률 자문을 대신하지 않는다. 특히 문의 보유와 국외 이전 동의 방식은 법률 검토가 필요하다.

# 보안 점검 보고서 — 2026-08-10

**범위**: 개발 코드(Flutter 클라이언트 + Cloud Functions 서버) 및 비즈니스 로직.
**방법**: 저장소 실물 코드·설정 정적 검토. 실기기 동적 점검(런타임 파일/키체인
확인)은 별도로 표기했다 — 코드만으로 판정 불가한 항목이 있다.
**기준**: 이 앱은 **이용자 본인이 아닌 제3자(명함 주인)의 개인정보**를 저장하는
앱이라, 일반 앱보다 데이터 잔존·유출에 엄격한 기준을 적용한다.

> ⚠️ 이 문서는 **개발 관점의 자체 점검**이다. 정식 출시 전 외부 보안 검토
> (특히 개인정보 처리)를 대체하지 않는다. Google Play / App Store 심사와도
> 별개다.

---

## 0. 요약

전반적으로 **서버 측 권한 경계가 잘 잡혀 있다.** Firestore 규칙이 필드 단위로
좁혀져 있고(P0-8), 민감 토큰(Apple refresh, Gemini 키)이 클라이언트에서 완전히
분리돼 있으며, 로그에 제3자 개인정보를 남기지 않는 원칙이 지켜진다.

**남은 위험은 클라이언트 측 데이터 잔존과 테스트용 임시 완화에 집중돼 있다.**
등급별 정리:

| 등급 | 건수 | 요지 |
|---|---|---|
| 🔴 출시 전 필수 | 3 | App Check 임시 해제, 회원탈퇴 로컬 잔존(수정됨·미검증), 게스트 평문 저장 |
| 🟠 권장 | 4 | Secure Storage 옵션, Android 백업 플래그, 관리자 이메일=비밀번호 구조, 입력 길이 상한 |
| 🟢 확인됨(양호) | 6 | 아래 참조 |
| 📱 플랫폼별 | — | 4·5절 |

---

## 1. 🔴 출시 전 반드시 처리

### 1-1. App Check 강제가 꺼져 있음 (서버, 공통)

`functions/src/index.ts`:

```
enforceAppCheck: false,   // generateBriefing
```

직원 테스트를 위해 의도적으로 끈 상태다(테스터 허용목록으로 대체). 대신 함수
본문에서 **유효 App Check 토큰 OR 허용목록 이메일**을 수동 검사한다 — 즉 지금도
아무나 호출할 수 있는 것은 아니다.

- **위험**: 허용목록에 오른 이메일이 유출되면, 그 계정으로 로그인한 누구든
  회사 명의 유료 Gemini 키로 AI를 호출할 수 있다. 하루 한도(20, 테스트값)가
  유일한 방어선.
- **조치**: 테스트 종료 후 `enforceAppCheck: true` 복원 + `config/testers`
  비우기(HANDOFF **P0-9**). **⚠️ 2026-08-18 갱신 — 원래 여기 있던 세 번째
  조치(`DAILY_LIMIT` 10 복원, P0-11)는 빠졌다.** 충전형 확정으로 한도 제도
  자체가 없어지기 때문이다(P1-5로 흡수). **대신 이 위험의 방어선이 하나
  줄어든다** — 지갑이 켜지기 전까지는 남은 두 조치가 더 중요해졌다.
- 이미 코드 주석·HANDOFF에 되돌리기 항목으로 등록돼 있음. **잊으면 출시 후
  비용/남용 위험.**

### 1-2. 회원탈퇴 후 기기 데이터 잔존 (클라이언트, 공통) — *수정됨, 미검증*

2026-08-10 점검에서 발견해 같은 날 수정(`fix/account-deletion-local-cleanup`).
탈퇴 시 **명함 이미지(`contact_card_*.enc`)·프로필 사진(평문 JPG)·기기 암호화
키(`enc_key_v1_<uid>`)** 세 가지가 기기에 남았다.

- **왜 중대한가**: 남는 것이 **제3자(명함 주인)의 개인정보**이고, 이미지와
  기기 키가 함께 남으면 복호화 가능한 상태다. iOS Keychain은 앱 삭제 후에도
  남는다.
- **상태**: 서버 삭제는 원래부터 완전했다. 로컬 정리 코드를 추가했고 두 삭제
  경로(정상/다기기 이미 삭제됨) 모두 연결했다.
- ⬜ **미검증**: `adb run-as`(Android) / 탈퇴→재가입(iOS) 실기기 확인 필요.
  파일·Keychain은 코드 리뷰로 판정 불가.

### 1-3. 로그인 전(게스트) 데이터는 평문 저장 (클라이언트, 공통)

`contacts_repository.dart`: 로그인 전에는 암호화 키를 만들 수 없어 명함이
**평문 JSON**으로 기기에 저장된다.

- **완화**: 이 앱은 `AuthGate`로 로그인을 강제하므로 정상 흐름에선 게스트
  상태로 명함을 저장할 일이 거의 없다. 로그인 시 평문분을 암호화로 마이그레이션.
- **잔여 위험**: 마이그레이션 전에 기기를 탈취당하면 그 짧은 창의 평문이 노출.
  debug 빌드의 "로그인 건너뛰기"로 게스트 진입이 가능하나 **release엔 없음**
  (`kDebugMode` 가드 확인).
- **조치**: 출시 빌드에서 게스트 저장 경로가 실제로 도달 불가능한지 재확인.
  가능하면 게스트 명함 저장 자체를 막는 편이 깔끔하다.

---

## 2. 🟠 권장 (출시 후라도)

### 2-1. FlutterSecureStorage 기본 옵션 사용 (클라이언트)

`encryption_key_service.dart`가 `const FlutterSecureStorage()`를 옵션 없이 쓴다.
암호화 키를 여기 보관하므로 **플랫폼별 강화 옵션을 명시**하는 것을 권한다.

- **Android**: `AndroidOptions(encryptedSharedPreferences: true)` — 구형 기기에서
  keystore 폴백 품질을 올린다.
- **iOS**: `IOSOptions(accessibility: first_unlock_this_device)` — 잠금 해제 후
  접근으로 제한 + iCloud 키체인 동기화 차단(다른 기기로 키가 새지 않게).
- 현재도 OS 보안 저장소를 쓰므로 치명적이진 않으나, 키의 중요도상 명시 권장.

### 2-2. Android `allowBackup` 미지정 (Android)

`AndroidManifest.xml`에 `android:allowBackup`/`fullBackupContent`가 없어 **기본값
`true`**. adb 백업이나 자동 클라우드 백업으로 앱 데이터(암호화된 명함 + 게스트
평문분)가 빠져나갈 수 있다.

- **조치**: `android:allowBackup="false"` 또는 백업 규칙으로 SharedPreferences·
  secure 파일 제외. 제3자 정보를 다루는 앱이라 `false`를 권한다.

### 2-3. 관리자 이메일이 사실상 비밀번호 (서버)

`firestore.rules`/`ADMIN_EMAILS`가 **이메일 화이트리스트 + email_verified**로
관리자를 판정한다. 즉 그 이메일로 회원가입해 인증 메일만 받으면 관리자가 된다.

- **완화**: `email_verified` 요구가 방어선(메일 수신자만 가능). 코드 주석에도
  의도가 명시돼 있음.
- **잔여 위험**: 그 메일 계정이 탈취되면 관리자 권한을 얻는다. 관리자 기능이
  사용량 조회·공지·문의 관리로 제한돼 있어 피해 범위는 한정적(명함·키는 조회
  불가 — `getUserUsage`가 사용량만 반환).
- **조치**: 관리 계정에 **2단계 인증** 적용을 운영 정책으로. 그룹메일 임시
  허용(`globe@`)은 문제 해결 후 제거.

### 2-4. 서버 입력 길이 상한 부재 (서버)

`generateBriefing`이 `contactSummary`·`communicationLogs` 등을 받아 프롬프트로
조립하는데, **필드별 문자열 길이 상한이 서버에 없다.** 앱에는 있으나(2000/300자)
App Check가 꺼진 지금은 앱을 거치지 않은 호출이 가능하다.

- **위험**: 초장문 입력으로 토큰 비용을 부풀리는 남용. `maxOutputTokens`는
  출력만 제한하고 **입력 토큰은 무제한**.
- **조치**: 서버에서 각 필드 `.slice(상한)` + 소통 기록 개수 상한. App Check
  복원 시 위험은 줄지만, 허용목록 계정도 있으니 서버 상한이 근본 방어.

---

## 3. 🟢 확인됨 (양호)

- **Firestore 규칙 필드 단위 제어**: `users/{uid}` 쓰기를
  `encryptionKeyB64·profile·updatedAt`로 좁힘. `aiUsage`(한도 카운터) 클라이언트
  쓰기 차단 — 한도 무한 초기화 구멍을 막음(P0-8). catch-all 기본 거부.
- **암호화 키 불변 규칙**: 한 번 발급된 `encryptionKeyB64` 변경 차단 — 키 교체로
  서버 백업 전체가 열람 불가가 되는 사고 예방.
- **민감 토큰 완전 분리**: Apple refresh token(`appleAuth/{uid}`)과 감사 로그
  (`aiAuditLogs`)는 **클라이언트 읽기·쓰기 모두 `false`**, 서버 Admin SDK만 접근.
- **비밀값 관리**: Gemini 키·Apple .p8을 `defineSecret`(Secret Manager)로 보관.
  코드·저장소에 원문 없음. 저장소의 `AIza...` 키는 Firebase **클라이언트 config**
  로, 노출돼도 무해한 값(규칙이 실제 방어).
- **로그 위생**: `debugPrint`/`logger`가 이름·전화·이메일·주소를 찍지 않음.
  값 존재 여부/타입만 기록. 서버는 uid·토큰 원문을 Cloud Logging에 안 남김.
- **데이터 최소화**: 통화기록·SMS·전화상태·마이크·저장소 권한을 매니페스트
  병합에서 제거(`tools:node="remove"`). 좌표·명함 이미지는 서버 백업 제외.
  평문 통신(`http://`) 없음. AI 전송은 요청마다 명시 동의.

---

## 4. 📱 Android 세부

| 항목 | 상태 | 비고 |
|---|---|---|
| 권한 최소화 | ✅ 양호 | 통화·SMS·마이크·저장소 명시 제거. INTERNET·위치·카메라만 |
| `<queries>` 스코프 | ✅ 양호 | kakaotalk·tel만 선언(과다 조회 없음) |
| 서명 | ⚠️ 조건부 | `key.properties` 있으면 업로드 키, 없으면 **debug 키 폴백**. CI/배포 환경에 key.properties 누락 시 debug 서명 APK가 나갈 수 있음 — `tool/build_app.sh`가 아닌 경로 주의 |
| `allowBackup` | 🟠 미지정(기본 true) | 2-2 참조 |
| Proguard/R8 | ✅ 적용 | release에 `proguard-android-optimize` + 규칙. 코드 난독화 있음 |
| cleartext | ✅ 차단 | `usesCleartextTraffic` 미설정(기본 false, API28+) + http 미사용 |
| `exported` | ✅ 적절 | MainActivity만 exported, LAUNCHER 인텐트 정상 |

**Android 우선 조치**: `allowBackup="false"`, 배포 파이프라인에서 서명 키 존재를
강제(폴백으로 debug 서명이 나가지 않게).

---

## 5. 📱 iOS 세부

| 항목 | 상태 | 비고 |
|---|---|---|
| 권한 설명 문자열 | ✅ 있음 | 위치·카메라·사진 `NS...UsageDescription` 존재 |
| 위치 권한 범위 | ✅ 양호 | `Geolocator.requestPermission()`은 iOS에서 **'사용 중 허용'만** 요청함(코드 확인). plist의 Always 키는 플러그인이 요구해 넣은 것이고 실제 '항상' 요청은 없음 |
| ATS(App Transport Security) | ✅ 양호 | `NSAllowsArbitraryLoads` 없음 — HTTPS 강제 유지 |
| Keychain 잔존 | 🔴 관련 | 1-2와 연결. 앱 삭제로도 안 지워지는 Keychain 특성상 **탈퇴 시 명시 삭제가 필수**(수정됨·미검증) |
| `UIFileSharingEnabled` | ✅ 미설정 | 파일 앱으로 문서 디렉터리(암호화 명함) 노출 안 됨 |
| 수출 규정 | 🟠 키 부재 | `ITSAppUsesNonExemptEncryption` **키가 Info.plist에 없음** — 업로드/심사 때마다 수동 응답을 요구받는다. 표준 암호화만 쓰므로 `false`를 넣어 두면 매번 묻지 않음(P1-21) |

**iOS 우선 조치**: Keychain 키 삭제 검증(1-2), `IOSOptions` 접근성 제한(2-1),
위치 '항상' 요청 여부 확인.

---

## 6. 조치 우선순위

**테스트 종료 → 출시 사이에 반드시**
1. App Check 복원 3종 세트(1-1) — P0-9·P0-11
2. 회원탈퇴 로컬 정리 **실기기 검증**(1-2) — Android/iOS 각 1회
3. `allowBackup="false"`(2-2)
4. 서버 입력 길이 상한(2-4)

**출시 전 권장**
5. Secure Storage 옵션 명시(2-1)
6. 게스트 평문 저장 경로 재확인(1-3)
7. `ITSAppUsesNonExemptEncryption=false` 추가(5절·P1-21)

**운영 정책**
8. 관리자 계정 2FA(2-3)
9. 배포 파이프라인 서명 키 강제(4절)

---

## 부록 — 점검하지 않은 것(범위 밖·별도 필요)

- **동적 분석**: 런타임 메모리 덤프, 네트워크 트래픽 실측(MITM), 루팅/탈옥 기기
  거동 — 별도 도구·환경 필요.
- **의존성 취약점**: `flutter pub` / `npm audit` 전수 — 여기선 미실행(P2-10에
  npm audit 잔존 7건 기록 있음).
- **개인정보 영향평가(PIA)**: 제3자 정보 대량 처리라 법률 전문가 검토 권장.
- **스토어 심사 정책 적합성**: Play Data safety / App Privacy 양식(P0-7)은 별건.

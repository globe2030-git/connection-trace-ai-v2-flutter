# 디자인 시스템 규칙 (Figma ↔ 코드)

Figma 디자인을 이 앱의 코드로 옮길 때, 그리고 반대로 코드를 Figma로 올릴 때
지켜야 할 규칙. **Figma에서 뽑은 값을 그대로 하드코딩하지 않고, 아래 토큰과
컴포넌트로 치환하는 것이 이 문서의 목적이다.**

작성 근거는 2026-08-15 기준 실제 코드(`lib/core/theme/`, `lib/core/icons/`,
`lib/presentation/common/`, `pubspec.yaml`)다. 코드가 바뀌면 이 문서도 함께 고친다.

관련 파일 하나로 요약하면: **색은 `AppColors`, 폰트는 Pretendard, 카드는
`GlassCard`, 아이콘은 `AppIcon`.**

---

## 0. 짝이 되는 Figma 파일

- 핸드오프 파일: `https://www.figma.com/design/mrmngo1yi7usqLhoFN1bLk`
  (file_key `mrmngo1yi7usqLhoFN1bLk`, 파일명 "커넥션센스 — 앱 화면 디자인 (핸드오프)")
- 의도한 구성: 페이지 ① 토큰·컴포넌트(색상 스타일 19 · 텍스트 스타일 8 ·
  컴포넌트 13), 페이지 ② 화면 11종. 관리자 콘솔은 제외(웹·검정 테마라 별개 체계).

### ⚠️ 그런데 지금 그 파일은 비어 있다 (2026-08-15 확인)

MCP로 실제 조회한 결과, 파일에는 **페이지 하나(`0:1` "① 토큰 · 컴포넌트")만
있고 그 안에는 텍스트 노드 2개**(제목 한 줄, 설명 한 줄)뿐이다. 캔버스 실측
크기 553×94px. **색상 스타일·텍스트 스타일·컴포넌트 13종·화면 11종이 전부
없고, 페이지 ②도 없다.**

즉 **지금 이 파일을 디자이너에게 보내면 빈 파일을 보내는 것이다.** 다시
만들어야 한다. 그때까지 **코드가 유일한 기준**이며, 아래 1~6절이 그 기준을
받아 적은 것이다.

- ⚠️ **Figma의 서체는 Noto Sans KR로 대체돼 있었다.** 실제 앱은 Pretendard다.
  다시 만들 때도 이 대체가 반복되므로, Figma에서 텍스트를 코드로 옮길 때
  `fontFamily`를 Noto Sans KR로 쓰면 안 된다.

---

## 1. 색 — `lib/core/theme/app_colors.dart` 밖에서 색을 정의하지 않는다

Figma에서 hex를 읽었으면 `Color(0xFF...)`로 적지 말고, 아래 표에서 같은 값을
찾아 `AppColors.<이름>`으로 쓴다. 표에 없는 색이 필요하면 **먼저 정말 새 색이
맞는지 의심하고**, 맞다면 `AppColors`에 이름과 용도 주석을 달아 추가한다.

### 배경 · 표면

| 토큰 | 값 | 쓰는 곳 |
|---|---|---|
| `bgBase` | `#F7F8FA` | 페이지 배경(`scaffoldBackgroundColor`, AppBar 배경) |
| `bgElevated` | `#FFFFFF` | 떠 있는 표면(하단 탭바 등) |
| `cardSurface` | `#FFFFFF` | 카드, 입력 필드 채움 |
| `borderSubtle` | `#E8EBF0` | 카드·입력 필드의 옅은 경계, 구분선 |
| `borderFunctional` | `#DDE2EA` | 좀 더 또렷해야 하는 기능적 경계 |
| `cardShadow` | `#111827` 4% | 카드 그림자 색 (블러 14, offset 0/4) |

### 텍스트

| 토큰 | 값 | 쓰는 곳 |
|---|---|---|
| `textPrimary` | `#171A21` | 본문·제목 |
| `textSecondary` | `#5F6673` | 보조 설명 |
| `textMuted` | `#7B8391` | 더 약한 부가 정보 |

### 브랜드 액센트 (2색 원칙)

| 토큰 | 값 | 쓰는 곳 |
|---|---|---|
| `accent` | `#2563EB` | 주요 액션, 포커스 테두리, 아이콘 강조 |
| `accentText` | `#1D4ED8` | 액센트 위 텍스트·선택된 탭 (대비 확보용 한 단계 진한 톤) |
| `accentSoft` | `#E8F0FE` | 선택 배경, 탭 인디케이터 |
| `accentSoftStrong` | `#D5E2FC` | 원형 아이콘 배경처럼 존재감이 더 필요한 자리 |

### 상태색 — 장식이 아니라 의미가 있을 때만

| 토큰 | 값 | 쓰는 곳 |
|---|---|---|
| `destructive` | `#EF4444` | 오류, 삭제 |
| `warningText` | `#B45309` | 주의(오류만큼 강하지 않은 조치 유도). bgBase 위 4.6:1로 WCAG AA 통과 |
| `warningSoft` | `#FEF3C7` | 주의 배경 |

### 소통 채널 범례색 — 2색 원칙의 기능적 예외

통화/문자/이메일/카카오톡을 목록에서 구분하는 카테고리 색이다. 차트 범례와
같은 성격이라 브랜드 색과 별개로 존재한다. **이 넷 말고 다른 곳에 쓰지 않는다.**

`channelCall` `#38BDF8` · `channelSms` `#84CC16` · `channelEmail` `#F59E0B` ·
`channelKakao` `#FEE500`(카카오 공식 브랜드 옐로우, 변경 불가)

### 지금 남아 있는 예외 4곳

토큰화되지 않은 `Color(0x...)`가 코드에 4건 있다. 새로 만들지 말고, 손댈 일이
생기면 토큰으로 올리는 쪽으로 정리한다.

- `settings_view.dart:1422` `#2D7D46`
- `briefing_overlay_view.dart:29` `#B91C1C` (`_onPageErrorText`)
- `location_consent_sheet.dart:98` `#332B76C5` (반투명)
- `nearby_map_view.dart:365` `#33000000` (지도 위 그림자)

### 다크 모드는 없다

`AppTheme`은 `lightTheme` 하나뿐이다. Figma에 다크 변형이 있어도 코드로 옮기지
않는다. 색 이름이 값과 반대라 오해를 낳았던 전례가 있어(`bgDarkSlate` 등)
지금 이름은 전부 의미 기반이다 — 다크 시절 이름으로 되돌리지 않는다.

---

## 2. 타이포그래피 — Pretendard 번들 폰트

`fontFamily: 'Pretendard'`가 `ThemeData` 최상위에 있어 하위 텍스트 스타일에
상속된다. **개별 위젯에서 `fontFamily`를 다시 지정하지 않는다.**

번들된 굵기는 **400 / 500 / 600 / 700 / 800** 다섯 가지다. Figma가 w300이나
w900을 쓰고 있으면 가장 가까운 값으로 맞춘다(Flutter가 자동 대체하지만,
의도가 코드에 남도록 명시하는 편이 낫다).

`google_fonts`로 런타임에 내려받는 방식은 쓰지 않는다 — 첫 실행에서 기본 폰트로
보였다가 뒤늦게 바뀌는 문제가 있었다.

### 정의된 텍스트 스타일

| 스타일 | 크기 | 굵기 | 자간 | 색 |
|---|---|---|---|---|
| `displayLarge` | 36 | w800 | −1.0 | `textPrimary` |
| `titleLarge` | 20 | w700 | −0.5 | `textPrimary` |
| `bodyLarge` | 16 | w500 | — | `textPrimary` |
| `bodyMedium` | 14 | w400 | — | `textSecondary` |

**큰 글자일수록 자간을 좁힌다**(36 → −1.0, 20 → −0.5, 본문 → 0)가 이 앱의
규칙이다. 새 스타일을 만들면 이 곡선을 따른다.

위 넷으로 안 되는 크기는 `Theme.of(context).textTheme.<가장 가까운 것>.copyWith(...)`로
파생시킨다. `TextStyle`을 맨바닥부터 새로 쓰면 색과 폰트가 테마에서 떨어져 나온다.

---

## 3. 모서리 반경 — 용도별로 정해져 있다

Figma에서 읽은 반경을 그대로 쓰지 말고 아래 계단에 맞춘다. 실제 사용 빈도
기준이며, 목록 위쪽이 표준이다.

| 반경 | 쓰는 곳 |
|---|---|
| **999** | 캡슐(칩, 검색바, 완전한 알약 모양) |
| **22** | `GlassCard` — 카드의 표준 |
| **18** | 입력 필드(`inputDecorationTheme`) |
| **16 / 14 / 12** | 카드 안쪽 요소, 작은 컨테이너, 버튼 |
| **8 / 10** | 작은 배지, 썸네일 |
| **2** | 얇은 인디케이터·바 |

13, 17, 30, 6, 7 같은 1회성 값이 코드에 남아 있지만 **표준이 아니다.** 새로
만들지 않는다.

---

## 4. 간격 — 4의 배수

수직 간격은 `SizedBox(height: ...)`로, 안쪽 여백은 `EdgeInsets`로 준다.
실제로 쓰이는 값은 **4 · 8 · 12 · 16 · 20 · 24**가 압도적이다.

| 상황 | 값 |
|---|---|
| 붙어 있는 요소 사이 | 4, 6, 8 |
| 같은 그룹 안의 항목 사이 | 10, 12 |
| 그룹과 그룹 사이 | 16, 20 |
| 화면 가장자리 여백 | 16 또는 20 |
| 카드 안쪽 여백 | 16(`GlassCard` 기본) 또는 20 |
| 큰 섹션 구분 | 24, 32 |

**2, 3, 18, 26 같은 값은 쓰지 않는다.** Figma가 그런 값을 주면 가장 가까운
4의 배수로 반올림한다(코드에 소수 남아 있는 것은 정리 대상이지 본보기가 아니다).

---

## 5. 컴포넌트 — 새로 만들기 전에 여기부터 본다

`lib/presentation/common/`에 있는 것을 먼저 쓴다. Figma에 비슷한 컴포넌트가
있으면 새 위젯을 만들 게 아니라 아래 중 하나에 매핑한다.

| 위젯 | 무엇 | 메모 |
|---|---|---|
| `GlassCard` | 카드 표준 | 반경 22, 배경 `cardSurface`, 1px `borderSubtle` 테두리, `cardShadow` 그림자, 기본 패딩 16. `onTap`을 주면 잉크 리플까지 붙는다. 코드 13곳에서 쓰인다 |
| `ActionCircleButton` | 원형 아이콘 버튼 | 통화·문자 등 행 액션 |
| `ContactAvatar` | 인물 아바타 | 사진 없으면 이니셜 — **스톡 사진으로 채우지 않는다** |
| `AiUsageChip` | AI 잔여 표시 칩 | |
| `SameAddressGroupHeader` | 같은 주소 그룹 머리글 | |
| `ZoomableCardImage` | 명함 이미지 확대 뷰 | |
| `AddressSearchView` | 주소 검색 | WebView 기반. `file://` origin 함정이 있었던 곳이라 함부로 손대지 않는다 |
| `LegalDocumentView` | 약관·방침 표시 | |
| `AuthGate` / `SplashGate` / `VersionGate` | 화면 진입 게이트 | 화면이 아니라 감싸는 장치 |

### 버튼

Material 기본 버튼을 그대로 쓴다(전용 래퍼 없음). 성격에 맞춰 고른다.

- `ElevatedButton` — 화면의 주요 액션 (34곳)
- `OutlinedButton` — 보조 액션 (26곳)
- `TextButton` — 취소·부가 링크 (69곳)
- `FilledButton` — 드물게 사용 (9곳). 새로 늘리지 않는다

---

## 6. 아이콘 — `Icon(Icons.xxx)`가 아니라 `AppIcon`

Claude Design 핸드오프의 커스텀 SVG 아이콘 40종이 `AppIconId` enum에 있다
(공식 38종 + 직접 제작 2종: `qrScan`, `galleryUpload`).

```dart
AppIcon(AppIconId.cardWallet, size: 24)   // 색을 안 주면 주변 IconTheme을 따름
```

- 격자 **24×24**, 선 굵기 **1.25px**.
- SVG 안에 강조색 `#2563EB`가 고정돼 있고 기본 색만 `currentColor`다 —
  `AppIcon`이 그 부분만 치환하므로 **색을 바꿔도 브랜드 강조는 유지된다.**
- 에셋 경로는 `assets/images/{도메인}/{이름}.svg`. 도메인 폴더는 코드의
  `features/` 구조와 같은 원리로 나뉜다(nearby, ai, wallet, settings, comm,
  scan, common, brand, profile).
- ⚠️ `pubspec.yaml`의 `assets:`는 **직계 파일만 포함하고 하위 폴더는 재귀되지
  않는다.** 새 도메인 폴더를 만들면 `pubspec.yaml`에 줄을 추가해야 한다.
- 없는 아이콘이 필요하면 같은 규칙(24×24 · 1.25px · currentColor + #2563EB 강조)로
  만들어 `AppIconId`에 추가한다. Material 아이콘을 섞지 않는다.

---

## 7. 이 앱에서만 해당하는 주의

### 가짜 데이터를 만들지 않는다

Figma 화면에는 예시 인물·예시 알림이 채워져 있다. **그건 목업이지 구현 대상이
아니다.** 데이터가 없으면 빈 상태를 그대로 보여준다. 과거에 프로필 사진 선택이
실제로는 스톡 사진 4장을 순환시키는 가짜 구현이었던 전례가 있다.

### 개인정보가 화면에 나오는 앱이다

이름·전화번호·이메일·주소는 제3자(명함 주인)의 개인정보다. 스크린샷을
공유하거나 로그를 남길 때 값이 그대로 찍히지 않게 한다.

### 화면 목록과 코드 위치

| 도메인 | 코드 |
|---|---|
| 로그인 | `lib/presentation/features/auth/` |
| 주변(레이더)·지도·명함 지갑 | `lib/presentation/features/radar/` |
| AI 브리핑 | `lib/presentation/features/briefing/` |
| 설정·문의·공지 | `lib/presentation/features/settings/` |
| AI 충전(지갑) | `lib/presentation/features/wallet/` — ⚠️ 과금 관련. main 병합 보류 정책이 걸려 있다(CLAUDE.md 6절) |

---

## 8. Figma → 코드로 옮길 때 순서

1. `get_design_context`로 노드를 읽기 **전에** `/figma-design-to-code` 스킬을 부른다(필수).
2. 뽑힌 색·크기·반경·간격을 위 1~4절 표로 **치환**한다. 하드코딩된 채로 두지 않는다.
3. 이미 있는 컴포넌트(5절)로 조립할 수 있는지 먼저 본다.
4. 아이콘은 `AppIcon`으로 바꾼다(6절).
5. `flutter analyze` — error·warning 0. info를 늘리지 않는다.
6. 겉모습만 바뀐 변경이면 **부분 테스트**(그 화면 + 같은 스타일 쓰는 화면)로
   충분하다. 전체 테스트는 배포 직전 한 번이다(CLAUDE.md 4절).

## 9. 코드 → Figma로 올릴 때

- `/figma-use` 스킬을 부른 뒤 `use_figma`를 쓴다(필수).
- file_key는 0절의 것을 쓴다 — 새 파일을 만들면 핸드오프가 둘로 갈라진다.
- 값을 직접 박지 말고 색상 스타일·텍스트 스타일·컴포넌트를 **먼저 만들고 거기에
  바인딩**한다. 한 곳을 고치면 전 화면에 반영되는 구조를 만들기 위해서다.
- 0절대로 파일이 비어 있으므로 순서는 **① 변수·스타일 → ② 컴포넌트 → ③ 화면**이다.
  화면부터 그리면 스타일이 안 붙은 채로 굳는다.
- 작업 후 `get_metadata`로 **실제로 저장됐는지 반드시 확인한다.** 이 파일이 빈
  채로 "완료"로 기록돼 있었던 것이 정확히 이 확인을 건너뛴 결과다.

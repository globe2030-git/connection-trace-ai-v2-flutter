# 이미지 에셋 카탈로그

앱에서 쓰는 모든 이미지의 **미리보기 · 의미 · 사용처** 목록.
파일명만으로 어떤 이미지인지 알기 어렵다는 지적(2026-08-11)에 따라 만들었다.
**이미지를 추가/삭제/개명하면 이 문서도 함께 고칠 것** — 어긋난 카탈로그는
없느니만 못하다. 파일 존재 여부는 `test/asset_files_test.dart`가 검증한다.

## 구조 규칙

- 위치: `assets/images/{도메인}/{기능명}.{svg|png|jpg}`
- 도메인 = 화면 단위 (코드의 `features/{도메인}/` 구조와 같은 원리)
- 파일명 = 12자 이내 기능명, snake_case
- SVG는 24×24 격자·선 1.25px, 기본색 `currentColor` + 강조색 브랜드 블루(#2563EB) 고정
  — 코드에서는 `AppIcon(AppIconId.xxx)`로만 사용 (`lib/core/icons/app_icons.dart`)

## brand/ — 브랜드 (로고·앱아이콘·스플래시)

| 미리보기 | 파일 | 의미 | 사용처 |
|---|---|---|---|
| <img src="../../assets/images/brand/ci.png" width="48"> | `ci.png` | 회사 CI 로고 | 로그인 화면 상단 |
| <img src="../../assets/images/brand/splash.png" width="48"> | `splash.png` | 스플래시 마크 (위치핀+인물+명함) | 앱 시작 스플래시, 주변 화면 로딩 |
| <img src="../../assets/images/brand/icon.png" width="48"> | `icon.png` | 앱 런처 아이콘 원본 | flutter_launcher_icons 생성 소스 |
| <img src="../../assets/images/brand/mark.svg" width="32"> | `mark.svg` | 앱 아이콘 마크(라인) | 앱 내 브랜드 표시 |

## common/ — 공통 (어느 화면에나 나올 수 있는 것)

| 미리보기 | 파일 | 의미 | 사용처 (AppIconId) |
|---|---|---|---|
| <img src="../../assets/images/common/back.svg" width="32"> | `back.svg` | 뒤로 가기 | `back` |
| <img src="../../assets/images/common/share.svg" width="32"> | `share.svg` | 공유 | `share` |
| <img src="../../assets/images/common/save.svg" width="32"> | `save.svg` | 저장/다운로드 | `saveDownload` |
| <img src="../../assets/images/common/sync.svg" width="32"> | `sync.svg` | 동기화 | `sync` |
| <img src="../../assets/images/common/notify.svg" width="32"> | `notify.svg` | 알림(종) | `notification` |
| <img src="../../assets/images/common/connect.svg" width="32"> | `connect.svg` | 연결 중 상태 | `connecting` |
| <img src="../../assets/images/common/more.svg" width="32"> | `more.svg` | 더보기(⋯) | `more` |

## nearby/ — 주변 인맥 (레이더 화면)

| 미리보기 | 파일 | 의미 | 사용처 (AppIconId) |
|---|---|---|---|
| <img src="../../assets/images/nearby/people.svg" width="32"> | `people.svg` | 주변 인맥 (탭바 아이콘) | `nearbyPeople` |
| <img src="../../assets/images/nearby/radar.svg" width="32"> | `radar.svg` | 레이더 감지 | `radarDetect` |
| <img src="../../assets/images/nearby/radius.svg" width="32"> | `radius.svg` | 감지 반경 설정 | `detectRadius` |
| <img src="../../assets/images/nearby/pin_on.svg" width="32"> | `pin_on.svg` | 위치 사용 중 핀 | `pinActive` |
| <img src="../../assets/images/nearby/pin_off.svg" width="32"> | `pin_off.svg` | 위치 꺼짐 핀 | `pinInactive` |
| <img src="../../assets/images/nearby/map.jpg" width="48"> | `map.jpg` | "지금 가까운 사람" 카드의 지도 배경 | radar_view.dart |

## wallet/ — 명함 지갑

| 미리보기 | 파일 | 의미 | 사용처 (AppIconId) |
|---|---|---|---|
| <img src="../../assets/images/wallet/wallet.svg" width="32"> | `wallet.svg` | 명함 지갑 (탭바 아이콘) | `cardWallet` |
| <img src="../../assets/images/wallet/add.svg" width="32"> | `add.svg` | 명함 추가 | `addCard` |
| <img src="../../assets/images/wallet/edit.svg" width="32"> | `edit.svg` | 명함 수정 | `editCard` |
| <img src="../../assets/images/wallet/fav.svg" width="32"> | `fav.svg` | 즐겨찾기(별) | `favorite` |

## scan/ — 명함 스캔·등록

| 미리보기 | 파일 | 의미 | 사용처 (AppIconId) |
|---|---|---|---|
| <img src="../../assets/images/scan/scan.svg" width="32"> | `scan.svg` | 명함 카메라 스캔 | `scanCard` |
| <img src="../../assets/images/scan/gallery.svg" width="32"> | `gallery.svg` | 갤러리에서 이미지 업로드 | `galleryUpload` |

## comm/ — 소통 기록 (통화·문자·이메일·카카오톡)

| 미리보기 | 파일 | 의미 | 사용처 (AppIconId) |
|---|---|---|---|
| <img src="../../assets/images/comm/call.svg" width="32"> | `call.svg` | 전화 걸기 | `call` |
| <img src="../../assets/images/comm/callchk.svg" width="32"> | `callchk.svg` | 통화 완료 확인 | `callCheck` |
| <img src="../../assets/images/comm/msg.svg" width="32"> | `msg.svg` | 문자 메시지 | `message` |
| <img src="../../assets/images/comm/mailsend.svg" width="32"> | `mailsend.svg` | 이메일 보내기 | `mailSend` |
| <img src="../../assets/images/comm/maillink.svg" width="32"> | `maillink.svg` | 이메일 연결 | `emailLink` |
| <img src="../../assets/images/comm/chatsend.svg" width="32"> | `chatsend.svg` | 채팅(카카오톡) 보내기 | `chatSend` |
| <img src="../../assets/images/comm/memo.svg" width="32"> | `memo.svg` | 메모 남기기 | `memo` |
| <img src="../../assets/images/comm/recent.svg" width="32"> | `recent.svg` | 최근 소통 이력 | `recentContact` |

## ai/ — AI 대화 가이드

| 미리보기 | 파일 | 의미 | 사용처 (AppIconId) |
|---|---|---|---|
| <img src="../../assets/images/ai/brief.svg" width="32"> | `brief.svg` | AI 브리핑 | `aiBriefing` |
| <img src="../../assets/images/ai/talkpts.svg" width="32"> | `talkpts.svg` | 대화 포인트 | `talkPoints` |
| <img src="../../assets/images/ai/chip.svg" width="32"> | `chip.svg` | AI 잔여 횟수 칩 | `aiChip` |
| <img src="../../assets/images/ai/datainfo.svg" width="32"> | `datainfo.svg` | AI 전송 데이터 안내 | `aiDataInfo` |
| <img src="../../assets/images/ai/proc.svg" width="32"> | `proc.svg` | AI 생성 중(처리 중) | `aiProcessing` |

## settings/ — 설정

| 미리보기 | 파일 | 의미 | 사용처 (AppIconId) |
|---|---|---|---|
| <img src="../../assets/images/settings/gear.svg" width="32"> | `gear.svg` | 설정 (탭바 아이콘) | `settings` |
| <img src="../../assets/images/settings/logout.svg" width="32"> | `logout.svg` | 로그아웃 | `logout` |
| <img src="../../assets/images/settings/acctdel.svg" width="32"> | `acctdel.svg` | 계정 삭제(회원 탈퇴) | `accountDelete` |
| <img src="../../assets/images/settings/cancel.svg" width="32"> | `cancel.svg` | 서비스 해지 | `cancelService` |
| <img src="../../assets/images/settings/locinfo.svg" width="32"> | `locinfo.svg` | 위치정보 이용 안내 | `locationInfo` |
| <img src="../../assets/images/settings/revoke.svg" width="32"> | `revoke.svg` | 동의 철회 | `consentRevoke` |
| <img src="../../assets/images/settings/carddata.svg" width="32"> | `carddata.svg` | 명함 데이터 보관 안내 | `cardData` |

## profile/ — 내 프로필

| 미리보기 | 파일 | 의미 | 사용처 (AppIconId) |
|---|---|---|---|
| <img src="../../assets/images/profile/qr.svg" width="32"> | `qr.svg` | QR 명함 교환 | `qrScan` |

## 번들에서 제외된 레거시 (참고)

`assets/icons3d/`에 남아 있는 파일(radar.png, 라벤더 시절 이미지 등)과
`assets/icon/`은 **앱에서 쓰지 않아 번들에서 제외**했다. 도구 스크립트
(`tool/generate_app_icon*.dart`)가 참조하므로 파일은 보존한다.

# 📋 Connection Trace AI v2 (Flutter) - 인수인계 및 업무 일지 (HANDOVER NOTES)

**작성일시**: 2026년 7월 31일 22:30  
**프로젝트 경로**: `~/Claude/connection-trace-ai-v2-flutter`  
**기술 스택**: Flutter (Dart 3.x, Material 3 Dark Theme), Clean MVVM Architecture, Provider State Management, SharedPreferences Local Persistence

---

## 📌 1. 금일 달성한 주요 기능 및 완성 작업 (Accomplished Tasks)

### 1) 🎴 명함 정보 수정 (Business Card Edit System)
- `WalletView` 내 각 명함 카드에 연필 수정 버튼(`Icons.edit_outlined`) 추가.
- `AddCardModalView`를 신규 등록과 기존 명함 수정 기능 겸용으로 확장 (`widget.contactToEdit`).
- 기존 명함 정보를 자동 pre-fill 로드하고, 수정 후 `ContactsRepository` 및 디스크(`SharedPreferences`)에 영구 반영.

### 2) 🖼️ 프로필 사진 선택 및 원형 아바타 렌더링
- `ContactModel`에 `avatarUrl` 필드 추가.
- `AddCardModalView` 상단에 프로필 사진 선택 카메라 아바타 배치 (터치 시 사진 프리셋 전환).
- **명함지갑**, **근접 인맥 리스트**, **30초 AI 대화 브리핑** 전체 화면에 프로필 사진 원형 아바타 렌더링 적용.

### 3) 📡 레이더 화면 ME(내 위치) 와이파이 파동 애니메이션
- `RadarView` 중앙의 ME(나)와 근접 인맥(김민준 이사)의 시각적 구분감 문제 해결.
- `RadarPulseHeroWidget`: 내 위치(ME)는 콤팩트한 와이파이 파동 인디케이터(`Icons.wifi_tethering`) 및 라임색 테두리로 배치하고, 동심원 와이파이 파동 애니메이션 적용.
- 주변 근접 인맥은 궤도 상의 Target 레이더 팁으로 표출되어 100% 명확한 대비 제공.

### 4) 🔢 근접 인맥 리스트 정렬 규칙 적용
- `RadarViewModel.filteredContacts`:
  - **1순위**: 사용자 중심 **가까운 거리순 (Distance Ascending)**
  - **2순위**: 거리가 같을 경우 **한글 이름 가나다순 (Alphabetical Name)**

### 5) 💾 서버/앱 재시작 시 데이터 보존 및 `Memo Summary` 필드 복원
- `ContactsRepository`의 디스크 동기화(`_saveToDisk()`) 보장으로 재시작 후에도 입력/수정/삭제된 명함 데이터 100% 영구 보존.
- 30초 AI 브리핑 타이틀을 `📝 Memo Summary`로 변경 및 `AddCardModalView`에 `Memo Summary (메모 및 특징 요약)` 입력 필드 복원.
- `FocusTraversalGroup` 적용으로 **`Tab` 키 및 `엔터` 키 입력 시 건너븀 없는 1칸 순차 포커스 이동** 구현.

### 6) 📸 명함 카메라 스캔 & 🖼️ 갤러리 파일 탐색기 모달 연동
- `CameraScanModalView`: 실제 명함 가이드 틀과 상하 스캔 레이저 라이트 애니메이션, 대형 셔터 버튼이 장착된 명함 전용 스캔 화면 제작.
- `FilePickerModalView`: 기기 갤러리/파일 탐색기 모달 제작. 컴퓨터/스마트폰 실제 파일 선택 버튼(`[💻 내 컴퓨터/스마트폰 실제 파일 선택하기]`)을 제공하여 선택 파일 미리보기 및 AI OCR 텍스트 자동 파싱.

### 7) 📍 주소 위치(GPS) 검증 및 🛣️ 도로명 주소 자동 변환 팝업
- `AddressGeocodingService`: 입력 주소의 지오코딩 가능 여부 검증.
- 부실 주소 시: *"GPS 위치를 정밀하게 찾을 수 없습니다"* 팝업 후 주소 입력 필드로 커서 자동 이동.
- 지번/변환 가능 주소 시: *"표준 정밀 도로명 주소(서울특별시 강남구 테헤란로 123)로 자동 변환하시겠습니까?"* 팝업 제공 후 선택 시 도로명 주소로 치환하여 저장.

### 8) 💬 최근 소통 Trace 연동 (통화 / 문자 / 이메일 / 카카오톡) & 테스트 모달
- `CommunicationLogModel`: 최근 통화, SMS 문자, 이메일, 카카오톡 4개 채널 소통 이력 데이터 구조 구축.
- `BriefingOverlayView`에 `💬 최근 소통 Trace 연동` 카드 렌더링.
- `CommunicationTraceTestModalView`: 4개 채널별 소통 연동 신호를 실시간 가상 발생시켜 AI 브리핑에 즉시 연동되는 테스트 도구 완성.

### 9) 🎨 UI/UX 기획 재점검 및 버튼 역할 분리
- **우측 상단 QR 아이콘**: P2P 내 QR 공유 및 맞교환 전용 (`QrCodeModalView`).
- **화면 중앙 [명함 등록] 버튼**: 명함 직접 작성 및 OCR 촬영/이미지 스캔 전용 (`AddCardModalView`).
- **[감지 켜기] 버튼**: 실시간 백그라운드 탐지 `감지 ON` ↔ `감지 OFF` 스위치 연동 완료.

---

## 🎯 2. 내일 진행해야 할 일 (Next Tasks to Do)

1. **📱 실제 스마트폰 네이티브 칩 API 연동 (Camera & File Picker Native Packages)**:
   - Web/Desktop 테스트 환경을 넘어 실제 Android APK / iOS IPA 빌드를 위해 `image_picker: ^1.1.2` 및 `file_picker: ^8.1.7` 네이티브 패키지 연결.
2. **🔊 AI 브리핑 음성(TTS) 브리핑 재생 기능**:
   - `flutter_tts` 패키지를 활용해 30초 AI 대화 브리핑을 이동 중 음성으로 들을 수 있는 TTS 플레이어 버튼 연결.
3. **🗺️ 근접 인맥 인터랙티브지도 뷰 (Map View UI)**:
   - 현재 레이더 리스트 뷰 외에 `google_maps_flutter` 또는 커스텀 Vector Map 뷰 탭 전환 기능 제공.
4. **📊 소통 주기 알림 및 롱텀 인맥 리마인더**:
   - 3개월 이상 소통이 없었던 인맥을 자동 감지하여 "안부 인사 제안" 알림 띄우기.

---

## 🏗️ 3. 주요 아키텍처 및 핵심 파일 구조 (Key Codebase Sitemap)

- `lib/data/models/contact_model.dart`: 명함 데이터 모델 (이름, 회사, 주소, 통화/문자/카카오/이메일 소통 이력 `commLogs`, `avatarUrl`, `memo` 포함)
- `lib/data/repositories/contacts_repository.dart`: 명함 데이터 중앙 저장소 (`SharedPreferences` 로컬 디스크 스토리지 연동 `saved_contacts_v2`)
- `lib/core/services/address_geocoding_service.dart`: 주소 검증 및 도로명 주소 자동 변환 서비스
- `lib/core/services/ocr_scanner_service.dart`: AI OCR 명함 텍스트 파싱 서비스
- `lib/presentation/features/radar/views/radar_view.dart`: 메인 레이더 메인 화면 (ME 와이파이 파동, 인맥 거리/가나다순 리스트)
- `lib/presentation/features/radar/views/camera_scan_modal_view.dart`: 명함 촬영 뷰파인더 모달
- `lib/presentation/features/wallet/views/file_picker_modal_view.dart`: 기기 갤러리 이미지 파일 탐색기 모달
- `lib/presentation/features/wallet/views/add_card_modal_view.dart`: 명함 등록/수정, OCR 텍스트 복원, 도로명 주소 변환 모달
- `lib/presentation/features/radar/views/priority_modal_view.dart`: VIP 우선 감지 설정 모달
- `lib/presentation/features/radar/views/communication_trace_test_modal_view.dart`: 통화/문자/카카오톡/이메일 연동 실시간 테스트 모달
- `lib/presentation/features/briefing/views/briefing_overlay_view.dart`: 30초 AI 대화 브리핑 및 최근 소통 Trace 연동 오버레이

---

## 🛠️ 4. 개발 환경 구동 및 검증 명령어

```bash
# 1) 의존성 패키지 확인
flutter pub get

# 2) 정적 분석 검사 (결과: 0 Errors)
flutter analyze

# 3) Chrome 브라우저 실행
flutter run -d chrome
```

---
*인수인계 문서 작성 완료 (Next Agent Ready)*

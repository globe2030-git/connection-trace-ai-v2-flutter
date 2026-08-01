# Connection Trace AI v2 (Flutter) — Planning Backlog

## 향후 후보 (미착수)

- **(2026-08 메모리/최적화 감사에서 파생, 실제 기능 작업 때 같이 정리하기로 결정)**
  코드 정적 감사 결과 메모리 누수는 없었음(AnimationController/TextEditingController/
  FocusNode 전부 정상 dispose, ChangeNotifier 리스너 등록/해제 쌍 정확, Timer/
  StreamSubscription 사용 자체가 없음, OCR 비동기 흐름에 `mounted` 가드 있음).
  다만 다음 3가지는 "누수는 아니지만 최적화 여지"로 확인됨 — 실제 기능(OCR/GPS/
  지오코딩 등) 붙이는 작업과 함께 정리하기로 사용자가 결정:
  1. `radar_view.dart`의 "근접 인맥 리스트"가 `ListView.builder`가 아니라
     `Column` + `.map()`으로 전부 즉시 렌더링됨(`wallet_view.dart`는 이미
     `ListView.builder` 사용 중이라 대조됨). 인맥 수가 늘어나면 스크롤 성능에
     영향 줄 수 있음.
  2. `context.watch<RadarViewModel>()`/`context.watch<WalletViewModel>()`가 각
     화면 최상단에서 호출돼 뷰모델 값 하나만 바뀌어도 화면 전체가 리빌드됨.
     `Selector`나 좁은 범위 `Consumer`로 좁히면 리빌드 범위 최적화 가능.
  3. `RadarViewModel.filteredContacts`/`nearbyAlertContact` getter가 호출될
     때마다 전체 인맥 거리 계산을 캐싱 없이 다시 수행 — 같은 프레임에 두 getter가
     같이 호출되면 거리 계산이 중복됨.
- **(2026-08 실제 기능 전환 결정)** OCR/GPS/지오코딩이 전부 하드코딩된 mock임을
  실측 확인(Antigravity가 만든 초기 버전) — 실제 Tesseract/ML Kit OCR, 실제
  Geolocator 기반 GPS, 실제 Nominatim(또는 유사) 지오코딩으로 교체 필요. 다음
  주요 작업 단계.
- **(2026-08 결정)** 소통 이력(통화/문자/이메일/카카오톡) 연동: 기본은 수동 메모,
  통화/문자/이메일은 사용자가 선택적으로 연동 가능하게 구성. 아이폰은 OS 정책상
  통화/문자 로그 접근이 원천적으로 불가해 수동 메모만 가능(편의성 고려해서 설계
  필요) — 안드로이드는 `READ_CALL_LOG` 등 권한으로 제한적으로 가능하나 Play
  Store 심사 반려 리스크 있음. 카카오톡은 어느 플랫폼에서도 개인 대화 읽기 API가
  존재하지 않아 연동 자체가 불가(수동 메모만 가능).
- **(2026-08 UI 리디자인에서 파생)** 나머지 화면(명함 지갑, 설정, 각종 모달)이
  다크 뉴트럴 + 액센트 #004EA2 2색 팔레트로 올바르게 렌더링되는지 사용자가
  직접 `flutter run -d chrome`으로 확인 필요 — 이 개발 환경의 브라우저 자동화가
  Flutter Web 클릭/키보드 이벤트를 인식하지 못해(html renderer 특성) 탭 전환
  클릭 기반 검증을 못 함(알려진 툴링 제약, React 프로젝트의 네이티브 파일
  다이얼로그 제약과 같은 카테고리).

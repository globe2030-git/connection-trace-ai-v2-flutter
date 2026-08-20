import 'dart:async';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/utils/korean_phone_formatter.dart';
import '../../../../core/utils/ocr_origin.dart';
import '../../../../core/utils/scan_temp_cleanup.dart';
import '../../../../core/utils/web_tab_guard.dart';
import '../../../../core/services/address_geocoding_service.dart';
import '../../../../core/services/contact_image_service.dart';
import '../../../../core/services/card_rect_detector.dart';
// ⚠️ 측정 전용 — backlog 277이 끝나면 이 import와 쓰는 곳을 함께 지운다.
import '../../../../core/utils/measure_sample_sink.dart';
import '../../../../core/services/doc_scanner_capture_service.dart';
import '../../../../core/services/ocr_scanner_service.dart';
import '../../../../core/utils/scan_conflict.dart';
import '../../../../core/services/ocr_stats_service.dart';
import '../../../../data/models/contact_model.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../common/address_search_view.dart';
import '../../../common/card_image_viewer.dart';
import '../../../common/contact_avatar.dart';
import '../view_models/wallet_view_model.dart';
import 'scan_field_conflict_sheet.dart';
import 'camera_scan_modal_view.dart';
import 'file_picker_modal_view.dart';

/// 저장 시 "도로명 주소로 변환하시겠습니까?" 팝업을 다시 띄울지 결정한다.
///
/// [confirmedRoadNameAddress]는 사용자가 지난 팝업에서 이 주소에 대해 이미
/// 결론을 낸 값이다 — "네, 도로명으로 변경"을 눌렀을 때는 바뀐 도로명
/// 주소를, "기존 입력 유지"를 눌렀을 때는 원본 주소를 그대로 기록해 두
/// 버튼의 결과가 대칭이 되게 한다. [rawAddress]가 그 값과 같으면(=바로 그
/// 주소에 대해 이미 결정이 끝났으면) 다시 묻지 않는다.
///
/// "기존 입력 유지" 쪽에서 이 기록을 빼먹으면, 사용자가 원본 주소를 그대로
/// 두고 다시 저장을 눌러도 [rawAddress]가 [confirmedRoadNameAddress]와 계속
/// 달라서 같은 팝업이 무한히 다시 떴다(테스터 A, 갤럭시 폴드7, 1.0.0(8) 제보).
bool shouldShowRoadNameConversionDialog({
  required String? roadNameAddress,
  required String rawAddress,
  required String? confirmedRoadNameAddress,
}) {
  return roadNameAddress != null &&
      roadNameAddress != rawAddress &&
      rawAddress != confirmedRoadNameAddress;
}

class AddCardModalView extends StatefulWidget {
  final ContactModel? contactToEdit;
  // QR 스캔 등으로 미리 채워 넣을 값 — contactToEdit과 달리 "새 명함"으로
  // 저장된다(기존 id를 덮어쓰지 않음). 필드 초기값 채우는 용도로만 쓰임.
  final ContactModel? prefillData;

  const AddCardModalView({super.key, this.contactToEdit, this.prefillData});

  /// 이 화면은 입력 필드가 많아 isScrollControlled 시트가 내용 높이만큼
  /// 자라나는데, iOS는 필드 한 줄 높이가 안드로이드보다 약간씩 커서(폰트
  /// 지표 차이) 시트가 화면 맨 위 노치까지 거의 닿아 "위로 붙어 보인다"는
  /// 문제가 있었다(실기기 확인, 안드로이드는 정상 — 사용자 피드백). 시트
  /// 최대 높이를 "명함 지갑" 화면의 제목 시작 위치(상태 표시줄 높이 + 그
  /// 화면과 같은 12px 여백)로 고정해, 내용이 아무리 길어도 시트 위쪽이 그
  /// 지점보다 올라가지 않게 한다 — 넘치는 내용은 내부 스크롤로 처리된다.
  static Future<T?> show<T>(
    BuildContext context, {
    ContactModel? contact,
    ContactModel? prefillData,
  }) {
    final topInset = MediaQuery.of(context).padding.top;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height - topInset - 12,
      ),
      builder: (_) =>
          AddCardModalView(contactToEdit: contact, prefillData: prefillData),
    );
  }

  @override
  State<AddCardModalView> createState() => _AddCardModalViewState();
}

class _AddCardModalViewState extends State<AddCardModalView> {
  final _formKey = GlobalKey<FormState>();
  // 이 화면은 자체 Scaffold 없이 showModalBottomSheet의 콘텐츠로만 쓰여서
  // ScaffoldMessenger.of(context)를 쓰면 스낵바가 모달 뒤 페이지로 가서 시트에
  // 가려 안 보인다. 그렇다고 이 화면을 Scaffold로 감싸면 showModalBottomSheet가
  // 콘텐츠 높이를 스스로 계산하는 방식과 충돌해 폼이 한 줄만 그려지고 나머지가
  // 통째로 안 보이는 훨씬 심각한 레이아웃 버그가 남(실기기로 확인됨). 그래서
  // Scaffold/ScaffoldMessenger에 기대지 않고, 폼 안에 직접 배너를 그려서
  // 안내 메시지를 표시한다 — 어떤 상황에서도 확실히 모달 위에 보임.
  String? _inlineNoticeText;
  bool _inlineNoticeIsError = false;
  VoidCallback? _inlineNoticeAction;
  String? _inlineNoticeActionLabel;

  // 명함 인식 품질 측정(개인정보 없이 형태만): 자동 인식이 각 필드에 실제로
  // 넣은 값을 스캔 시점에 스냅샷으로 잡아 두고, 저장 시점에 사용자가 그걸
  // 어떻게 바꿨는지(그대로/고침/지움)만 집계한다. 값 자체는 집계로 넘어가지
  // 않는다 — 이 스냅샷은 "저장 시점 비교" 용도로 메모리에만 잠깐 머문다.
  final OcrStatsService _ocrStats = OcrStatsService();
  final Map<String, String> _ocrParsedSnapshot = {};

  // Text Controllers
  late TextEditingController _nameController;
  late TextEditingController _companyController;
  late TextEditingController _titleController;
  // 부서 — 직함과 별개 칸(2026-08-19 확정, 추가 321). 예전에는 이 화면의
  // 라벨이 '직함 / 부서'로 **한 칸에 둘을 받고 있었다.**
  late TextEditingController _departmentController;
  late TextEditingController _addressController;
  late TextEditingController _addressDetailController;
  late TextEditingController _postalCodeController;
  late TextEditingController _phoneController;
  late TextEditingController _officePhoneController;
  late TextEditingController _directPhoneController;
  late TextEditingController _faxController;
  late TextEditingController _emailController;
  late TextEditingController _websiteController;
  late TextEditingController _tagsController;
  late TextEditingController _interestsController;
  late TextEditingController _memoController;

  // Strict Contiguous Sequential Focus Nodes to prevent Tab/Enter key jumping
  final _nameFocusNode = FocusNode();
  final _companyFocusNode = FocusNode();
  final _titleFocusNode = FocusNode();
  final _departmentFocusNode = FocusNode();
  final _addressFocusNode = FocusNode();
  final _addressDetailFocusNode = FocusNode();
  final _postalCodeFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _officePhoneFocusNode = FocusNode();
  final _directPhoneFocusNode = FocusNode();
  final _faxFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _websiteFocusNode = FocusNode();
  final _tagsFocusNode = FocusNode();
  final _interestsFocusNode = FocusNode();
  final _memoFocusNode = FocusNode();

  // [버그 수정] Tab 키가 필드를 건너뛰던 문제 — FocusTraversalOrder, 필드별
  // Focus.onKeyEvent, 폼 전체 Shortcuts+Actions(NextFocusIntent 재정의)까지 Dart
  // 레벨에서 세 가지를 시도했지만 전부 재현 계속됨. 디버그 로그로 확인해보니 Dart
  // 쪽 currentIndex 자체는 Tab마다 정확히 1씩 증가하는데, 그 직후 "브라우저의 기본
  // Tab 동작"이 별도로 한 번 더 끼어들어 실제 화면 포커스를 그 다음 칸으로 밀어버려
  // 결과적으로 한 칸 더 건너뛰는 것으로 나타남 — 즉 Dart 레벨 어떤 방식으로도 브라우저
  // 자체의 네이티브 Tab 기본 동작을 완전히 못 막았던 것. 그래서 web_tab_guard.dart에서
  // document keydown을 capture 단계에서 직접 가로채 preventDefault로 브라우저 기본
  // 동작 자체를 원천 차단하고, 포커스 이동은 오직 이 리스트 순서 기준 _moveFocus만
  // 담당한다(initState에서 WebTabGuard.install로 연결).
  late final List<FocusNode> _fieldFocusOrder;

  // 프로필 사진 — 실제 로컬 파일 경로(원격 URL 아님). image_picker로 고른
  // 사진을 앱 문서 디렉터리에 복사해 영구 보관한다.
  String? _selectedAvatarUrl;
  bool _isPickingAvatar = false;
  String? _scannedRawText;
  List<String> _scannedRawLines = [];
  bool _isScanningOcr = false;
  bool _showRawTextCard = false;
  bool _isSavingCard = false;
  // 사용자가 "네, 도로명으로 변경"을 눌러 확정한 주소를 기억해 둔다. 매번
  // 저장할 때마다 새로 역지오코딩을 하는데, 같은 좌표라도 OS
  // Geocoder(특히 Android)가 호출할 때마다 구성요소 순서/공백이 미묘하게
  // 달라진 문자열을 줄 때가 있어서, 이미 사용자가 확정한 텍스트와 주소
  // 입력칸이 그대로면(직접 다시 고치지 않았다면) 도로명 변환창을 또
  // 띄우지 않는다 — 저장할 때마다 변환창이 계속 다시 뜨던 문제.
  String? _confirmedRoadNameAddress;

  /// 좌표 조회가 실패했을 때 다시 시도할 **같은 위치의 다른 표기**(도로명↔지번).
  /// 우편번호 검색에서 받아 둔다 — OS 지오코더가 한쪽 표기로는 좌표를 못 찾는
  /// 경우가 있고 방향은 둘 다 가능하다(2026-08-14 실사용 확인).
  String? _addressGeocodeFallback;

  // X 버튼으로 닫으려 할 때 "정말 취소할지" 물을지 판단하는 기준값 — 화면을
  // 열었을 때(수정이면 기존 명함 값, 신규면 빈 값) 스냅샷을 떠 두고, 닫기
  // 직전 각 필드와 비교한다. 신규 등록 중 아무것도 안 적고 바로 닫으면
  // 굳이 물어볼 필요가 없어서, 값이 하나라도 바뀐 경우에만 확인창을 띄운다.
  late final Map<String, String> _initialValues;
  late final String? _initialAvatarUrl;

  bool get _isEditing => widget.contactToEdit != null;

  // 이 명함의 주소가 지오코딩을 모두 실패해 좌표를 못 얻은 상태인지(P1-25).
  // true면 주소 필드 아래에 "주변 목록에 안 뜬다" 안내를 띄운다.
  bool _addressGeoFailed = false;

  // 명함 이미지 관련(추가 133, C안):
  // - _cardImagePath: 이미 저장된 암호화 명함 이미지 경로(편집 진입 시 로드).
  // - _scannedCardImages: 이번에 새로 스캔한 원본(임시) 경로들. 앞/뒷면을
  //   이어 스캔하면 2장 이상 쌓인다. hadName은 그 스캔에서 이름이 읽혔는지 —
  //   대표 이미지 기본 선택에 쓴다(보통 이름이 있는 면이 앞면).
  // - _selectedScanIndex: 위 목록에서 대표(저장 대상)로 고른 이미지.
  //   예전에는 마지막 스캔 한 장만 기억해서, 앞면→뒷면 순서로 스캔하면
  //   뒷면이 대표가 되고 바꿀 방법이 없었다(사용자 제보, 2026-08-10).
  // - _useCardAsAvatar: 목록 아바타로 명함 이미지를 쓸지(사용자 선택).
  String? _cardImagePath;
  final List<({String path, bool hadName})> _scannedCardImages = [];
  int _selectedScanIndex = -1;

  /// **직전 스캔이 실제로 채운 입력칸**들. 재촬영에서 그 칸만 비우고 다시
  /// 채우기 위해 기억한다.
  ///
  /// 초점이 안 맞거나 잘못 찍어서 **같은 면을 다시 찍고 싶은 경우**가 흔한데
  /// (사용자 제보 2026-08-14), 이걸 모르면 재촬영이 그냥 한 번 더 스캔한 것이
  /// 되어 값이 누적된다. 앞면 값은 지키고 방금 것만 되돌리려면 어느 칸이
  /// 방금 채워졌는지 알아야 한다.
  final Set<String> _lastScanFilledKeys = {};

  /// 이번 스캔에서 **충돌 선택으로 값이 바뀐 칸**의 바꾸기 전 값(F-01).
  ///
  /// `_lastScanFilledKeys`(비어 있던 칸을 채운 것)와 성격이 다르다. 저쪽은
  /// 재촬영 때 **비우면** 되지만, 이쪽은 원래 값이 있던 칸이라 비우면 앞면에서
  /// 읽은 값까지 사라진다 — **이전 값으로 되돌려야** 한다.
  final Map<String, ({String text, String? snapshot})> _lastScanReplacedValues =
      {};

  /// 이 명함을 지금까지 몇 번 스캔했는지(0=아직, 1=앞면, 2=앞+뒷면).
  ///
  /// **명함 한 장은 앞면과 뒷면까지가 최대 행동**이다(사용자 정의 2026-08-14).
  /// 그 전에는 횟수 개념이 없어 세 번, 네 번 찍으면 계속 누적됐고 "여기서
  /// 끝났다"는 지점도 없었다. 이 값으로 안내 문구와 초기화 시점을 정한다.
  int _scanCount = 0;

  /// "여기서 완료"로 스캔 흐름을 **끝냈는지**.
  ///
  /// 끝낸 뒤 사용자가 다시 촬영을 시작하면 그것은 **새 스캔 흐름**이다. 이
  /// 표시가 없으면 `_scanCount`가 그대로 남아 다음 촬영이 자동으로 "뒷면"으로
  /// 계산되고, 그래서 **뒷면 선택지가 사라진다** — 사용자 제보 "사진찍기 →
  /// 다시찍기 → 여기서완료 → 사진찍기 → 뒷면찍기가 없어짐"(2026-08-14).
  bool _scanSessionClosed = false;
  bool _useCardAsAvatar = false;

  /// 스캔 임시 파일을 **버릴 때** 지운다(추가 253).
  ///
  /// ## 왜 필요한가
  ///
  /// `_scannedCardImages`에 쌓이는 것은 **평문 명함 사진**이다. 저장본은
  /// AES-256-GCM으로 암호화하는데(`ContactImageService`) 그 원본이 캐시에
  /// 그대로 남으면 **암호화하는 이유 자체가 무력해진다.** 목록에서 빼는 것과
  /// 파일을 지우는 것은 다른 일인데, 여태 앞의 것만 하고 있었다.
  ///
  /// ⚠️ **저장이 끝난 뒤에만 부른다.** 저장은 화면이 닫히기 전에 이 경로를
  /// 읽어 암호화한다 — 미리 지우면 빈 파일을 읽는다. 그래서 부르는 자리는
  /// **버리는 것이 확정된 지점**뿐이다(재촬영 / 새 명함으로 시작 / 화면 닫힘).
  ///
  /// 던지지 않는다. 정리가 실패해도 등록은 계속돼야 한다.
  /// 세 번째 면이 들어왔을 때 묻는다(추가 293).
  ///
  /// ⚠️ **막지 않는다.** 접이식·부록면이 있는 명함도 있어서 세 장 이상이 늘
  /// 잘못은 아니다. 다만 **다른 사람 명함을 잘못 찍은 경우가 훨씬 흔하고**,
  /// 그때 그냥 저장되면 **남의 명함이 이 사람 명함으로 남는다.**
  Future<void> _askThirdFace() async {
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('면이 세 장이 됐어요'),
        content: const Text(
          '명함은 보통 앞면과 뒷면 두 장이에요.\n'
          '혹시 다른 사람 명함을 찍으셨나요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('방금 찍은 면 빼기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('그대로 두기'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // 대화상자를 그냥 닫으면(null) **빼지 않는다** — 사용자가 고르지 않은 것을
    // 지우는 쪽으로 해석하면 안 된다.
    if (keep == false) _removeScannedFace(_scannedCardImages.length - 1);
  }

  /// 스캔한 면 하나를 목록에서 뺀다(추가 293).
  ///
  /// ⚠️ **파일도 지운다.** 이건 제3자의 평문 명함 사진이라, 화면에서만 빼고
  /// 임시 파일을 남기면 그게 곧 우리가 닷새에 걸쳐 막은 그 문제다
  /// (추가 248·269·275).
  ///
  /// 📌 대표로 고른 면을 빼면 **첫 장이 대표가 된다** — 대표가 없는 상태를
  /// 만들지 않는다. 마지막 한 장까지 빼면 스캔 이미지가 없는 상태로 돌아간다.
  void _removeScannedFace(int index) {
    if (index < 0 || index >= _scannedCardImages.length) return;
    final removed = _scannedCardImages.removeAt(index);
    unawaited(deleteQuietly(removed.path));
    setState(() {
      if (_scannedCardImages.isEmpty) {
        _selectedScanIndex = -1;
      } else if (_selectedScanIndex == index) {
        _selectedScanIndex = 0;
      } else if (_selectedScanIndex > index) {
        _selectedScanIndex -= 1;
      }
    });
  }

  void _discardScanFiles(Iterable<String> paths) {
    for (final p in paths) {
      unawaited(deleteQuietly(p));
    }
  }

  /// 대표로 선택된 새 스캔 이미지의 경로. 새 스캔이 없으면 null.
  String? get _scannedCardImageSourcePath =>
      (_selectedScanIndex >= 0 &&
          _selectedScanIndex < _scannedCardImages.length)
      ? _scannedCardImages[_selectedScanIndex].path
      : null;

  @override
  void initState() {
    super.initState();
    final c = widget.contactToEdit ?? widget.prefillData;
    _selectedAvatarUrl = c?.avatarUrl;
    _cardImagePath = c?.cardImagePath;
    _useCardAsAvatar = c?.useCardAsAvatar ?? false;
    // 서버 복원을 거친 명함은 cardImagePath가 유실될 수 있다(백업 JSON에
    // 로컬 경로를 넣지 않으므로). 기기에 암호문 파일이 남아 있으면 다시
    // 이어준다 — 이게 없으면 수정 화면에서 명함 이미지와 "대표 이미지로
    // 사용" 토글이 통째로 안 보여, 나중에 대표로 지정할 방법이 없었다
    // (사용자 제보, 2026-08-11). 저장 시 이 경로가 다시 로컬에 기록된다.
    if (_cardImagePath == null && widget.contactToEdit != null) {
      ContactImageService()
          .findExistingCardImagePath(widget.contactToEdit!.id)
          .then((path) {
            if (path != null && mounted) {
              setState(() => _cardImagePath = path);
            }
          });
    }
    _nameController = TextEditingController(text: c?.name ?? '');
    _companyController = TextEditingController(text: c?.company ?? '');
    _titleController = TextEditingController(text: c?.title ?? '');
    _departmentController = TextEditingController(text: c?.department ?? '');
    _addressController = TextEditingController(text: c?.address ?? '');
    _addressDetailController = TextEditingController(
      text: c?.addressDetail ?? '',
    );
    _postalCodeController = TextEditingController(text: c?.postalCode ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _officePhoneController = TextEditingController(text: c?.officePhone ?? '');
    _directPhoneController = TextEditingController(text: c?.directPhone ?? '');
    _faxController = TextEditingController(text: c?.fax ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _websiteController = TextEditingController(text: c?.website ?? '');
    // ⚠️ 신규 등록의 기본값은 **빈 값**이어야 한다. 예전에는 `'AI, IT'`가
    // 박혀 있어서, 회계사 명함을 등록해도 태그에 `AI`·`IT`가 그대로 저장됐다
    // (테스터 제보 — 통합본 E-08). 데모용 더미값이 그대로 남아 있던 것이고,
    // "가짜 데이터를 만들지 않는다"(CLAUDE.md 4절)에 정면으로 걸린다.
    //
    // 태그가 틀리면 인맥 분류·검색·추천이 전부 어긋나는데, 사용자는 자기가
    // 넣은 값인 줄 알고 지우지 않는다. 무엇을 적는 칸인지는 입력칸 안내
    // 문구(`예: AI, 바이오, C-Level`)가 이미 알려 준다.
    _tagsController = TextEditingController(text: c?.tags.join(', ') ?? '');
    _interestsController = TextEditingController(
      text: c != null ? c.interests.join(', ') : '',
    );
    _memoController = TextEditingController(text: c?.memo ?? '');
    _fieldFocusOrder = [
      _nameFocusNode,
      _companyFocusNode,
      _titleFocusNode,
      _departmentFocusNode,
      _addressFocusNode,
      _addressDetailFocusNode,
      _postalCodeFocusNode,
      _phoneFocusNode,
      _officePhoneFocusNode,
      _directPhoneFocusNode,
      _faxFocusNode,
      _emailFocusNode,
      _websiteFocusNode,
      _tagsFocusNode,
      _interestsFocusNode,
      _memoFocusNode,
    ];
    // 입력 칸을 탭하면 키보드가 올라오는데, 포커스된 칸이 폼 아래쪽이면
    // 키보드에 가려 보이지 않던 문제(사용자 제보 2026-08-14). viewInsets 패딩만
    // 으로는 키보드 애니메이션 타이밍 때문에 기본 자동 스크롤이 어긋나므로,
    // 포커스를 얻으면 그 칸을 명시적으로 화면 안으로 끌어온다.
    for (final node in _fieldFocusOrder) {
      node.addListener(() => _ensureFocusedFieldVisible(node));
    }

    // 자동 인식 표시(F-09)를 감시한다. 키는 `_ocrParsedSnapshot`에 쓰는 것과
    // **정확히 같아야** 하며(파서가 채울 때 쓰는 키), 다르면 표시가 영영
    // 안 붙는다. 여기 없는 칸(태그·관심사·메모)은 파서가 채우지 않는다.
    _watchOcrBadge('name', _nameController);
    _watchOcrBadge('company', _companyController);
    _watchOcrBadge('title', _titleController);
    _watchOcrBadge('department', _departmentController);
    _watchOcrBadge('address', _addressController);
    _watchOcrBadge('addressDetail', _addressDetailController);
    _watchOcrBadge('postal', _postalCodeController);
    _watchOcrBadge('mobile', _phoneController);
    _watchOcrBadge('office', _officePhoneController);
    _watchOcrBadge('fax', _faxController);
    _watchOcrBadge('email', _emailController);
    _watchOcrBadge('website', _websiteController);
    WebTabGuard.install(onTab: (shiftKey) => _moveFocus(shiftKey ? -1 : 1));

    // 편집 중인 기존 명함이 주소 지오코딩을 모두 실패했는지 비동기로 확인해
    // 주소 필드 아래 안내를 띄운다(P1-25). 신규 등록/OCR 프리필은 아직 저장·
    // 재계산 전이라 대상이 아니다.
    final editing = widget.contactToEdit;
    if (editing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final failed = await context
            .read<ContactsRepository>()
            .hasAddressGeocodingFailed(editing);
        if (mounted) setState(() => _addressGeoFailed = failed);
      });
    }

    _initialAvatarUrl = _selectedAvatarUrl;
    _initialValues = {
      'name': _nameController.text,
      'company': _companyController.text,
      'title': _titleController.text,
      'department': _departmentController.text,
      'address': _addressController.text,
      'addressDetail': _addressDetailController.text,
      'postalCode': _postalCodeController.text,
      'phone': _phoneController.text,
      'officePhone': _officePhoneController.text,
      'directPhone': _directPhoneController.text,
      'fax': _faxController.text,
      'email': _emailController.text,
      'website': _websiteController.text,
      'tags': _tagsController.text,
      'interests': _interestsController.text,
      'memo': _memoController.text,
    };
  }

  @override
  void dispose() {
    // 화면이 닫히는 시점에 남아 있는 스캔 임시 파일을 전부 지운다(추가 253).
    //
    // 여기 하나로 세 경우가 함께 닫힌다:
    //
    // - **폼 취소** — 등록하지 않고 닫았으니 전부 버려진다
    // - **중복 병합**(`_applyUpdateToExisting`) — 기존 명함에 합치고 닫는다
    // - **고르지 않은 나머지 면** — 앞뒷면을 스캔해도 저장은 대표 한 장만
    //   가져간다. 나머지는 아무도 안 지우고 있었다
    //
    // 저장을 거친 경우 대표 한 장은 `ContactImageService`가 이미 지웠지만,
    // [deleteQuietly]는 없는 파일에 조용히 넘어가므로 겹쳐 불러도 안전하다.
    // 저장은 `Navigator.pop`보다 먼저 끝나므로 여기서 지워도 늦지 않다.
    _discardScanFiles(_scannedCardImages.map((e) => e.path));

    WebTabGuard.uninstall();
    _nameController.dispose();
    _companyController.dispose();
    _titleController.dispose();
    _departmentController.dispose();
    _addressController.dispose();
    _addressDetailController.dispose();
    _postalCodeController.dispose();
    _phoneController.dispose();
    _officePhoneController.dispose();
    _directPhoneController.dispose();
    _faxController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _tagsController.dispose();
    _interestsController.dispose();
    _memoController.dispose();

    _nameFocusNode.dispose();
    _companyFocusNode.dispose();
    _titleFocusNode.dispose();
    _departmentFocusNode.dispose();
    _addressFocusNode.dispose();
    _addressDetailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _officePhoneFocusNode.dispose();
    _directPhoneFocusNode.dispose();
    _faxFocusNode.dispose();
    _emailFocusNode.dispose();
    _websiteFocusNode.dispose();
    _tagsFocusNode.dispose();
    _interestsFocusNode.dispose();
    _memoFocusNode.dispose();
    super.dispose();
  }

  // _fieldFocusOrder 리스트 기준으로 현재 포커스된 필드를 찾아 delta칸 이동한다
  // (+1 = 정방향 Tab, -1 = Shift+Tab). 위젯 트리 순서나 브라우저 네이티브 DOM
  // 탭 순서와 무관하게 오직 이 리스트만이 이동 순서를 결정한다.
  void _moveFocus(int delta) {
    final currentIndex = _fieldFocusOrder.indexWhere((n) => n.hasFocus);
    if (currentIndex == -1) return;
    final nextIndex = currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= _fieldFocusOrder.length) {
      FocusScope.of(context).unfocus();
      return;
    }
    _fieldFocusOrder[nextIndex].requestFocus();
  }

  /// 두 촬영 경로를 뒤집는 스위치 — ⚠️ **debug 빌드에서만 보인다.**
  ///
  /// release·테스터 배포 빌드에는 **아예 없다**. 로그인 화면의 "로그인
  /// 건너뛰기"와 같은 취급이라, 이용자에게 보이는 촬영 진입점은 **그대로
  /// 하나**다(제품 원칙 2-3절 *"같은 일을 하는 진입점 세 개 이상"*에 안 걸린다).
  ///
  /// **왜 필요한가**: 2단계가 *"실제 명함 20~30장으로 둘을 나란히 재기"*인데,
  /// 상수 플래그만 두면 **명함 한 장마다 빌드를 다시 깔아야 해서** 나란히
  /// 비교가 안 된다. 이 스위치는 그 측정을 위한 도구다.
  ///
  /// 📌 **2단계가 끝나면 지운다.**
  /// ⚠️ **2단계 대조가 끝나면 지울 임시 스위치들이다.**
  ///
  /// 세 경로를 같은 기기에서 번갈아 재기 위해 있다. **재는 일이 끝나면
  /// 기본값 하나만 남기고 이 스위치들과 진 경로를 지운다** — 제품 원칙의
  /// *"같은 일을 하는 진입점 셋 이상은 만들지 않는다"*(추가 261)에 걸린다.
  ///
  /// release 빌드에는 안 보이므로 지금 사용자에게 닿지는 않는다. 다만
  /// **지우는 시점을 적어 두지 않으면 그대로 남는다.**
  ///
  /// | 스위치 | 끔 | 켬 |
  /// |---|---|---|
  /// | 촬영 경로 | 우리 촬영 화면 | A안 문서 스캐너 |
  /// | 테두리 검출 | **기존 고정 가이드**(예전 그대로) | **B′**(명함을 찾아 자름) |
  ///
  /// ⚠️ **`kDebugMode`가 아니라 `!kReleaseMode`**다. 아이폰 debug 빌드는
  /// 디버거 없이 뜨지 않아(2026-08-16 실측) **debug 전용이면 아이폰에서
  /// 스위치를 아예 쓸 수 없다.**
  Widget _buildDocScannerDebugSwitch() {
    if (kReleaseMode) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: docScannerCaptureEnabled,
      builder: (_, useDocScanner, _) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Switch(
              value: useDocScanner,
              onChanged: (v) => docScannerCaptureEnabled.value = v,
            ),
            Expanded(
              child: Text(
                useDocScanner ? '[측정] 촬영: A안 문서 스캐너' : '[측정] 촬영: 우리 화면',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ⚠️⚠️ **측정 전용 — backlog 277이 끝나면 통째로 지운다.**
  ///
  /// 켜면 촬영한 크롭본을 `card_samples`에 남긴다. 일괄 스캔이 그 폴더를
  /// 읽으므로, **같은 명함을 경로마다 찍어 나란히 채점**할 수 있게 된다.
  ///
  /// ⚠️ **평문 명함 사진이 기기에 쌓인다.** 우리가 닷새에 걸쳐 다섯 군데서
  /// 막은 바로 그것이라(아이폰 262.7MB · 안드로이드 204MB), **재는 동안만
  /// 켜고 끝나면 지운다.** release 빌드에서는 켜도 코드가 안 돈다.
  Widget _buildMeasureSampleSwitch() {
    if (!kDebugMode) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: cardCropKeepForMeasurement,
      builder: (_, keep, _) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Switch(
              value: keep,
              onChanged: (v) => cardCropKeepForMeasurement.value = v,
            ),
            Expanded(
              child: Text(
                keep ? '[측정] ⚠️ 크롭본 남기는 중(평문)' : '[측정] 크롭본 안 남김',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 테두리 검출(B′) 켜기/끄기 — ⚠️ **2단계 대조용 임시 스위치.**
  ///
  /// 끄면 **검출 코드가 아예 안 돈다.** 프레임도 안 보내고 테두리도 안 그리며,
  /// 자르기도 기존 고정 가이드 상자로 간다 — **경로 자체가 예전이 된다.**
  /// 그래야 나란히 재는 것이 뜻이 있다.
  ///
  /// 📌 되돌림 장치이기도 하다. 실기기에서 문제가 나면 코드를 되돌리기 전에
  /// 이 스위치부터 내려 확인할 수 있다.
  Widget _buildCardRectDebugSwitch() {
    if (kReleaseMode) return const SizedBox.shrink();
    // ⚠️ 스위치를 둘로 갈랐다(추가 293). 예전에는 하나가 **검출과 자르기를
    // 같이** 켜서, *"빈 화면 촬영만 막고 자르기는 예전 것"*이 불가능했다.
    return Column(
      children: [
        _debugToggle(
          notifier: cardRectDetectionEnabled,
          onLabel: '[측정] 검출: 켬 (빈 화면·손 자동촬영 막기)',
          offLabel: '[측정] 검출: 끔 (막지 않음)',
        ),
        _debugToggle(
          notifier: cardRectCropEnabled,
          onLabel: '[측정] 자르기: B′ 테두리',
          offLabel: '[측정] 자르기: 기존 고정 가이드',
        ),
      ],
    );
  }

  Widget _debugToggle({
    required ValueNotifier<bool> notifier,
    required String onLabel,
    required String offLabel,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (_, value, _) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Switch(value: value, onChanged: (v) => notifier.value = v),
            Expanded(
              child: Text(
                value ? onLabel : offLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 기성 문서 스캐너로 찍고 인식까지 한다(추가 266, 1단계).
  ///
  /// 기존 촬영 화면([CameraScanModalView])은 **자기 안에서 인식까지 마치고**
  /// [OcrScanResult]를 `pop`으로 돌려준다. 이 경로에는 우리 화면이 없으므로
  /// **여기서 같은 일을 한다** — 돌려주는 값의 모양이 같아야 부르는 쪽을
  /// 갈라놓지 않는다.
  ///
  /// 사용자가 취소하면 `null`.
  ///
  /// ⚠️ **평문 사진을 새게 두지 않는다.** 인식까지 못 간 사진은 넘겨줄 곳이
  /// 없으므로 여기서 지운다 — 기존 경로가 인식 실패 시 크롭본을 지우는 것과
  /// 같은 자리다(추가 253). 인식에 성공하면 그 파일은 저장 쪽이 넘겨받으므로
  /// **여기서 지우면 안 된다.**
  Future<OcrScanResult?> _scanWithDocScanner() async {
    setState(() => _isScanningOcr = true);
    // 지울 책임이 아직 우리에게 있는 파일. 넘겨준 뒤에는 null로 비운다.
    String? orphanPath;
    try {
      final capture = await DocScannerCaptureService.capture();
      if (capture == null) return null; // 사용자가 스캐너를 닫았다.
      orphanPath = capture.path;
      final scanned = await OcrScannerService.scanBusinessCard(
        XFile(capture.path),
      );
      orphanPath = null; // 인식 성공 — 이제 저장 쪽이 이 파일의 주인이다.
      return scanned;
    } catch (e) {
      if (!mounted) return null;
      // 권한 거부는 "실패"가 아니라 사용자가 막은 것이라 문구를 따로 준다 —
      // "인식에 실패했습니다"만 보면 무엇을 해야 할지 알 수 없다.
      final denied =
          e is CunningDocumentScannerException && e.code == 'permission_denied';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            denied
                ? '⚠️ 카메라 권한이 없어 명함을 촬영할 수 없습니다. 설정에서 권한을 켜 주세요.'
                : '⚠️ 명함 인식에 실패했습니다: $e',
          ),
          backgroundColor: AppColors.destructive,
        ),
      );
      return null;
    } finally {
      await deleteQuietly(orphanPath);
      if (mounted) setState(() => _isScanningOcr = false);
    }
  }

  /// AI OCR Business Card Scanner (Camera / Image Gallery)
  Future<void> _performOcrScan({
    required bool isFromCamera,

    /// 지금 찍는 면. 카메라 화면에 그대로 표시된다(추가 191).
    String sideLabel = '앞면',
  }) async {
    OcrScanResult? result;

    if (isFromCamera) {
      if (docScannerCaptureEnabled.value) {
        // 새 촬영 경로(추가 266, 1단계). 기성 문서 스캐너가 **가이드 상자가
        // 아니라 명함 테두리**를 찾아 잘라 준다. 돌려주는 값의 모양이 같아서
        // 아래 흐름(충돌 감지·필드 채움·사진 목록·저장)은 그대로 돈다.
        result = await _scanWithDocScanner();
      } else {
        // Open camera scanner view with viewfinder shutter
        result = await Navigator.push<OcrScanResult>(
          context,
          MaterialPageRoute(
            builder: (_) => CameraScanModalView(sideLabel: sideLabel),
          ),
        );
      }
    } else {
      // Open interactive gallery / file explorer picker view
      result = await showModalBottomSheet<OcrScanResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FilePickerModalView(sideLabel: sideLabel),
      );
    }

    if (result == null || !mounted) return;

    // 이미 이름이 채워져 있는데 새로 스캔한 이름이 다르면, 같은 명함의
    // 뒷면이 아니라 완전히 "다른 명함"을 스캔한 것으로 본다 — 이 경우
    // 그대로 fill-if-empty만 하면 새 명함 정보가 하나도 안 들어가고
    // 조용히 무시되는 문제가 있었다(사용자 제보: "다른 명함을 스캔하면
    // 필드가 변경되지 않네"). 덮어쓸지, 기존처럼 빈 칸만 채울지 사용자에게
    // 물어본다.
    final existingName = _nameController.text.trim();
    final scannedName = result.name.trim();
    // 이름만 보면 앞면에서 이름을 못 읽었을 때 감지가 아예 안 된다 —
    // 휴대폰·이메일까지 본다(ScanConflict 주석 참고, backlog 추가 189).
    final looksLikeDifferentCard = ScanConflict.looksLikeDifferentCard(
      existingName: existingName,
      scannedName: scannedName,
      existingPhone: _phoneController.text,
      scannedPhone: result.phone,
      existingEmail: _emailController.text,
      scannedEmail: result.email,
    );

    var overwrite = false;
    if (looksLikeDifferentCard) {
      final choice = await _showDifferentCardScannedDialog(
        existingName: existingName,
        scannedName: scannedName,
      );
      if (!mounted) return;
      if (choice == null) return; // 대화상자 닫힘 — 아무것도 안 바꾸고 그대로 둔다.
      overwrite = choice;
    }

    // 스캔 결과가 실제로 어느 필드에 "새로" 들어갈지는 지금(덮어쓰기 여부 +
    // 각 칸이 비어 있었는지)으로 결정된다. 파서가 채운 값만 스냅샷에 남겨
    // 저장 시점에 사용자가 고쳤는지 비교한다(값은 집계로 안 넘어감).
    final fieldSources = <String, (TextEditingController, String)>{
      'name': (_nameController, result.name),
      'company': (_companyController, result.company),
      'title': (_titleController, result.title),
      'department': (_departmentController, result.department),
      'address': (_addressController, result.address),
      'addressDetail': (_addressDetailController, result.addressDetail),
      'postal': (_postalCodeController, result.postalCode),
      'mobile': (_phoneController, result.phone),
      'office': (_officePhoneController, result.officePhone),
      'fax': (_faxController, result.fax),
      'email': (_emailController, result.email),
      'website': (_websiteController, result.website),
    };
    fieldSources.forEach((key, src) {
      final (controller, parsedValue) = src;
      final wasEmpty = controller.text.trim().isEmpty;
      // 덮어쓰기면 파서 값이 그 칸을 차지한다. 채우기(fill-if-empty)면 비어
      // 있던 칸에만 들어간다. 어느 쪽이든 파서가 준 값이 실제로 들어간
      // 경우만 스냅샷에 남긴다.
      final landed = (overwrite || wasEmpty) && parsedValue.trim().isNotEmpty;
      if (landed) _ocrParsedSnapshot[key] = parsedValue.trim();
    });

    // 이번 스캔이 어느 칸을 채웠는지 기억해 둔다(재촬영에서 되돌릴 대상).
    // 충돌 선택으로 바뀐 칸은 아래에서 다시 채워진다.
    _lastScanReplacedValues.clear();
    _lastScanFilledKeys
      ..clear()
      ..addAll(
        fieldSources.entries
            .where((e) {
              final (controller, parsedValue) = e.value;
              return (overwrite || controller.text.trim().isEmpty) &&
                  parsedValue.trim().isNotEmpty;
            })
            .map((e) => e.key),
      );
    // 파싱 형태(내용 없음)를 집계에 더한다 — fire-and-forget.
    final shape = result.parseShape;
    if (shape != null) {
      unawaited(_ocrStats.recordParse(shape));
    }

    setState(() {
      _isScanningOcr = false;
      _showRawTextCard = true;
      // RAW 텍스트 박스는 "방금 스캔한 사진에서 뭘 읽었는지" 확인용이라 앞/뒷면을
      // 여러 번 스캔해도 누적시키지 않고 가장 최근 스캔 결과만 보여준다 — 계속
      // 이어붙이면 같은 면을 다시 스캔했을 때 중복 텍스트가 끝없이 쌓여 오히려
      // 확인하기 어려워짐(폼 필드 자체는 아래에서 이미 누적되고 있음).
      _scannedRawText = result!.rawText;
      // ⚠️ **명함에 인쇄된 구분자에서 쪼갠다** (2026-08-19, 추가 325).
      //
      // 예전에는 원문 줄을 그대로 칩으로 깔았다. 그런데 한 줄에 둘이 들어 있는
      // 명함이 흔하다(`A아키텍처팀 | 선임 Architect`). 그러면 **어느 칸으로
      // 보내도 나머지가 딸려 가서**, 퀵 매핑으로 고칠 수가 없었다.
      //
      // 📌 **파서 판단으로 나누지 않는다.** 파서가 놓친 값(실측 미검출 23건)은
      // 조각으로도 안 나오게 되므로, **원문이 안전망 노릇을 못 하게 된다.**
      // 명함에 **실제로 인쇄된 구분자**에서만 자른다.
      //
      // ⚠️ **공백·한글↔영문 경계로는 안 자른다.** 실측 103장으로 재 봤다
      // (추가 325). 구분자만 쓰면 칩이 평균 8.2 → 9.6개로 거의 그대로인데,
      // 한글↔영문 경계까지 자르면 **평균 24개 · 최대 147개**가 되어 화면을
      // 뒤덮는다. 주소 줄(`07795 서울특별시 강서구 …`)이 조각조각 나는데,
      // 정작 주소는 통째로 옮겨야 하는 값이다.
      _scannedRawLines = _splitScannedLines(result.rawLines);
      if (overwrite) {
        // 다른 명함으로 새로 시작하는 것이므로 **이전 명함의 흔적을 전부**
        // 지운다. 예전에는 입력칸 9개만 새로 쓰고 아래 값들이 남아서, 새
        // 명함을 저장하는데 **좌표가 이전 명함 주소로 잡히는** 일이 가능했다
        // (backlog 추가 189).
        // 앞 명함의 사진은 여기서 확실히 버려진다 — 파일도 함께 지운다
        // (추가 253). 목록만 비우면 평문 사진이 캐시에 남았다.
        _discardScanFiles(_scannedCardImages.map((e) => e.path));
        _scannedCardImages.clear();
        _selectedScanIndex = -1;
        _ocrParsedSnapshot.clear();
        _confirmedRoadNameAddress = null;
        _addressGeocodeFallback = null;
        _addressGeoFailed = false;
        _interestsController.clear();
        _scanCount = 0;
        _scanSessionClosed = false;
      }
      // 스캔한 명함 이미지를 대표 후보 목록에 쌓는다(추가 133). 기본 대표는
      // "이름이 읽힌 면"(보통 앞면) — 예전에는 무조건 마지막 스캔이 대표가
      // 돼서 앞면→뒷면 순서로 스캔하면 뒷면이 대표가 되고 바꿀 수도 없었다.
      // 두 장 이상이면 미리보기 아래 썸네일로 직접 바꿀 수 있다.
      if (result.imagePath != null && result.imagePath!.isNotEmpty) {
        final hadName = scannedName.isNotEmpty;
        _scannedCardImages.add((path: result.imagePath!, hadName: hadName));
        final currentHadName =
            _selectedScanIndex >= 0 &&
            _scannedCardImages[_selectedScanIndex].hadName;
        if (_selectedScanIndex < 0 || (hadName && !currentHadName)) {
          _selectedScanIndex = _scannedCardImages.length - 1;
        }
        // 신규 등록에서 명함을 촬영했으면 "대표 이미지로 사용"을 기본 켠다
        // (사용자 요청, 2026-08-11). 예전엔 기본 꺼짐이라, 등록 때 안 켜면
        // 목록에서 명함 사진이 안 보였고 나중에 켜는 방법도 찾기 어려웠다.
        // 첫 장에서만 켜고 이후엔 손대지 않는다 — 사용자가 직접 껐다면
        // 뒷면을 추가 스캔해도 그 선택을 뒤집지 않기 위함. 기존 명함
        // 편집(contactToEdit != null)에서는 저장된 선택을 존중한다.
        if (widget.contactToEdit == null && _scannedCardImages.length == 1) {
          _useCardAsAvatar = true;
        }
      }
      if (overwrite) {
        _setTextFromStart(_nameController, result.name);
        _setTextFromStart(_companyController, result.company);
        _setTextFromStart(_titleController, result.title);
        _setTextFromStart(_departmentController, result.department);
        _setTextFromStart(_addressController, result.address);
        _setTextFromStart(_addressDetailController, result.addressDetail);
        _setTextFromStart(_postalCodeController, result.postalCode);
        _setTextFromStart(_phoneController, result.phone);
        _setTextFromStart(_officePhoneController, result.officePhone);
        _setTextFromStart(_faxController, result.fax);
        _setTextFromStart(_emailController, result.email);
        _setTextFromStart(_websiteController, result.website);
        _tagsController.text = result.tags.join(', ');
        // ⚠️ 메모 칸은 **비운 채로 둔다.** 예전에는 여기에 "AI OCR 스캔으로 자동
        // 추출된 명함 텍스트 정보입니다."를 넣었는데, 그건 사용자가 쓰지 않은
        // 문장이 사용자 메모로 저장되는 것이라 E-08(태그 기본값 `AI, IT`)과
        // 같은 유형의 가짜 데이터였다(CLAUDE.md 4절).
        //
        // 실제 피해도 있었다 — 이 문장이 AI 브리핑 요청에 `메모:`로 그대로
        // 실려 나갔다(2026-08-15 실기기에서 확인). 아무 정보도 없는 문장에
        // 토큰을 쓰고, AI는 그걸 이 사람에 대한 맥락으로 읽는다.
        _memoController.text = '';
      } else {
        // 명함 앞/뒷면에 정보가 나뉘어 있는 경우가 흔해서(예: 앞면엔 이름·직함만,
        // 뒷면에 전화번호·주소·이메일) 새 스캔 결과로 폼을 통째로 덮어쓰지 않고
        // "이미 채워진 필드는 그대로 두고, 비어 있는 필드만" 채운다 — 뒷면을
        // 이어서 스캔해도 앞면에서 읽은 값이 날아가지 않게.
        _fillIfEmpty(_nameController, result.name);
        _fillIfEmpty(_companyController, result.company);
        _fillIfEmpty(_titleController, result.title);
        _fillIfEmpty(_departmentController, result.department);
        _fillIfEmpty(_addressController, result.address);
        _fillIfEmpty(_addressDetailController, result.addressDetail);
        _fillIfEmpty(_postalCodeController, result.postalCode);
        _fillIfEmpty(_phoneController, result.phone);
        _fillIfEmpty(_officePhoneController, result.officePhone);
        _fillIfEmpty(_faxController, result.fax);
        _fillIfEmpty(_emailController, result.email);
        _fillIfEmpty(_websiteController, result.website);
        if (_tagsController.text.trim().isEmpty && result.tags.isNotEmpty) {
          _tagsController.text = result.tags.join(', ');
        }
        // 메모는 채우지 않는다 — 위 `overwrite` 분기와 같은 이유다.
      }
    });

    // ⚠️ **명함은 앞뒤 두 면이다**(추가 293, 사용자 지적).
    //
    // 세 번째 면이 들어오면 **다른 명함을 잘못 찍었을 가능성이 높다.** 실제로
    // 그런 일이 있었고, 그때는 뺄 방법도 없어 남의 명함이 그대로 저장될 뻔했다.
    //
    // 📌 **막지 않고 묻는다.** 앞뒤가 아니라 접이식·부록면이 있는 명함도 있어서
    // 세 장 이상이 늘 잘못은 아니다. 고르는 것은 사용자다.
    if (_scannedCardImages.length >= 3) {
      await _askThirdFace();
    }

    // F-01 — 이미 값이 있는 칸에 **다른 값**이 들어온 경우를 사용자 눈앞에
    // 꺼낸다. 위 `_fillIfEmpty`는 빈 칸만 채우므로, 앞면에서 읽은 칸에 뒷면이
    // 다른 값을 읽어 오면 그 값이 **조용히 버려졌다.** 사용자는 그런 값이
    // 있었다는 사실조차 몰랐다(앞면 휴대폰 / 뒷면 대표번호가 흔한 예다).
    //
    // 덮어쓰기(`새 명함으로 시작`)는 이미 사용자가 "전부 새 값"을 고른 것이라
    // 다시 묻지 않는다.
    if (!overwrite) {
      await _resolveScanFieldConflicts(result);
      if (!mounted) return;
    }

    final missingFields = <String>[
      if (_nameController.text.trim().isEmpty) '이름',
      if (_companyController.text.trim().isEmpty) '회사명',
      if (_addressController.text.trim().isEmpty) '주소',
      if (_phoneController.text.trim().isEmpty) '휴대폰 번호',
      if (_emailController.text.trim().isEmpty) '이메일',
    ];

    if (!mounted) return;
    // "여기서 완료" 뒤에 다시 찍기 시작했다면 새 흐름이다 — 앞면부터 다시 센다.
    if (_scanSessionClosed) {
      _scanCount = 0;
      _scanSessionClosed = false;
    }
    _scanCount = overwrite ? 1 : _scanCount + 1;

    _showInlineNotice(
      missingFields.isEmpty
          ? '📸 스캔한 내용으로 채웠습니다. AI 인식이 완벽하지 않을 수 있으니 아래 정보를 확인해 주세요.'
          : '⚠️ ${missingFields.join(', ')} 정보를 찾지 못했습니다. 명함 뒷면에 있을 수도 있어요.',
      isError: missingFields.isNotEmpty,
    );

    await _askNextScanStep(isFromCamera: isFromCamera, missing: missingFields);
  }

  /// 이번 스캔이 **이미 채워져 있던 칸**에 다른 값을 들고 온 경우, 칸마다
  /// 어느 값을 쓸지 고르게 한다(F-01).
  ///
  /// 부딪히는 칸이 하나도 없으면 아무것도 묻지 않는다 — 대부분의 뒷면 스캔은
  /// 빈 칸만 채우므로 이 물음이 뜨지 않는다.
  Future<void> _resolveScanFieldConflicts(OcrScanResult result) async {
    // 칸마다 "무엇을 같은 값으로 볼지"가 다르다. 전화는 구분자를, 이름은
    // 음절 사이 공백을, 이메일은 대소문자를 무시한다.
    const fields = <(String key, String label, ScanValueKind kind)>[
      ('name', '이름', ScanValueKind.name),
      ('company', '회사명', ScanValueKind.text),
      ('title', '직함', ScanValueKind.text),
      ('department', '부서', ScanValueKind.text),
      ('address', '회사 주소', ScanValueKind.text),
      ('addressDetail', '상세주소', ScanValueKind.text),
      ('postal', '우편번호', ScanValueKind.text),
      ('mobile', '휴대폰 번호', ScanValueKind.phone),
      ('office', '사무실 전화번호', ScanValueKind.phone),
      ('email', '이메일', ScanValueKind.email),
    ];
    final scannedValues = <String, String>{
      'name': result.name,
      'company': result.company,
      'title': result.title,
      'address': result.address,
      'addressDetail': result.addressDetail,
      'postal': result.postalCode,
      'mobile': result.phone,
      'office': result.officePhone,
      'email': result.email,
    };

    final conflicts = <ScanFieldConflict>[];
    for (final (key, label, kind) in fields) {
      final controller = _controllerFor(key);
      if (controller == null) continue;
      final current = controller.text;
      final scanned = scannedValues[key] ?? '';
      if (!ScanConflict.valuesConflict(
        existing: current,
        scanned: scanned,
        kind: kind,
      )) {
        continue;
      }
      conflicts.add(
        ScanFieldConflict(
          key: key,
          label: label,
          currentValue: current.trim(),
          scannedValue: scanned.trim(),
        ),
      );
    }
    if (conflicts.isEmpty) return;

    final picked = await showScanFieldConflictSheet(
      context,
      conflicts: conflicts,
    );
    if (!mounted || picked == null || picked.isEmpty) return;

    setState(() {
      picked.forEach((key, value) {
        final controller = _controllerFor(key);
        if (controller == null) return;
        // 재촬영은 "방금 스캔이 바꾼 것"을 되돌리는 동작이다. 여기서 바뀐 칸은
        // **비우는 것이 아니라 이전 값으로 돌려놓아야** 앞면에서 읽은 값이
        // 날아가지 않는다. 그래서 바꾸기 전 값을 들고 있는다.
        _lastScanReplacedValues[key] = (
          text: controller.text,
          snapshot: _ocrParsedSnapshot[key],
        );
        _setTextFromStart(controller, value);
        // 파서가 준 값이 실제로 이 칸에 들어갔으므로 스냅샷에도 남긴다 —
        // 저장 시점에 "사용자가 고쳤는지"를 이 값과 비교해 판단한다.
        _ocrParsedSnapshot[key] = value;
      });
    });
  }

  /// 스캔 한 번이 끝날 때마다 **다음에 무엇을 할지** 묻는다.
  ///
  /// **명함 한 장은 앞면과 뒷면까지가 최대 행동**이다(사용자 정의 2026-08-14).
  /// 예전에는 이 물음이 없어서 "여기서 끝났다"는 지점이 없었고, 필수 항목이
  /// 비었을 때만 "뒷면도 스캔해 보세요" 안내가 떴다. 다 채워졌으면 아무것도
  /// 묻지 않아 사용자가 뒷면을 찍어야 할지 판단할 근거가 없었다.
  ///
  /// **재촬영**도 여기 있다 — 초점이 안 맞거나 잘못 찍는 일이 흔한데, 그냥 다시
  /// 찍으면 값이 **누적**됐다(사용자 제보). 재촬영은 방금 스캔이 채운 칸만
  /// 되돌리고 다시 채운다.
  Future<void> _askNextScanStep({
    required bool isFromCamera,
    required List<String> missing,
  }) async {
    final isBackDone = _scanCount >= 2;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.cardSurface,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBackDone ? '앞면과 뒷면을 모두 스캔했습니다' : '다음으로 무엇을 할까요?',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  missing.isEmpty
                      ? '명함 한 장은 앞면과 뒷면까지 스캔할 수 있습니다.'
                      : '${_withObjectParticle(missing.join(', '))} 찾지 못했습니다. 뒷면에 있을 수 있습니다.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                if (!isBackDone)
                  ListTile(
                    minTileHeight: 56,
                    leading: const Icon(
                      Icons.flip_to_back,
                      color: AppColors.accentText,
                    ),
                    title: Text(isFromCamera ? '뒷면 촬영' : '뒷면 이미지 선택'),
                    subtitle: const Text('지금 채워진 값은 그대로 두고 빈 칸만 채웁니다'),
                    onTap: () => Navigator.of(sheetContext).pop('back'),
                  ),
                ListTile(
                  minTileHeight: 56,
                  leading: const Icon(
                    Icons.refresh,
                    color: AppColors.accentText,
                  ),
                  // 촬영으로 들어왔는지 업로드로 들어왔는지에 따라 말이 다르다 —
                  // 업로드인데 "다시 찍기"라고 하면 사용자는 카메라가 열릴 줄 안다.
                  title: Text(isFromCamera ? '다시 찍기' : '다른 이미지 선택'),
                  subtitle: Text(
                    isFromCamera
                        ? '방금 스캔으로 채워진 값을 지우고 이 면을 다시 찍습니다'
                        : '방금 스캔으로 채워진 값을 지우고 이미지를 다시 고릅니다',
                  ),
                  onTap: () => Navigator.of(sheetContext).pop('retake'),
                ),
                ListTile(
                  minTileHeight: 56,
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.accentText,
                  ),
                  title: const Text('여기서 완료'),
                  subtitle: const Text('스캔을 끝내고 내용을 확인·수정합니다'),
                  onTap: () => Navigator.of(sheetContext).pop('done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == 'done') _scanSessionClosed = true;
    if (!mounted || choice == null || choice == 'done') return;

    // 뒷면을 고르면 카메라 화면도 "뒷면"으로 연다. 재촬영은 방금 찍던 면을
    // 그대로 다시 찍는 것이므로 현재 면 라벨을 유지한다.
    final nextLabel = choice == 'back' ? '뒷면' : _currentSideLabel;

    if (choice == 'retake') {
      setState(() {
        // 방금 스캔이 채운 칸만 비운다 — 앞면에서 읽은 값은 지킨다.
        for (final key in _lastScanFilledKeys) {
          _controllerFor(key)?.clear();
          _ocrParsedSnapshot.remove(key);
        }
        _lastScanFilledKeys.clear();
        // 충돌 선택으로 바뀐 칸은 **비우지 않고 이전 값으로 되돌린다**(F-01).
        // 비우면 앞면에서 읽은 값까지 함께 사라진다.
        _lastScanReplacedValues.forEach((key, previous) {
          final controller = _controllerFor(key);
          if (controller != null) {
            _setTextFromStart(controller, previous.text);
          }
          final snapshot = previous.snapshot;
          if (snapshot == null) {
            _ocrParsedSnapshot.remove(key);
          } else {
            _ocrParsedSnapshot[key] = snapshot;
          }
        });
        _lastScanReplacedValues.clear();
        // 방금 찍은 사진도 후보에서 뺀다. 파일도 함께 지운다(추가 253) —
        // 다시 찍는 것이므로 그 사진은 확실히 안 쓰인다. 한 번 등록하면서
        // 여러 번 재촬영할 수 있어, 화면이 닫힐 때까지 미루면 그동안 평문
        // 사진이 장마다 쌓인다.
        if (_scannedCardImages.isNotEmpty) {
          _discardScanFiles([_scannedCardImages.last.path]);
          _scannedCardImages.removeLast();
          _selectedScanIndex = _scannedCardImages.isEmpty
              ? -1
              : _scannedCardImages.length - 1;
        }
        _scanCount = _scanCount > 0 ? _scanCount - 1 : 0;
      });
    }
    await _performOcrScan(isFromCamera: isFromCamera, sideLabel: nextLabel);
  }

  /// 지금 찍고 있는 면. 스캔 횟수로 판단한다 — 아직 한 번도 안 찍었거나
  /// 재촬영이면 앞면, 앞면을 마쳤으면 뒷면이다.
  String get _currentSideLabel => _scanCount >= 1 ? '뒷면' : '앞면';

  /// 목적격 조사를 받침에 맞춰 붙인다("주소를", "이메일을").
  ///
  /// "주소을(를)"처럼 괄호로 두 개를 다 보여주면 기계가 쓴 문장처럼 읽힌다.
  /// 마지막 글자의 받침만 보면 되므로 규칙이 단순하다 — 한글이 아니면
  /// 판단할 근거가 없어 "를"을 쓴다(영문 단어 뒤에는 그쪽이 자연스럽다).
  static String _withObjectParticle(String word) {
    if (word.isEmpty) return word;
    final last = word.characters.last;
    final code = last.runes.first;
    if (code < 0xAC00 || code > 0xD7A3) return '$word를';
    final hasBatchim = (code - 0xAC00) % 28 != 0;
    return '$word${hasBatchim ? '을' : '를'}';
  }

  /// 스캔 결과 키(`name`·`company` …)에 해당하는 입력칸. 재촬영에서 되돌릴 때
  /// 쓴다.
  TextEditingController? _controllerFor(String key) => switch (key) {
    'name' => _nameController,
    'company' => _companyController,
    'title' => _titleController,
    'address' => _addressController,
    'addressDetail' => _addressDetailController,
    'postal' => _postalCodeController,
    'mobile' => _phoneController,
    'office' => _officePhoneController,
    'email' => _emailController,
    _ => null,
  };

  void _showQuickFieldMapperSheet(String text) {
    // ⚠️ **키보드를 먼저 내린다** (사용자 관찰, 2026-08-19).
    //
    // 칸에 커서가 있는 상태에서 칩을 누르면 키보드가 올라와 있는데, 그러면
    // 시트가 **키보드 뒤로 들어가거나 화면 밖으로 밀린다.** 실제로 실기기에서
    // "칩을 눌러도 아무 일이 없다"로 보였다.
    //
    // 📌 값을 칸에 넣는 것이 이 시트의 일이라, 여는 시점에 커서가 있는 것이
    // 오히려 정상이다 — 그래서 **드물게 나는 상황이 아니라 흔한 상황**이다.
    FocusScope.of(context).unfocus();

    showModalBottomSheet(
      context: context,
      // 이 화면에서 **잘 뜨는** 카메라 스캔 시트와 같은 설정으로 맞춘다(:722).
      // 없으면 높이가 화면의 9/16로 묶여, 칸이 12개로 늘어난 지금은 내용이
      // 잘릴 수 있다 — release에서는 경고 없이 잘린다.
      isScrollControlled: true,
      backgroundColor: AppColors.bgBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            // ⚠️ 키보드가 아직 남아 있어도 내용이 가려지지 않게 그만큼 띄운다.
            // `unfocus()`가 즉시 반영되지 않는 순간이 있다.
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.touch_app,
                      color: AppColors.accentText,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '\'$text\' — 어느 칸으로?',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '이 줄을 어느 칸으로 보낼까요? 고른 칸에 그대로 들어갑니다.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _quickMapTile('👤 성명 (이름)', () {
                      _setTextFromStart(_nameController, text);
                    }),
                    _quickMapTile('🏢 회사명', () {
                      _setTextFromStart(_companyController, text);
                    }),
                    // 2026-08-19(추가 324): 부서 칸을 만들면서 이 통로를 빠뜨렸다.
                    // ⚠️ **이 통로가 없으면 부서 칸은 파서가 맞힐 때만 채워진다.**
                    // 실측에서 남은 오류의 성격이 "자리 바꿔 앉기"라, 사용자가
                    // 손으로 옮기는 길이 파서 규칙보다 값이 크다(추가 323).
                    _quickMapTile('🗂 부서', () {
                      _setTextFromStart(_departmentController, text);
                    }),
                    _quickMapTile('💼 직함', () {
                      _setTextFromStart(_titleController, text);
                    }),
                    _quickMapTile('📞 휴대폰 번호', () {
                      _setPhoneFromStart(_phoneController, text);
                    }),
                    // 2026-08-19(추가 324): 아래 다섯은 **통로가 없었다.**
                    //
                    // 실측 82장에서 상세주소 12 · 팩스 10 · 사무실 7 · 우편번호 3
                    // = **32건이 손으로 고칠 길조차 없었다**(전체 127건의 25%).
                    // 파서가 못 고치는 값을 사람이 옮기는 것이 이 시트의 일인데,
                    // 정작 갈 자리가 없으면 시트를 열어도 소용이 없다.
                    _quickMapTile('☎️ 사무실 전화', () {
                      _setPhoneFromStart(_officePhoneController, text);
                    }),
                    _quickMapTile('📠 팩스', () {
                      _setPhoneFromStart(_faxController, text);
                    }),
                    _quickMapTile('✉️ 이메일', () {
                      _setTextFromStart(_emailController, text);
                    }),
                    _quickMapTile('🌐 홈페이지', () {
                      _setTextFromStart(_websiteController, text);
                    }),
                    _quickMapTile('📍 주소', () {
                      _setTextFromStart(_addressController, text);
                    }),
                    _quickMapTile('🏠 상세주소', () {
                      _setTextFromStart(_addressDetailController, text);
                    }),
                    _quickMapTile('📮 우편번호', () {
                      _setTextFromStart(_postalCodeController, text);
                    }),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _quickMapTile(String label, VoidCallback onSelect) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
      ),
      backgroundColor: AppColors.bgBase,
      side: const BorderSide(color: AppColors.borderSubtle),
      onPressed: () {
        setState(() {
          onSelect();
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $label 항목에 세팅되었습니다!'),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.accentText,
          ),
        );
      },
    );
  }

  /// 이름이 이미 채워진 상태에서 다른 이름의 명함을 스캔했을 때 묻는다.
  /// true = 새 명함으로 전체 덮어쓰기, false = 기존처럼 빈 칸만 채우기
  /// (뒷면 이어서 스캔), null = 사용자가 그냥 닫음(아무 것도 안 바꿈).
  Future<bool?> _showDifferentCardScannedDialog({
    required String existingName,
    required String scannedName,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '다른 명함을 스캔하셨나요?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '입력 중이던 "$existingName" 님과 이름이 달라요("$scannedName").\n'
          '같은 명함의 뒷면이면 "뒷면 이어서" 를, 아예 다른 명함이면\n'
          '"새 명함으로 시작" 을 선택해 주세요.',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '뒷면 이어서',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '새 명함으로 시작',
              style: TextStyle(
                color: AppColors.accentText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ScaffoldMessenger 대신 폼 안에 직접 그리는 안내 배너 — 위쪽 설명 참고.
  void _showInlineNotice(
    String text, {
    required bool isError,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    setState(() {
      _inlineNoticeText = text;
      _inlineNoticeIsError = isError;
      _inlineNoticeActionLabel = actionLabel;
      _inlineNoticeAction = onAction;
    });
  }

  void _dismissInlineNotice() {
    setState(() {
      _inlineNoticeText = null;
      _inlineNoticeAction = null;
      _inlineNoticeActionLabel = null;
    });
  }

  Future<void> _openAddressSearch({String? initialQuery}) async {
    // 검색 화면 진입 시점에 이미 입력칸에 있는 텍스트(OCR 스캔 결과 포함)를
    // 넘겨서, 처음부터 다시 타이핑하지 않아도 되게 한다 — "위치를 찾지
    // 못했어요" 다이얼로그에서 재검색할 때 특히 도움이 된다(사용자 요청).
    final query = initialQuery ?? _addressController.text.trim();
    final result = await Navigator.push<AddressSearchResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddressSearchView(initialQuery: query.isEmpty ? null : query),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final picked = result.address.trim();
      _setTextFromStart(_addressController, picked);
      // 공식 우편번호 서비스에서 고른 주소는 이미 검증된 주소다. 저장할 때
      // 좌표를 역지오코딩해 만든 문자열로 "변환하시겠습니까?"를 다시 묻지
      // 않는다 — 그 제안은 오히려 구 단위가 빠진 짧은 주소를 만든다
      // (backlog 추가 83, 사용자 제보).
      _confirmedRoadNameAddress = picked;
      _addressGeocodeFallback = result.geocodeFallback;

      // 아파트/오피스텔처럼 건물명이 있는 주소는 상세주소 칸이 비어 있을 때만
      // 자동으로 채운다 — 이미 동/호수 등을 직접 입력해 뒀다면 덮어쓰지 않음.
      // 건물명이 주소 문장에 이미 들어간 경우(공동주택 등)에는 상세주소에
      // 중복으로 넣지 않는다.
      if (result.buildingName != null &&
          !picked.contains(result.buildingName!) &&
          _addressDetailController.text.trim().isEmpty) {
        _addressDetailController.text = result.buildingName!;
      }
      if (result.postalCode != null) {
        _postalCodeController.text = result.postalCode!;
      }
    });
  }

  /// "테헤란로 123", "언주로30길 45"처럼 도로명(로/길) 뒤에 건물번호 숫자가
  /// 바로 오는 형태면 이미 정상적인 도로명 주소로 본다. "역삼동 123-45"
  /// 같은 지번 주소는 로/길이 없어서 걸리지 않는다(그런 주소만 변환 제안).
  bool _looksLikeRoadNameAddress(String address) {
    return RegExp(r'(로|길)\s*\d').hasMatch(address);
  }

  void _fillIfEmpty(TextEditingController controller, String value) {
    if (controller.text.trim().isEmpty && value.trim().isNotEmpty) {
      _setTextFromStart(controller, value);
    }
  }

  /// `controller.text = value`만 쓰면 커서가 자동으로 맨 끝에 가서, 한 줄
  /// 입력칸(주소처럼 긴 텍스트)에서 값이 시작 부분부터가 아니라 끝부분만
  /// 보이는 채로 스크롤돼 있어 "글자가 잘려서 들어간 것"처럼 보이는 문제가
  /// 있었다. 커서를 맨 앞(0)으로 둬서 항상 텍스트 시작부터 보이게 한다.
  /// 전화 칸에 **코드로** 값을 넣을 때 쓴다.
  ///
  /// ⚠️ `KoreanPhoneNumberFormatter`는 `TextInputFormatter`라 **사람이 타이핑할
  /// 때만** 걸린다. 퀵 매핑은 값을 코드로 넣으므로 포맷터를 안 거치고,
  /// `02 6360 6910`처럼 **공백으로 읽힌 원문이 그대로 저장된다.**
  ///
  /// 2026-08-19(추가 324)에 퀵 매핑에 사무실·팩스를 더하면서 이 구멍이
  /// 넓어졌다(전에는 휴대폰 하나였다). 규칙을 새로 쓰지 않고 **같은 포맷터를
  /// 그대로 불러** 쓴다 — 두 벌이 되면 서로 다르게 틀리기 시작한다.
  void _setPhoneFromStart(TextEditingController controller, String value) {
    // ⚠️ **전화번호 모양일 때만 정리한다** (2026-08-19 실기기 제보, 추가 327).
    //
    // 포맷터는 **뭐가 들어오든 전화번호로 만든다** — 숫자만 뽑아 무조건 3-4-4나
    // 2-4-4로 끊는다. 그래서 전화가 아니거나 자릿수가 모자라면 **없는 구조를
    // 지어낸다.**
    //
    // ```
    // 31-709-7071        → 317-09-7071   앞 0을 OCR이 놓친 번호가 더 나빠진다
    // 07795 서울 중구 …   → 077-9500      주소인데 전화처럼 만든다
    // E. a@b.com         → 100           이메일에서 숫자만 뽑는다
    // ```
    //
    // 📌 **없는 구조를 지어내느니 원문을 그대로 두는 편이 낫다.** 사용자가 보고
    // 고칠 수 있다. 자리를 밀어 놓으면 **틀린 줄도 모르고 저장된다.**
    //
    // ⚠️ 타이핑용 포맷터에는 이 조건을 걸지 않는다 — 손으로 칠 때는 `010`까지만
    // 쳐도 정리돼야 하는데, 조건을 걸면 타이핑이 망가진다.
    final digits = value.replaceAll(RegExp(r'\D'), '');
    final looksLikePhone =
        digits.startsWith('0') && digits.length >= 9 && digits.length <= 11;
    if (!looksLikePhone) {
      _setTextFromStart(controller, value);
      return;
    }
    final formatted = KoreanPhoneNumberFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: value))
        .text;
    _setTextFromStart(controller, formatted.isEmpty ? value : formatted);
  }

  /// 생김새만으로 알 수 있는 값 — 전화·이메일·홈페이지(추가 326).
  ///
  /// ⚠️ **어느 칸인지는 정하지 않는다.** *"이건 전화번호 모양이다"*까지만 본다.
  /// 파서 판단으로 나누면 파서가 놓친 값이 조각으로도 안 나와서 **원문이
  /// 안전망 노릇을 못 한다.**
  static final _valueShapeRegExp = RegExp(
    r'[\w.+-]+@[\w.-]+\.\w+'
    r'|(?:https?://|www\.)[\w./\-]+'
    r'|\d{2,4}[-. ]\d{3,4}[-. ]\d{4}'
    r'|01\d{9}|0\d{9,10}',
  );

  /// 원문 줄을 **옮길 수 있는 단위**로 쪼갠다(추가 325·326).
  ///
  /// 두 단계다.
  ///
  /// 1. **명함에 인쇄된 구분자**(`|` `·` `/`)에서 자른다.
  /// 2. 그러고도 **값이 둘 이상 든 조각**만 값 경계에서 한 번 더 자른다.
  ///
  /// ⚠️ **2단계는 값이 둘 이상일 때만 한다.** 값이 하나뿐인 줄
  /// (`T 02-6360-6910`)까지 자르면 `T` 같은 라벨이 **쓸모없는 칩**으로 떨어져
  /// 나온다. 전화 칸에 넣을 때는 포맷터가 숫자만 뽑으므로 라벨이 붙어 있어도
  /// 상관없다.
  ///
  /// 📌 **착수 전에 103장으로 쟀다**(추가 326).
  /// ```
  /// 구분자만            평균  9.6  최대  51  30개↑ 3장
  /// + 값 둘 이상만 쪼갬  평균 13.6  최대 119  30개↑ 3장  ← 이것
  /// + 값을 전부 쪼갬     평균 15.3  최대 125  30개↑ 4장
  /// ```
  /// 최대 119는 과대 검출이 아니다 — **한 장에 연락처가 여럿 인쇄된 명함**이고,
  /// 그런 장이야말로 쪼개야 옮길 수 있다. 다만 그런 장은 3/103이라 *"칩이
  /// 많으면 접기"*는 **아직 안 넣었다.**
  static List<String> _splitScannedLines(List<String> lines) {
    final out = <String>[];
    for (final line in lines) {
      final pieces = line
          .split(RegExp(r'\s*[|·｜/]\s*'))
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      for (final piece in (pieces.isEmpty ? [line] : pieces)) {
        final values = _valueShapeRegExp.allMatches(piece).toList();
        // 값 하나라도, **값 아닌 자리에 한글이 있으면** 떼어낸다.
        // `이현석 M 010-9354-5742`처럼 이름과 전화가 한 덩어리로 읽히는
        // 명함이 흔하다 — 그대로 두면 이름 칸으로 보낼 때 전화가 딸려 간다.
        // 영문 라벨(`T` `F` `Mobile.`)은 한글이 아니라 안 걸린다 — 그건
        // 떼어내면 쓸모없는 칩만 늘어난다(추가 327).
        final restHasHangul =
            RegExp(r'[가-힣]').hasMatch(piece.replaceAll(_valueShapeRegExp, ' '));
        if (values.length < 2 && !(values.length == 1 && restHasHangul)) {
          out.add(piece);
          continue;
        }
        var last = 0;
        for (final m in values) {
          final head = piece.substring(last, m.start).trim();
          if (head.isNotEmpty) out.add(head);
          out.add(m.group(0)!);
          last = m.end;
        }
        final tail = piece.substring(last).trim();
        if (tail.isNotEmpty) out.add(tail);
      }
    }
    return out;
  }

  void _setTextFromStart(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  /// 갤러리에서 고른 사진을 앱 문서 디렉터리에 복사해 영구 보관한다
  /// (image_picker가 주는 경로는 임시 캐시라 앱 재시작 시 사라질 수 있음).
  /// 명함마다 별도 파일이라 매번 고유한 파일명을 쓴다.
  Future<void> _pickContactAvatar() async {
    setState(() => _isPickingAvatar = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;
      final docsDir = await getApplicationDocumentsDirectory();
      final savedPath =
          '${docsDir.path}/contact_avatar_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(picked.path).copy(savedPath);
      // 갤러리가 만든 사본은 복사가 끝나면 안 쓰인다 — 여기서 지운다
      // (추가 253). 명함 주인의 얼굴 사진이 앱 캐시에 평문으로 남는 자리였다.
      //
      // ⚠️ `imageQuality: 90`이라 플러그인이 `scaled_*`를 새로 만들어 그
      // 경로를 돌려준다. 우리가 지울 수 있는 것은 그 축소본이고, 플러그인이
      // UUID 폴더에 남기는 원본 사본에는 손이 닿지 않는다 — 그건 앱 시작
      // 쓸어담기(추가 248)가 걷어낸다.
      unawaited(deleteQuietly(picked.path));
      if (!mounted) return;
      setState(() => _selectedAvatarUrl = savedPath);
    } catch (e) {
      if (!mounted) return;
      _showInlineNotice('사진을 불러오지 못했습니다: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPickingAvatar = false);
    }
  }

  void _removeContactAvatar() {
    setState(() => _selectedAvatarUrl = null);
  }

  /// 스캔한 명함 이미지 미리보기 + "대표 이미지로 사용" 토글(추가 133, C안).
  /// 방금 스캔한 원본(임시 파일)은 평문이라 Image.file로, 이미 저장된 이미지는
  /// 암호문이라 복호화([ContactImageService])해 Image.memory로 그린다.
  Widget _buildCardImageSection() {
    final hasFresh = _scannedCardImageSourcePath != null;
    final hasSaved = _cardImagePath != null;
    if (!hasFresh && !hasSaved) return const SizedBox.shrink();

    final uid = context.read<AuthRepository>().firebaseUid;

    // 누르면 전체 화면으로 크게 열린다 — 미리보기 높이(180px)로는 눕혀 찍은
    // 명함의 글자를 읽을 수 없다(사용자 제보, 2026-08-14).
    Widget preview;
    if (hasFresh) {
      preview = ZoomableCardImage(
        image: FileImage(File(_scannedCardImageSourcePath!)),
      );
    } else if (uid != null) {
      preview = FutureBuilder<Uint8List?>(
        future: ContactImageService().loadDecryptedCardImage(
          uid: uid,
          path: _cardImagePath!,
        ),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final bytes = snap.data;
          if (bytes == null) return const SizedBox.shrink();
          return ZoomableCardImage(image: MemoryImage(bytes));
        },
      );
    } else {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.badge_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
            SizedBox(width: 6),
            Text(
              '스캔한 명함',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.borderSubtle.withValues(alpha: 0.8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 180),
              color: AppColors.bgBase,
              child: preview,
            ),
          ),
        ),
        // 앞/뒷면처럼 여러 장을 스캔한 경우 — 어느 면을 대표로 저장할지
        // 고를 수 있게 썸네일을 보여준다. 기본은 이름이 읽힌 면.
        if (_scannedCardImages.length > 1) ...[
          const SizedBox(height: 8),
          const Text(
            '여러 면을 스캔했어요 — 대표로 쓸 면을 선택하세요.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _scannedCardImages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final isSelected = i == _selectedScanIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedScanIndex = i),
                  child: SizedBox(
                    width: 92,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.accent
                                    : AppColors.borderSubtle,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.file(
                                File(_scannedCardImages[i].path),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        // ⚠️ **빼는 길**(추가 293, 실기기 지적).
                        //
                        // 실수로 **다른 사람 명함**을 한 장 더 찍었는데 이 화면에서
                        // 지울 수가 없었다 — 고르는 것만 되고 빼는 것이 없었다.
                        // 그러면 남의 명함이 그대로 저장된다.
                        Positioned(
                          top: -6,
                          right: -6,
                          child: IconButton(
                            iconSize: 16,
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            visualDensity: VisualDensity.compact,
                            icon: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.black54,
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                            tooltip: '이 면 빼기',
                            onPressed: () => _removeScannedFace(i),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 4),
        // 이미지엔 개인정보가 인쇄돼 있어 로컬에 암호화 보관됨을 정직하게 안내.
        const Text(
          '이 기기에 암호화되어 저장돼요.',
          style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _useCardAsAvatar,
          onChanged: (v) => setState(() => _useCardAsAvatar = v),
          activeThumbColor: AppColors.accent,
          title: const Text(
            '이 명함을 대표 이미지로 사용',
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          subtitle: const Text(
            '켜면 명함 목록에서도 이니셜 대신 명함 이미지가 보여요.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _saveCard() async {
    // 1. Basic required validations
    if (_nameController.text.trim().isEmpty) {
      _focusAndShowError(_nameFocusNode, '⚠️ 이름을 입력해 주세요.');
      return;
    }
    if (_companyController.text.trim().isEmpty) {
      _focusAndShowError(_companyFocusNode, '⚠️ 회사명을 입력해 주세요.');
      return;
    }

    // 주소는 선택 입력이다(F-02, 테스터 요청). 명함에 주소가 아예 없는 경우가
    // 흔한데 예전에는 주소가 비면 저장 자체가 막혀 등록을 못 했다. 주소를 비우면
    // 좌표를 못 얻어 '주변' 목록에는 안 뜨지만, 명함 등록·조회는 정상 동작한다.
    // (빈 주소일 때의 저장 경로는 아래 지오코딩 단계에서 분기한다.)
    final rawAddress = _addressController.text.trim();

    final phoneVal = _phoneController.text.trim();
    final phoneRegExp = RegExp(r'^\d{2,3}-\d{3,4}-\d{4}$');
    if (phoneVal.isEmpty) {
      _focusAndShowError(_phoneFocusNode, '⚠️ 휴대폰 번호를 입력해 주세요.');
      return;
    } else if (!phoneRegExp.hasMatch(phoneVal)) {
      _focusAndShowError(
        _phoneFocusNode,
        '⚠️ 올바른 전화번호 형식(예: 010-1234-5678)으로 입력해 주세요.',
      );
      return;
    }

    final emailVal = _emailController.text.trim();
    if (emailVal.isEmpty) {
      _focusAndShowError(_emailFocusNode, '⚠️ 이메일을 입력해 주세요.');
      return;
    } else if (!emailVal.contains('@') || !emailVal.contains('.')) {
      _focusAndShowError(_emailFocusNode, '⚠️ 올바른 이메일 형식을 입력해 주세요.');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 1-b. 전화번호 중복 확인(P1-40). 같은 번호가 이미 등록돼 있으면(같은 사람
    // 명함을 두 번 스캔한 경우 등) 그냥 두 건으로 쌓이지 않도록 저장 전에
    // 확인을 받는다. 편집 중에는 자기 자신과 부딪히므로 검사하지 않는다.
    // 저장 상태(_isSavingCard)를 켜기 전에 두어, 사용자가 취소해도 되돌릴
    // 상태가 없게 한다.
    if (!_isEditing) {
      final dup = context.read<WalletViewModel>().findDuplicateByPhone(
        phoneVal,
      );
      if (dup != null) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('이미 등록된 번호예요'),
            content: Text(
              '같은 전화번호가 "${dup.name}" 님으로 이미 등록돼 있어요.\n'
              '그래도 새 명함으로 추가할까요?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('그래도 추가'),
              ),
            ],
          ),
        );
        if (proceed != true) {
          // "취소"를 골랐다는 건 이 명함을 등록하지 않기로 확정한 것이므로
          // 등록 화면까지 함께 닫는다(사용자 제보, 2026-08-12) — 예전엔
          // 폼에 그대로 남아 닫기 버튼을 한 번 더 눌러야 했다.
          if (mounted) Navigator.pop(context);
          return;
        }
        if (!mounted) return;
      }
    }

    // 주소가 비어 있으면 지오코딩할 대상이 없다 — 건너뛰고 좌표 없이 저장한다.
    // 빈 문자열을 validateAndConvert에 넘기면 "주소를 못 찾았다" 다이얼로그가
    // 잘못 뜨므로 여기서 먼저 걸러낸다(F-02).
    //
    // 단, 침묵 저장은 하지 않는다 — 명함 뒷면에 주소가 있는데 앞면만 보고
    // 등록해 버리는 실수를 막기 위해 한 번 확인한다(사용자 실기기 피드백,
    // 2026-08-14). 중복 전화번호 확인과 같은 패턴. 주소가 채워져 있으면 이
    // 확인은 뜨지 않고 기존대로 바로 지오코딩·저장으로 넘어간다.
    if (rawAddress.isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('주소 없이 저장할까요?'),
          content: const Text(
            '주소가 비어 있어요. 명함 뒷면에 주소가 있을 수 있어요.\n'
            '주소 없이 저장하면 \'주변\'에는 표시되지 않아요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('그래도 저장'),
            ),
          ],
        ),
      );
      // 취소(또는 바깥 탭으로 닫음)면 저장하지 않고 폼으로 돌아간다 —
      // 주소를 입력하거나 뒷면을 스캔할 수 있게.
      if (proceed != true || !mounted) return;
      _executeFinalSave('', null);
      return;
    }

    // 2. Address Geocoding & Road Name Address Conversion Dialog
    setState(() => _isSavingCard = true);
    final addressResult = await AddressGeocodingService.validateAndConvert(
      rawAddress,
      fallbackAddress: _addressGeocodeFallback,
    );
    if (!mounted) return;
    setState(() => _isSavingCard = false);

    if (!addressResult.isValid) {
      // Unresolvable address prompt
      _showUnresolvableAddressDialog(rawAddress);
      return;
    }

    // 입력 주소가 이미 정상적인 도로명 주소면(예: "...테헤란로 123") 역지오코딩
    // 재구성 결과로 덮어쓰지 않고 원본 그대로 저장한다. OS Geocoder가 좌표를
    // 다시 역지오코딩할 때 구성요소가 빠지거나(짤림) 아예 지번 표기로 바뀐
    // 문자열을 돌려주는 경우가 있어서, 이미 맞는 도로명 주소를 "개선"하려다
    // 오히려 망가뜨리는 문제가 있었다 — 도로명이 아닌 주소(지번 등)에만
    // 변환을 제안한다.
    if (_looksLikeRoadNameAddress(rawAddress)) {
      _executeFinalSave(rawAddress, addressResult.geoPosition);
      return;
    }

    // Check if Road Name Address conversion prompt is needed
    if (shouldShowRoadNameConversionDialog(
      roadNameAddress: addressResult.roadNameAddress,
      rawAddress: rawAddress,
      confirmedRoadNameAddress: _confirmedRoadNameAddress,
    )) {
      _showRoadNameConversionDialog(addressResult);
      return;
    }

    // 좌표는 찾았지만(주소 자체는 유효) 역지오코딩으로 도로명 주소를 못 얻은
    // 경우 — 바꿀 도로명이 없으니 조용히 원본 주소로 저장하지 않고, 왜
    // 변환창이 안 뜨는지 짧게 안내한 뒤 저장한다.
    if (addressResult.roadNameAddress == null) {
      _showInlineNotice('ℹ️ 도로명 주소를 찾지 못해 입력하신 주소로 저장합니다.', isError: false);
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
    }

    _executeFinalSave(
      addressResult.roadNameAddress ?? rawAddress,
      addressResult.geoPosition,
    );
  }

  void _showUnresolvableAddressDialog(String rawAddress) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '정확한 위치를 찾지 못했어요',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$rawAddress"의 정확한 GPS 좌표를 지도 서비스에서 찾지 못했습니다. 신축 건물이거나 지도에 아직 반영되지 않은 주소인 경우 흔히 있는 일이에요 — 주소 자체가 틀렸다는 뜻은 아닙니다.',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            if (_scannedRawText != null) ...[
              const Text(
                '💡 명함 RAW 스캔 텍스트:',
                style: TextStyle(
                  color: AppColors.accentText,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgBase,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _scannedRawText!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              '위치 없이 저장해도 명함 정보는 그대로 저장되고, "주변 인맥" 거리 계산에서만 제외돼요. 주소에 오타가 있는 것 같다면 수정해 주세요.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addressFocusNode.requestFocus();
            },
            child: const Text(
              '직접 수정',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          // 스캔/입력된 주소를 그대로 검색창에 붙여넣기만 하면 되게 넘겨서,
          // "위치를 못 찾았다"는 이유만으로 처음부터 다시 타이핑하지 않아도
          // 되게 한다(사용자 요청 — 이 경우가 자주 발생한다고 확인됨).
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openAddressSearch(initialQuery: rawAddress);
            },
            child: const Text(
              '주소 다시 검색',
              style: TextStyle(
                color: AppColors.accentText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 다음(카카오) 우편번호 검색처럼 이미 실제로 존재하는 주소로
          // 확인됐는데도, 기기 내장 Geocoder(특히 Android)가 특정 도로명을
          // 못 찾아서 저장 자체가 막히는 경우가 있었다 — 위치 없이라도
          // 저장은 할 수 있게 탈출구를 준다. geo가 없으면 주변 거리 계산
          // 대상에서만 자동으로 빠지고, 나머지 정보는 정상 저장된다.
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeFinalSave(rawAddress, null);
            },
            child: const Text(
              '위치 없이 저장',
              style: TextStyle(
                color: AppColors.accentText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 원래 입력 주소에서 새 도로명 주소 부분을 뺀 나머지(건물명/층/호수 등
  /// 상세 정보)를 뽑아낸다. 도로명 주소는 지오코딩 좌표를 다시 역지오코딩해서
  /// 행정구역 구성요소로 새로 조립한 문자열이라(_reverseGeocodeToRoadName),
  /// 스캔 원본과 표기가 미묘하게 다를 수 있다(예: "역삼동"이 삽입되거나
  /// 구/동 표기 순서가 다름) — 그래서 전체 문자열을 통째로 비교하면 실제로는
  /// 못 찾는 경우가 많았다. 대신 도로명 주소의 마지막 토큰(보통 건물번호,
  /// 예: "123")만 원본에서 찾아 그 뒤를 상세정보로 보는 방식이 훨씬 안정적이다.
  String? _extractAddressRemainder(String original, String roadName) {
    final trimmedOriginal = original.trim();
    final trimmedRoadName = roadName.trim();
    if (trimmedRoadName.isEmpty || trimmedOriginal == trimmedRoadName)
      return null;

    // 1. 도로명 주소 전체가 원본의 접두어로 그대로 들어있는 가장 흔한 경우.
    if (trimmedOriginal.startsWith(trimmedRoadName)) {
      final remainder = trimmedOriginal
          .substring(trimmedRoadName.length)
          .trim();
      return remainder.isEmpty ? null : remainder;
    }

    // 2. 마지막 토큰(건물번호)을 원본에서 찾아 그 뒤를 상세정보로 취급.
    final roadTokens = trimmedRoadName
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (roadTokens.isNotEmpty) {
      final lastToken = roadTokens.last;
      final idx = trimmedOriginal.lastIndexOf(lastToken);
      if (idx >= 0) {
        final afterIdx = idx + lastToken.length;
        final remainder = trimmedOriginal.substring(afterIdx).trim();
        // 남은 문자열이 숫자/하이픈으로 바로 이어지면(예: "123-45") 건물번호의
        // 나머지 일부일 수 있으니 상세정보로 보지 않는다.
        if (remainder.isNotEmpty && !RegExp(r'^[-\d]').hasMatch(remainder)) {
          return remainder;
        }
      }
    }

    return null;
  }

  void _showRoadNameConversionDialog(AddressValidationResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '도로명 주소 자동 변환',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '입력하신 주소를 표준 정밀 도로명 주소로 자동 변환하시겠습니까?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgBase,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• 기존 입력 주소: ${result.originalAddress}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• 변경 도로명 주소: ${result.roadNameAddress}',
                    style: const TextStyle(
                      color: AppColors.accentText,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // "네, 도로명으로 변경"과 대칭이 되게, 이 주소에 대해 변환을
              // 하지 않기로 확정됐다는 것도 _confirmedRoadNameAddress에
              // 기록한다. 여기서는 주소 텍스트를 바꾸지 않으므로 원본
              // 주소(result.originalAddress, rawAddress와 동일한 trim된 값)를
              // 그대로 저장한다. 이걸 빼먹으면 사용자가 원본 주소로 다시
              // 저장을 눌러도 rawAddress != _confirmedRoadNameAddress가 계속
              // 참이라 같은 변환 팝업이 무한히 다시 떴다(테스터 A, 갤럭시
              // 폴드7, 1.0.0(8)).
              setState(() {
                _confirmedRoadNameAddress = result.originalAddress;
              });
            },
            child: const Text(
              '기존 입력 유지',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 도로명으로 바꾸면 기존에 입력했던 "5층 501호" 같은 상세 정보가
              // 도로명 주소엔 안 들어가서 그냥 사라져 버리는 문제가 있었다 —
              // 원래 입력 주소에서 새 도로명 주소를 뺀 나머지를 상세주소로
              // 옮겨 담아 보존한다(상세주소를 이미 직접 입력해 뒀으면 덮어쓰지 않음).
              // 그리고 곧바로 저장하지 않고 폼으로 돌아가서 사용자가 상세주소가
              // 제대로 채워졌는지 직접 확인한 뒤 "명함 저장하기"를 눌러 저장하게
              // 한다(자동 저장 시 확인 없이 등록돼 버리는 문제가 있었음).
              final remainder = _extractAddressRemainder(
                result.originalAddress,
                result.roadNameAddress!,
              );
              setState(() {
                _setTextFromStart(_addressController, result.roadNameAddress!);
                _confirmedRoadNameAddress = result.roadNameAddress;
                if (remainder != null &&
                    _addressDetailController.text.trim().isEmpty) {
                  _addressDetailController.text = remainder;
                }
              });
              _showInlineNotice(
                '🛣️ 도로명 주소로 변경했습니다. 상세주소가 올바른지 확인하고 저장해 주세요.',
                isError: false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text(
              '네, 도로명으로 변경',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 폼을 성격이 다른 두 덩어리로 가르는 헤더(F-04).
  ///
  /// "명함에서 읽은 정보"와 "내가 덧붙이는 정보"를 구분한다. 테스터 피드백은
  /// *자동으로 읽힌 값과 내가 쓴 메모가 섞여 보인다*였는데, 원인은 두 성격의
  /// 칸이 **같은 모양으로 연달아** 놓여 있던 것이다. 칸 모양을 바꾸는 대신
  /// 헤더로 나눈 이유는, 입력칸 스타일을 둘로 만들면 이후 모든 화면에서 그
  /// 두 스타일을 계속 맞춰야 하기 때문이다.
  Widget _buildFormSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      // 위쪽 여백을 크게 둬서 앞 섹션과 시각적으로 떨어뜨린다. 아래는 곧바로
      // 첫 입력칸이 오므로 좁게.
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.accentText),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 이 칸이 **아직 자동 인식 값 그대로인가**(F-09).
  ///
  /// 판정 규칙 자체는 [isStillOcrValue]에 있다 — 화면에서 떼어내 테스트로
  /// 고정했다(`lib/core/utils/ocr_origin.dart` 문서화 참고).
  bool _isStillOcrValue(String? ocrKey, TextEditingController controller) =>
      isStillOcrValue(
        key: ocrKey,
        snapshot: _ocrParsedSnapshot,
        currentText: controller.text,
      );

  /// 자동 인식 표시가 붙은 칸을 사용자가 고치면 **그 즉시** 표시가 사라지도록
  /// 다시 그린다(F-09).
  ///
  /// 매 글자마다 `setState`를 부르면 이 큰 폼 전체가 리빌드된다. 그래서 표시가
  /// 실제로 **켜짐↔꺼짐으로 바뀌는 순간에만** 다시 그린다 — 대부분의 타이핑은
  /// 이미 꺼진 상태라 아무 일도 하지 않는다.
  void _watchOcrBadge(String key, TextEditingController controller) {
    var wasBadged = _isStillOcrValue(key, controller);
    controller.addListener(() {
      final isBadged = _isStillOcrValue(key, controller);
      if (isBadged == wasBadged) return;
      wasBadged = isBadged;
      if (mounted) setState(() {});
    });
  }

  /// 자동 인식이 채운 값들을 저장 시점의 최종 값과 비교해, 사용자가 각 필드를
  /// 어떻게 바꿨는지(그대로/고침/지움)만 집계에 남긴다. **값은 넘기지 않는다.**
  /// 스캔을 한 번도 안 했으면(스냅샷이 비었으면) 아무것도 기록하지 않는다.
  void _recordOcrCorrections() {
    if (_ocrParsedSnapshot.isEmpty) return;
    final finalValues = <String, String>{
      'name': _nameController.text.trim(),
      'company': _companyController.text.trim(),
      'title': _titleController.text.trim(),
      'address': _addressController.text.trim(),
      'addressDetail': _addressDetailController.text.trim(),
      'postal': _postalCodeController.text.trim(),
      'mobile': _phoneController.text.trim(),
      'office': _officePhoneController.text.trim(),
      'email': _emailController.text.trim(),
    };
    final corrections = <String, OcrCorrectionKind>{};
    _ocrParsedSnapshot.forEach((key, parsed) {
      final current = finalValues[key] ?? '';
      if (current == parsed) {
        corrections[key] = OcrCorrectionKind.unchanged;
      } else if (current.isEmpty) {
        corrections[key] = OcrCorrectionKind.cleared;
      } else {
        corrections[key] = OcrCorrectionKind.edited;
      }
    });
    unawaited(_ocrStats.recordCorrections(corrections));
  }

  Future<void> _executeFinalSave(
    String finalAddress,
    GeoPosition? resolvedGeo,
  ) async {
    // 저장이 확정되는 지점 — 여기서 한 번만 자동 인식 대비 수정 형태를
    // 남긴다(중복 병합 경로로 빠지든 신규로 저장하든 모두 이 지점을 지난다).
    _recordOcrCorrections();

    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final interests = _interestsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    // 신규 등록일 때만 중복 검사 — 수정(_isEditing)은 이미 어떤 명함을 고치는지
    // 확정된 상태라 검사할 필요가 없다. 휴대폰 번호가 "같은 사람"을 가장
    // 신뢰할 수 있게 식별하는 값이라(이직해도 개인 번호는 잘 안 바뀜) 이걸로
    // 매칭한다.
    if (!_isEditing) {
      final duplicate = _findDuplicateContact(_phoneController.text.trim());
      if (duplicate != null) {
        final wantsUpdate = await _showDuplicateFoundDialog(duplicate);
        if (!mounted) return;
        if (wantsUpdate == false) {
          // "기존 정보 유지" = 이 명함을 등록하지 않기로 확정한 것이므로
          // 등록 화면까지 함께 닫는다. 예전엔 폼에 남아서 닫기 버튼을 한 번
          // 더 눌러야 했다(사용자 불편 제보, 2026-08-11). 번호를 잘못 입력해
          // 중복으로 오인된 경우에는 다이얼로그를 시스템 뒤로가기로 닫으면
          // (아래 null 분기) 폼이 유지되므로 고칠 길이 남아 있다.
          Navigator.pop(context);
          return;
        }
        if (wantsUpdate != true) return; // 다이얼로그만 닫힘 — 폼 유지(입력 수정 기회).

        final deleteOldRecord = await _showKeepHistoryDialog();
        if (!mounted) return;
        if (deleteOldRecord == null) return; // 대화상자 닫힘 — 저장 보류

        _applyUpdateToExisting(
          duplicate,
          finalAddress,
          resolvedGeo,
          tags,
          interests,
          deleteOldRecord: deleteOldRecord,
        );
        return;
      }
    }

    final contactId = _isEditing
        ? widget.contactToEdit!.id
        : DateTime.now().millisecondsSinceEpoch.toString();

    // 명함 이미지(추가 133): 새로 스캔한 이미지가 있으면 암호화(P1-9)해서
    // 보관하고 그 경로를 쓴다. 없으면 편집 중이던 기존 이미지를 유지한다.
    // 로그인(uid) 없으면(게스트) 키가 없어 저장하지 않는다.
    // 편집이면 화면 상태(_cardImagePath)를 쓴다 — 위 initState의 재연결로
    // 복원된 경로가 있으면 저장하면서 로컬에 다시 기록되게 하기 위함.
    var cardImagePath = _isEditing ? _cardImagePath : null;
    final uid = context.read<AuthRepository>().firebaseUid;
    if (_scannedCardImageSourcePath != null && uid != null) {
      final saved = await ContactImageService().saveEncryptedCardImage(
        uid: uid,
        contactId: contactId,
        sourcePath: _scannedCardImageSourcePath!,
      );
      if (!mounted) return;
      if (saved != null) cardImagePath = saved;
    }

    final contact = ContactModel(
      id: contactId,
      name: _nameController.text.trim(),
      company: _companyController.text.trim(),
      title: _titleController.text.trim().isEmpty
          ? '담당자'
          : _titleController.text.trim(),
      department: _departmentController.text.trim().isEmpty
          ? null
          : _departmentController.text.trim(),
      address: finalAddress,
      addressDetail: _addressDetailController.text.trim().isEmpty
          ? null
          : _addressDetailController.text.trim(),
      postalCode: _postalCodeController.text.trim().isEmpty
          ? null
          : _postalCodeController.text.trim(),
      phone: _phoneController.text.trim(),
      officePhone: _officePhoneController.text.trim().isEmpty
          ? null
          : _officePhoneController.text.trim(),
      directPhone: _directPhoneController.text.trim().isEmpty
          ? null
          : _directPhoneController.text.trim(),
      fax: _faxController.text.trim().isEmpty
          ? null
          : _faxController.text.trim(),
      email: _emailController.text.trim(),
      website: _websiteController.text.trim().isEmpty
          ? null
          : _websiteController.text.trim(),
      avatarUrl: _selectedAvatarUrl,
      tags: tags.isEmpty ? ['신규'] : tags,
      interests: interests,
      // 주소를 실제 좌표로 확인하지 못했다면 가짜 좌표를 넣지 않는다.
      // geo가 null인 명함은 주변 거리 계산 대상에서 자동으로 제외된다.
      geo: resolvedGeo ?? (_isEditing ? widget.contactToEdit!.geo : null),
      // AI 대화 브리핑을 열 때 실제 연동된 AI가 생성 — 여기서는 하드코딩된
      // 문구 대신 빈 값으로 시작한다.
      talkingPoints: _isEditing
          ? widget.contactToEdit!.talkingPoints
          : const [],
      commLogs: _isEditing ? widget.contactToEdit!.commLogs : [],
      isPriority: _isEditing ? widget.contactToEdit!.isPriority : true,
      memo: _memoController.text.trim().isEmpty
          ? null
          : _memoController.text.trim(),
      cardImagePath: cardImagePath,
      // 이미지가 실제로 있을 때만 "대표 이미지로 사용"이 의미가 있다.
      useCardAsAvatar: _useCardAsAvatar && cardImagePath != null,
    );

    if (_isEditing) {
      context.read<WalletViewModel>().updateContact(contact);
    } else {
      context.read<WalletViewModel>().addContact(contact);
    }

    Navigator.pop(context);

    // 여기서는 이미 모달을 닫았으므로(위 pop) 폼 내부 배너가 아니라 바깥
    // (명함 지갑 화면)의 ScaffoldMessenger를 찾아가야 스낵바가 뜬다.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEditing
              ? '🎉 ${contact.name} 님의 명함 정보가 수정되었습니다!'
              : '🎉 ${contact.name} 님의 명함이 등록되었습니다!',
        ),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  String _normalizeDuplicatePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
  }

  // "같은 사람"을 식별하는 기준은 휴대폰 번호 — 이직해서 회사/직함/이메일이
  // 바뀌어도 개인 번호는 잘 안 바뀌기 때문에 가장 신뢰할 수 있는 값이다.
  ContactModel? _findDuplicateContact(String phone) {
    final normalized = _normalizeDuplicatePhone(phone);
    if (normalized.isEmpty) return null;
    for (final c in context.read<WalletViewModel>().contacts) {
      if (_normalizeDuplicatePhone(c.phone) == normalized) return c;
    }
    return null;
  }

  Future<bool?> _showDuplicateFoundDialog(ContactModel existing) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '이미 등록된 인맥입니다',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '휴대폰 번호가 같은 기존 명함이 있습니다. 어떻게 할까요?',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgBase,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '기존 정보',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${existing.name} · ${existing.title} · ${existing.company}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '새로 입력한 정보',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_nameController.text.trim()} · ${_titleController.text.trim()} · ${_companyController.text.trim()}',
                    style: const TextStyle(
                      color: AppColors.accentText,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '기존 정보 유지',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '최신 정보로 업데이트',
              style: TextStyle(
                color: AppColors.accentText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showKeepHistoryDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '기존 정보 처리',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          '업데이트하면 기존 명함 정보(회사·직함·연락처 등)는 어떻게 할까요?\n"기록으로 남기기"를 선택하면 메모에 이전 정보가 남습니다.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '기록으로 남기기',
              style: TextStyle(
                color: AppColors.accentText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '삭제',
              style: TextStyle(
                color: AppColors.destructive,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _applyUpdateToExisting(
    ContactModel existing,
    String finalAddress,
    GeoPosition? resolvedGeo,
    List<String> tags,
    List<String> interests, {
    required bool deleteOldRecord,
  }) {
    final newMemo = _memoController.text.trim();
    String? mergedMemo;
    if (deleteOldRecord) {
      mergedMemo = newMemo.isEmpty ? null : newMemo;
    } else {
      final dateLabel = DateTime.now().toIso8601String().substring(0, 10);
      final oldFields = [
        existing.company,
        existing.title,
        // 2026-08-19(추가 328): 부서 칸을 만들면서 **여기 넣는 걸 빠뜨렸다**.
        // 이직하면 부서도 바뀌는데 이전 부서가 안 남았다.
        // ⚠️ 비어 있으면 넣지 않는다 — 옛 명함에는 이 값이 아예 없다(null).
        if (existing.department != null && existing.department!.isNotEmpty)
          existing.department,
        existing.phone,
        if (existing.officePhone != null && existing.officePhone!.isNotEmpty)
          existing.officePhone,
        if (existing.email.isNotEmpty) existing.email,
        if (existing.address != null && existing.address!.isNotEmpty)
          existing.address,
      ].join(' / ');
      final oldSnapshot = '[이전 정보 · $dateLabel] $oldFields';
      mergedMemo = [oldSnapshot, if (newMemo.isNotEmpty) newMemo].join('\n');
    }

    // id/talkingPoints/commLogs/isPriority는 copyWith에서 안 건드리면 기존
    // 값 그대로 유지됨 — "같은 사람"의 소통 이력·우선순위는 명함 버전이
    // 바뀌어도 이어지는 게 맞다.
    final updated = existing.copyWith(
      name: _nameController.text.trim(),
      company: _companyController.text.trim(),
      title: _titleController.text.trim().isEmpty
          ? '담당자'
          : _titleController.text.trim(),
      department: _departmentController.text.trim().isEmpty
          ? null
          : _departmentController.text.trim(),
      address: finalAddress,
      addressDetail: _addressDetailController.text.trim().isEmpty
          ? null
          : _addressDetailController.text.trim(),
      postalCode: _postalCodeController.text.trim().isEmpty
          ? null
          : _postalCodeController.text.trim(),
      phone: _phoneController.text.trim(),
      officePhone: _officePhoneController.text.trim().isEmpty
          ? null
          : _officePhoneController.text.trim(),
      directPhone: _directPhoneController.text.trim().isEmpty
          ? null
          : _directPhoneController.text.trim(),
      fax: _faxController.text.trim().isEmpty
          ? null
          : _faxController.text.trim(),
      email: _emailController.text.trim(),
      website: _websiteController.text.trim().isEmpty
          ? null
          : _websiteController.text.trim(),
      avatarUrl: _selectedAvatarUrl ?? existing.avatarUrl,
      tags: tags.isEmpty ? existing.tags : tags,
      interests: interests.isEmpty ? existing.interests : interests,
      geo: resolvedGeo ?? existing.geo,
      memo: mergedMemo,
    );

    context.read<WalletViewModel>().updateContact(updated);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🔄 ${updated.name} 님의 정보를 최신 정보로 업데이트했습니다.'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  void _focusAndShowError(FocusNode focusNode, String message) {
    focusNode.requestFocus();
    _showInlineNotice(message, isError: true);
  }

  bool _hasUnsavedChanges() {
    if (_selectedAvatarUrl != _initialAvatarUrl) return true;
    return _initialValues.entries.any((entry) {
      final controller = switch (entry.key) {
        'name' => _nameController,
        'company' => _companyController,
        'title' => _titleController,
        'address' => _addressController,
        'addressDetail' => _addressDetailController,
        'postalCode' => _postalCodeController,
        'phone' => _phoneController,
        'officePhone' => _officePhoneController,
        'directPhone' => _directPhoneController,
        'fax' => _faxController,
        'email' => _emailController,
        'website' => _websiteController,
        'tags' => _tagsController,
        'interests' => _interestsController,
        'memo' => _memoController,
        _ => null,
      };
      return controller != null && controller.text != entry.value;
    });
  }

  // X 버튼 처리 — 입력한 내용이 있는데 실수로 눌러 닫으면 그대로 사라지는
  // 문제가 있어서, 뭔가 바뀐 게 있을 때만 확인창을 띄운다(사용자 요청).
  Future<void> _handleCancelTap() async {
    if (!_hasUnsavedChanges()) {
      Navigator.pop(context);
      return;
    }
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _isEditing ? '명함 수정을 취소할까요?' : '명함 등록을 취소할까요?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          '지금까지 입력한 내용이 저장되지 않고 모두 사라져요.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '계속 작성',
              style: TextStyle(
                color: AppColors.accentText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '취소하기',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (shouldDiscard == true && mounted) {
      Navigator.pop(context);
    }
  }

  // 포커스된 입력 칸을 키보드 위(화면 안)로 끌어온다. 키보드가 올라오는
  // 애니메이션(≈0.3초)이 끝난 뒤에 스크롤해야 실제 viewInsets 기준으로 맞아,
  // 애니메이션 도중 어긋나 칸이 가리는 것을 막는다.
  void _ensureFocusedFieldVisible(FocusNode node) {
    if (!node.hasFocus) return;
    Future.delayed(const Duration(milliseconds: 300), () {
      // 지연 뒤에도 여전히 이 시트가 살아 있고(mounted) 그 칸이 포커스를
      // 쥐고 있을 때만 스크롤한다 — 포커스가 살아 있으면 node.context도 유효한
      // 트리를 가리킨다.
      if (!mounted || !node.hasFocus) return;
      final ctx = node.context;
      if (ctx == null) return;
      // 칸을 뷰포트 중앙쯤에 두어 키보드 위로 확실히 올린다.
      //
      // ⚠️ ignore 주석은 **경고가 찍히는 줄 바로 위**에 있어야 한다. 예전에는
      // 호출이 한 줄이라 위에 붙여 뒀는데, `dart format`이 인자를 줄바꿈하자
      // 주석과 경고 지점이 어긋나 경고가 되살아났다(analyze 19 → 20).
      Scrollable.ensureVisible(
        // ignore: use_build_context_synchronously
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // X 버튼뿐 아니라 안드로이드 뒤로가기/스와이프로 시트를 닫으려 할
      // 때도 같은 확인 절차를 타게 한다 — X 버튼만 막으면 뒤로가기로는
      // 그냥 바로 닫혀서 입력 내용이 조용히 사라지는 구멍이 남는다.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleCancelTap();
      },
      child: Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          // 여러 줄 메모 칸이 있는 화면이다. Android에서 멀티라인 입력칸은
          // 키보드에 완료 키 대신 **줄바꿈 키**가 떠서 키보드를 닫을 방법이
          // 없다 — 그대로 두면 위쪽이 키보드에 가린 채 스크롤도 막힌다
          // (통합본 E-10). 끌어서 스크롤하면 키보드를 내린다.
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            AppIcon(
                              _isEditing
                                  ? AppIconId.editCard
                                  : AppIconId.addCard,
                              size: 20,
                              color: AppColors.textPrimary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isEditing ? '명함 정보 수정' : '새 명함 직접 등록',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                        ),
                        tooltip: '입력 취소',
                        onPressed: _handleCancelTap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _buildInlineNotice(),

                  // 내 디지털 명함 수정 화면과 같은 스타일(박스·"OCR" 라벨
                  // 없이 아웃라인 버튼 2개만)로 통일 — 사용자 피드백.
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isScanningOcr
                              ? null
                              : () => _performOcrScan(isFromCamera: true),
                          icon: _isScanningOcr
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accentText,
                                  ),
                                )
                              : const AppIcon(
                                  AppIconId.scanCard,
                                  size: 18,
                                  color: AppColors.accentText,
                                ),
                          label: const Text(
                            '명함 촬영 스캔',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.accentText,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.accentText),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isScanningOcr
                              ? null
                              : () => _performOcrScan(isFromCamera: false),
                          icon: const AppIcon(
                            AppIconId.galleryUpload,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          label: const Text(
                            '이미지 업로드',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: AppColors.borderSubtle,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  _buildDocScannerDebugSwitch(),
                  _buildCardRectDebugSwitch(),
                  _buildMeasureSampleSwitch(),

                  const SizedBox(height: 12),

                  // 📸 Profile Photo Selector Widget — 갤러리에서 실제 사진을
                  // 골라 앱 문서 디렉터리에 저장한다(가짜 스톡 사진 프리셋 아님).
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          // deferToChild(기본)면 원형 아바타의 투명한 모서리에서
                          // 탭이 새어나가 히트 영역이 좁다(P1-11). opaque로 72×72
                          // 사각 전체를 탭 대상으로 만든다.
                          behavior: HitTestBehavior.opaque,
                          onTap: _isPickingAvatar ? null : _pickContactAvatar,
                          child: Semantics(
                            button: true,
                            label: '프로필 사진 선택',
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                ContactAvatar(
                                  photoPath: _selectedAvatarUrl,
                                  name: _nameController.text,
                                  radius: 36,
                                ),
                                if (_isPickingAvatar)
                                  const SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: AppColors.accentText,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedAvatarUrl == null
                              ? '프로필 사진 선택 (터치하여 갤러리에서 선택)'
                              : '사진 변경 (터치)',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_selectedAvatarUrl != null)
                          TextButton(
                            onPressed: _removeContactAvatar,
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 32),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              '사진 삭제',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.destructive,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 📇 스캔한 명함 이미지 미리보기 + "대표 이미지로 사용" 토글(추가 133)
                  _buildCardImageSection(),

                  // Collapsible RAW Scanned Text Card
                  if (_scannedRawText != null) ...[
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showRawTextCard = !_showRawTextCard),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentText.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.accentText.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              // 2026-08-19(추가 325): 사용자가 **칩을 "인식
                              // 결과"로 읽고, 잘못된 칩은 피해서** 안 눌렀다.
                              // 실제로는 정반대다 — 칩은 명함 원문이고, 칸이
                              // 잘못 채워졌을 때 **고치려고 누르는 것**이다.
                              // 그래서 머리글에 목적을 적는다.
                              '📄 명함 원문 — 칸이 잘못 채워졌을 때 고치기',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentText,
                              ),
                            ),
                            Icon(
                              _showRawTextCard
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: AppColors.accentText,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showRawTextCard) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.bgBase,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '💡 아래는 명함에서 읽은 줄 그대로예요. '
                              '값이 엉뚱한 칸에 들어갔다면, 그 줄을 눌러 '
                              '알맞은 칸으로 보내세요.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_scannedRawLines.isNotEmpty)
                              // ⚠️ **칩 너비를 화면에 맞춘다**(추가 293, 실기기 지적).
                              //
                              // 예전에는 길이 제한이 없어, OCR이 한 줄로 길게 읽으면
                              // (`wwW.CREAMHOUSE.CO.KR T.02 508 2712 F.070 5084…`)
                              // **화면 밖으로 넘쳤다** — debug에서는 노란 줄무늬가
                              // 뜨고 **release에서는 경고 없이 잘린다.** 보이지
                              // 않을 뿐 더 나쁘다.
                              //
                              // 📌 글자는 줄여 보여도 **누를 때는 원문 전체**를
                              // 넘긴다. 칩은 고르는 손잡이지 읽는 곳이 아니다.
                              LayoutBuilder(
                                builder: (context, constraints) => Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _scannedRawLines.map((line) {
                                    return InkWell(
                                      onTap: () =>
                                          _showQuickFieldMapperSheet(line),
                                      borderRadius: BorderRadius.circular(8),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: constraints.maxWidth,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.accent.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: AppColors.accent
                                                  .withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  line,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        AppColors.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(
                                                Icons.touch_app_outlined,
                                                size: 13,
                                                color: AppColors.accentText,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              )
                            else
                              Text(
                                _scannedRawText!,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary,
                                  fontFamily: 'monospace',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],

                  // F-04: 여기부터는 **명함에 인쇄된 정보**다. 아래 "내가
                  // 덧붙이는 정보"와 성격이 달라 헤더로 갈라 놓는다 — 테스터가
                  // "자동으로 읽힌 값과 내가 쓴 메모가 구분이 안 된다"고 했다.
                  _buildFormSectionHeader(
                    icon: Icons.badge_outlined,
                    title: '명함에서 읽은 정보',
                    subtitle: _ocrParsedSnapshot.isEmpty
                        ? '명함에 인쇄된 내용을 적는 칸이에요'
                        : '옅은 파란 칸은 자동으로 읽은 값이에요. 고치면 표시가 사라집니다',
                  ),

                  // 1. 이름 (필수)
                  _buildFormField(
                    controller: _nameController,
                    ocrKey: 'name',
                    focusNode: _nameFocusNode,
                    order: 1,
                    nextFocusNode: _companyFocusNode,
                    label: '이름 *',
                    hint: '예: 홍길동',
                    trailingLegend: '* 필수 입력 항목',
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '이름을 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // 2. 회사명 (필수)
                  _buildFormField(
                    controller: _companyController,
                    ocrKey: 'company',
                    focusNode: _companyFocusNode,
                    order: 2,
                    nextFocusNode: _titleFocusNode,
                    label: '회사명 *',
                    hint: '예: 카카오 / 삼성전자',
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '회사명을 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // 3. 직함 (선택)
                  _buildFormField(
                    controller: _titleController,
                    ocrKey: 'title',
                    focusNode: _titleFocusNode,
                    order: 3,
                    nextFocusNode: _departmentFocusNode,
                    label: '직함',
                    hint: '예: 팀장',
                  ),
                  const SizedBox(height: 10),

                  // 3-2. 부서 (선택) — 2026-08-19에 직함에서 갈랐다(추가 321).
                  _buildFormField(
                    controller: _departmentController,
                    ocrKey: 'department',
                    focusNode: _departmentFocusNode,
                    order: 4,
                    nextFocusNode: _addressFocusNode,
                    label: '부서',
                    hint: '예: R&D 센터',
                  ),
                  const SizedBox(height: 10),

                  // 4. 회사 주소 — 도로명까지(위치 정보/지오코딩의 기준이 되는 부분)
                  _buildFormField(
                    controller: _addressController,
                    ocrKey: 'address',
                    focusNode: _addressFocusNode,
                    order: 4,
                    nextFocusNode: _addressDetailFocusNode,
                    label: '회사 주소 (도로명)',
                    hint: '예: 서울특별시 강남구 테헤란로 123 (선택)',
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.search,
                        color: AppColors.accentText,
                      ),
                      tooltip: '도로명주소 검색',
                      onPressed: _openAddressSearch,
                    ),
                  ),
                  // P1-25: 주소로 위치를 못 찾으면 이 명함은 '주변' 목록에 안 뜬다.
                  // 사용자에게 이유와 조치(주소 수정)를 알려 준다.
                  if (_addressGeoFailed) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderFunctional),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.location_off,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '위치를 못 찾았어요. 주소를 확인해 주세요.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),

                  // 4-1. 상세주소(선택) — 건물명/층/호수 등. 위치 정보에는 안 쓰이고
                  // 표시용으로만 별도 보관.
                  _buildFormField(
                    controller: _addressDetailController,
                    ocrKey: 'addressDetail',
                    focusNode: _addressDetailFocusNode,
                    order: 4.5,
                    nextFocusNode: _postalCodeFocusNode,
                    label: '상세주소 (선택)',
                    hint: '예: 5층 501호',
                  ),
                  const SizedBox(height: 10),

                  // 4-2. 우편번호(선택) — 지오코딩에는 안 쓰이고 표시/등록용으로만
                  // 보관. OCR 스캔 또는 도로명주소 검색에서 자동으로 채워진다.
                  _buildFormField(
                    controller: _postalCodeController,
                    ocrKey: 'postal',
                    focusNode: _postalCodeFocusNode,
                    order: 4.7,
                    nextFocusNode: _phoneFocusNode,
                    label: '우편번호 (선택)',
                    hint: '예: 06193',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),

                  // 5. 휴대폰 번호 (필수 + 실시간 형식 감시)
                  _buildFormField(
                    controller: _phoneController,
                    ocrKey: 'mobile',
                    focusNode: _phoneFocusNode,
                    order: 5,
                    nextFocusNode: _officePhoneFocusNode,
                    label: '휴대폰 번호 *',
                    hint: '예: 010-1234-5678',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '휴대폰 번호를 입력해 주세요.';
                      }
                      final phoneRegExp = RegExp(r'^\d{2,3}-\d{3,4}-\d{4}$');
                      if (!phoneRegExp.hasMatch(val.trim())) {
                        return '올바른 전화번호 형식(예: 010-1234-5678)으로 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // 6. 사무실 전화번호 (선택)
                  _buildFormField(
                    controller: _officePhoneController,
                    ocrKey: 'office',
                    focusNode: _officePhoneFocusNode,
                    order: 6,
                    nextFocusNode: _directPhoneFocusNode,
                    label: '사무실 전화번호 (선택)',
                    hint: '예: 02-123-4567',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 10),

                  // 6-1. 직통 전화번호 (선택)
                  _buildFormField(
                    controller: _directPhoneController,
                    focusNode: _directPhoneFocusNode,
                    order: 6.3,
                    nextFocusNode: _faxFocusNode,
                    label: '직통 전화번호 (선택)',
                    hint: '예: 02-123-4568',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 10),

                  // 6-2. 팩스 (선택)
                  _buildFormField(
                    controller: _faxController,
                    ocrKey: 'fax',
                    focusNode: _faxFocusNode,
                    order: 6.6,
                    nextFocusNode: _emailFocusNode,
                    label: '팩스 (선택)',
                    hint: '예: 02-123-4569',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 10),

                  // 7. 이메일 (필수!)
                  _buildFormField(
                    controller: _emailController,
                    ocrKey: 'email',
                    focusNode: _emailFocusNode,
                    order: 7,
                    nextFocusNode: _websiteFocusNode,
                    label: '이메일 *',
                    hint: '예: example@company.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '이메일을 입력해 주세요.';
                      }
                      if (!val.contains('@') || !val.contains('.')) {
                        return '올바른 이메일 형식을 입력해 주세요.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // 7-1. 웹사이트 (선택)
                  _buildFormField(
                    controller: _websiteController,
                    ocrKey: 'website',
                    focusNode: _websiteFocusNode,
                    order: 7.5,
                    nextFocusNode: _tagsFocusNode,
                    label: '웹사이트 (선택)',
                    hint: '예: www.company.com',
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 10),

                  // F-04: 여기부터는 **명함에 없는, 내가 덧붙이는 정보**다.
                  // 자동 인식은 이 아래 칸을 절대 채우지 않는다.
                  _buildFormSectionHeader(
                    icon: Icons.edit_note,
                    title: '내가 덧붙이는 정보',
                    subtitle: '명함에 없는 내용이에요. AI 대화 가이드가 참고합니다',
                  ),

                  // 8. 태그 키워드
                  _buildFormField(
                    controller: _tagsController,
                    focusNode: _tagsFocusNode,
                    order: 8,
                    nextFocusNode: _interestsFocusNode,
                    label: '태그 키워드 (쉼표 구분)',
                    hint: '예: AI, 바이오, C-Level',
                  ),
                  const SizedBox(height: 10),

                  // 8-1. 관심사 — AI 대화 브리핑이 안부 인사 소재로 참고한다.
                  // tags(카테고리 분류용)와는 목적이 달라 별도 입력칸으로 분리.
                  _buildFormField(
                    controller: _interestsController,
                    focusNode: _interestsFocusNode,
                    order: 8.5,
                    nextFocusNode: _memoFocusNode,
                    label: '관심사 (쉼표 구분, 선택)',
                    hint: '예: 골프, 와인, 자녀 교육',
                  ),
                  const SizedBox(height: 10),

                  // 9. Memo Summary (메모 및 특징 요약)
                  _buildFormField(
                    controller: _memoController,
                    focusNode: _memoFocusNode,
                    order: 9,
                    isLast: true,
                    maxLines: 3,
                    label: 'Memo Summary (메모 및 특징 요약)',
                    hint: '인맥에 대한 주요 특징, 비즈니스 연관성, 미팅 메모 등을 자유롭게 입력하세요.',
                  ),
                  const SizedBox(height: 22),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSavingCard ? null : _saveCard,
                      icon: _isSavingCard
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : AppIcon(
                              _isEditing
                                  ? AppIconId.editCard
                                  : AppIconId.saveDownload,
                              color: Colors.white,
                            ),
                      label: Text(
                        _isSavingCard
                            ? '주소 확인 중...'
                            : (_isEditing ? '명함 수정 완료' : '명함 저장하기'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineNotice() {
    if (_inlineNoticeText == null) return const SizedBox.shrink();
    final color = _inlineNoticeIsError
        ? AppColors.destructive
        : AppColors.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              _inlineNoticeText!,
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          if (_inlineNoticeActionLabel != null && _inlineNoticeAction != null)
            TextButton(
              onPressed: () {
                _dismissInlineNotice();
                _inlineNoticeAction?.call();
              },
              child: Text(
                _inlineNoticeActionLabel!,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.close, size: 16, color: color),
            onPressed: _dismissInlineNotice,
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required double order,
    FocusNode? nextFocusNode,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool isLast = false,
    int maxLines = 1,
    bool autofocus = false,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
    // 화면 맨 위에 따로 떠 있던 "* 필수 입력 항목" 범례를 첫 필드(이름) 라벨
    // 옆으로 옮겨 붙이기 위한 파라미터.
    String? trailingLegend,
    // 자동 인식이 채울 수 있는 칸이면 `_ocrParsedSnapshot`의 키를 준다(F-09).
    // 스냅샷에 그 키가 있고 **값이 아직 그대로면** "자동 인식" 표시가 붙는다.
    // 사용자가 한 글자라도 고치면 값이 달라져 표시가 저절로 사라진다 — 별도
    // 상태를 두지 않는 이유다.
    String? ocrKey,
  }) {
    // 라벨을 입력란 위 별도 줄에 두지 않고 **입력란 안쪽 플로팅 라벨**로
    // 넣는다(사용자 요청, 2026-08-10). 필드마다 라벨 줄 하나와 그 아래 여백이
    // 사라져 한 화면에 항목이 서너 개 더 들어온다.
    //
    // 입력란 자체의 높이는 줄이지 않았다 — 터치 목표가 작아지면 오타를 고치기
    // 어려워진다. 줄인 것은 라벨이 차지하던 자리뿐이다.
    final isAutoFilled = _isStillOcrValue(ocrKey, controller);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "* 필수 입력 항목" 범례는 라벨 줄에 붙어 있었는데, 그 줄이 없어졌으니
        // 필드 위에 오른쪽 정렬로 따로 놓는다. 이 범례를 쓰는 필드는 첫 번째
        // (이름) 하나뿐이라 화면 전체로 보면 한 줄만 늘어난다.
        if (trailingLegend != null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              trailingLegend,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.destructive,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
          inputFormatters: inputFormatters,
          maxLines: maxLines,
          textInputAction: maxLines > 1
              ? TextInputAction.newline
              : (isLast ? TextInputAction.done : TextInputAction.next),
          onEditingComplete: () {
            if (nextFocusNode != null) {
              nextFocusNode.requestFocus();
            } else {
              FocusScope.of(context).unfocus();
            }
          },
          onFieldSubmitted: (_) {
            if (nextFocusNode != null) {
              FocusScope.of(context).requestFocus(nextFocusNode);
            }
          },
          validator: validator,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            // 비어 있을 때는 라벨이 입력란 안에 앉아 있다가, 입력을 시작하면
            // 위로 떠올라 테두리에 걸린다. 떠오른 뒤에도 무슨 항목인지 계속
            // 보이므로 별도 라벨 줄이 필요 없다.
            labelStyle: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: label.contains('*')
                  ? AppColors.accentText
                  : AppColors.textSecondary,
            ),
            floatingLabelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: label.contains('*')
                  ? AppColors.accentText
                  : AppColors.textSecondary,
            ),
            // 라벨이 떠 있는 동안에만 예시 문구를 보여 준다. 둘을 동시에
            // 띄우면 한 칸에 글자가 두 줄로 겹쳐 읽기 어렵다.
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
            filled: true,
            // 자동 인식이 채운 값은 옅은 강조 배경으로 구분한다(F-09). 라벨 줄을
            // 하나 더 만들지 않으려고 배경·아이콘으로만 표시했다 — 이 폼은
            // 라벨 줄을 없애 항목을 더 담기로 한 이력이 있다(2026-08-10).
            fillColor: isAutoFilled ? AppColors.accentSoft : AppColors.bgBase,
            // 아이콘도 같은 이유로 칸 **안쪽**에 둔다. 세로 공간을 안 먹는다.
            prefixIcon: isAutoFilled
                ? const Tooltip(
                    message: '명함에서 자동으로 읽은 값이에요. 고치면 이 표시가 사라집니다.',
                    child: Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: AppColors.accentText,
                    ),
                  )
                : null,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 24,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            errorStyle: const TextStyle(
              color: AppColors.destructive,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderFunctional),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borderFunctional),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.accentText,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.destructive,
                width: 1.5,
              ),
            ),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}

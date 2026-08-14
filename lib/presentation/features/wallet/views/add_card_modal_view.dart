import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../../core/utils/korean_phone_formatter.dart';
import '../../../../core/utils/web_tab_guard.dart';
import '../../../../core/services/address_geocoding_service.dart';
import '../../../../core/services/contact_image_service.dart';
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
import 'camera_scan_modal_view.dart';
import 'file_picker_modal_view.dart';

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
  late TextEditingController _addressController;
  late TextEditingController _addressDetailController;
  late TextEditingController _postalCodeController;
  late TextEditingController _phoneController;
  late TextEditingController _officePhoneController;
  late TextEditingController _emailController;
  late TextEditingController _tagsController;
  late TextEditingController _interestsController;
  late TextEditingController _memoController;

  // Strict Contiguous Sequential Focus Nodes to prevent Tab/Enter key jumping
  final _nameFocusNode = FocusNode();
  final _companyFocusNode = FocusNode();
  final _titleFocusNode = FocusNode();
  final _addressFocusNode = FocusNode();
  final _addressDetailFocusNode = FocusNode();
  final _postalCodeFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _officePhoneFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
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
    _addressController = TextEditingController(text: c?.address ?? '');
    _addressDetailController = TextEditingController(
      text: c?.addressDetail ?? '',
    );
    _postalCodeController = TextEditingController(text: c?.postalCode ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _officePhoneController = TextEditingController(text: c?.officePhone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
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
      _addressFocusNode,
      _addressDetailFocusNode,
      _postalCodeFocusNode,
      _phoneFocusNode,
      _officePhoneFocusNode,
      _emailFocusNode,
      _tagsFocusNode,
      _interestsFocusNode,
      _memoFocusNode,
    ];
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
      'address': _addressController.text,
      'addressDetail': _addressDetailController.text,
      'postalCode': _postalCodeController.text,
      'phone': _phoneController.text,
      'officePhone': _officePhoneController.text,
      'email': _emailController.text,
      'tags': _tagsController.text,
      'interests': _interestsController.text,
      'memo': _memoController.text,
    };
  }

  @override
  void dispose() {
    WebTabGuard.uninstall();
    _nameController.dispose();
    _companyController.dispose();
    _titleController.dispose();
    _addressController.dispose();
    _addressDetailController.dispose();
    _postalCodeController.dispose();
    _phoneController.dispose();
    _officePhoneController.dispose();
    _emailController.dispose();
    _tagsController.dispose();
    _interestsController.dispose();
    _memoController.dispose();

    _nameFocusNode.dispose();
    _companyFocusNode.dispose();
    _titleFocusNode.dispose();
    _addressFocusNode.dispose();
    _addressDetailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _officePhoneFocusNode.dispose();
    _emailFocusNode.dispose();
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

  /// AI OCR Business Card Scanner (Camera / Image Gallery)
  Future<void> _performOcrScan({
    required bool isFromCamera,

    /// 지금 찍는 면. 카메라 화면에 그대로 표시된다(추가 191).
    String sideLabel = '앞면',
  }) async {
    OcrScanResult? result;

    if (isFromCamera) {
      // Open camera scanner view with viewfinder shutter
      result = await Navigator.push<OcrScanResult>(
        context,
        MaterialPageRoute(
          builder: (_) => CameraScanModalView(sideLabel: sideLabel),
        ),
      );
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
      'address': (_addressController, result.address),
      'addressDetail': (_addressDetailController, result.addressDetail),
      'postal': (_postalCodeController, result.postalCode),
      'mobile': (_phoneController, result.phone),
      'office': (_officePhoneController, result.officePhone),
      'email': (_emailController, result.email),
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
      _scannedRawLines = result.rawLines;
      if (overwrite) {
        // 다른 명함으로 새로 시작하는 것이므로 **이전 명함의 흔적을 전부**
        // 지운다. 예전에는 입력칸 9개만 새로 쓰고 아래 값들이 남아서, 새
        // 명함을 저장하는데 **좌표가 이전 명함 주소로 잡히는** 일이 가능했다
        // (backlog 추가 189).
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
        _setTextFromStart(_addressController, result.address);
        _setTextFromStart(_addressDetailController, result.addressDetail);
        _setTextFromStart(_postalCodeController, result.postalCode);
        _setTextFromStart(_phoneController, result.phone);
        _setTextFromStart(_officePhoneController, result.officePhone);
        _setTextFromStart(_emailController, result.email);
        _tagsController.text = result.tags.join(', ');
        _memoController.text = result.rawText.isEmpty
            ? ''
            : 'AI OCR 스캔으로 자동 추출된 명함 텍스트 정보입니다.';
      } else {
        // 명함 앞/뒷면에 정보가 나뉘어 있는 경우가 흔해서(예: 앞면엔 이름·직함만,
        // 뒷면에 전화번호·주소·이메일) 새 스캔 결과로 폼을 통째로 덮어쓰지 않고
        // "이미 채워진 필드는 그대로 두고, 비어 있는 필드만" 채운다 — 뒷면을
        // 이어서 스캔해도 앞면에서 읽은 값이 날아가지 않게.
        _fillIfEmpty(_nameController, result.name);
        _fillIfEmpty(_companyController, result.company);
        _fillIfEmpty(_titleController, result.title);
        _fillIfEmpty(_addressController, result.address);
        _fillIfEmpty(_addressDetailController, result.addressDetail);
        _fillIfEmpty(_postalCodeController, result.postalCode);
        _fillIfEmpty(_phoneController, result.phone);
        _fillIfEmpty(_officePhoneController, result.officePhone);
        _fillIfEmpty(_emailController, result.email);
        if (_tagsController.text.trim().isEmpty && result.tags.isNotEmpty) {
          _tagsController.text = result.tags.join(', ');
        }
        if (_memoController.text.trim().isEmpty) {
          _memoController.text = 'AI OCR 스캔으로 자동 추출된 명함 텍스트 정보입니다.';
        }
      }
    });

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
        // 방금 찍은 사진도 후보에서 뺀다.
        if (_scannedCardImages.isNotEmpty) {
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
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
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
                        '\'$text\' 텍스트 세팅',
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
                  '터치하면 해당 입력 칸으로 즉시 채워집니다.',
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
                    _quickMapTile('💼 직함', () {
                      _setTextFromStart(_titleController, text);
                    }),
                    _quickMapTile('📞 휴대폰 번호', () {
                      _setTextFromStart(_phoneController, text);
                    }),
                    _quickMapTile('✉️ 이메일', () {
                      _setTextFromStart(_emailController, text);
                    }),
                    _quickMapTile('📍 주소', () {
                      _setTextFromStart(_addressController, text);
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
                  child: Container(
                    width: 92,
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

    final rawAddress = _addressController.text.trim();
    if (rawAddress.isEmpty) {
      _focusAndShowError(_addressFocusNode, '⚠️ 회사 주소를 입력해 주세요.');
      return;
    }

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
    if (addressResult.roadNameAddress != null &&
        addressResult.roadNameAddress != rawAddress &&
        rawAddress != _confirmedRoadNameAddress) {
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
            onPressed: () => Navigator.pop(ctx),
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
      email: _emailController.text.trim(),
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
      email: _emailController.text.trim(),
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
        'email' => _emailController,
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
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
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
                              '📄 OCR 스캔 RAW 텍스트 확인 / 복원',
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
                              '💡 텍스트 칩을 터치하면 해당 항목으로 1초 세팅돼요:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_scannedRawLines.isNotEmpty)
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _scannedRawLines.map((line) {
                                  return InkWell(
                                    onTap: () =>
                                        _showQuickFieldMapperSheet(line),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.accent.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            line,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textPrimary,
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
                                  );
                                }).toList(),
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

                  // 1. 이름 (필수)
                  _buildFormField(
                    controller: _nameController,
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

                  // 3. 직함 / 부서 (선택)
                  _buildFormField(
                    controller: _titleController,
                    focusNode: _titleFocusNode,
                    order: 3,
                    nextFocusNode: _addressFocusNode,
                    label: '직함 / 부서',
                    hint: '예: 팀장 / R&D 센터',
                  ),
                  const SizedBox(height: 10),

                  // 4. 회사 주소 — 도로명까지(위치 정보/지오코딩의 기준이 되는 부분)
                  _buildFormField(
                    controller: _addressController,
                    focusNode: _addressFocusNode,
                    order: 4,
                    nextFocusNode: _addressDetailFocusNode,
                    label: '회사 주소 (도로명) *',
                    hint: '예: 서울특별시 강남구 테헤란로 123',
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return '회사 주소를 입력해 주세요.';
                      }
                      return null;
                    },
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
                    focusNode: _officePhoneFocusNode,
                    order: 6,
                    nextFocusNode: _emailFocusNode,
                    label: '사무실 전화번호 (선택)',
                    hint: '예: 02-123-4567',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 10),

                  // 7. 이메일 (필수!)
                  _buildFormField(
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    order: 7,
                    nextFocusNode: _tagsFocusNode,
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
  }) {
    // 라벨을 입력란 위 별도 줄에 두지 않고 **입력란 안쪽 플로팅 라벨**로
    // 넣는다(사용자 요청, 2026-08-10). 필드마다 라벨 줄 하나와 그 아래 여백이
    // 사라져 한 화면에 항목이 서너 개 더 들어온다.
    //
    // 입력란 자체의 높이는 줄이지 않았다 — 터치 목표가 작아지면 오타를 고치기
    // 어려워진다. 줄인 것은 라벨이 차지하던 자리뿐이다.
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
            fillColor: AppColors.bgBase,
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

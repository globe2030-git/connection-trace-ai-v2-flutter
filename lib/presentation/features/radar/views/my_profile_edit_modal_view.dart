import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../../core/utils/image_file_cache.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/korean_phone_formatter.dart';
import '../../../../core/services/ocr_scanner_service.dart';
import '../../../../core/utils/scan_temp_cleanup.dart';
import '../../../../data/models/my_profile_model.dart';
import '../../../../data/repositories/my_profile_repository.dart';
import '../../../common/address_search_view.dart';
import '../../wallet/views/camera_scan_modal_view.dart';
import '../../wallet/views/file_picker_modal_view.dart';

class MyProfileEditModalView extends StatefulWidget {
  const MyProfileEditModalView({super.key});

  /// `AddCardModalView.show()`와 같은 이유로 필요하다: isScrollControlled
  /// 시트가 내용 높이만큼 자라나는데, iOS는 필드 한 줄 높이가 안드로이드보다
  /// 커서 시트가 화면 맨 위까지 붙어 보인다(실기기 확인 — "명함지갑에서
  /// 수정할 때 올라오는 방식이 아니어서 너무 위로 올라갔어"). 명함 편집
  /// 화면은 이미 이 방식으로 고쳐져 있었는데 내 프로필 편집 화면엔 그 수정이
  /// 안 들어가 있었다 — 같은 상한을 적용한다.
  static Future<void> show(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height - topInset - 12,
      ),
      builder: (_) => const MyProfileEditModalView(),
    );
  }

  @override
  State<MyProfileEditModalView> createState() => _MyProfileEditModalViewState();
}

class _MyProfileEditModalViewState extends State<MyProfileEditModalView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _titleController;
  late final TextEditingController _companyController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _addressDetailController;
  // 아래 다섯은 OCR이 읽어 오면서도 담을 칸이 없어 버려지던 값이다(2026-08-26).
  late final TextEditingController _departmentController;
  late final TextEditingController _officePhoneController;
  late final TextEditingController _faxController;
  late final TextEditingController _websiteController;
  late final TextEditingController _postalCodeController;

  /// 이번 편집에서 명함을 몇 면 스캔했는지(0=아직, 1=앞면, 2=앞+뒷면).
  ///
  /// **명함 한 장은 앞면과 뒷면까지가 최대**다(사용자 정의 2026-08-14,
  /// 등록 화면과 같은 규칙). 이 값으로 카메라에 보낼 면 이름과 안내 문구를
  /// 정한다.
  ///
  /// ⚠️ 등록 화면과 달리 **사진을 보관하지 않으므로 대표 선택·면 빼기는
  /// 없다.** 여기서 세는 것은 "무엇을 찍는 중인가"뿐이다.
  int _scanCount = 0;

  /// 생일(월·일). 저장은 "MM-DD" 한 문자열이지만 입력은 두 목록으로 받는다.
  int? _birthMonth;
  int? _birthDay;

  // 이 화면은 자체 Scaffold 없이 showModalBottomSheet의 콘텐츠로만 쓰여서
  // ScaffoldMessenger.of(context)를 쓰면 스낵바가 모달 뒤 페이지로 가서 안 보이고,
  // Scaffold로 감싸면 시트 높이 계산과 충돌해 레이아웃이 깨진다(add_card_modal_view.dart
  // 에서 실기기로 확인된 문제) — 폼 안에 직접 그리는 배너로 우회한다.
  String? _inlineNoticeText;
  bool _inlineNoticeIsError = false;
  String? _inlineNoticeActionLabel;
  VoidCallback? _inlineNoticeAction;

  String? _avatarPath;
  bool _avatarCleared = false;
  bool _isPickingAvatar = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<MyProfileRepository>().profile;
    _nameController = TextEditingController(text: profile.name);
    _titleController = TextEditingController(text: profile.title);
    _companyController = TextEditingController(text: profile.company);
    _phoneController = TextEditingController(text: profile.phone);
    _emailController = TextEditingController(text: profile.email);
    _addressController = TextEditingController(text: profile.address);
    _departmentController = TextEditingController(
      text: profile.department ?? '',
    );
    _officePhoneController = TextEditingController(
      text: profile.officePhone ?? '',
    );
    _faxController = TextEditingController(text: profile.fax ?? '');
    _websiteController = TextEditingController(text: profile.website ?? '');
    _postalCodeController = TextEditingController(
      text: profile.postalCode ?? '',
    );
    _birthMonth = profile.birthMonth;
    _birthDay = profile.birthDay;
    _addressDetailController = TextEditingController(
      text: profile.addressDetail ?? '',
    );
    _avatarPath = profile.avatarPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _addressDetailController.dispose();
    _departmentController.dispose();
    _officePhoneController.dispose();
    _faxController.dispose();
    _websiteController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  Future<void> _openAddressSearch() async {
    // 입력칸에 이미 있는 주소를 검색어로 넘긴다. 안 넘기면 빈 검색창이 떠
    // 처음부터 다시 타이핑해야 한다 — 명함 등록 화면은 넘기고 있었는데
    // 이 화면만 빠져 있었다(사용자 제보, 2026-08-26).
    //
    // ⚠️ 예전에는 클립보드에 복사해 두는 방식이라 넘기지 않아도 티가 덜
    // 났는데, 그 방식을 걷어내면서(웹뷰에서 붙여넣기가 안 됐다) 이 화면만
    // **기존 주소가 검색창으로 가는 경로가 아예 없는** 상태가 됐다.
    final query = _addressController.text.trim();
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
      // 아파트/오피스텔처럼 건물명이 있는 주소는 상세주소 칸이 비어 있을 때만
      // 자동으로 채운다 — 이미 동/호수 등을 직접 입력해 뒀다면 덮어쓰지 않음.
      // 건물명이 주소 문장에 이미 들어간 경우(공동주택 등)에는 상세주소에
      // 중복으로 넣지 않는다.
      if (result.buildingName != null &&
          !picked.contains(result.buildingName!) &&
          _addressDetailController.text.trim().isEmpty) {
        _addressDetailController.text = result.buildingName!;
      }
    });
  }

  /// `controller.text = value`만 쓰면 커서가 맨 끝으로 가서, 한 줄짜리 주소
  /// 입력칸에서 시작 부분이 아니라 끝부분만 스크롤되어 보여 "글자가 잘려서
  /// 들어간 것"처럼 보이는 문제가 있었다. 커서를 맨 앞(0)으로 둬서 항상
  /// 텍스트 시작부터 보이게 한다.
  void _setTextFromStart(TextEditingController controller, String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  /// 내 명함도 실물 명함을 스캔해서 채울 수 있어야 한다는 요청으로 추가 —
  /// 명함 등록 화면과 동일한 카메라/파일 스캔을 재사용한다. 이 화면은 "이미
  /// 채워진 프로필을 고치는" 폼이라 명함 등록 때처럼 빈 칸만 채우는 방식이
  /// 아니라, 스캔으로 실제 읽힌 값만(빈 문자열은 무시) 기존 값 위에 덮어써
  /// "실물 명함으로 프로필을 최신화"하는 의도에 맞춘다.
  Future<void> _performOcrScan({
    required bool isFromCamera,
    String sideLabel = '앞면',
  }) async {
    OcrScanResult? result;
    if (isFromCamera) {
      result = await Navigator.push<OcrScanResult>(
        context,
        // 지금 어느 면을 찍는 중인지 카메라 화면에 띄운다. 종전에는 이 화면이
        // 라벨을 안 넘겨 **언제나 "앞면"으로 보였다** — 뒷면을 고르고 들어와도
        // 알 수 없었다(등록 화면이 2026-08-14에 같은 이유로 고친 자리다).
        MaterialPageRoute(
          builder: (_) => CameraScanModalView(sideLabel: sideLabel),
        ),
      );
    } else {
      result = await showModalBottomSheet<OcrScanResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FilePickerModalView(sideLabel: sideLabel),
      );
    }
    // 이 화면은 **텍스트만 쓰고 이미지는 저장하지 않는다.** 그래서 스캔이 남긴
    // 평문 사진 파일을 아무도 지우지 않는다 — 명함 등록 화면은 저장하면서
    // 지우지만(`saveEncryptedCardImage`), 여기는 그 경로를 아예 안 지난다.
    //
    // 결과를 다 쓴 뒤에 지운다. 지금 지워도 되는 이유는 아래에서 `result`의
    // **문자열 필드만** 읽고 파일은 다시 열지 않기 때문이다.
    if (result != null) unawaited(deleteQuietly(result.imagePath));
    if (result == null || !mounted) return;

    setState(() {
      // 면 하나를 읽었다. 등록 화면과 달리 사진을 쌓지 않으므로 세기만 한다.
      if (_scanCount < 2) _scanCount++;
      final scanned = result!;
      // 읽힌 값만 덮어쓴다 — 빈 문자열은 "못 읽었다"는 뜻이라, 그걸로 덮으면
      // 사용자가 손으로 넣어 둔 값이 스캔 한 번에 지워진다.
      void fill(TextEditingController controller, String value) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) controller.text = trimmed;
      }

      fill(_nameController, scanned.name);
      fill(_titleController, scanned.title);
      fill(_companyController, scanned.company);
      fill(_phoneController, scanned.phone);
      fill(_emailController, scanned.email);
      final address = scanned.address.trim();
      // 주소만 다른 함수를 쓴다 — 한 줄짜리 칸이라 커서가 끝으로 가면
      // 주소 앞부분이 안 보인다(_setTextFromStart 주석 참고).
      if (address.isNotEmpty) _setTextFromStart(_addressController, address);
      fill(_addressDetailController, scanned.addressDetail);
      // 아래 다섯은 OCR이 예전부터 읽고 있었는데 **받을 칸이 없어 버려졌다**
      // (2026-08-26 사용자 지적). 칸을 만들면서 함께 잇는다.
      fill(_departmentController, scanned.department);
      fill(_officePhoneController, scanned.officePhone);
      fill(_faxController, scanned.fax);
      fill(_websiteController, scanned.website);
      fill(_postalCodeController, scanned.postalCode);
    });

    // 명함 앞/뒷면에 정보가 나뉜 경우가 흔해서(add_card_modal_view.dart와 동일한
    // 패턴) 못 채운 칸이 있으면 "뒷면도 스캔해 보라"고 안내한다.
    //
    // ⚠️ **필수와 선택을 갈라서 본다**(2026-08-26). 종전에는 필수 다섯만 보고
    // 판정해서, 앞면에 그 다섯이 다 있으면 안내가 안 떴다. 그런데 **웹사이트·
    // 팩스·부서는 뒷면에 있는 경우가 흔하다** — 안내가 안 뜨면 뒷면을 찍을
    // 버튼도 안 나오고, 그 값들은 영영 안 들어온다(사용자 지적).
    final missingRequired = <String>[
      if (_nameController.text.trim().isEmpty) '이름',
      if (_companyController.text.trim().isEmpty) '회사명',
      if (_addressController.text.trim().isEmpty) '주소',
      if (_phoneController.text.trim().isEmpty) '휴대폰 번호',
      if (_emailController.text.trim().isEmpty) '이메일',
    ];
    final missingOptional = <String>[
      if (_departmentController.text.trim().isEmpty) '부서',
      if (_officePhoneController.text.trim().isEmpty) '사무실 전화',
      if (_faxController.text.trim().isEmpty) '팩스',
      if (_websiteController.text.trim().isEmpty) '웹사이트',
      if (_postalCodeController.text.trim().isEmpty) '우편번호',
    ];

    if (!mounted) return;

    // 뒷면까지 찍었으면 더 권하지 않는다 — 명함은 두 면이 최대다.
    final canScanBack = _scanCount < 2;

    if (missingRequired.isEmpty && missingOptional.isEmpty) {
      _showInlineNotice(
        '📸 스캔한 명함 정보로 채웠습니다. AI 인식이 완벽하지 않을 수 있으니 내용을 확인하고 저장해 주세요.',
        isError: false,
      );
      return;
    }

    if (missingRequired.isNotEmpty) {
      _showInlineNotice(
        '⚠️ ${missingRequired.join(', ')} 정보를 찾지 못했습니다. 명함 뒷면에 있을 수도 있어요'
        '${canScanBack ? ' — 뒷면도 스캔해 보세요.' : '. 직접 입력해 주세요.'}',
        isError: true,
        actionLabel: canScanBack ? '뒷면 스캔' : null,
        onAction: canScanBack
            ? () => _performOcrScan(isFromCamera: isFromCamera, sideLabel: '뒷면')
            : null,
      );
      return;
    }

    // 여기부터는 선택 항목만 빈 경우다. **없어도 되는 값이므로 경고가 아니다** —
    // 빨간 문구로 띄우면 "뭔가 잘못됐다"로 읽힌다.
    _showInlineNotice(
      '📸 채웠습니다. ${missingOptional.join(', ')}은(는) 못 찾았어요 — 선택 항목이라 비워 두셔도 됩니다'
      '${canScanBack ? '. 명함 뒷면에 있다면 뒷면도 스캔해 보세요.' : '.'}',
      isError: false,
      actionLabel: canScanBack ? '뒷면 스캔' : null,
      onAction: canScanBack
          ? () => _performOcrScan(isFromCamera: isFromCamera, sideLabel: '뒷면')
          : null,
    );
  }

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

  /// 갤러리에서 고른 사진을 앱 문서 디렉터리에 고정된 파일명으로 복사해 둔다.
  /// image_picker가 주는 경로는 임시 캐시라 앱 재시작 시 사라질 수 있어서,
  /// 영구 보관하려면 직접 복사해야 한다. 매번 같은 파일명으로 덮어써서
  /// 이전 사진 파일이 버려지지 않게 한다.
  ///
  /// ⚠️ 그 대가로 **이미지 캐시를 직접 비워야 한다.** `FileImage`는 경로로
  /// 캐시 키를 잡아서, 내용이 바뀌어도 경로가 같으면 옛 사진을 그대로 보여준다
  /// (통합본 E-07 — `evictImageFileCache` 주석 참고).
  Future<void> _pickAvatarPhoto() async {
    setState(() => _isPickingAvatar = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return;
      final docsDir = await getApplicationDocumentsDirectory();
      final savedPath = '${docsDir.path}/my_profile_avatar.jpg';
      await File(picked.path).copy(savedPath);
      // 복사가 끝나면 고른 사본은 쓰임이 끝났다 — **평문이므로 지운다**
      // (추가 247). 실기기에서 이 사본이 그대로 남아 있었다
      // (`cache/scaled_743.png`, 2026-08-14자).
      //
      // ⚠️ `!mounted`로 먼저 빠져나가면 안 된다. 사진을 고르는 사이 화면이
      // 닫히는 경우가 있는데, 그때가 **아무도 안 지우는** 경우다. 그래서
      // 복사·삭제를 먼저 하고 화면 갱신만 mounted로 막는다.
      unawaited(deleteQuietly(picked.path));
      await evictImageFileCache(savedPath);
      if (!mounted) return;
      setState(() {
        _avatarPath = savedPath;
        _avatarCleared = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _inlineNoticeText = '⚠️ 사진을 불러오지 못했습니다: $e');
    } finally {
      if (mounted) setState(() => _isPickingAvatar = false);
    }
  }

  void _removeAvatarPhoto() {
    setState(() {
      _avatarPath = null;
      _avatarCleared = true;
    });
  }

  /// 빈 칸은 `''`가 아니라 null로 저장한다 — 모델의 선택 항목이 전부
  /// nullable이고, `''`와 null이 섞이면 "값이 있나"를 두 가지로 물어야 한다.
  static String? _emptyToNull(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final updated = MyProfileModel(
      name: _nameController.text.trim(),
      title: _titleController.text.trim(),
      company: _companyController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
      addressDetail: _addressDetailController.text.trim().isEmpty
          ? null
          : _addressDetailController.text.trim(),
      department: _emptyToNull(_departmentController),
      officePhone: _emptyToNull(_officePhoneController),
      fax: _emptyToNull(_faxController),
      website: _emptyToNull(_websiteController),
      postalCode: _emptyToNull(_postalCodeController),
      avatarPath: _avatarCleared ? null : _avatarPath,
      // 월만 고르고 일을 안 고른 상태는 저장하지 않는다(formatMonthDay가 null).
      birthMonthDay: MyProfileModel.formatMonthDay(_birthMonth, _birthDay),
    );

    context.read<MyProfileRepository>().updateProfile(updated);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('👤 내 디지털 명함 정보를 저장했습니다.'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
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
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          AppIcon(
                            AppIconId.editCard,
                            size: 20,
                            color: AppColors.textPrimary,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '내 디지털 명함 수정',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Center(child: _buildAvatarPicker()),
                  const SizedBox(height: 16),

                  if (OcrScannerService.isSupportedOnThisPlatform) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _performOcrScan(isFromCamera: true),
                            icon: const AppIcon(
                              AppIconId.scanCard,
                              size: 18,
                              color: AppColors.accentText,
                            ),
                            label: const Text(
                              '내 명함 카메라 스캔',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.accentText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.accentText,
                              ),
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
                            onPressed: () =>
                                _performOcrScan(isFromCamera: false),
                            icon: const AppIcon(
                              AppIconId.galleryUpload,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            label: const Text(
                              '파일에서 스캔',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
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
                    // 앞면을 한 번 읽은 뒤에는 **안내가 없어도** 뒷면을 찍을 수
                    // 있어야 한다. 종전에는 뒷면으로 가는 길이 "못 찾은 항목이
                    // 있습니다" 안내에 딸린 버튼뿐이라, **앞면이 잘 읽히면
                    // 뒷면을 찍을 방법이 사라졌다**(사용자 지적 2026-08-26).
                    if (_scanCount == 1) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _performOcrScan(
                            isFromCamera: true,
                            sideLabel: '뒷면',
                          ),
                          icon: const AppIcon(
                            AppIconId.scanCard,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          label: const Text(
                            '뒷면도 스캔 (선택)',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
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
                    const SizedBox(height: 12),
                  ],

                  if (_inlineNoticeText != null) ...[
                    _buildInlineNotice(),
                    const SizedBox(height: 12),
                  ],

                  _buildField(
                    controller: _nameController,
                    label: '이름 / 직책 *',
                    hint: '예: 홍길동 대표',
                    required: true,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _titleController,
                    label: '직함',
                    hint: '예: C-Level',
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _companyController,
                    label: '회사명 *',
                    hint: '예: 커넥션 트레이스 AI',
                    required: true,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _departmentController,
                    label: '부서 (선택)',
                    hint: '예: 영업본부',
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _phoneController,
                    label: '휴대폰 번호 *',
                    hint: '예: 010-1234-5678',
                    keyboardType: TextInputType.phone,
                    required: true,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _officePhoneController,
                    label: '사무실 전화 (선택)',
                    hint: '예: 02-1234-5678',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _faxController,
                    label: '팩스 (선택)',
                    hint: '예: 02-1234-5679',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneNumberFormatter()],
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _emailController,
                    label: '이메일 *',
                    hint: '예: example@company.com',
                    keyboardType: TextInputType.emailAddress,
                    required: true,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty)
                        return '이메일을 입력해 주세요.';
                      if (!val.contains('@') || !val.contains('.'))
                        return '올바른 이메일 형식을 입력해 주세요.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _websiteController,
                    label: '웹사이트 (선택)',
                    hint: '예: https://example.com',
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _addressController,
                    label: '주소 (도로명) *',
                    hint: '예: 서울특별시 강남구 테헤란로 123',
                    required: true,
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.search,
                        color: AppColors.accentText,
                      ),
                      tooltip: '도로명주소 검색',
                      onPressed: _openAddressSearch,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _addressDetailController,
                    label: '상세주소 (선택)',
                    hint: '예: 5층 501호',
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _postalCodeController,
                    label: '우편번호 (선택)',
                    hint: '예: 06134',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  _buildBirthdayField(),

                  const SizedBox(height: 22),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const AppIcon(
                        AppIconId.saveDownload,
                        color: Colors.white,
                      ),
                      label: const Text(
                        '저장하기',
                        style: TextStyle(
                          fontSize: 15,
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

  void _dismissInlineNotice() {
    setState(() {
      _inlineNoticeText = null;
      _inlineNoticeIsError = false;
      _inlineNoticeActionLabel = null;
      _inlineNoticeAction = null;
    });
  }

  Widget _buildInlineNotice() {
    final color = _inlineNoticeIsError
        ? AppColors.destructive
        : AppColors.accent;
    return Container(
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

  Widget _buildAvatarPicker() {
    return Column(
      children: [
        Stack(
          children: [
            GestureDetector(
              onTap: _isPickingAvatar ? null : _pickAvatarPhoto,
              child: CircleAvatar(
                radius: 40,
                backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                backgroundImage: _avatarPath != null
                    ? FileImage(File(_avatarPath!))
                    : null,
                child: _isPickingAvatar
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accentText,
                        ),
                      )
                    : (_avatarPath == null
                          ? Text(
                              _nameController.text.trim().isNotEmpty
                                  ? _nameController.text.trim().substring(0, 1)
                                  : '?',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accentText,
                              ),
                            )
                          : null),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _isPickingAvatar ? null : _pickAvatarPhoto,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_avatarPath != null) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: _removeAvatarPhoto,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '사진 삭제',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.destructive,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 생일 입력 — 월/일 선택 목록 두 개.
  ///
  /// **자유 입력이 아닌 이유**: 저장 형식이 `"MM-DD"`로 0을 채운 두 자리여야
  /// 한다("이번 달 생일자"를 문자열 범위로 뽑기 때문). 텍스트로 받으면
  /// "10-1"·"10/1"·"10월 1일"이 섞여 들어와 그 규칙이 깨진다.
  ///
  /// **연도를 안 받는 이유**: 생일 축하·혜택에는 월일이면 충분한데, 연도가
  /// 붙으면 생년월일 전체가 되어 식별력이 크게 올라간다.
  Widget _buildBirthdayField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _birthMonth,
                isExpanded: true,
                decoration: _birthdayDecoration('생일 월 (선택)'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                dropdownColor: AppColors.cardSurface,
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('지정 안 함'),
                  ),
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem<int>(value: m, child: Text('$m월')),
                ],
                onChanged: (value) => setState(() {
                  _birthMonth = value;
                  if (value == null) {
                    _birthDay = null;
                  } else if (_birthDay != null &&
                      _birthDay! > _daysInMonth(value)) {
                    // 2월을 골랐는데 31일이 남아 있는 상태를 막는다.
                    _birthDay = _daysInMonth(value);
                  }
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _birthDay,
                isExpanded: true,
                decoration: _birthdayDecoration('생일 일 (선택)'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                dropdownColor: AppColors.cardSurface,
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('지정 안 함'),
                  ),
                  for (var d = 1; d <= _daysInMonth(_birthMonth); d++)
                    DropdownMenuItem<int>(value: d, child: Text('$d일')),
                ],
                // 월을 안 고르면 일만 저장할 수 없으므로 비활성화한다.
                onChanged: _birthMonth == null
                    ? null
                    : (value) => setState(() => _birthDay = value),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6, left: 4),
          child: Text(
            '연도는 받지 않습니다. 생일 축하와 혜택 안내에만 사용됩니다.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  /// 윤년은 따지지 않고 2월을 29일까지 허용한다 — 연도를 안 받으므로 판단할
  /// 근거가 없고, 2월 29일생을 못 고르게 막을 이유도 없다.
  int _daysInMonth(int? month) => switch (month) {
    2 => 29,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };

  InputDecoration _birthdayDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    ),
    floatingLabelStyle: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: AppColors.textSecondary,
    ),
    filled: true,
    fillColor: AppColors.bgBase,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      borderSide: const BorderSide(color: AppColors.accentText, width: 1.5),
    ),
  );

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool required = false,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    // 명함 등록·수정 화면과 같은 방식으로, 라벨을 별도 줄에 두지 않고
    // **입력란 안쪽 플로팅 라벨**로 넣는다(사용자 요청, 2026-08-10).
    // 필드마다 라벨 줄과 여백이 사라져 한 화면에 항목이 더 들어온다.
    // 입력란 높이는 그대로 둔다 — 줄인 것은 라벨이 차지하던 자리뿐이다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
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
          validator:
              validator ??
              (required
                  ? (val) => (val == null || val.trim().isEmpty)
                        ? '${label.replaceAll(' *', '')}을(를) 입력해 주세요.'
                        : null
                  : null),
        ),
      ],
    );
  }
}

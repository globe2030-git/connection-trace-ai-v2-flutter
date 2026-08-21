import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ocr_scanner_service.dart';
import '../../../../core/utils/gallery_pick_order.dart';
import '../../../../core/utils/gallery_picker_ui.dart';
import '../../../../core/utils/scan_temp_cleanup.dart';

/// 갤러리에서 **2장을 한 번에** 골랐을 때 각 장을 인식한 결과(P2-②).
///
/// [FilePickerModalView]가 `allowMultiSelect: false`(기본값)면 지금까지처럼
/// [OcrScanResult] 하나를 그대로 돌려준다 — 이 타입은 **그 계약을 바꾸지
/// 않는다.** `allowMultiSelect: true`인 호출부(명함 등록 화면의 첫 갤러리
/// 선택)만 이 타입으로 받는다.
///
/// ⚠️ **병합은 여기서 하지 않는다.** [results]는 순서만 있는 원문 인식
/// 결과 목록이고, 앞/뒷면을 실제 입력칸에 채워 넣는 것은 부르는 쪽
/// (`AddCardModalView._applyOcrResult`)이 **기존 앞/뒷면 누적 로직**을
/// 그대로 두 번 태워서 한다 — 새 병합 로직을 여기 만들지 않는다.
class GalleryOcrBatch {
  const GalleryOcrBatch(this.results);

  /// 선택 순서(사용자가 "순서 바꾸기"로 바로잡은 뒤) — 0번이 앞면, 1번이
  /// 있으면 뒷면.
  final List<OcrScanResult> results;
}

class FilePickerModalView extends StatefulWidget {
  /// 지금 고르는 면("앞면"/"뒷면"). 제목 옆에 표시한다.
  ///
  /// 카메라 화면과 같은 이유다(추가 191) — 뒷면 스캔을 골라 들어와도 화면에
  /// 표시가 없으면 지금 무엇을 넣는 중인지 알 수 없다.
  final String sideLabel;

  /// **최대 2장**을 한 번에 골라 앞/뒷면으로 배정할 수 있게 할지(P2-②).
  ///
  /// ⚠️ **기본값은 false다.** 이 화면은 명함 등록 화면 말고도 "내 프로필
  /// 수정"(`my_profile_edit_modal_view.dart`)에서도 단일 스캔 용도로 쓴다 —
  /// 그쪽은 `showModalBottomSheet<OcrScanResult>`로 이 화면을 부르므로,
  /// 여기서 [GalleryOcrBatch]를 돌려주면 타입이 안 맞아 터진다. **한 장만
  /// 고르는 기존 화면들은 이 값을 켜지 않은 채로 둔다** — 그러면 아래 로직이
  /// [_picked]가 1장 이하일 때 하던 대로 [OcrScanResult]를 그대로 반환한다.
  final bool allowMultiSelect;

  const FilePickerModalView({
    super.key,
    this.sideLabel = '앞면',
    this.allowMultiSelect = false,
  });

  @override
  State<FilePickerModalView> createState() => _FilePickerModalViewState();
}

class _FilePickerModalViewState extends State<FilePickerModalView> {
  // 이 화면은 자체 Scaffold 없이 showModalBottomSheet의 콘텐츠로만 쓰여서
  // ScaffoldMessenger.of(context)를 쓰면 스낵바가 모달 뒤 페이지로 가서 안 보이고,
  // Scaffold로 감싸면 시트 높이 계산과 충돌해 레이아웃이 깨진다 — 폼 안에 직접
  // 그리는 배너로 우회한다(add_card_modal_view.dart와 동일 패턴).
  String? _errorNotice;

  /// 고른 사진들 — **순서가 곧 앞(0)/뒷(1) 배정**이다(P2-②).
  ///
  /// ⚠️ `allowMultiSelect: false`인 기존 화면들에서는 이 목록의 길이가
  /// 0 또는 1을 절대 넘지 않는다 — 그 경우 아래 build()는 예전과 **똑같은**
  /// 위젯 트리를 그린다(배지·순서 바꾸기 없음).
  final List<XFile> _picked = [];
  final List<Uint8List> _pickedBytes = [];
  bool _isPicking = false;
  bool _isProcessing = false;

  /// 고른 사진의 **책임을 부른 쪽에 넘겼는지**(2026-08-16).
  ///
  /// 갤러리에서 고르면 image_picker가 **앱 임시 폴더에 사본을 만든다** — 이
  /// 사본은 평문이고, 명함 이미지에는 이름·전화·이메일이 인쇄돼 있어 그대로
  /// 두면 저장본을 암호화하는 이유가 무력해진다(추가 243).
  ///
  /// 인식에 성공해 결과를 넘기면(`Navigator.pop`) 그 사본은 **부른 쪽이
  /// 저장에 쓰므로 여기서 지우면 안 된다**(명함 등록 화면이
  /// `saveEncryptedCardImage`로 암호화한 뒤 지운다). 반대로 넘기지 못한 채
  /// 화면이 닫히면 아무도 안 쓰므로 여기서 지운다.
  ///
  /// ⚠️ 지우는 것은 **앱 임시 폴더의 사본**이지 사진첩 원본이 아니다.
  bool _handedOverToCaller = false;

  Future<void> _pickFromGallery() async {
    setState(() => _isPicking = true);
    try {
      // ⚠️ 갈아치우는 앞 사본들은 확실히 안 쓰인다 — 새로 고른 사진과
      // 경로가 겹치지 않는 것만 지운다(같은 사진을 다시 고르는 드문 경우
      // 방어).
      final discarded = List<XFile>.of(_picked);

      final List<XFile> newPicks;
      if (widget.allowMultiSelect) {
        newPicks = await OcrScannerService.pickUpToTwoImagesFromGallery();
      } else {
        final single = await OcrScannerService.pickImageFromGallery();
        newPicks = single == null ? [] : [single];
      }
      if (newPicks.isEmpty) return; // 사용자가 취소함 — 기존 선택 유지.

      final bytesList = <Uint8List>[];
      for (final file in newPicks) {
        bytesList.add(await file.readAsBytes());
      }

      for (final old in discarded) {
        if (!newPicks.any((f) => f.path == old.path)) {
          unawaited(deleteQuietly(old.path));
        }
      }

      if (!mounted) {
        // 고르는 사이에 화면이 닫혔다 — 아무도 안 쓸 사본이므로 지운다.
        for (final f in newPicks) {
          unawaited(deleteQuietly(f.path));
        }
        return;
      }
      setState(() {
        _picked
          ..clear()
          ..addAll(newPicks);
        _pickedBytes
          ..clear()
          ..addAll(bytesList);
      });
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  /// "앞·뒷면 순서 바꾸기"(P2-②) — 2장을 골랐을 때만 뜬다.
  ///
  /// 실제 계산은 [swapFrontBackOrder](순수 함수, `gallery_pick_order.dart`)
  /// 하나뿐이다 — 위젯 테스트 없이도 순서 로직을 검증하기 위해 뺐다.
  void _swapOrder() {
    setState(() {
      final files = swapFrontBackOrder(List.of(_picked));
      final bytes = swapFrontBackOrder(List.of(_pickedBytes));
      _picked
        ..clear()
        ..addAll(files);
      _pickedBytes
        ..clear()
        ..addAll(bytes);
    });
  }

  @override
  void dispose() {
    // 고르기만 하고 인식하지 않은 채 닫으면 사본이 남는다. 넘긴 것은
    // 부른 쪽이 책임지므로 건드리지 않는다.
    if (!_handedOverToCaller) {
      for (final f in _picked) {
        unawaited(deleteQuietly(f.path));
      }
    }
    super.dispose();
  }

  Future<void> _processSelectedImages() async {
    if (_picked.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final results = <OcrScanResult>[];
      for (final file in _picked) {
        results.add(await OcrScannerService.scanBusinessCard(file));
      }
      if (!mounted) return;
      _handedOverToCaller = true;
      if (widget.allowMultiSelect) {
        Navigator.pop(context, GalleryOcrBatch(results));
      } else {
        // ⚠️ **1장 경로는 예전과 같은 타입을 그대로 돌려준다** — 이 화면을
        // `showModalBottomSheet<OcrScanResult>`로 여는 다른 화면(내 프로필
        // 수정)이 있어, 여기서 타입을 바꾸면 그쪽이 깨진다.
        Navigator.pop(context, results.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _errorNotice = '⚠️ 명함 인식에 실패했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTwo = _picked.length == 2;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
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
                Row(
                  children: [
                    const AppIcon(
                      AppIconId.galleryUpload,
                      color: AppColors.accentText,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      // ⚠️ 2장을 고른 경우에만 문구가 바뀐다 — 0·1장일 때는
                      // 기존 화면과 글자까지 같다(순수 함수로 고정해 검증함).
                      galleryPickerHeaderTitle(
                        sideLabel: widget.sideLabel,
                        pickedCount: _picked.length,
                      ),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_errorNotice != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.destructive.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.destructive.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.destructive,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorNotice!,
                        style: const TextStyle(
                          color: AppColors.destructive,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.destructive,
                      ),
                      onPressed: () => setState(() => _errorNotice = null),
                    ),
                  ],
                ),
              ),

            if (!OcrScannerService.isSupportedOnThisPlatform)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.destructive.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.destructive.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.destructive,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '웹 브라우저에서는 OCR 인식이 지원되지 않습니다. 이미지 선택은 미리 볼 수 있지만, 실제 텍스트 인식은 모바일(Android/iOS) 앱에서만 가능합니다.',
                        style: TextStyle(
                          color: AppColors.destructive,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (widget.allowMultiSelect && _picked.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '앞·뒷면을 한 번에 최대 2장까지 고를 수 있어요. 1장만 골라도 됩니다.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),

            // 실제 기기 갤러리에서 고른 이미지 미리보기 / 선택 트리거
            Expanded(
              child: hasTwo
                  ? _buildTwoImagePreview()
                  : _buildSingleImagePreview(),
            ),

            if (hasTwo)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isPicking ? null : _swapOrder,
                  icon: const Icon(
                    Icons.swap_horiz,
                    size: 16,
                    color: AppColors.accentText,
                  ),
                  label: const Text(
                    '앞·뒷면 순서 바꾸기',
                    style: TextStyle(color: AppColors.accentText),
                  ),
                ),
              )
            else if (_picked.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isPicking ? null : _pickFromGallery,
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                    color: AppColors.accentText,
                  ),
                  label: const Text(
                    '다른 이미지 선택',
                    style: TextStyle(color: AppColors.accentText),
                  ),
                ),
              ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed:
                    (_picked.isEmpty ||
                        _isProcessing ||
                        !OcrScannerService.isSupportedOnThisPlatform)
                    ? null
                    : _processSelectedImages,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const AppIcon(AppIconId.scanCard, color: Colors.white),
                label: Text(
                  galleryPickerPrimaryButtonLabel(
                    isProcessing: _isProcessing,
                    pickedCount: _picked.length,
                  ),
                  style: const TextStyle(
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
    );
  }

  /// 0장 또는 1장일 때의 미리보기 — **기존 화면과 위젯 트리가 같다**
  /// (회귀 0을 위해 손대지 않은 부분).
  Widget _buildSingleImagePreview() {
    final bytes = _pickedBytes.isEmpty ? null : _pickedBytes.first;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: bytes != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                width: double.infinity,
              ),
            )
          : InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _isPicking ? null : _pickFromGallery,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isPicking)
                      const CircularProgressIndicator(
                        color: AppColors.accentText,
                      )
                    else ...[
                      const Icon(
                        Icons.add_photo_alternate,
                        size: 48,
                        color: AppColors.accentText,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.allowMultiSelect
                            ? '탭하여 갤러리에서 명함 사진 선택 (최대 2장)'
                            : '탭하여 갤러리에서 명함 사진 선택',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  /// 2장을 골랐을 때의 나란한 미리보기 — 순서 배지(1=앞면, 2=뒷면)를 얹는다
  /// (P2-②).
  Widget _buildTwoImagePreview() {
    return Row(
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _buildBadgedThumbnail(index: i)),
        ],
      ],
    );
  }

  Widget _buildBadgedThumbnail({required int index}) {
    final isFront = index == 0;
    return Stack(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.bgBase,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(
              _pickedBytes[index],
              fit: BoxFit.cover,
              height: double.infinity,
              width: double.infinity,
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isFront ? AppColors.accentText : AppColors.textSecondary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              isFront ? '앞면 1' : '뒷면 2',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

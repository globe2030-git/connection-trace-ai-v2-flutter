import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/ocr_scanner_service.dart';
import '../../../../core/utils/card_quad_warp.dart';
import '../../../../core/utils/crop_mode_corners.dart';
import '../../../../core/utils/gallery_crop_step.dart';
import '../../../../core/utils/gallery_pick_order.dart';
import '../../../../core/utils/gallery_picker_ui.dart';
import '../../../../core/utils/image_rotation_bake.dart';
import '../../../../core/utils/scan_temp_cleanup.dart';
import 'manual_crop_view.dart';

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

  /// 인식 전에 자르기 화면(`ManualCropView`)을 거치게 할지(398).
  ///
  /// ⚠️ **기본값은 false다.** 이 화면은 명함 등록(`add_card_modal_view.dart`)
  /// 말고도 "내 프로필 수정"(`my_profile_edit_modal_view.dart`)에서도 쓰는데,
  /// 398은 **명함 등록 경로만** 겨냥한 확장이다(브리프에 프로필 쪽 언급이
  /// 없어 회귀 0을 위해 손대지 않는 쪽을 택함 — PM 보고 참고). 명함 등록
  /// 화면만 이 값을 켠다.
  final bool enableManualCrop;

  const FilePickerModalView({
    super.key,
    this.sideLabel = '앞면',
    this.allowMultiSelect = false,
    this.enableManualCrop = false,
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
      final filesToScan = <XFile>[];
      // 자르기로 새 파일이 생겨 원본을 대신하게 된 경로들 — **성공해서 화면을
      // 닫기 직전에** 한꺼번에 지운다. 도중에 취소해 처음부터 다시 시도할 수
      // 있어야 하므로, 여기서 바로 지우지 않는다(아래 취소 분기 참고).
      final supersededOriginals = <String>[];

      if (widget.enableManualCrop) {
        for (var i = 0; i < _picked.length; i++) {
          final stepLabel = galleryCropStepLabel(
            index: i,
            totalCount: _picked.length,
          );
          final cropped = await _cropPickedImage(
            _picked[i],
            stepLabel: stepLabel,
          );
          if (!mounted) return;
          if (cropped == null) {
            // 자르기 화면에서 뒤로 가 취소했다 — 전체 처리를 중단하고 고른
            // 사진 목록으로 돌아간다(카메라 경로의 취소 처리와 같은 판단).
            setState(() => _isProcessing = false);
            return;
          }
          filesToScan.add(cropped);
          if (cropped.path != _picked[i].path) {
            supersededOriginals.add(_picked[i].path);
          }
        }
      } else {
        filesToScan.addAll(_picked);
      }

      final results = <OcrScanResult>[];
      for (final file in filesToScan) {
        results.add(await OcrScannerService.scanBusinessCard(file));
      }
      if (!mounted) return;
      _handedOverToCaller = true;
      for (final path in supersededOriginals) {
        await deleteQuietly(path);
      }
      // ⚠️ 위 삭제 루프도 await를 거치는 비동기 틈이다 — mounted를 한 번 더
      // 확인한 뒤에 context를 쓴다(use_build_context_synchronously).
      if (!mounted) return;
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

  /// 자르기 화면(`ManualCropView`)을 열어 갤러리 사진 한 장을 다듬는다(398).
  ///
  /// 반환:
  /// - 자르기 완료 → 잘라낸 새 파일.
  /// - [자르기 없이 사용] → [original] 그대로(공존 원칙 — 기존 동작).
  /// - 취소(뒤로 가기) → null. 부르는 쪽이 전체 처리를 중단한다.
  ///
  /// ⚠️ **[original] 자체는 이 함수가 지우지 않는다.** 도중에 취소하면
  /// 사용자가 같은 사진으로 다시 시도할 수 있어야 하는데, 여기서 원본을
  /// 지워 버리면 그 재시도가 "사진을 열지 못했습니다"로 막힌다 — 원본을
  /// 대신할 파일이 생겼을 때 원본을 지우는 결정은 **전체 배치가 끝까지
  /// 성공한 뒤에** [_processSelectedImages]가 한다.
  Future<XFile?> _cropPickedImage(XFile original, {String? stepLabel}) async {
    // ⚠️ **먼저 EXIF 방향을 굽는다**(398). `bakeExifOrientation` 문서
    // 참고 — 갤러리 사진은 이 화면에서 돌린 적이 없어도 파일 자체에 방향
    // 태그가 남아 있을 수 있다. 안 구우면 이 화면(Flutter `Image.file`)과
    // `warpCardToFile`(항상 굽는다)이 같은 파일을 다른 방향으로 읽는 조합이
    // 생겨, 자른 결과가 명함과 안 맞는다(추가 397과 같은 종류의 어긋남).
    final baked = await bakeExifOrientation(original);
    if (!mounted) {
      if (baked.path != original.path) unawaited(deleteQuietly(baked.path));
      return null;
    }

    final popped = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ManualCropView(
          imagePath: baked.path,
          allowSkip: true,
          stepLabel: stepLabel,
          // 398: 갤러리 원본은 실제 자동 테두리 검출을 거치지 않았다 —
          // [CropAdjustMode.auto]로 열면 "테두리를 자동으로 찾았어요" 배너가
          // 실제로 하지 않은 일을 한 것처럼 보인다(가짜 데이터 금지 원칙).
          // `ManualCropView.initialMode` 문서 참고.
          initialMode: CropAdjustMode.manual,
        ),
      ),
    );
    if (!mounted) {
      if (baked.path != original.path) unawaited(deleteQuietly(baked.path));
      return null;
    }

    final outcome = galleryCropOutcomeFor(popped);
    if (outcome == GalleryCropOutcome.cancelled) {
      if (baked.path != original.path) await deleteQuietly(baked.path);
      return null;
    }
    if (outcome == GalleryCropOutcome.useOriginal) {
      if (baked.path != original.path) await deleteQuietly(baked.path);
      return original;
    }

    // outcome == GalleryCropOutcome.cropped
    final picked = popped as ManualCropResult;
    // ⚠️ **워프의 실제 원본은 `picked.imagePath`이지 `baked.path`가
    // 아니다**(P2-③과 같은 이유). 크롭 화면 안에서 [회전]을 눌렀으면 그
    // 화면이 `baked.path` 위에 한 번 더 구운 파일을 기준으로 귀퉁이를
    // 찍어 뒀다 — `baked.path`를 그대로 쓰면 좌표계가 섞인다.
    final sourcePath = picked.imagePath;
    // baked·회전 중간본은 이 지점부터 더는 쓰이지 않는다(성공하든 실패하든).
    Future<void> cleanUpIntermediates() async {
      final intermediates = <String>{
        if (baked.path != original.path) baked.path,
        if (sourcePath != baked.path && sourcePath != original.path)
          sourcePath,
      };
      for (final path in intermediates) {
        await deleteQuietly(path);
      }
    }

    try {
      final outPath =
          '${Directory.systemTemp.path}/card_scan_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await compute(
        warpCardToFile,
        CardWarpRequest(
          sourcePath: sourcePath,
          visibleCornersFlat: cornersToFlat(picked.corners),
          screenWidth: picked.imageSize.width,
          screenHeight: picked.imageSize.height,
          outputPath: outPath,
          // 사람이 모서리를 직접 짚었으니 여백을 더하지 않는다.
          margin: 0,
          // ⚠️ 397 수정과 같은 좌표계를 그대로 쓴다 — 화면 매핑을 거치지
          // 않는다(갤러리 이미지는 EXIF 방향이 다양해 이 경로가 더 중요하다).
          cornersAreImageRelative: true,
          // 사용자가 자르기 화면의 [회전] 버튼과 귀퉁이로 방향을 이미
          // 확정했다 — 여기서 다시 뒤집지 않는다(추가 397).
          autoUpright: false,
        ),
      );
      await cleanUpIntermediates();
      if (result == null) {
        // 자르기 실패 — 원본으로 되돌아간다(카메라 경로와 같은 안전선).
        return original;
      }
      return XFile(result.path);
    } catch (_) {
      await cleanUpIntermediates();
      return original;
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

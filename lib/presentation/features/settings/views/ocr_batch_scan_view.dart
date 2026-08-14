import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/ocr_scanner_service.dart';
import '../../../../core/theme/app_colors.dart';

/// 관리자 전용 — 명함 이미지 여러 장을 한 번에 스캔해 파싱 결과를 표로 본다.
///
/// **왜 필요한가**: 인식 규칙을 고칠 때마다 한 장씩 눈으로 확인해서는 "전체가
/// 좋아졌는지"를 알 수 없다. 실제로 2026-08-13 하루 동안 로고·슬로건이 이름/
/// 회사명 칸을 침범하는 문제를 네 번 고쳤는데, 고칠 때마다 다른 모양의 변종이
/// 나왔고 매번 한 장씩 기기에서 확인해야 했다(backlog 추가 180). 여러 장을
/// 한 번에 돌려 표로 보면 어디가 틀리는지 한눈에 보이고, 이 표가 그대로
/// 정답 데이터의 초안이 된다.
///
/// ⚠️ **개인정보**: 이 화면은 명함 주인(제3자)의 이름·전화·이메일·주소를 그대로
/// 보여준다. 그래서 (1) 관리자에게만 노출하고, (2) 전부 기기 안에서만 처리하며
/// 서버로 아무것도 보내지 않고, (3) 로그에 값을 찍지 않는다(실패한 파일 수만
/// 센다). 클립보드 복사는 사용자가 버튼을 눌렀을 때만 일어난다.
class OcrBatchScanView extends StatefulWidget {
  const OcrBatchScanView({super.key});

  @override
  State<OcrBatchScanView> createState() => _OcrBatchScanViewState();
}

/// 한 장의 스캔 결과. 화면 표시와 클립보드 복사에만 쓰인다(저장하지 않는다).
class _BatchRow {
  final String fileName;
  final OcrScanResult? result;

  /// 스캔 자체가 실패한 경우. 개인정보가 섞이지 않도록 예외 타입만 담는다.
  final String? errorType;

  const _BatchRow({required this.fileName, this.result, this.errorType});
}

class _OcrBatchScanViewState extends State<OcrBatchScanView> {
  final List<_BatchRow> _rows = [];
  bool _running = false;
  int _done = 0;
  int _total = 0;

  /// 명함 이미지가 들어 있는 폴더를 찾아 통째로 읽는다.
  ///
  /// **왜 갤러리 선택기를 안 쓰나**: 시스템 선택기는 촬영일(EXIF) 순으로 정렬해서
  /// 예전 날짜의 명함 수십 장이 목록 아래에 묻힌다. 67장을 하나씩 눌러 고르는
  /// 것은 현실적이지 않았다(2026-08-13 실제로 시도하다 포기).
  ///
  /// **두 곳을 순서대로 본다.**
  /// 1. 앱 내부 문서 폴더 — `adb shell run-as`로 넣는다. 앱 소유라 항상 읽힌다.
  /// 2. 앱 전용 외부 저장소 — `adb push`로 넣기는 쉽지만, 그렇게 만든 폴더는
  ///    **shell 소유라 앱이 읽지 못하고** `PathAccessException(errno 13)`이 난다
  ///    (2026-08-13 실기기에서 확인). 기기·안드로이드 버전에 따라 되는 경우도
  ///    있어 후보로는 남겨 둔다.
  ///
  /// 넣는 방법은 `docs/planning/backlog.md` 추가 181 참고.
  Future<void> _scanFromAppFolder() async {
    final candidates = <Directory>[];
    try {
      final docs = await getApplicationDocumentsDirectory();
      candidates.add(Directory('${docs.path}/card_samples'));
    } catch (_) {
      // 경로를 못 얻으면 다음 후보로 넘어간다.
    }
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) candidates.add(Directory('${ext.path}/card_samples'));
    } catch (_) {
      // 안드로이드가 아니거나 외부 저장소가 없는 경우.
    }

    const exts = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'};
    final tried = <String>[];
    for (final dir in candidates) {
      tried.add(dir.path);
      List<FileSystemEntity> entries;
      try {
        if (!dir.existsSync()) continue;
        entries = dir.listSync();
      } catch (e) {
        // 권한 거부 등은 예외로 던져 화면을 멈추게 하지 말고 다음 후보로 넘어간다.
        // 예전에는 이 예외가 잡히지 않아 버튼을 눌러도 아무 일도 안 일어나는
        // 것처럼 보였다(로그에만 남았다).
        debugPrint('일괄 스캔 폴더 읽기 실패: ${e.runtimeType}');
        continue;
      }
      final images =
          entries
              .whereType<File>()
              .where((f) => exts.any((e) => f.path.toLowerCase().endsWith(e)))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      if (images.isNotEmpty) {
        await _runScan(images.map((f) => XFile(f.path)).toList());
        return;
      }
    }

    _toast(
      tried.isEmpty
          ? '앱 폴더를 찾지 못했습니다(안드로이드에서만 동작).'
          : '읽을 수 있는 이미지가 없습니다. 확인한 경로: ${tried.join(' , ')}',
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAndScan() async {
    final files = await OcrScannerService.pickImagesFromGallery();
    if (files.isEmpty || !mounted) return;
    await _runScan(files);
  }

  Future<void> _runScan(List<XFile> files) async {
    if (!mounted) return;

    setState(() {
      _rows.clear();
      _running = true;
      _done = 0;
      _total = files.length;
    });

    for (final file in files) {
      // 이름만 쓴다 — 전체 경로에는 사용자 계정명 등이 들어갈 수 있다.
      final fileName = file.name;
      _BatchRow row;
      try {
        final result = await OcrScannerService.scanBusinessCard(file);
        row = _BatchRow(fileName: fileName, result: result);
      } catch (e) {
        row = _BatchRow(fileName: fileName, errorType: e.runtimeType.toString());
      }
      if (!mounted) return;
      setState(() {
        _rows.add(row);
        _done++;
      });
    }

    if (!mounted) return;
    setState(() => _running = false);
  }

  /// 표를 파일로도 남긴다. 67줄짜리 표를 휴대폰 클립보드로 옮기는 것은
  /// 현실적이지 않아서(붙여넣을 곳이 마땅치 않다), 이미지와 같은 폴더에
  /// `scan_result.tsv`로 써 둔다. 맥에서는
  /// `adb shell run-as <패키지> cat app_flutter/card_samples/scan_result.tsv`로
  /// 그대로 읽을 수 있다.
  Future<void> _saveAsTsvFile() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/card_samples');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}/scan_result.tsv');
      file.writeAsStringSync(_buildTsv());
      _toast('저장했습니다: ${file.path}');
    } catch (e) {
      _toast('파일로 저장하지 못했습니다(${e.runtimeType}).');
    }
  }

  /// 표와 원본 이미지를 **기기 밖으로 내보낸다**(검수 도구에서 쓰려고).
  ///
  /// 예전에는 `adb shell run-as`로만 꺼낼 수 있어서, 검수를 하려면 맥에 개발
  /// 환경이 있어야 했다. 검수는 개발자가 아니어도 하는 일이라 공유 시트로
  /// 넘길 수 있게 한다(AirDrop·메일·파일 앱 등).
  ///
  /// ⚠️ 내보내는 파일에는 **명함 주인(제3자)의 실명·전화·이메일·주소**가 그대로
  /// 들어 있다. 그래서 어디로 보낼지는 반드시 사용자가 공유 시트에서 고르게
  /// 하고, 앱이 목적지를 정하지 않는다.
  Future<void> _shareTsv({required bool withImages}) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/card_samples');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final tsv = File('${dir.path}/scan_result.tsv');
      tsv.writeAsStringSync(_buildTsv());

      final files = <XFile>[XFile(tsv.path)];
      if (withImages) {
        final images =
            dir
                .listSync()
                .whereType<File>()
                .where(
                  (f) => RegExp(
                    r'\.(png|jpe?g)$',
                    caseSensitive: false,
                  ).hasMatch(f.path),
                )
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path));
        files.addAll(images.map((f) => XFile(f.path)));
      }
      await SharePlus.instance.share(
        ShareParams(
          files: files,
          subject: '명함 인식 검수 자료',
        ),
      );
    } catch (e) {
      _toast('내보내지 못했습니다(${e.runtimeType}).');
    }
  }

  Future<void> _copyAsTsv() async {
    await Clipboard.setData(ClipboardData(text: _buildTsv()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_rows.length}건을 클립보드에 복사했습니다.'),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  String _buildTsv() {
    final buffer = StringBuffer()
      ..writeln(
        [
          '파일명',
          '이름',
          '회사',
          '직함',
          '휴대폰',
          '사무실',
          '이메일',
          '우편번호',
          '주소',
          '상세주소',
          // 인식 원문. "왜 이 값이 들어갔나"를 표만 보고 알 수 없어서 덧붙인다 —
          // 이름을 왜 버렸는지 같은 판단은 원문 없이는 진단이 안 된다(추가 198).
          '원문',
        ].join('\t'),
      );
    for (final row in _rows) {
      final r = row.result;
      buffer.writeln(
        [
          row.fileName,
          r?.name ?? '(스캔 실패)',
          r?.company ?? '',
          r?.title ?? '',
          r?.phone ?? '',
          r?.officePhone ?? '',
          r?.email ?? '',
          r?.postalCode ?? '',
          r?.address ?? '',
          r?.addressDetail ?? '',
          (r?.rawLines ?? const <String>[]).join(' ⏐ '),
        ].map((s) => s.replaceAll('\t', ' ').replaceAll('\n', ' ')).join('\t'),
      );
    }
    return buffer.toString();
  }

  /// 채워진 항목 수 — "인식이 얼마나 됐나"의 거친 지표. 맞았는지는 사람이
  /// 확인해야 한다(그래서 표를 보여준다).
  int _filledCount(OcrScanResult r) => [
    r.name,
    r.company,
    r.title,
    r.phone,
    r.officePhone,
    r.email,
    r.address,
  ].where((v) => v.trim().isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('명함 일괄 스캔'),
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          if (_rows.isNotEmpty && !_running)
            IconButton(
              icon: const Icon(Icons.save_alt_outlined),
              tooltip: '표를 파일(scan_result.tsv)로 저장',
              onPressed: _saveAsTsvFile,
            ),
          if (_rows.isNotEmpty && !_running)
            IconButton(
              icon: const Icon(Icons.copy_all_outlined),
              tooltip: '표를 클립보드로 복사',
              onPressed: _copyAsTsv,
            ),
          if (_rows.isNotEmpty && !_running)
            PopupMenuButton<bool>(
              icon: const Icon(Icons.ios_share_outlined),
              tooltip: '검수용으로 내보내기',
              onSelected: (withImages) => _shareTsv(withImages: withImages),
              itemBuilder: (context) => const [
                PopupMenuItem(value: false, child: Text('표(TSV)만 내보내기')),
                PopupMenuItem(value: true, child: Text('표 + 명함 이미지 내보내기')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 18, color: AppColors.accentText),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '선택한 이미지는 기기 안에서만 처리하며 서버로 보내지 않습니다. '
                    '명함 주인의 개인정보가 그대로 표시되니 화면 공유에 주의하세요.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _running ? null : _pickAndScan,
                icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
                label: Text(
                  _running ? '스캔 중… ($_done / $_total)' : '명함 이미지 여러 장 선택',
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
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _running ? null : _scanFromAppFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('앱 폴더(card_samples) 전체 스캔'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accentText,
                  side: BorderSide(
                    color: AppColors.accent.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
          if (_running)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LinearProgressIndicator(
                value: _total == 0 ? null : _done / _total,
                backgroundColor: AppColors.textMuted.withValues(alpha: 0.15),
                color: AppColors.accent,
              ),
            ),
          Expanded(
            child: _rows.isEmpty
                ? const Center(
                    child: Text(
                      '아직 스캔한 명함이 없습니다.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _card(_rows[index], index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(_BatchRow row, int index) {
    final r = row.result;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${index + 1}.',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  row.fileName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (r != null)
                Text(
                  '${_filledCount(r)}/7',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentText,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (r == null)
            Text(
              '스캔 실패 (${row.errorType})',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            )
          else ...[
            _field('이름', r.name),
            _field('회사', r.company),
            _field('직함', r.title),
            _field('휴대폰', r.phone),
            _field('사무실', r.officePhone),
            _field('이메일', r.email),
            _field('주소', [
              r.postalCode,
              r.address,
              r.addressDetail,
            ].where((s) => s.trim().isNotEmpty).join(' ')),
          ],
        ],
      ),
    );
  }

  /// 빈 값은 "—"로 보여준다. 빈 칸으로 두면 "인식됐는데 화면이 안 그렸나"와
  /// 구분이 안 된다.
  Widget _field(String label, String value) {
    final empty = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              empty ? '—' : value,
              style: TextStyle(
                fontSize: 13,
                color: empty ? AppColors.textMuted : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

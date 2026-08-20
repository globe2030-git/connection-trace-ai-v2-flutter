import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/ocr_stats_service.dart';
import '../../../../core/services/geo_backfill_service.dart';
import '../../../../data/repositories/contacts_repository.dart';
import '../../../../core/theme/app_colors.dart';

/// 명함 인식(OCR 파싱) 품질 진단 화면.
///
/// 어떤 필드가 자주 비는지, 이름을 얼마나 약한 근거로 뽑는지, 사용자가 자동
/// 인식 결과를 얼마나 고치는지를 **값 없이 형태(비율)** 로만 보여준다. 개선
/// 로직을 어디에 넣을지 데이터로 판단하기 위한 것이다.
///
/// 표시되는 모든 수치는 이름/전화/이메일/주소 **원문을 담지 않는다.** 이
/// 기기에만 저장되며 서버로 전송하지 않는다.
class OcrStatsView extends StatefulWidget {
  const OcrStatsView({super.key});

  @override
  State<OcrStatsView> createState() => _OcrStatsViewState();
}

class _OcrStatsViewState extends State<OcrStatsView> {
  final OcrStatsService _service = OcrStatsService();
  OcrStatsSummary? _summary;
  /// 주소 → 좌표 변환 실패 형태 집계(추가 342). `{형태코드: 건수}`.
  Map<String, int> _geoFail = const {};
  bool _loading = true;

  static const _fieldLabels = {
    'name': '이름',
    'company': '회사명',
    'title': '직함',
    'mobile': '휴대폰',
    'office': '사무실 전화',
    'email': '이메일',
    'address': '주소',
    'addressDetail': '상세주소',
    'postal': '우편번호',
  };

  static const _nameSourceLabels = {
    'keywordSplit': '직함 줄에서 분리',
    'koreanStripped': '한글 이름줄',
    'mixedTokenFront': '혼용줄 앞 토큰',
    'mixedTokenLast': '혼용줄 끝 토큰',
    'fontSizePreferred': '글자 크기 폴백(개선)',
    'leftoverFallback': '맨 앞 줄 폴백(약함)',
    'none': '못 찾음',
  };

  static const _companySourceLabels = {
    'keyword': '회사 키워드',
    'leftoverPick': '남은 줄에서 선택',
    'none': '못 찾음',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summary = await _service.readSummary();
    final geoFail = await GeoBackfillService.readFailureShapeStats();
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _geoFail = geoFail;
      _loading = false;
    });
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('측정값 초기화'),
        content: const Text('지금까지 모은 명함 인식 통계를 지웁니다. 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('초기화', style: TextStyle(color: AppColors.destructive)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.reset();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        elevation: 0,
        title: const Text(
          '명함 인식 진단',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            tooltip: '측정값 초기화',
            icon: const Icon(Icons.delete_outline),
            onPressed: _summary?.isEmpty ?? true ? null : _confirmReset,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final s = _summary!;
    // ⚠️ 스캔 기록이 없어도 **좌표 실패는 따로 쌓인다**(주소는 손으로도 넣는다).
    // 둘 다 비었을 때만 빈 화면을 보여준다.
    if (s.isEmpty && _geoFail.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '아직 스캔 데이터가 없습니다.\n명함을 스캔해 등록하면 여기에\n인식 품질이 쌓입니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _privacyNote(),
        const SizedBox(height: 16),
        ..._geoFailureSection(),
        _card('전체', [
          _statRow('스캔 파싱 횟수', '${s.scans}회'),
          _statRow(
            '자동 인식을 고친 명함',
            '${s.correctedCards}건'
            '${s.scans > 0 ? ' (${_pct(s.correctedCards, s.scans)})' : ''}',
          ),
        ]),
        const SizedBox(height: 16),
        _card(
          '필드별 인식률 (채워진 비율)',
          [
            for (final key in _fieldLabels.keys)
              _statRow(
                _fieldLabels[key]!,
                '${s.filled[key] ?? 0}/${s.scans}'
                ' (${_pct(s.filled[key] ?? 0, s.scans)})',
              ),
          ],
        ),
        const SizedBox(height: 16),
        _card(
          '이름을 뽑은 경로',
          [
            for (final entry in _sortedEntries(s.nameSource))
              _statRow(
                _nameSourceLabels[entry.key] ?? entry.key,
                '${entry.value} (${_pct(entry.value, s.scans)})',
              ),
          ],
        ),
        const SizedBox(height: 16),
        _card(
          '회사명을 뽑은 경로',
          [
            for (final entry in _sortedEntries(s.companySource))
              _statRow(
                _companySourceLabels[entry.key] ?? entry.key,
                '${entry.value} (${_pct(entry.value, s.scans)})',
              ),
          ],
        ),
        const SizedBox(height: 16),
        _card(
          '필드별 사용자 수정 (오인식 신호)',
          _correctionRows(s),
        ),
      ],
    );
  }

  List<Widget> _correctionRows(OcrStatsSummary s) {
    final rows = <Widget>[];
    for (final key in _fieldLabels.keys) {
      final byKind = s.corrections[key];
      if (byKind == null) continue;
      final edited = byKind['edited'] ?? 0;
      final cleared = byKind['cleared'] ?? 0;
      if (edited == 0 && cleared == 0) continue;
      rows.add(
        _statRow(
          _fieldLabels[key]!,
          '고침 $edited · 지움 $cleared',
        ),
      );
    }
    if (rows.isEmpty) {
      rows.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '아직 수정 기록이 없습니다.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }
    return rows;
  }

  List<MapEntry<String, int>> _sortedEntries(Map<String, int> m) {
    final entries = m.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  String _pct(int n, int total) {
    if (total <= 0) return '0%';
    return '${(n * 100 / total).round()}%';
  }

  /// 주소 → 좌표 변환 실패를 **형태별로** 보여준다(추가 342).
  ///
  /// ## 왜 화면이 필요했나
  ///
  /// 집계는 `GeoBackfillService`가 예전부터 쌓고 있었는데 **보여 주는 곳이
  /// 없었다.** 읽는 함수 주석에 *"진단 화면용"*이라고 적혀 있었지만 그 화면이
  /// 없었다.
  ///
  /// ⚠️ **`adb`로는 못 꺼낸다** — 2026-08-20 실측:
  ///
  /// ```
  /// adb run-as    release 빌드는 debuggable이 아니라 거부된다
  /// adb backup    안드로이드 12 이후 앱 데이터를 안 내준다(헤더 47바이트만 왔다)
  /// ```
  ///
  /// debug 빌드를 얹으면 재설치가 되어 **재려던 데이터가 날아간다.** 그래서
  /// 화면이 유일한 길이다.
  ///
  /// ## 무엇에 쓰나
  ///
  /// 이 숫자가 판단 셋을 붙잡고 있다 — 주소 검색 API를 바꿀지, 좌표를 서버에
  /// 둘지, backfill이 배터리를 얼마나 먹는지.
  ///
  /// ⚠️ **개인정보는 안 담긴다.** 동 이름·번지·건물명은 애초에 저장하지 않고
  /// *"도로명인가/지번인가/숫자가 있나/건물명이 있나/길이"*만 남는다.
  List<Widget> _geoFailureSection() {
    // ⚠️ **분모를 함께 보여준다**(추가 344). 건수만으로는 *"11건이 많은 건가"*를
    // 말할 수 없다 — 주소 있는 명함 20장 중이면 시급하고 150장 중이면 아니다.
    //
    // 명함 목록에서 **지금 상태로** 센다. 시도 횟수를 새로 세면 0부터 시작해
    // 이미 쌓인 실패와 짝이 안 맞는다.
    final cov = GeoBackfillService.countGeoCoverage(
      context.read<ContactsRepository>().contacts,
    );
    if (_geoFail.isEmpty && cov.withAddress == 0) return const [];
    final total = _geoFail.values.fold<int>(0, (a, b) => a + b);
    final sorted = _geoFail.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      _card('주소 → 좌표 변환', [
        _statRow('주소가 있는 명함', '${cov.withAddress}장'),
        _statRow(
          '그중 좌표가 없음',
          '${cov.missingGeo}장'
          '${cov.withAddress > 0 ? ' (${_pct(cov.missingGeo, cov.withAddress)})' : ''}',
        ),
        if (total > 0) _statRow('실패로 기록된 횟수', '$total건'),
        for (final e in sorted)
          _statRow(GeoBackfillService.describeFailureShape(e.key), '${e.value}건'),
      ]),
      const SizedBox(height: 16),
    ];
  }

  Widget _privacyNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: AppColors.accentText),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '이 통계는 이름·전화·이메일·주소 같은 값을 담지 않습니다(형태·비율만). '
              '명함 인식 품질을 개선하기 위해 익명 통계로 수집될 수 있습니다.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.accentText,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

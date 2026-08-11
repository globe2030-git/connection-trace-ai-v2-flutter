import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ocr_scanner_service.dart';

/// 사용자가 자동 인식 결과를 저장 시점에 어떻게 바꿨는지의 형태.
/// **값(무엇으로 바꿨는지)은 남기지 않는다** — "바꿨다/지웠다/직접 채웠다"만.
enum OcrCorrectionKind {
  /// 파서가 채운 값을 사용자가 그대로 저장(수정 안 함).
  unchanged,

  /// 파서가 채운 값을 다른 값으로 고쳤다(오인식 신호).
  edited,

  /// 파서가 채운 값을 지워서 비웠다(잘못 채운 신호).
  cleared,
}

/// 명함 인식(OCR 파싱) 품질을 **개인정보 없이** 측정하기 위한 기기 내부 집계.
///
/// ### 왜 필요한가
/// 이 앱에서 실제로 터진 결함은 "코드는 맞는데 실물이 틀린" 유형이었다. 명함
/// 인식도 마찬가지로, 어떤 명함에서 어떤 필드가 자주 비는지·이름을 얼마나
/// 약한 근거로 찍는지는 실제 사용 데이터로만 보인다. 그 데이터를 원문 없이
/// 모으기 위한 것이다.
///
/// ### 개인정보 원칙
/// - 이름/전화/이메일/주소 **원문을 절대 저장하지 않는다.** 채워졌는지(0/1),
///   어떤 규칙으로 뽑았는지, 줄이 몇 개인지 같은 **형태**만 센다.
/// - 그래서 값이 아닌 집계(카운터)만 남고, 일반 `shared_preferences`(암호화
///   안 됨)에 둬도 유출될 개인정보가 없다.
/// - **서버로는 형태 집계만 올린다(2026-08-11).** 로그인한 사용자의 익명
///   집계를 `ocrStats/{uid}`에 올려 관리자 콘솔에서 전 사용자 인식률을 본다.
///   올라가는 값도 여전히 카운트뿐이라 개인정보가 없다. 사용자가 앱을 거치지
///   않고 조작해도 관리자 통계만 지저분해질 뿐 보안 영향이 없어(돈·한도와
///   다름) 소유자-쓰기를 허용한다(firestore.rules `ocrStats`).
class OcrStatsService {
  static const String _key = 'ocr_parse_stats_v1';

  /// 테스트에서 갈아끼울 수 있게 열어 둔다.
  final Future<SharedPreferences> Function() _prefs;

  /// 서버 업로드를 켤지. 위젯/유닛 테스트에서 Firebase가 없을 때 꺼서 잡음을
  /// 없앤다(실사용에선 항상 켜짐 — Firebase 미초기화면 어차피 조용히 실패).
  final bool _uploadEnabled;

  OcrStatsService({
    Future<SharedPreferences> Function()? prefs,
    this._uploadEnabled = true,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  /// 한 번의 스캔 파싱 결과 형태를 집계에 더한다.
  Future<void> recordParse(OcrParseShape shape) async {
    final data = await _load();
    data.scans++;
    if (shape.nameFilled) data.filled['name'] = (data.filled['name'] ?? 0) + 1;
    if (shape.companyFilled) {
      data.filled['company'] = (data.filled['company'] ?? 0) + 1;
    }
    if (shape.titleFilled) {
      data.filled['title'] = (data.filled['title'] ?? 0) + 1;
    }
    if (shape.mobileFilled) {
      data.filled['mobile'] = (data.filled['mobile'] ?? 0) + 1;
    }
    if (shape.officeFilled) {
      data.filled['office'] = (data.filled['office'] ?? 0) + 1;
    }
    if (shape.emailFilled) {
      data.filled['email'] = (data.filled['email'] ?? 0) + 1;
    }
    if (shape.addressFilled) {
      data.filled['address'] = (data.filled['address'] ?? 0) + 1;
    }
    if (shape.addressDetailFilled) {
      data.filled['addressDetail'] = (data.filled['addressDetail'] ?? 0) + 1;
    }
    if (shape.postalFilled) {
      data.filled['postal'] = (data.filled['postal'] ?? 0) + 1;
    }
    final ns = shape.nameSource.name;
    data.nameSource[ns] = (data.nameSource[ns] ?? 0) + 1;
    final cs = shape.companySource.name;
    data.companySource[cs] = (data.companySource[cs] ?? 0) + 1;
    await _save(data);
    unawaited(_uploadIfPossible(data));
  }

  /// 저장 시점에 사용자가 필드별로 파서 결과를 어떻게 바꿨는지를 집계한다.
  /// [corrections]는 `필드명 -> 수정 종류`. unchanged는 세지 않아도 되지만
  /// 넣어도 무방하다(분모 계산용으로 저장한다).
  Future<void> recordCorrections(
    Map<String, OcrCorrectionKind> corrections,
  ) async {
    if (corrections.isEmpty) return;
    final data = await _load();
    data.correctedCards++;
    corrections.forEach((field, kind) {
      final byKind = data.corrections.putIfAbsent(field, () => {});
      final k = kind.name;
      byKind[k] = (byKind[k] ?? 0) + 1;
    });
    await _save(data);
    unawaited(_uploadIfPossible(data));
  }

  /// 로그인한 사용자의 집계(형태만)를 `ocrStats/{uid}`에 통째로 덮어쓴다.
  /// 개인정보는 없다 — 필드별 카운트와 경로 분포뿐. 실패는 조용히 무시한다
  /// (오프라인·비로그인·Firebase 미초기화 모두 여기서 삼킨다).
  Future<void> _uploadIfPossible(_OcrStatsData data) async {
    if (!_uploadEnabled) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return; // 게스트는 올리지 않는다.
      await FirebaseFirestore.instance.collection('ocrStats').doc(uid).set({
        ...data.toJson(),
        // 안드로이드/iOS 인식률 차이를 관리자에서 보기 위한 플랫폼 태그(개인
        // 식별과 무관). defaultTargetPlatform은 'android'/'iOS' 등을 준다.
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('OCR 통계 업로드 실패: $e');
    }
  }

  /// 화면에 보여줄 요약을 읽어온다.
  Future<OcrStatsSummary> readSummary() async {
    final data = await _load();
    return OcrStatsSummary(
      scans: data.scans,
      correctedCards: data.correctedCards,
      filled: Map.unmodifiable(data.filled),
      nameSource: Map.unmodifiable(data.nameSource),
      companySource: Map.unmodifiable(data.companySource),
      corrections: {
        for (final e in data.corrections.entries)
          e.key: Map.unmodifiable(e.value),
      },
    );
  }

  /// 집계를 비운다(측정 구간을 새로 시작하고 싶을 때).
  Future<void> reset() async {
    final prefs = await _prefs();
    await prefs.remove(_key);
  }

  Future<_OcrStatsData> _load() async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return _OcrStatsData.empty();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return _OcrStatsData.empty();
      return _OcrStatsData.fromJson(decoded);
    } catch (e) {
      debugPrint('OCR 통계 로드 실패: $e');
      return _OcrStatsData.empty();
    }
  }

  Future<void> _save(_OcrStatsData data) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(_key, jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('OCR 통계 저장 실패: $e');
    }
  }
}

/// 화면 표시용 읽기 전용 요약.
class OcrStatsSummary {
  /// 지금까지 집계된 스캔 파싱 횟수.
  final int scans;

  /// 자동 인식 후 사용자가 한 필드라도 고친 명함 수(저장 기준).
  final int correctedCards;

  /// 필드별로 "채워진" 스캔 수. 분모는 [scans].
  final Map<String, int> filled;

  /// 이름을 뽑은 경로별 횟수(OcrNameSource.name 기준).
  final Map<String, int> nameSource;

  /// 회사명을 뽑은 경로별 횟수(OcrCompanySource.name 기준).
  final Map<String, int> companySource;

  /// 필드별 수정 종류 집계(`필드 -> {edited/cleared/unchanged -> 수}`).
  final Map<String, Map<String, int>> corrections;

  const OcrStatsSummary({
    required this.scans,
    required this.correctedCards,
    required this.filled,
    required this.nameSource,
    required this.companySource,
    required this.corrections,
  });

  bool get isEmpty => scans == 0;
}

class _OcrStatsData {
  int scans;
  int correctedCards;
  final Map<String, int> filled;
  final Map<String, int> nameSource;
  final Map<String, int> companySource;
  final Map<String, Map<String, int>> corrections;

  _OcrStatsData({
    required this.scans,
    required this.correctedCards,
    required this.filled,
    required this.nameSource,
    required this.companySource,
    required this.corrections,
  });

  factory _OcrStatsData.empty() => _OcrStatsData(
    scans: 0,
    correctedCards: 0,
    filled: {},
    nameSource: {},
    companySource: {},
    corrections: {},
  );

  factory _OcrStatsData.fromJson(Map<dynamic, dynamic> json) {
    Map<String, int> intMap(dynamic v) {
      if (v is! Map) return {};
      return v.map(
        (k, val) => MapEntry(k as String, (val as num?)?.toInt() ?? 0),
      );
    }

    Map<String, Map<String, int>> nestedMap(dynamic v) {
      if (v is! Map) return {};
      return v.map((k, val) => MapEntry(k as String, intMap(val)));
    }

    return _OcrStatsData(
      scans: (json['scans'] as num?)?.toInt() ?? 0,
      correctedCards: (json['correctedCards'] as num?)?.toInt() ?? 0,
      filled: intMap(json['filled']),
      nameSource: intMap(json['nameSource']),
      companySource: intMap(json['companySource']),
      corrections: nestedMap(json['corrections']),
    );
  }

  Map<String, dynamic> toJson() => {
    'scans': scans,
    'correctedCards': correctedCards,
    'filled': filled,
    'nameSource': nameSource,
    'companySource': companySource,
    'corrections': corrections,
  };
}

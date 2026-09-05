/// **명함을 무엇에서 읽어 냈는가** — 파싱 원본 (2026-09-05, globe2030님 지적).
///
/// ## 왜 필요한가
///
/// 파서를 고쳐도 **이미 등록된 명함은 그대로다.** 원본이 안 남아 있기 때문이다.
/// 2026-09-05 실측에서 그 사실이 드러났다 — `OcrScanResult.rawText` 가
/// `add_card_modal_view` 까지 오지만 **화면에 보여 주기만 하고**
/// `ContactModel` 에는 필드 자체가 없다. 저장하는 순간 사라진다.
///
/// ⭐ **코드가 이미 이 문제를 알고 있었다** — `ocr_scanner_service.dart` 의
/// `rawLineBoxes` 주석: *"파서를 고쳐도 다시 재려면 스캔을 다시 돌려야 한다."*
/// 일괄 스캔 평가용 TSV(추가 317)에는 남기는데 **이용자 명함에는 안 남긴다.**
///
/// ## ⭐ 핵심 — OCR 과 파싱은 다른 단계다
///
/// ```
/// ① OCR    이미지 → 텍스트    ML Kit · 기기에서 · 비싸다
/// ② 파싱    텍스트 → 필드     우리 코드 · 싸다 · 🚨 고치는 것은 거의 항상 이쪽
/// ```
///
/// 원본 텍스트가 없으면 사진을 전부 내려받아 **기기에서 ①부터** 다시 해야 한다.
/// 있으면 **②만 다시 돌린다** — 사진이 필요 없다.
///
/// ## 🚨 미루면 데이터가 사라지는 유일한 항목이다
///
/// 원본은 **저장하는 순간에만** 남길 수 있다. 안 남긴 명함은 되살릴 방법이
/// 사진에서 재OCR 하는 무거운 길밖에 없다. 다른 설계 항목들은 늦어도 되지만
/// 이것만은 **미루는 동안 되살릴 수 없는 데이터가 쌓인다.**
///
/// ## 담지 않는 것과 그 이유
///
/// ```
/// rawLines    ❌ rawText 에서 다시 만들 수 있다 (구분자로 쪼갠 파생값)
///                🚨 쪼개는 규칙이 바뀌면 저장해 둔 쪽이 오히려 낡는다
/// 좌표         ⬜ 아직 안 담는다 — 크기를 못 쟀다(표본이 저장소 밖)
///                ⚠️ 이것만은 rawText 에서 못 만든다. 담을지는 재고 나서 정한다
/// ```
///
/// ## 🚨 개인정보
///
/// [rawText] 는 **명함 주인의 개인정보 원문 그대로**다 — 이름·전화·주소가
/// 통째로 들어 있다. 이용자 본인이 아니라 **제3자**의 것이다.
/// **명함 본문과 똑같이 암호화해 저장한다.** 로그에 찍지 않는다.
///
/// 설계: `docs/planning/specs/사람-레이어-C안-설계-2026-09-05.md` §2-3-3
library;

/// 지금 파서의 판(版).
///
/// 🚨 **파서를 고치면 이 값을 올린다.** 안 올리면 [CardSourceModel.parserVersion]
/// 이 거짓말을 하게 되고, 그러면 **무엇을 다시 돌려야 하는지 알 수 없다** —
/// 전부 다시 돌리거나 아무것도 못 돌리는 둘 중 하나가 된다.
///
/// ⚠️ **판을 올리는 것이 재파싱을 부르지는 않는다.** 이 값은 「언제 뽑은
/// 것인가」를 적어 두는 표식일 뿐이고, 다시 돌릴지는 사람이 정한다.
const int kCardParserVersion = 1;

/// 명함 한 장을 만들어 낸 원본.
class CardSourceModel {
  const CardSourceModel({
    required this.cardId,
    required this.rawText,
    required this.parserVersion,
    required this.scannedAt,
  });

  /// 어느 명함에서 나온 것인가. `ContactModel.id` 와 같다.
  final String cardId;

  /// OCR 이 읽어 낸 글자 원문.
  ///
  /// ⚠️ **앞·뒷면을 여러 번 스캔하면 마지막 것만 남는다** — 화면의 RAW 텍스트
  /// 상자가 원래 그렇게 동작한다(`add_card_modal_view` 주석). 즉 이 값은
  /// **「그 명함의 전부」가 아니라 「마지막으로 읽은 면」**이다. 재파싱 결과를
  /// 옛 결과와 견줄 때 이 한계를 잊으면 안 된다.
  final String rawText;

  /// 이 원본으로 파싱했을 때의 파서 판. [kCardParserVersion] 참고.
  final int parserVersion;

  /// 스캔한 시각.
  final DateTime scannedAt;

  /// 직접 입력해 만든 명함처럼 **원본이 없는** 경우.
  ///
  /// 📌 `null` 을 돌려주는 이유: 빈 [rawText] 로 문서를 만들면 **「스캔했는데
  /// 아무것도 못 읽었다」와 「스캔한 적이 없다」가 같은 모양**이 된다. 나중에
  /// 재파싱 대상을 고를 때 그 둘은 다르게 다뤄야 한다.
  static CardSourceModel? forScan({
    required String cardId,
    required String? rawText,
    required DateTime scannedAt,
    int parserVersion = kCardParserVersion,
  }) {
    final text = rawText?.trim() ?? '';
    if (text.isEmpty) return null;
    return CardSourceModel(
      cardId: cardId,
      rawText: text,
      parserVersion: parserVersion,
      scannedAt: scannedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'cardId': cardId,
    'rawText': rawText,
    'parserVersion': parserVersion,
    'scannedAt': scannedAt.toIso8601String(),
  };

  /// 저장된 것을 되읽는다.
  ///
  /// ⚠️ **못 읽으면 `null` 이다 — 예외를 던지지 않는다.** 원본은 **있으면 좋은
  /// 것**이지 없으면 앱이 멈춰야 하는 것이 아니다. 한 장이 깨졌다고 명함첩
  /// 전체가 안 열리면 그쪽이 훨씬 나쁘다.
  ///
  /// 📌 이것은 명함 본문과 **정반대 판단**이다. 본문은 못 읽었을 때
  /// 「없다」로 넘어가면 안 되고(PR #820), 원본은 넘어가도 된다 — **본문은
  /// 잃으면 복구가 안 되고 원본은 다시 스캔하면 된다.**
  static CardSourceModel? fromJson(Map<String, dynamic> json) {
    final cardId = json['cardId'];
    final rawText = json['rawText'];
    if (cardId is! String || cardId.isEmpty) return null;
    if (rawText is! String || rawText.isEmpty) return null;

    final scannedAt = DateTime.tryParse(json['scannedAt'] as String? ?? '');
    if (scannedAt == null) return null;

    final version = json['parserVersion'];
    return CardSourceModel(
      cardId: cardId,
      rawText: rawText,
      // 판이 없거나 이상하면 0 — "언제 것인지 모른다"는 뜻이다.
      // 🚨 kCardParserVersion 으로 채우면 안 된다. 그러면 옛 원본이 최신 판으로
      // 뽑힌 것처럼 보여 재파싱 대상에서 조용히 빠진다.
      parserVersion: version is int ? version : 0,
      scannedAt: scannedAt,
    );
  }

  @override
  String toString() =>
      // 🚨 rawText 는 제3자 개인정보다. 길이만 찍는다.
      'CardSourceModel(cardId: $cardId, rawText: ${rawText.length}자, '
      'parserVersion: $parserVersion)';
}

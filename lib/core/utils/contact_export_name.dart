import '../../data/models/contact_model.dart';

/// 명함을 내보낼 때 **주소록 이름 칸에 무엇을 적을지**(추가 494).
///
/// ## 왜 이름 칸을 건드리나
///
/// 리멤버 설정 실물(2026-08-26, 사용자 촬영본 43프레임 전수 확인)에서 구분에
/// 실제로 쓰이는 장치가 이것이었다.
///
/// ```
/// 「연락처에 저장」  이름+직책(회사명)
///   이름 항목에 이름 외 다른 정보를 함께 저장할 수 있습니다
/// ```
///
/// 주소록 이름 칸에 `홍길동 부장(가상상사)` 로 들어간다. **동명이인이
/// 갈리고, 내가 넣은 것인지도 이름만 보고 안다.** 그룹 라벨보다 질기다 —
/// 주소록 앱을 바꿔도 클라우드로 옮겨도 이름은 따라간다.
///
/// 🚨 **`#` 는 넣지 않는다.** 리멤버의 `#` 는 분류가 아니라 **카카오톡이
/// 주소록의 사람을 자동으로 친구 추가하는 것을 막는 장치**이고 기본값도
/// 꺼짐이다. 목적이 다르다(사용자 확정, 2026-08-26).
enum ContactExportNameFormat {
  /// 🚨 **기본값.** 주소록은 이용자의 것이고, 이름을 건드리는 쪽이 더 큰
  /// 개입이다. 묻기 전에는 이것으로 나간다.
  nameOnly,
  nameTitle,
  nameTitleCompany,
  nameCompany;

  /// 설정·선택 화면에 보이는 이름.
  String get label => switch (this) {
        ContactExportNameFormat.nameOnly => '이름만',
        ContactExportNameFormat.nameTitle => '이름 + 직책',
        ContactExportNameFormat.nameTitleCompany => '이름 + 직책(회사명)',
        ContactExportNameFormat.nameCompany => '이름(회사명)',
      };

  /// 기기에 적는 값. **enum 이름이 아니라 이 문자열을 쓴다** — 나중에 enum
  /// 순서나 이름을 바꿔도 이미 저장된 설정이 안 깨진다.
  String get storageKey => switch (this) {
        ContactExportNameFormat.nameOnly => 'name_only',
        ContactExportNameFormat.nameTitle => 'name_title',
        ContactExportNameFormat.nameTitleCompany => 'name_title_company',
        ContactExportNameFormat.nameCompany => 'name_company',
      };

  static ContactExportNameFormat fromStorage(String? raw) => switch (raw) {
        'name_title' => ContactExportNameFormat.nameTitle,
        'name_title_company' => ContactExportNameFormat.nameTitleCompany,
        'name_company' => ContactExportNameFormat.nameCompany,
        // 모르는 값이면 **가장 덜 개입하는 쪽**으로 떨어뜨린다.
        _ => ContactExportNameFormat.nameOnly,
      };
}

/// 형식대로 이름 칸 문자열을 만든다.
///
/// ## 🚨 빈 값이 껍데기를 남기지 않는다
///
/// 직책이 없는 명함은 실제로 있다. 형식만 그대로 따르면 이런 것이 나온다.
///
/// ```
/// 홍길동  (가상상사)   ← 직책 자리가 비어 공백이 둘
/// 홍길동 부장()        ← 회사명이 없는데 괄호만
/// ```
///
/// **주소록에 한 번 들어가면 이용자가 손으로 고쳐야 한다.** 그래서 없는
/// 조각은 그 자리째 빼고, 남은 것으로 자연스럽게 만든다.
String buildExportName(ContactModel c, ContactExportNameFormat format) {
  final name = c.name.trim();
  final title = (c.title).trim();
  final company = (c.company).trim();

  // 이름이 없으면 무엇을 붙여도 이상해진다. 그대로 둔다.
  if (name.isEmpty) return name;

  final wantTitle = format == ContactExportNameFormat.nameTitle ||
      format == ContactExportNameFormat.nameTitleCompany;
  final wantCompany = format == ContactExportNameFormat.nameTitleCompany ||
      format == ContactExportNameFormat.nameCompany;

  final head = wantTitle && title.isNotEmpty ? '$name $title' : name;
  return wantCompany && company.isNotEmpty ? '$head($company)' : head;
}

/// 설정·선택 화면의 **미리보기**.
///
/// 🚨 *"이름 형식을 고르세요"* 만으로는 무엇을 고르는지 모른다. 네 형식이
/// 각각 어떻게 보이는지 보여 준다.
///
/// ⚠️ **가상값이다.** 실제 명함을 미리보기에 쓰면, 고르는 화면에서 제3자
/// 개인정보가 형식마다 네 번 보이게 된다.
String previewOf(ContactExportNameFormat format) => switch (format) {
      ContactExportNameFormat.nameOnly => '홍길동',
      ContactExportNameFormat.nameTitle => '홍길동 부장',
      ContactExportNameFormat.nameTitleCompany => '홍길동 부장(가상상사)',
      ContactExportNameFormat.nameCompany => '홍길동(가상상사)',
    };

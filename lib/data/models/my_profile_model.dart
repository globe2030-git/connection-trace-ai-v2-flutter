class MyProfileModel {
  final String name;
  final String title;
  final String company;
  /// 부서 — 명함에 흔히 있는데 이 화면에는 칸이 없어 **OCR이 읽고도 버리던**
  /// 값이다(2026-08-26). 남의 명함(`ContactModel.department`)에는 이미 있었다.
  final String? department;
  final String phone;
  /// 사무실 전화 — 휴대폰과 별개. 명함에 둘 다 인쇄된 경우가 흔하다.
  final String? officePhone;
  /// 팩스 — 지금도 명함에 남아 있는 항목이라 OCR이 읽는다.
  final String? fax;
  final String email;
  /// 웹사이트 — 회사 홈페이지. vCard의 `URL`로 나간다.
  final String? website;
  // 주소1 — 도로명 등 기본 주소(위치 정보의 기준이 되는 부분).
  final String address;
  // 상세주소 — 건물명/동/호수 등. 위치 정보(지오코딩)에는 쓰이지 않고 표시용으로만
  // 별도 보관.
  final String? addressDetail;
  /// 우편번호 — 지오코딩에는 쓰지 않고 표시·vCard용이다.
  final String? postalCode;

  /// 스캔한 **내 명함 사진**의 암호문 파일 경로(2026-08-26 사용자 지시).
  ///
  /// ⚠️ [avatarPath]와 **다른 값**이다 — 저쪽은 상대에게 보여 주는 얼굴
  /// 사진이고, 이것은 **실물 명함 이미지**다. 화면이 둘을 섞어 말하면 안 된다.
  ///
  /// 남의 명함과 **같은 경로를 탄다**(`ContactImageService`, AES-256-GCM).
  /// 내 명함만 다른 경로를 만들면 규칙이 두 벌이 되고, 서버 백업을 켤 때
  /// 한쪽이 빠진다.
  ///
  /// 🚨 **QR/vCard 공유에는 나가지 않는다.** vCard는 글자만 담는다.
  final String? cardImagePath;
  // 내 프로필 사진 — 연락처 아바타(프리셋 URL 순환)와 달리 본인의 실제 사진이라
  // 갤러리에서 고른 이미지를 앱 문서 디렉터리에 복사해 둔 로컬 파일 경로를 저장한다.
  final String? avatarPath;

  /// 생일 — **월·일만** `"MM-DD"` 형식으로 보관한다(예: `"10-01"`). 미지정이면 null.
  ///
  /// **연도를 안 받는 이유**: 생일 축하·생일 혜택에 필요한 건 월일뿐인데,
  /// 연도까지 붙으면 생년월일 전체가 되어 이름과 조합했을 때 사실상 개인이
  /// 특정된다. 월일만으로는 식별력이 훨씬 낮다.
  ///
  /// **왜 0을 채우나**: `"10-01"`처럼 두 자리로 맞춰야 문자열 정렬이 날짜
  /// 순서와 같아진다. 그래야 "이번 달 생일자"를 `>= "10-01" && <= "10-31"`
  /// 범위로 그대로 뽑을 수 있다. `"10-1"`이 섞이면 정렬이 깨진다.
  /// 값을 만들 때는 [formatMonthDay]를 쓴다.
  ///
  /// 지금은 **받아 두기만 하고 쓰지 않는다** — 생일 축하 알림·생일 무료 충전은
  /// 나중에 붙인다(사용자 결정 2026-08-13). 그때 기존 가입자의 생일이 없으면
  /// 다시 물어봐야 하므로 입력만 먼저 열어 둔다.
  final String? birthMonthDay;

  const MyProfileModel({
    required this.name,
    required this.title,
    required this.company,
    required this.phone,
    required this.email,
    required this.address,
    this.department,
    this.officePhone,
    this.fax,
    this.website,
    this.addressDetail,
    this.postalCode,
    this.cardImagePath,
    this.avatarPath,
    this.birthMonthDay,
  });

  /// 월·일을 저장 형식(`"MM-DD"`)으로 만든다. 범위를 벗어나면 null.
  static String? formatMonthDay(int? month, int? day) {
    if (month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  /// 저장된 `"MM-DD"`에서 월을 꺼낸다. 값이 없거나 형식이 깨졌으면 null.
  int? get birthMonth => _birthPart(0);

  /// 저장된 `"MM-DD"`에서 일을 꺼낸다. 값이 없거나 형식이 깨졌으면 null.
  int? get birthDay => _birthPart(1);

  int? _birthPart(int index) {
    final parts = birthMonthDay?.split('-');
    if (parts == null || parts.length != 2) return null;
    return int.tryParse(parts[index]);
  }

  // 최초 실행 시 기본값 — 예전엔 "홍길동 대표" 같은 가짜 인물 정보를 채워
  // 뒀는데, 사용자가 프로필을 아직 안 고쳤을 때 QR/vCard로 그 가짜 정보가
  // 실제 명함처럼 공유될 수 있는 문제가 있었다(실사용자가 받으면 가짜
  // 연락처가 그대로 등록됨). 빈 값으로 시작해 "아직 설정 안 함" 상태를
  // 명확히 구분한다.
  /// 아직 내 명함을 만들지 않은 상태인가.
  ///
  /// 이름 하나로 판단한다 — 회사·직함은 프리랜서나 개인 사용자에게는 비어
  /// 있는 게 정상이고, 이름 없이 나머지만 채우는 경우는 없다.
  ///
  /// 이게 필요한 이유: 앱을 처음 깔면 내 명함이 없는데 화면 어디에도 그걸
  /// 알리는 표시가 없어서, 무엇을 먼저 해야 하는지 알 수 없었다(실사용
  /// 피드백). 내 명함은 AI 대화 가이드가 "나는 누구인지"를 상대에게 말하는
  /// 근거로도 쓰이므로, 비어 있으면 결과 품질도 떨어진다.
  bool get isUnset => name.trim().isEmpty;

  static const MyProfileModel defaultProfile = MyProfileModel(
    name: '',
    title: '',
    company: '',
    phone: '',
    email: '',
    address: '',
  );

  /// 사용자가 아직 프로필을 한 번도 저장하지 않은 상태인지 — 이름이 비어
  /// 있으면 QR 공유·AI 브리핑 등에서 가짜/빈 정보를 실제 정보처럼 쓰지
  /// 않도록 화면단에서 이 값으로 분기한다.
  bool get isSetUp => name.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    'title': title,
    'company': company,
    'phone': phone,
    'email': email,
    'address': address,
    'department': department,
    'officePhone': officePhone,
    'fax': fax,
    'website': website,
    'addressDetail': addressDetail,
    'postalCode': postalCode,
    'cardImagePath': cardImagePath,
    'avatarPath': avatarPath,
    'birthMonthDay': birthMonthDay,
  };

  factory MyProfileModel.fromJson(Map<String, dynamic> json) => MyProfileModel(
    name: json['name'] as String? ?? defaultProfile.name,
    title: json['title'] as String? ?? defaultProfile.title,
    company: json['company'] as String? ?? defaultProfile.company,
    phone: json['phone'] as String? ?? defaultProfile.phone,
    email: json['email'] as String? ?? defaultProfile.email,
    address: json['address'] as String? ?? defaultProfile.address,
    // 아래 다섯은 2026-08-26에 생긴 칸이다. 그 전에 저장된 프로필에는 키가
    // 아예 없어 null로 읽힌다 — birthMonthDay와 같은 이유로 마이그레이션이
    // 필요 없다. 반대로 낡은 앱이 새 JSON을 읽어도 모르는 키를 무시하므로
    // 스키마 버전을 올리지 않는다.
    department: json['department'] as String?,
    officePhone: json['officePhone'] as String?,
    fax: json['fax'] as String?,
    website: json['website'] as String?,
    addressDetail: json['addressDetail'] as String?,
    postalCode: json['postalCode'] as String?,
    cardImagePath: json['cardImagePath'] as String?,
    avatarPath: json['avatarPath'] as String?,
    // 이 필드가 없던 시절에 저장된 프로필은 null로 읽힌다 — 마이그레이션 불필요.
    birthMonthDay: json['birthMonthDay'] as String?,
  );

  MyProfileModel copyWith({
    String? name,
    String? title,
    String? company,
    String? phone,
    String? email,
    String? address,
    String? department,
    String? officePhone,
    String? fax,
    String? website,
    String? addressDetail,
    String? postalCode,
    // 명함 사진도 "지웠다"를 표현해야 해서 프로필 사진과 같은 방식을 쓴다.
    String? cardImagePath,
    bool clearCardImage = false,
    // 사진을 지우는 경우까지 표현해야 해서(값 있음/없음/명시적 null) 다른
    // 필드처럼 `?? this.x`로는 부족함 — 항상 이 값 그대로 반영한다는 별도
    // 플래그를 둔다.
    String? avatarPath,
    bool clearAvatar = false,
    // 생일도 "지정 안 함"으로 되돌릴 수 있어야 해서 사진과 같은 방식을 쓴다.
    String? birthMonthDay,
    bool clearBirthday = false,
  }) {
    return MyProfileModel(
      name: name ?? this.name,
      title: title ?? this.title,
      company: company ?? this.company,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      department: department ?? this.department,
      officePhone: officePhone ?? this.officePhone,
      fax: fax ?? this.fax,
      website: website ?? this.website,
      addressDetail: addressDetail ?? this.addressDetail,
      postalCode: postalCode ?? this.postalCode,
      cardImagePath: clearCardImage
          ? null
          : (cardImagePath ?? this.cardImagePath),
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      birthMonthDay:
          clearBirthday ? null : (birthMonthDay ?? this.birthMonthDay),
    );
  }
}

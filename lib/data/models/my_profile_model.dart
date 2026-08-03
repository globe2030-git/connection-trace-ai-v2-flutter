class MyProfileModel {
  final String name;
  final String title;
  final String company;
  final String phone;
  final String email;
  // 주소1 — 도로명 등 기본 주소(위치 정보의 기준이 되는 부분).
  final String address;
  // 상세주소 — 건물명/동/호수 등. 위치 정보(지오코딩)에는 쓰이지 않고 표시용으로만
  // 별도 보관.
  final String? addressDetail;
  // 내 프로필 사진 — 연락처 아바타(프리셋 URL 순환)와 달리 본인의 실제 사진이라
  // 갤러리에서 고른 이미지를 앱 문서 디렉터리에 복사해 둔 로컬 파일 경로를 저장한다.
  final String? avatarPath;

  const MyProfileModel({
    required this.name,
    required this.title,
    required this.company,
    required this.phone,
    required this.email,
    required this.address,
    this.addressDetail,
    this.avatarPath,
  });

  // 최초 실행 시 기본값 — 예전엔 "홍길동 대표" 같은 가짜 인물 정보를 채워
  // 뒀는데, 사용자가 프로필을 아직 안 고쳤을 때 QR/vCard로 그 가짜 정보가
  // 실제 명함처럼 공유될 수 있는 문제가 있었다(실사용자가 받으면 가짜
  // 연락처가 그대로 등록됨). 빈 값으로 시작해 "아직 설정 안 함" 상태를
  // 명확히 구분한다.
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
        'addressDetail': addressDetail,
        'avatarPath': avatarPath,
      };

  factory MyProfileModel.fromJson(Map<String, dynamic> json) => MyProfileModel(
        name: json['name'] as String? ?? defaultProfile.name,
        title: json['title'] as String? ?? defaultProfile.title,
        company: json['company'] as String? ?? defaultProfile.company,
        phone: json['phone'] as String? ?? defaultProfile.phone,
        email: json['email'] as String? ?? defaultProfile.email,
        address: json['address'] as String? ?? defaultProfile.address,
        addressDetail: json['addressDetail'] as String?,
        avatarPath: json['avatarPath'] as String?,
      );

  MyProfileModel copyWith({
    String? name,
    String? title,
    String? company,
    String? phone,
    String? email,
    String? address,
    String? addressDetail,
    // 사진을 지우는 경우까지 표현해야 해서(값 있음/없음/명시적 null) 다른
    // 필드처럼 `?? this.x`로는 부족함 — 항상 이 값 그대로 반영한다는 별도
    // 플래그를 둔다.
    String? avatarPath,
    bool clearAvatar = false,
  }) {
    return MyProfileModel(
      name: name ?? this.name,
      title: title ?? this.title,
      company: company ?? this.company,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      addressDetail: addressDetail ?? this.addressDetail,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
    );
  }
}

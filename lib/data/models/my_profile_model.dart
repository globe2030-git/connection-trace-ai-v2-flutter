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

  // 최초 실행 시 보여줄 기본값 — 사용자가 "직접 추가"로 실제 정보를 입력하기
  // 전까지 화면이 비어 보이지 않게 하는 안내용 예시.
  static const MyProfileModel defaultProfile = MyProfileModel(
    name: '홍길동 대표',
    title: 'C-Level',
    company: '커넥션 트레이스 AI',
    phone: '010-1234-5678',
    email: 'gildong.hong@connectiontrace.ai',
    address: '서울특별시 강남구 테헤란로 123',
    addressDetail: '5층 501호',
  );

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

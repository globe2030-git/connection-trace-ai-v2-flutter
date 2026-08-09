import '../../core/utils/geo_utils.dart';

class CommunicationLogModel {
  final String id;
  final String type; // 'call', 'sms', 'email', 'kakao'
  final String summary;
  final DateTime timestamp;
  // 이전 버전에서 자동 연동 여부를 저장하던 호환 필드. 스토어 출시 빌드에서는
  // 통화기록·문자 제한 권한을 사용하지 않으므로 신규 기록은 수동 입력(false)이다.
  final bool isAutoSynced;
  // 'manual' 또는 'gmail'. 제한 권한으로 읽은 통화/문자 기록은 출시 빌드에서
  // 새로 생성하지 않는다. 기존 저장 데이터와의 호환을 위해 문자열로 보관한다.
  final String source;

  CommunicationLogModel({
    String? id,
    required this.type,
    required this.summary,
    required this.timestamp,
    this.isAutoSynced = false,
    this.source = 'manual',
  }) : id = id ?? '${timestamp.microsecondsSinceEpoch}_$type';

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'summary': summary,
    'timestamp': timestamp.toIso8601String(),
    'isAutoSynced': isAutoSynced,
    'source': source,
  };

  factory CommunicationLogModel.fromJson(Map<String, dynamic> json) =>
      CommunicationLogModel(
        id: json['id'] as String?,
        type: json['type'] as String? ?? 'call',
        summary: json['summary'] as String? ?? '',
        timestamp: DateTime.parse(json['timestamp'] as String),
        isAutoSynced: json['isAutoSynced'] as bool? ?? false,
        source:
            json['source'] as String? ??
            ((json['isAutoSynced'] as bool? ?? false) ? 'legacy' : 'manual'),
      );
}

class ContactModel {
  final String id;
  final String name;
  final String company;
  final String title;
  final String phone;
  final String? officePhone;
  final String email;
  // 주소1 — 도로명 등 기본 주소. 지오코딩(위치 정보)의 기준이 되는 부분.
  final String? address;
  // 상세주소 — 건물명/동/호수 등. 지오코딩에는 쓰이지 않고 표시용으로만 보관.
  final String? addressDetail;
  // 우편번호(5자리). 지오코딩에는 쓰이지 않고 표시/등록용으로만 보관.
  final String? postalCode;
  final String? avatarUrl;
  final GeoPosition? geo;
  final List<String> tags;
  // 관심사 — AI 대화 브리핑이 상대방과 자연스럽게 안부를 나눌 때 참고하는
  // 항목(취미/관심 분야 등). tags와 별개 필드로 둔 이유: tags는 "이 사람을
  // 어떤 카테고리로 분류할지"(예: AI, C-Level)이고 interests는 "이 사람과
  // 무슨 이야기를 나눌지"에 가까워 의미가 달라 섞으면 태그 목록이 지저분해짐.
  // 입력 UI는 tags와 동일하게 쉼표 구분 텍스트 입력을 따른다.
  final List<String> interests;
  final List<String> talkingPoints;
  final List<CommunicationLogModel> commLogs;
  final String? memo;
  // 명함을 등록했다는 것 자체가 이미 중요한 인맥이라는 뜻이라, 사용자가
  // 따로 "VIP"를 골라야 하는 별도 선택 단계는 의미가 없다는 판단으로
  // 기본값을 true로 바꿨다(이전엔 false였고 명함지갑에서 별표를 눌러야
  // VIP가 됐음 — 그 선택 UI 자체를 제거).
  final bool isPriority;

  /// 마지막으로 이 명함이 생성/수정된 시각. 다기기 동기화(P1-39 A안)에서
  /// "어느 쪽이 최신본인가"를 정하는 기준(last-write-wins). 예전 데이터에는
  /// 없을 수 있어 nullable이며, 병합에서 null은 "가장 오래됨"으로 취급한다.
  final DateTime? updatedAt;

  const ContactModel({
    required this.id,
    required this.name,
    required this.company,
    required this.title,
    required this.phone,
    this.officePhone,
    required this.email,
    this.address,
    this.addressDetail,
    this.postalCode,
    this.avatarUrl,
    this.geo,
    required this.tags,
    this.interests = const [],
    required this.talkingPoints,
    this.commLogs = const [],
    this.memo,
    this.isPriority = true,
    this.updatedAt,
  });

  /// 기기 저장용 — 좌표를 포함한다. 좌표를 매번 다시 계산하지 않기 위해
  /// 기기에는 그대로 들고 있는다.
  Map<String, dynamic> toJson() => _toJson(includeGeo: true);

  /// 서버 백업용 — **좌표(lat/lng)를 제외한다.**
  ///
  /// 좌표는 [address]를 지오코딩해서 얻은 파생값이라 서버에 보관할 이유가
  /// 없고, 보관하면 "회사가 위치정보를 보유한다"는 해석 여지가 생긴다
  /// (backlog 추가 75에서 확정한 C안). 새 기기에서 복원하면 좌표가 빈 채로
  /// 내려오고, `GeoBackfillService`가 주소로 다시 계산해 채운다.
  ///
  /// 서버 백업에는 반드시 이 메서드를 쓸 것 — [toJson]을 쓰면 좌표가 다시
  /// 올라간다.
  Map<String, dynamic> toBackupJson() => _toJson(includeGeo: false);

  Map<String, dynamic> _toJson({required bool includeGeo}) {
    return {
      'id': id,
      'name': name,
      'company': company,
      'title': title,
      'phone': phone,
      'officePhone': officePhone,
      'email': email,
      'address': address,
      'addressDetail': addressDetail,
      'postalCode': postalCode,
      'avatarUrl': avatarUrl,
      if (includeGeo) 'lat': geo?.lat,
      if (includeGeo) 'lng': geo?.lng,
      'tags': tags,
      'interests': interests,
      'talkingPoints': talkingPoints,
      'commLogs': commLogs.map((l) => l.toJson()).toList(),
      'memo': memo,
      'isPriority': isPriority,
      // 서버 백업에도 포함한다 — 다기기 병합의 최신본 판정 기준이라 서버에
      // 남아야 다른 기기가 비교할 수 있다(좌표와 달리 파생값이 아니다).
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      id: json['id'] as String,
      name: json['name'] as String,
      company: json['company'] as String,
      title: json['title'] as String,
      phone: json['phone'] as String,
      officePhone: json['officePhone'] as String?,
      email: json['email'] as String,
      address: json['address'] as String?,
      addressDetail: json['addressDetail'] as String?,
      postalCode: json['postalCode'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      geo: json['lat'] != null && json['lng'] != null
          ? GeoPosition(
              lat: (json['lat'] as num).toDouble(),
              lng: (json['lng'] as num).toDouble(),
            )
          : null,
      tags: List<String>.from(json['tags'] ?? []),
      interests: List<String>.from(json['interests'] ?? []),
      talkingPoints: List<String>.from(json['talkingPoints'] ?? []),
      commLogs:
          (json['commLogs'] as List<dynamic>?)
              ?.map(
                (l) =>
                    CommunicationLogModel.fromJson(l as Map<String, dynamic>),
              )
              .toList() ??
          [],
      memo: json['memo'] as String?,
      isPriority: json['isPriority'] as bool? ?? true,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  ContactModel copyWith({
    String? id,
    String? name,
    String? company,
    String? title,
    String? phone,
    String? officePhone,
    String? email,
    String? address,
    String? addressDetail,
    String? postalCode,
    String? avatarUrl,
    GeoPosition? geo,
    List<String>? tags,
    List<String>? interests,
    List<String>? talkingPoints,
    List<CommunicationLogModel>? commLogs,
    String? memo,
    bool? isPriority,
    DateTime? updatedAt,
  }) {
    return ContactModel(
      id: id ?? this.id,
      name: name ?? this.name,
      company: company ?? this.company,
      title: title ?? this.title,
      phone: phone ?? this.phone,
      officePhone: officePhone ?? this.officePhone,
      email: email ?? this.email,
      address: address ?? this.address,
      addressDetail: addressDetail ?? this.addressDetail,
      postalCode: postalCode ?? this.postalCode,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      geo: geo ?? this.geo,
      tags: tags ?? this.tags,
      interests: interests ?? this.interests,
      talkingPoints: talkingPoints ?? this.talkingPoints,
      commLogs: commLogs ?? this.commLogs,
      memo: memo ?? this.memo,
      isPriority: isPriority ?? this.isPriority,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

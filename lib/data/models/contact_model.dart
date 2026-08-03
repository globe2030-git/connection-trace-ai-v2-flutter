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
  final String? avatarUrl;
  final GeoPosition? geo;
  final List<String> tags;
  final List<String> talkingPoints;
  final List<CommunicationLogModel> commLogs;
  final String? memo;
  // 명함을 등록했다는 것 자체가 이미 중요한 인맥이라는 뜻이라, 사용자가
  // 따로 "VIP"를 골라야 하는 별도 선택 단계는 의미가 없다는 판단으로
  // 기본값을 true로 바꿨다(이전엔 false였고 명함지갑에서 별표를 눌러야
  // VIP가 됐음 — 그 선택 UI 자체를 제거).
  final bool isPriority;

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
    this.avatarUrl,
    this.geo,
    required this.tags,
    required this.talkingPoints,
    this.commLogs = const [],
    this.memo,
    this.isPriority = true,
  });

  Map<String, dynamic> toJson() {
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
      'avatarUrl': avatarUrl,
      'lat': geo?.lat,
      'lng': geo?.lng,
      'tags': tags,
      'talkingPoints': talkingPoints,
      'commLogs': commLogs.map((l) => l.toJson()).toList(),
      'memo': memo,
      'isPriority': isPriority,
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
      avatarUrl: json['avatarUrl'] as String?,
      geo: json['lat'] != null && json['lng'] != null
          ? GeoPosition(
              lat: (json['lat'] as num).toDouble(),
              lng: (json['lng'] as num).toDouble(),
            )
          : null,
      tags: List<String>.from(json['tags'] ?? []),
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
    String? avatarUrl,
    GeoPosition? geo,
    List<String>? tags,
    List<String>? talkingPoints,
    List<CommunicationLogModel>? commLogs,
    String? memo,
    bool? isPriority,
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
      avatarUrl: avatarUrl ?? this.avatarUrl,
      geo: geo ?? this.geo,
      tags: tags ?? this.tags,
      talkingPoints: talkingPoints ?? this.talkingPoints,
      commLogs: commLogs ?? this.commLogs,
      memo: memo ?? this.memo,
      isPriority: isPriority ?? this.isPriority,
    );
  }
}

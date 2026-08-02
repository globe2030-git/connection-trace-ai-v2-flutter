import '../../core/utils/geo_utils.dart';

class CommunicationLogModel {
  final String type; // 'call', 'sms', 'email', 'kakao'
  final String summary;
  final DateTime timestamp;
  // 기기의 실제 통화기록/문자 API로 자동 연동된 항목인지 여부. false면 데모
  // 데이터이거나(초기 목업 인맥) 수동으로 입력한 항목이라는 뜻 — 브리핑
  // 화면에서 "자동 연동" 배지를 붙여 사용자가 실제 연동인지 구분할 수 있게 함.
  final bool isAutoSynced;

  const CommunicationLogModel({
    required this.type,
    required this.summary,
    required this.timestamp,
    this.isAutoSynced = false,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'summary': summary,
        'timestamp': timestamp.toIso8601String(),
        'isAutoSynced': isAutoSynced,
      };

  factory CommunicationLogModel.fromJson(Map<String, dynamic> json) =>
      CommunicationLogModel(
        type: json['type'] as String? ?? 'call',
        summary: json['summary'] as String? ?? '',
        timestamp: DateTime.parse(json['timestamp'] as String),
        isAutoSynced: json['isAutoSynced'] as bool? ?? false,
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
    this.isPriority = false,
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
      commLogs: (json['commLogs'] as List<dynamic>?)
              ?.map((l) => CommunicationLogModel.fromJson(l as Map<String, dynamic>))
              .toList() ??
          [],
      memo: json['memo'] as String?,
      isPriority: json['isPriority'] as bool? ?? false,
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

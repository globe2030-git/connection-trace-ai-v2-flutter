import '../../core/utils/geo_utils.dart';

class CommunicationLogModel {
  final String type; // 'call', 'sms', 'email', 'kakao'
  final String summary;
  final DateTime timestamp;

  const CommunicationLogModel({
    required this.type,
    required this.summary,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'summary': summary,
        'timestamp': timestamp.toIso8601String(),
      };

  factory CommunicationLogModel.fromJson(Map<String, dynamic> json) =>
      CommunicationLogModel(
        type: json['type'] as String? ?? 'call',
        summary: json['summary'] as String? ?? '',
        timestamp: DateTime.parse(json['timestamp'] as String),
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
  final String? address;
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

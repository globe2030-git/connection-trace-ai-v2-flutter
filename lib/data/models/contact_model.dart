import '../../core/utils/geo_utils.dart';

class ContactModel {
  final String id;
  final String name;
  final String company;
  final String title;
  final String phone;
  final String email;
  final String? address;
  final GeoPosition? geo;
  final List<String> tags;
  final List<String> talkingPoints;
  final String? memo;
  final bool isPriority;

  const ContactModel({
    required this.id,
    required this.name,
    required this.company,
    required this.title,
    required this.phone,
    required this.email,
    this.address,
    this.geo,
    required this.tags,
    required this.talkingPoints,
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
      'email': email,
      'address': address,
      'lat': geo?.lat,
      'lng': geo?.lng,
      'tags': tags,
      'talkingPoints': talkingPoints,
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
      email: json['email'] as String,
      address: json['address'] as String?,
      geo: json['lat'] != null && json['lng'] != null
          ? GeoPosition(
              lat: (json['lat'] as num).toDouble(),
              lng: (json['lng'] as num).toDouble(),
            )
          : null,
      tags: List<String>.from(json['tags'] ?? []),
      talkingPoints: List<String>.from(json['talkingPoints'] ?? []),
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
    String? email,
    String? address,
    GeoPosition? geo,
    List<String>? tags,
    List<String>? talkingPoints,
    String? memo,
    bool? isPriority,
  }) {
    return ContactModel(
      id: id ?? this.id,
      name: name ?? this.name,
      company: company ?? this.company,
      title: title ?? this.title,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      geo: geo ?? this.geo,
      tags: tags ?? this.tags,
      talkingPoints: talkingPoints ?? this.talkingPoints,
      memo: memo ?? this.memo,
      isPriority: isPriority ?? this.isPriority,
    );
  }
}

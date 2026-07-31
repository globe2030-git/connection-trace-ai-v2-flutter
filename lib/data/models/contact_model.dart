import '../../core/utils/geo_utils.dart';

class ContactModel {
  final String id;
  final String name;
  final String company;
  final String title;
  final String phone;
  final String email;
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
    this.geo,
    required this.tags,
    required this.talkingPoints,
    this.memo,
    this.isPriority = false,
  });

  ContactModel copyWith({
    String? id,
    String? name,
    String? company,
    String? title,
    String? phone,
    String? email,
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
      geo: geo ?? this.geo,
      tags: tags ?? this.tags,
      talkingPoints: talkingPoints ?? this.talkingPoints,
      memo: memo ?? this.memo,
      isPriority: isPriority ?? this.isPriority,
    );
  }
}

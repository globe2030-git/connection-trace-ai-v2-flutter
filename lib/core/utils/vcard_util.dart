import '../../data/models/my_profile_model.dart';

/// 디지털 명함 QR 코드에 담을 vCard(VERSION 3.0) 텍스트를 만들고 읽는 유틸.
/// vCard는 업계 표준 포맷이라 아이폰/안드로이드 기본 카메라 앱으로 스캔해도
/// "연락처 추가"로 바로 인식되는 장점이 있다.
class VCardUtil {
  static String encodeProfile(MyProfileModel profile) {
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCARD')
      ..writeln('VERSION:3.0')
      ..writeln('N:;${profile.name};;;')
      ..writeln('FN:${profile.name}');
    if (profile.company.isNotEmpty) buffer.writeln('ORG:${profile.company}');
    if (profile.title.isNotEmpty) buffer.writeln('TITLE:${profile.title}');
    if (profile.phone.isNotEmpty) buffer.writeln('TEL;TYPE=CELL:${profile.phone}');
    if (profile.email.isNotEmpty) buffer.writeln('EMAIL:${profile.email}');
    final addressLine = [profile.address, profile.addressDetail]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' ');
    if (addressLine.isNotEmpty) buffer.writeln('ADR;TYPE=WORK:;;$addressLine;;;;');
    buffer.writeln('END:VCARD');
    return buffer.toString();
  }

  /// 스캔한 QR 원문이 vCard면 필드 맵으로 파싱해 반환하고, 아니면 null.
  static Map<String, String>? decode(String raw) {
    if (!raw.toUpperCase().contains('BEGIN:VCARD')) return null;

    final result = <String, String>{};
    for (final line in raw.split(RegExp(r'\r\n|\n|\r'))) {
      final idx = line.indexOf(':');
      if (idx == -1) continue;
      final key = line.substring(0, idx).split(';').first.toUpperCase();
      final value = line.substring(idx + 1).trim();
      if (value.isEmpty) continue;

      switch (key) {
        case 'FN':
          result['name'] = value;
          break;
        case 'ORG':
          result['company'] = value;
          break;
        case 'TITLE':
          result['title'] = value;
          break;
        case 'TEL':
          result.putIfAbsent('phone', () => value);
          break;
        case 'EMAIL':
          result.putIfAbsent('email', () => value);
          break;
        case 'ADR':
          final addr = value.split(';').where((p) => p.trim().isNotEmpty).join(' ');
          if (addr.isNotEmpty) result['address'] = addr;
          break;
      }
    }
    return result.isEmpty ? null : result;
  }
}

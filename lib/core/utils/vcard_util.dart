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
    // 부서는 vCard 3.0에서 ORG의 두 번째 성분이다(`ORG:회사;부서`).
    if (profile.company.isNotEmpty) {
      final dept = profile.department?.trim() ?? '';
      buffer.writeln(
        dept.isEmpty
            ? 'ORG:${profile.company}'
            : 'ORG:${profile.company};$dept',
      );
    }
    if (profile.title.isNotEmpty) buffer.writeln('TITLE:${profile.title}');
    if (profile.phone.isNotEmpty)
      buffer.writeln('TEL;TYPE=CELL:${profile.phone}');
    final officePhone = profile.officePhone?.trim() ?? '';
    if (officePhone.isNotEmpty)
      buffer.writeln('TEL;TYPE=WORK:$officePhone');
    final fax = profile.fax?.trim() ?? '';
    if (fax.isNotEmpty) buffer.writeln('TEL;TYPE=FAX:$fax');
    if (profile.email.isNotEmpty) buffer.writeln('EMAIL:${profile.email}');
    final website = profile.website?.trim() ?? '';
    if (website.isNotEmpty) buffer.writeln('URL:$website');
    final addressLine = [
      profile.address,
      profile.addressDetail,
    ].where((s) => s != null && s.trim().isNotEmpty).join(' ');
    // ADR 성분 순서: 사서함;확장;거리;시;도;우편번호;국가 — 우편번호는 여섯째다.
    final postal = profile.postalCode?.trim() ?? '';
    if (addressLine.isNotEmpty)
      buffer.writeln('ADR;TYPE=WORK:;;$addressLine;;;$postal;');
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
          final addr = value
              .split(';')
              .where((p) => p.trim().isNotEmpty)
              .join(' ');
          if (addr.isNotEmpty) result['address'] = addr;
          break;
      }
    }
    return result.isEmpty ? null : result;
  }
}

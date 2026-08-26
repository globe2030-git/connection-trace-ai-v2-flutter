import '../../data/models/contact_model.dart';
import '../../data/models/my_profile_model.dart';

/// 디지털 명함 QR 코드에 담을 vCard(VERSION 3.0) 텍스트를 만들고 읽는 유틸.
/// vCard는 업계 표준 포맷이라 아이폰/안드로이드 기본 카메라 앱으로 스캔해도
/// "연락처 추가"로 바로 인식되는 장점이 있다.
class VCardUtil {
  static String encodeProfile(MyProfileModel profile) {
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCARD')
      ..writeln('VERSION:3.0')
      ..writeln('N:;${_esc(profile.name)};;;')
      ..writeln('FN:${_esc(profile.name)}');
    // 부서는 vCard 3.0에서 ORG의 두 번째 성분이다(`ORG:회사;부서`).
    if (profile.company.isNotEmpty) {
      final dept = profile.department?.trim() ?? '';
      buffer.writeln(
        dept.isEmpty
            ? 'ORG:${_esc(profile.company)}'
            : 'ORG:${_esc(profile.company)};${_esc(dept)}',
      );
    }
    if (profile.title.isNotEmpty) buffer.writeln('TITLE:${_esc(profile.title)}');
    if (profile.phone.isNotEmpty)
      buffer.writeln('TEL;TYPE=CELL:${_esc(profile.phone)}');
    final officePhone = profile.officePhone?.trim() ?? '';
    if (officePhone.isNotEmpty)
      buffer.writeln('TEL;TYPE=WORK:${_esc(officePhone)}');
    final fax = profile.fax?.trim() ?? '';
    if (fax.isNotEmpty) buffer.writeln('TEL;TYPE=FAX:${_esc(fax)}');
    if (profile.email.isNotEmpty) buffer.writeln('EMAIL:${_esc(profile.email)}');
    final website = profile.website?.trim() ?? '';
    if (website.isNotEmpty) buffer.writeln('URL:${_esc(website)}');
    final addressLine = [
      profile.address,
      profile.addressDetail,
    ].where((s) => s != null && s.trim().isNotEmpty).join(' ');
    // ADR 성분 순서: 사서함;확장;거리;시;도;우편번호;국가 — 우편번호는 여섯째다.
    final postal = profile.postalCode?.trim() ?? '';
    if (addressLine.isNotEmpty)
      buffer.writeln('ADR;TYPE=WORK:;;${_esc(addressLine)};;;${_esc(postal)};');
    buffer.writeln('END:VCARD');
    return buffer.toString();
  }

  /// 명함(상대방)을 vCard 로 만든다 — 폰 주소록으로 내보낼 때 쓴다(추가 492).
  ///
  /// [encodeProfile]과 **같은 구조를 쓴다.** 두 인코더가 어긋나면 *"내 명함으로
  /// 보낼 때와 남의 명함으로 보낼 때가 다른"* 상태가 된다.
  ///
  /// ## 🚨 메모와 소통 기록은 넣지 않는다
  ///
  /// [ContactModel.memo]는 **이용자가 그 사람에 대해 적어 둔 사적인 메모**다.
  /// 소통 기록·대화 소재도 마찬가지다. 이것들은 **명함에 인쇄된 정보가 아니라
  /// 이용자가 만든 것**이고, 내보내기는 **OS 공유 시트를 거쳐 메신저로도 나갈 수
  /// 있다.** 메모가 딸려 나가면 이용자가 의도하지 않은 것이 남에게 간다.
  ///
  /// → **명함에 적혀 있었을 값만 내보낸다.**
  static String encodeContact(ContactModel c) {
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCARD')
      ..writeln('VERSION:3.0')
      ..writeln('N:;${_esc(c.name)};;;')
      ..writeln('FN:${_esc(c.name)}');
    if (c.company.isNotEmpty) {
      final dept = c.department?.trim() ?? '';
      buffer.writeln(
        dept.isEmpty
            ? 'ORG:${_esc(c.company)}'
            : 'ORG:${_esc(c.company)};${_esc(dept)}',
      );
    }
    if (c.title.isNotEmpty) buffer.writeln('TITLE:${_esc(c.title)}');
    if (c.phone.isNotEmpty) buffer.writeln('TEL;TYPE=CELL:${_esc(c.phone)}');
    // 직통·사무실 둘 다 업무 번호다. vCard 는 같은 TYPE 을 여러 줄 쓸 수 있다.
    final direct = c.directPhone?.trim() ?? '';
    if (direct.isNotEmpty) buffer.writeln('TEL;TYPE=WORK:${_esc(direct)}');
    final office = c.officePhone?.trim() ?? '';
    if (office.isNotEmpty) buffer.writeln('TEL;TYPE=WORK:${_esc(office)}');
    final fax = c.fax?.trim() ?? '';
    if (fax.isNotEmpty) buffer.writeln('TEL;TYPE=FAX:${_esc(fax)}');
    if (c.email.isNotEmpty) buffer.writeln('EMAIL:${_esc(c.email)}');
    final website = c.website?.trim() ?? '';
    if (website.isNotEmpty) buffer.writeln('URL:${_esc(website)}');
    final addressLine = [c.address, c.addressDetail]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' ');
    final postal = c.postalCode?.trim() ?? '';
    if (addressLine.isNotEmpty) {
      buffer.writeln('ADR;TYPE=WORK:;;${_esc(addressLine)};;;${_esc(postal)};');
    }
    buffer.writeln('END:VCARD');
    return buffer.toString();
  }

  /// vCard 값 안에서 뜻을 가지는 글자를 막아 둔다(RFC 2426 §2.4.2).
  ///
  /// 🚨 **명함 값은 OCR 이 읽은 것이라 이 글자들이 실제로 들어온다.**
  /// 회사명 *"가나다, 주식회사"*를 그대로 쓰면 쉼표가 값 구분자로 읽혀
  /// **연락처 앱에서 회사명이 잘린다.** 백슬래시가 먼저다 — 나중에 하면
  /// 앞서 넣은 백슬래시를 다시 이스케이프한다.
  static String _esc(String v) => v
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', '');

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
          result['name'] = _unesc(value);
          break;
        case 'ORG':
          result['company'] = _unesc(value);
          break;
        case 'TITLE':
          result['title'] = _unesc(value);
          break;
        case 'TEL':
          result.putIfAbsent('phone', () => _unesc(value));
          break;
        case 'EMAIL':
          result.putIfAbsent('email', () => _unesc(value));
          break;
        case 'ADR':
          // \; 는 값 안의 세미콜론이지 성분 구분자가 아니다.
          final addr = _splitEscaped(value, ';')
              .map(_unesc)
              .where((p) => p.trim().isNotEmpty)
              .join(' ');
          if (addr.isNotEmpty) result['address'] = addr;
          break;
      }
    }
    return result.isEmpty ? null : result;
  }

  /// [_esc] 의 짝. 값 안의 이스케이프를 원래 글자로 되돌린다.
  ///
  /// 🚨 **인코더에만 이스케이프를 넣으면 왕복이 깨진다.** 내 명함 QR 은 우리가
  /// 만들고 우리가 읽는다(`qr_code_modal_view`) — 풀지 않으면 쉼표 든 회사명이
  /// `가나다\, 주식회사` 그대로 상대 기기에 저장된다.
  static String _unesc(String v) {
    final out = StringBuffer();
    for (var i = 0; i < v.length; i++) {
      if (v[i] == '\\' && i + 1 < v.length) {
        final next = v[i + 1];
        i++;
        // \n·\N 만 줄바꿈이다. 나머지(\, \; \\)는 그 글자 자체.
        out.write(next == 'n' || next == 'N' ? '\n' : next);
      } else {
        out.write(v[i]);
      }
    }
    return out.toString();
  }

  /// 구분자로 쪼개되 **이스케이프된 구분자는 건드리지 않는다.**
  ///
  /// `ADR` 은 세미콜론으로 성분을 나누는데, 주소 안에 세미콜론이 들어 있으면
  /// 인코더가 `\;` 로 막아 뒀다. 그냥 `split(';')` 하면 그 자리에서 주소가
  /// 쪼개진다.
  static List<String> _splitEscaped(String v, String sep) {
    final parts = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < v.length; i++) {
      if (v[i] == '\\' && i + 1 < v.length) {
        buf.write(v[i]);
        buf.write(v[i + 1]);
        i++;
      } else if (v[i] == sep) {
        parts.add(buf.toString());
        buf.clear();
      } else {
        buf.write(v[i]);
      }
    }
    parts.add(buf.toString());
    return parts;
  }
}

import '../../data/models/contact_model.dart';

/// 한 칸이 **어떻게 달라지는가**.
enum FieldChangeKind {
  /// 양쪽 다 값이 있고 서로 다르다. 🚨 합치면 **기존 값이 남는다**.
  differs,

  /// 기존에는 있는데 새 명함에는 없다. 합쳐도 **안 사라진다**.
  onlyInExisting,

  /// 새 명함에만 있다. 합치면 **채워진다**.
  onlyInIncoming,
}

/// 확인창에 한 줄로 그릴 것.
class ContactFieldDiff {
  const ContactFieldDiff({
    required this.label,
    required this.kind,
    required this.existing,
    required this.incoming,
  });

  /// 사람이 읽는 칸 이름. 화면 문구와 같은 말을 쓴다.
  final String label;
  final FieldChangeKind kind;

  /// 기존 명함의 값. 없으면 빈 문자열.
  final String existing;

  /// 지금 등록하려는 명함의 값. 없으면 빈 문자열.
  final String incoming;
}

/// 두 명함이 **어느 칸에서 다른지** 센다. 같은 칸은 안 담는다.
///
/// ## 🚨 왜 필요한가 (2026-08-28)
///
/// 「합치기」를 고르면 무엇이 어떻게 되는지 이용자가 볼 수 없었다. 그래서
/// **멀쩡한 값이 OCR 오독으로 덮이는 것**을 모른 채 고르게 됐다.
///
/// ```
/// 실제 사례   직함  「본부장 | S」 → 「mono. alliance」   회사명이 직함 칸에 들어간 오독
/// 있을 수 있는 것  직함  「담당자」    → 「대리」            승진 — 새 값이 맞다
/// ```
///
/// 📌 **둘 다 「값이 둘 있고 다르다」인데 답이 반대다. 코드는 못 가른다.**
/// 그래서 **고르는 것이 아니라 보여 주는 것**이 답이다 — 이용자가 그것을 보고
/// 「합치기」와 「새로 추가」 중에서 고른다.
///
/// ⚠️ **값을 바꾸지 않는다.** 이 함수는 세기만 한다.
List<ContactFieldDiff> diffContacts({
  required ContactModel existing,
  required ContactModel incoming,
}) {
  // 화면에 보이는 차례대로. 이름은 뺀다 — 같아야 여기까지 온다.
  final fields = <(String, String?, String?)>[
    ('회사명', existing.company, incoming.company),
    ('직함', existing.title, incoming.title),
    ('부서', existing.department, incoming.department),
    ('휴대폰', existing.phone, incoming.phone),
    ('사무실 전화', existing.officePhone, incoming.officePhone),
    ('직통 전화', existing.directPhone, incoming.directPhone),
    ('팩스', existing.fax, incoming.fax),
    ('이메일', existing.email, incoming.email),
    ('웹사이트', existing.website, incoming.website),
    ('주소', existing.address, incoming.address),
    ('상세주소', existing.addressDetail, incoming.addressDetail),
    ('우편번호', existing.postalCode, incoming.postalCode),
  ];

  final out = <ContactFieldDiff>[];
  for (final (label, a, b) in fields) {
    final was = (a ?? '').trim();
    final now = (b ?? '').trim();
    if (was == now) continue; // 같으면 보여 줄 것이 없다

    final kind = was.isEmpty
        ? FieldChangeKind.onlyInIncoming
        : now.isEmpty
        ? FieldChangeKind.onlyInExisting
        : FieldChangeKind.differs;

    out.add(
      ContactFieldDiff(
        label: label,
        kind: kind,
        existing: was,
        incoming: now,
      ),
    );
  }
  return out;
}

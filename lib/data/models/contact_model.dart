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
  // 부서 — 직함과 별개 칸이다(2026-08-19 사용자 확정, 추가 320·321).
  //
  // ⚠️ 예전에는 부서가 갈 곳이 없어 **직함이나 회사 칸을 오염**시켰다. 정답지도
  // 장마다 `대리` / `경영지원팀 | 대리`로 갈렸고, 그래서 파서를 어느 쪽에
  // 맞춰도 반대쪽이 틀렸다(추가 286). 칸을 만들어 그 다툼을 없앤다.
  final String? department;
  final String phone;
  final String? officePhone;
  // 직통 전화 — "직통/DID/Direct" 라벨의 개인 유선. 대표번호(officePhone)와 구분.
  final String? directPhone;
  // 팩스 번호. 파서는 사무실 전화 오분류를 막으려고 팩스를 걷어내는데, 이
  // 필드가 생기면 버리는 대신 담는다.
  final String? fax;
  final String email;
  // 회사/개인 웹사이트 URL. 이메일 도메인과 구분해서 보관한다.
  final String? website;
  // 주소1 — 도로명 등 기본 주소. 지오코딩(위치 정보)의 기준이 되는 부분.
  final String? address;
  // 상세주소 — 건물명/동/호수 등. 지오코딩에는 쓰이지 않고 표시용으로만 보관.
  final String? addressDetail;
  // 우편번호(5자리). 지오코딩에는 쓰이지 않고 표시/등록용으로만 보관.
  final String? postalCode;
  final String? avatarUrl;
  final GeoPosition? geo;
  final List<String> tags;
  // 소속 그룹 id 목록(추가 427). 한 명함이 여러 그룹에 속할 수 있다(다중
  // 선택). **그룹 "이름"이 아니라 id를 저장한다** — 그룹 이름이 바뀌어도
  // 이 참조는 그대로 유효해야 하고(태그와 달리 이름 자체가 아니라 그룹이라는
  // 실체를 가리킴), 어느 그룹이 삭제되면 그 id 참조만 걷어낸다
  // (`GroupsViewModel.deleteGroup`). 그룹 목록(이름·생성일) 자체는 여기 없고
  // `GroupsRepository`가 `users/{uid}` 문서 필드로 따로 관리한다 — 법무
  // 검토(2026-08-23, group-feature-legal-note) 결론: 명함별 참조는 태그와
  // 같은 취급(이 필드), 그룹 "목록"은 명함과 독립적으로 존재하는 값이라
  // 별도 저장.
  final List<String> groupIds;
  // 관심사 — AI 대화 브리핑이 상대방과 자연스럽게 안부를 나눌 때 참고하는
  // 항목(취미/관심 분야 등). tags와 별개 필드로 둔 이유: tags는 "이 사람을
  // 어떤 카테고리로 분류할지"(예: AI, C-Level)이고 interests는 "이 사람과
  // 무슨 이야기를 나눌지"에 가까워 의미가 달라 섞으면 태그 목록이 지저분해짐.
  // 입력 UI는 tags와 동일하게 쉼표 구분 텍스트 입력을 따른다.
  final List<String> interests;
  final List<String> talkingPoints;
  final List<CommunicationLogModel> commLogs;
  final String? memo;
  // 스캔한 명함 이미지의 **암호화 파일 경로**(P1-9, 추가 133). 별도 프로필
  // 사진을 안 골라도 스캔한 명함을 그 인맥의 시각으로 쓸 수 있게 보관한다.
  // 로컬 전용(서버 백업 안 함) — 다른 기기에선 파일이 없어 표시가 이니셜로
  // 폴백된다. 실제 표시는 복호화가 필요하다([ContactImageService]).
  final String? cardImagePath;
  // 목록 아바타 자리에 이니셜 대신 위 명함 이미지를 쓸지(사용자 선택, C안).
  // 기본은 false — 목록은 이니셜, 명함 이미지는 상세에서만 보여준다.
  final bool useCardAsAvatar;
  // 명함을 등록했다는 것 자체가 이미 중요한 인맥이라는 뜻이라, 사용자가
  // 따로 "VIP"를 골라야 하는 별도 선택 단계는 의미가 없다는 판단으로
  // 기본값을 true로 바꿨다(이전엔 false였고 명함지갑에서 별표를 눌러야
  // VIP가 됐음 — 그 선택 UI 자체를 제거).
  final bool isPriority;

  /// 마지막으로 이 명함이 생성/수정된 시각. 다기기 동기화(P1-39 A안)에서
  /// "어느 쪽이 최신본인가"를 정하는 기준(last-write-wins). 예전 데이터에는
  /// 없을 수 있어 nullable이며, 병합에서 null은 "가장 오래됨"으로 취급한다.
  final DateTime? updatedAt;

  // --- F-10 재연락 루프(C 연락 후 후속) -------------------------------
  //
  // 전부 **사용자가 실제로 누른 것만** 들어간다. 앱이 추측해서 채우지 않는다
  // ([ReconnectPriorityService]의 "가짜 이유 금지" 가드레일과 같은 원칙).
  // 다른 명함 정보와 똑같이 암호화되어 저장·동기화된다.

  /// C에서 고른 직전 연락 반응. 'good' | 'normal' | 'none'. 안 눌렀으면 null.
  final String? lastReconnectOutcome;

  /// 위 반응을 남긴 시각.
  final DateTime? lastReconnectOutcomeAt;

  /// C에서 "언제 다시?"로 고른 시점. "안 정함"이면 null.
  /// 이 시각이 되기 전에는 A 후보에서 빠지고, 되면 최우선 후보가 된다.
  final DateTime? nextFollowUpAt;

  /// A에서 "이번엔 넘김"을 누른 결과. 이 시각까지는 후보에서 뺀다.
  final DateTime? reconnectSnoozedUntil;

  /// 반응 "없음"이 연달아 몇 번인지. A에서 덜 자주 띄우는 데만 쓴다.
  /// 다른 반응이 한 번이라도 나오면 0으로 돌아간다.
  final int reconnectNoResponseStreak;

  const ContactModel({
    required this.id,
    required this.name,
    required this.company,
    required this.title,
    this.department,
    required this.phone,
    this.officePhone,
    this.directPhone,
    this.fax,
    required this.email,
    this.website,
    this.address,
    this.addressDetail,
    this.postalCode,
    this.avatarUrl,
    this.geo,
    required this.tags,
    this.groupIds = const [],
    this.interests = const [],
    required this.talkingPoints,
    this.commLogs = const [],
    this.memo,
    this.cardImagePath,
    this.useCardAsAvatar = false,
    this.isPriority = true,
    this.updatedAt,
    this.lastReconnectOutcome,
    this.lastReconnectOutcomeAt,
    this.nextFollowUpAt,
    this.reconnectSnoozedUntil,
    this.reconnectNoResponseStreak = 0,
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
      'department': department,
      'phone': phone,
      'officePhone': officePhone,
      'directPhone': directPhone,
      'fax': fax,
      'email': email,
      'website': website,
      'address': address,
      'addressDetail': addressDetail,
      'postalCode': postalCode,
      'avatarUrl': avatarUrl,
      if (includeGeo) 'lat': geo?.lat,
      if (includeGeo) 'lng': geo?.lng,
      'tags': tags,
      // 태그와 동일하게 취급한다(법무 검토 결론) — 좌표·명함이미지 경로처럼
      // includeGeo로 가리지 않고 서버 백업에도 그대로 실린다.
      'groupIds': groupIds,
      'interests': interests,
      'talkingPoints': talkingPoints,
      'commLogs': commLogs.map((l) => l.toJson()).toList(),
      'memo': memo,
      // 명함 이미지 경로는 로컬 전용이라 서버 백업(includeGeo=false)에는 안
      // 넣는다 — 다른 기기에선 그 경로에 파일이 없어 의미가 없다. 좌표와
      // 같은 이유(파생/기기 종속)라 같은 플래그를 재사용한다.
      if (includeGeo) 'cardImagePath': cardImagePath,
      // 이건 사용자 선택(선호도)이라 서버에도 남겨 기기 간 일관되게 한다.
      'useCardAsAvatar': useCardAsAvatar,
      'isPriority': isPriority,
      // 서버 백업에도 포함한다 — 다기기 병합의 최신본 판정 기준이라 서버에
      // 남아야 다른 기기가 비교할 수 있다(좌표와 달리 파생값이 아니다).
      'updatedAt': updatedAt?.toIso8601String(),
      // F-10 재연락 기록. 서버 백업에도 넣는다 — 기기를 바꾸면 "언제 다시
      // 연락하기로 했는지"가 사라지는데, 그건 사용자가 직접 정한 약속이라
      // 좌표(파생값)와 성격이 다르다. 다른 명함 정보와 같이 암호화된다.
      'lastReconnectOutcome': lastReconnectOutcome,
      'lastReconnectOutcomeAt': lastReconnectOutcomeAt?.toIso8601String(),
      'nextFollowUpAt': nextFollowUpAt?.toIso8601String(),
      'reconnectSnoozedUntil': reconnectSnoozedUntil?.toIso8601String(),
      'reconnectNoResponseStreak': reconnectNoResponseStreak,
    };
  }

  factory ContactModel.fromJson(Map<String, dynamic> json) {
    return ContactModel(
      id: json['id'] as String,
      name: json['name'] as String,
      company: json['company'] as String,
      title: json['title'] as String,
      // ⚠️ 2026-08-19 이전에 저장된 명함에는 이 키가 없다 — null로 들어온다.
      // nullable이라 마이그레이션이 필요 없다.
      department: json['department'] as String?,
      phone: json['phone'] as String,
      officePhone: json['officePhone'] as String?,
      directPhone: json['directPhone'] as String?,
      fax: json['fax'] as String?,
      email: json['email'] as String,
      website: json['website'] as String?,
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
      // ⚠️ 2026-08-23 이전 저장분에는 이 키가 없다 — 빈 목록으로 안전하게
      // 폴백한다(마이그레이션 불필요, department와 같은 패턴).
      groupIds: List<String>.from(json['groupIds'] ?? []),
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
      cardImagePath: json['cardImagePath'] as String?,
      useCardAsAvatar: json['useCardAsAvatar'] as bool? ?? false,
      isPriority: json['isPriority'] as bool? ?? true,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      lastReconnectOutcome: json['lastReconnectOutcome'] as String?,
      lastReconnectOutcomeAt: json['lastReconnectOutcomeAt'] != null
          ? DateTime.tryParse(json['lastReconnectOutcomeAt'] as String)
          : null,
      nextFollowUpAt: json['nextFollowUpAt'] != null
          ? DateTime.tryParse(json['nextFollowUpAt'] as String)
          : null,
      reconnectSnoozedUntil: json['reconnectSnoozedUntil'] != null
          ? DateTime.tryParse(json['reconnectSnoozedUntil'] as String)
          : null,
      reconnectNoResponseStreak:
          (json['reconnectNoResponseStreak'] as num?)?.toInt() ?? 0,
    );
  }

  ContactModel copyWith({
    String? id,
    String? name,
    String? company,
    String? title,
    String? department,
    String? phone,
    String? officePhone,
    String? directPhone,
    String? fax,
    String? email,
    String? website,
    String? address,
    String? addressDetail,
    String? postalCode,
    String? avatarUrl,
    GeoPosition? geo,
    List<String>? tags,
    List<String>? groupIds,
    List<String>? interests,
    List<String>? talkingPoints,
    List<CommunicationLogModel>? commLogs,
    String? memo,
    String? cardImagePath,
    bool? useCardAsAvatar,
    bool? isPriority,
    DateTime? updatedAt,
    String? lastReconnectOutcome,
    DateTime? lastReconnectOutcomeAt,
    DateTime? nextFollowUpAt,
    DateTime? reconnectSnoozedUntil,
    int? reconnectNoResponseStreak,
    // `??` 방식의 copyWith는 **null로 되돌리는 것**을 표현할 수 없다. F-10에서는
    // "안 정함"(다음 시점 없음)과 "스누즈 해제"가 실제로 필요한 상태라, 그
    // 둘만 명시적 플래그를 둔다. 전체 필드에 도입하면 서명이 두 배가 된다.
    bool clearNextFollowUpAt = false,
    bool clearReconnectSnoozedUntil = false,
  }) {
    return ContactModel(
      id: id ?? this.id,
      name: name ?? this.name,
      company: company ?? this.company,
      title: title ?? this.title,
      department: department ?? this.department,
      phone: phone ?? this.phone,
      officePhone: officePhone ?? this.officePhone,
      directPhone: directPhone ?? this.directPhone,
      fax: fax ?? this.fax,
      email: email ?? this.email,
      website: website ?? this.website,
      address: address ?? this.address,
      addressDetail: addressDetail ?? this.addressDetail,
      postalCode: postalCode ?? this.postalCode,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      geo: geo ?? this.geo,
      tags: tags ?? this.tags,
      groupIds: groupIds ?? this.groupIds,
      interests: interests ?? this.interests,
      talkingPoints: talkingPoints ?? this.talkingPoints,
      commLogs: commLogs ?? this.commLogs,
      memo: memo ?? this.memo,
      cardImagePath: cardImagePath ?? this.cardImagePath,
      useCardAsAvatar: useCardAsAvatar ?? this.useCardAsAvatar,
      isPriority: isPriority ?? this.isPriority,
      updatedAt: updatedAt ?? this.updatedAt,
      lastReconnectOutcome: lastReconnectOutcome ?? this.lastReconnectOutcome,
      lastReconnectOutcomeAt:
          lastReconnectOutcomeAt ?? this.lastReconnectOutcomeAt,
      nextFollowUpAt: clearNextFollowUpAt
          ? null
          : (nextFollowUpAt ?? this.nextFollowUpAt),
      reconnectSnoozedUntil: clearReconnectSnoozedUntil
          ? null
          : (reconnectSnoozedUntil ?? this.reconnectSnoozedUntil),
      reconnectNoResponseStreak:
          reconnectNoResponseStreak ?? this.reconnectNoResponseStreak,
    );
  }
}

/// 명함 그룹(추가 427) — 이용자가 직접 만드는 분류 묶음(예: "삼성전자 사람들").
///
/// ⚠️ 그룹 **이름**은 제3자를 특정할 수 있는 자유 입력값이라 메모·태그와 같은
/// 취급을 받는다(법무 스팟 확인, `docs/planning/group-feature-legal-note-
/// 2026-08-23.md`). 저장은 [GroupsRepository]가 `users/{uid}` 문서의 암호화
/// 필드로 담당한다 — 이름 원문을 일반(비암호화) 저장소에 두지 않는다.
class GroupModel {
  final String id;
  final String name;
  final DateTime createdAt;

  const GroupModel({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory GroupModel.fromJson(Map<String, dynamic> json) => GroupModel(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  GroupModel copyWith({String? name}) => GroupModel(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
  );
}

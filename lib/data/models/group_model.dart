/// 그룹 기능(추가 427) UI 노출 스위치.
///
/// ## 왜 필요한가
///
/// 그룹 데이터 수집을 새로 고지하는 방침 **v2.3이 시행된 뒤**에 켠다.
///
/// ⚠️ **여기에 날짜를 적지 않는다**(2026-08-26 결정). 시행일은 방침 문서
/// (`docs/legal/privacy-policy.html`) 한 곳에만 둔다 — 날짜를 코드·문서에
/// 복사해 두었더니 **열 곳 넘게 퍼졌고, 일정이 바뀌자 전부 낡았다.**
/// 그런데 테스터 배포는 그보다 먼저(2026-08-24) 나간다 — 시행일 전 빌드에서
/// 그룹 UI가 보이면 아직 고지되지 않은 개인정보 항목을 실제로 수집하게 된다
/// (법무 스팟 확인, `docs/planning/group-feature-legal-note-2026-08-23.md`
/// 질문 1 "게시 순서 — 코드보다 고지가 먼저입니다").
///
/// ⚠️ **데이터는 건드리지 않는다.** 이 플래그는 화면 노출만 끄고, 저장·백업·
/// 복원 경로는 그대로 둔다 — 오늘(8/23) 실기기로 이미 만든 그룹은 꺼진 빌드
/// 에서도 값이 유지되며, 켜지면 그대로 다시 보인다.
///
/// ## 켜는 날
///
/// 방침 v2.3이 **실제로 게시되고 시행된 뒤**, 기본값을 `false`에서 `true`로 뒤집는
/// **한 줄짜리 커밋**으로 켠다. 빌드 시 `--dart-define=GROUPS_FEATURE=true`를
/// 주면 그 전에도 개발·확인용으로 켤 수 있다(`tool/build_app.sh`의 `groups`
/// 인자, 정의하지 않으면 항상 꺼진 채로 빌드된다).
const bool kGroupsFeatureEnabled = bool.fromEnvironment('GROUPS_FEATURE');

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

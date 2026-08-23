import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/group_model.dart';
import '../view_models/groups_view_model.dart';

/// 그룹 지정 바텀시트(추가 427 — 캔버스 확정안 ①).
///
/// - 다중 선택(한 명함이 여러 그룹에 속할 수 있다).
/// - 검색창이 "새 그룹 만들기"를 겸한다 — 입력값과 정확히 일치하는 그룹이
///   없으면 "'○○' 새 그룹 만들기" 행이 뜬다(리멤버의 별도 관리 화면 대신
///   검색 통합으로 단순화한 설계 결정, 브리프 참고).
/// - "관리" 모드에서 이름변경·삭제(삭제해도 명함은 유지, 참조만 제거).
///
/// ⚠️ **여기서 바로 명함에 커밋하지 않는다.** 이 시트는 선택 결과(그룹 id
/// 집합)만 돌려준다 — 새 명함 등록 중에는 아직 저장소에 그 명함이 없어
/// [GroupsViewModel.setContactGroups]를 부를 대상이 없기 때문이다. 커밋은
/// 호출부(상세 화면은 즉시, 등록 폼은 저장 시점에 [ContactModel.groupIds]로)
/// 몫이다.
class GroupAssignSheet extends StatefulWidget {
  final Set<String> initialSelectedGroupIds;

  const GroupAssignSheet({super.key, required this.initialSelectedGroupIds});

  static Future<Set<String>?> show(
    BuildContext context, {
    required Set<String> initialSelectedGroupIds,
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          GroupAssignSheet(initialSelectedGroupIds: initialSelectedGroupIds),
    );
  }

  @override
  State<GroupAssignSheet> createState() => _GroupAssignSheetState();
}

class _GroupAssignSheetState extends State<GroupAssignSheet> {
  late Set<String> _selected;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _managing = false;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelectedGroupIds};
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupsVm = context.watch<GroupsViewModel>();
    final allGroups = groupsVm.groups;
    final queryLower = _query.toLowerCase();
    final visible = queryLower.isEmpty
        ? allGroups
        : allGroups
              .where((g) => g.name.toLowerCase().contains(queryLower))
              .toList();
    final exactMatchExists = allGroups.any(
      (g) => g.name.trim().toLowerCase() == queryLower,
    );
    final showCreateRow = _query.isNotEmpty && !exactMatchExists;
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height - topInset - 12,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 10),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '그룹 지정',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _managing = !_managing),
                      child: Text(_managing ? '완료' : '관리'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '그룹 검색 또는 새 이름 입력',
                    hintStyle: TextStyle(color: AppColors.textMuted),
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  children: [
                    if (showCreateRow)
                      _CreateGroupRow(
                        name: _query,
                        onTap: () {
                          final created = groupsVm.createGroup(_query);
                          setState(() {
                            _selected.add(created.id);
                            _searchController.clear();
                          });
                        },
                      ),
                    if (visible.isEmpty && !showCreateRow)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          allGroups.isEmpty
                              ? '아직 만든 그룹이 없어요. 위 검색창에 이름을 적어 '
                                    '새 그룹을 만들어 보세요.'
                              : '검색 결과가 없어요.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    for (final g in visible)
                      _GroupRow(
                        group: g,
                        memberCount: groupsVm.memberCountOf(g.id),
                        managing: _managing,
                        selected: _selected.contains(g.id),
                        onToggle: () => setState(() {
                          if (!_selected.remove(g.id)) _selected.add(g.id);
                        }),
                        onRename: () => _renameGroup(context, groupsVm, g),
                        onDelete: () => _deleteGroup(context, groupsVm, g),
                      ),
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.borderSubtle),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textMuted,
                          side: const BorderSide(color: AppColors.borderSubtle),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(_selected),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('확인'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameGroup(
    BuildContext context,
    GroupsViewModel groupsVm,
    GroupModel group,
  ) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('그룹 이름 바꾸기'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(controller.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    groupsVm.renameGroup(group.id, trimmed);
  }

  Future<void> _deleteGroup(
    BuildContext context,
    GroupsViewModel groupsVm,
    GroupModel group,
  ) async {
    final memberCount = groupsVm.memberCountOf(group.id);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('"${group.name}" 그룹을 삭제할까요?'),
        content: Text(
          memberCount > 0
              ? '이 그룹에 속한 명함 $memberCount개는 그대로 남고, 그룹 지정만 '
                    '풀립니다.'
              : '그룹만 삭제됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    groupsVm.deleteGroup(group.id);
    setState(() => _selected.remove(group.id));
  }
}

/// "'○○' 새 그룹 만들기" 행 — 검색창이 새 그룹 만들기를 겸하는 자리.
class _CreateGroupRow extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _CreateGroupRow({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.add_circle_outline, color: AppColors.accentText),
      title: Text(
        '"$name" 새 그룹 만들기',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.accentText,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// 그룹 한 줄 — 평소엔 다중 선택 체크박스, "관리" 모드에선 이름변경·삭제 아이콘.
class _GroupRow extends StatelessWidget {
  final GroupModel group;
  final int memberCount;
  final bool managing;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _GroupRow({
    required this.group,
    required this.memberCount,
    required this.managing,
    required this.selected,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: managing ? null : onToggle,
      leading: managing
          ? null
          : Checkbox(
              value: selected,
              onChanged: (_) => onToggle(),
              activeColor: AppColors.accent,
            ),
      title: Text(
        group.name,
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      ),
      subtitle: Text(
        '$memberCount명',
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      trailing: managing
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '이름 바꾸기',
                  onPressed: onRename,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
                IconButton(
                  tooltip: '그룹 삭제',
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppColors.destructive,
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

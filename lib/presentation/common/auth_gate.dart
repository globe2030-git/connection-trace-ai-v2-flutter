import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/contacts_repository.dart';
import '../../data/repositories/my_profile_repository.dart';
import '../features/auth/views/login_view.dart';

/// 로그인 세션 확인이 끝날 때까지는 빈 배경을 보여주고(스플래시와 자연스럽게
/// 이어짐), 이후 로그인 여부에 따라 로그인 화면 또는 실제 앱 화면([child])을
/// 보여준다.
///
/// 로그인 성공 시점에 명함/프로필 리포지토리에 현재 계정의 Firebase uid를
/// 전달하고(서버 백업 대상 식별), 로컬 데이터가 비어있으면 서버 백업분을
/// 복원한다(backlog 추가 66 — 백업/복원 방식, 새 기기/재설치 시나리오).
class AuthGate extends StatefulWidget {
  final Widget child;

  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _lastHandledUid;

  void _syncUidAndRestore(BuildContext context, String? uid) {
    if (uid == _lastHandledUid) return;
    _lastHandledUid = uid;
    final contactsRepo = context.read<ContactsRepository>();
    final profileRepo = context.read<MyProfileRepository>();
    contactsRepo.setCurrentUid(uid);
    profileRepo.setCurrentUid(uid);
    if (uid != null) {
      contactsRepo.restoreFromServerIfEmpty(uid);
      profileRepo.restoreFromServerIfEmpty(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    if (auth.isLoading) {
      return const Scaffold(backgroundColor: AppColors.bgDarkSlate);
    }
    if (!auth.isSignedIn) {
      _syncUidAndRestore(context, null);
      return const LoginView();
    }
    _syncUidAndRestore(context, auth.firebaseUid);
    return widget.child;
  }
}

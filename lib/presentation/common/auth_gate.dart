import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/contacts_repository.dart';
import '../../data/repositories/my_profile_repository.dart';
import '../features/auth/views/login_view.dart';

/// 계정 전환 안전장치(backlog #50)에서 "이 기기에 마지막으로 로그인했던
/// uid"를 기억해두는 shared_preferences 키. 앱 재시작에도 유지되어야 해서
/// `_AuthGateState`의 메모리 변수(`_lastHandledUid`)와는 별개로 존재한다.
const kLastSignedInUidPrefsKey = 'last_signed_in_uid_v1';

/// 로그인 세션 확인이 끝날 때까지는 빈 배경을 보여주고(스플래시와 자연스럽게
/// 이어짐), 이후 로그인 여부에 따라 로그인 화면 또는 실제 앱 화면([child])을
/// 보여준다.
///
/// 로그인 성공 시점에 명함/프로필 리포지토리에 현재 계정의 Firebase uid를
/// 전달하고(서버 백업 대상 식별), 로컬 데이터가 비어있으면 서버 백업분을
/// 복원한다(backlog 추가 66 — 백업/복원 방식, 새 기기/재설치 시나리오).
///
/// backlog #50: 로컬에 데이터가 이미 있는 상태에서(계정A로 쓰던 중) 다른
/// 계정(계정B)으로 로그인하면 "로컬이 비어있을 때만 복원"하는 기존 규칙만
/// 으로는 두 계정 데이터가 뒤섞일 수 있다(계정A 로컬 데이터가 계정B 것처럼
/// 보이거나, 계정B로 저장을 시작하면 계정A 명함이 계정B uid로 서버에
/// 백업되는 교차 오염). 그래서 로그인한 uid가 마지막으로 기억해둔 uid와
/// 다르고 로컬에 기존 데이터가 있으면, 자동으로 아무거나 하지 않고
/// 사용자에게 명시적으로 묻는다.
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
    if (uid == null) return;
    // 계정 전환 다이얼로그를 띄울 수도 있으므로, 이번 프레임의 build가
    // 끝난 뒤(Navigator가 안전하게 쓸 수 있는 시점)로 미룬다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleAccountSync(context, uid, contactsRepo, profileRepo);
    });
  }

  Future<void> _handleAccountSync(
    BuildContext context,
    String uid,
    ContactsRepository contactsRepo,
    MyProfileRepository profileRepo,
  ) async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('마지막 로그인 uid 확인 실패: $e');
      await contactsRepo.restoreFromServerIfEmpty(uid);
      await profileRepo.restoreFromServerIfEmpty(uid);
      return;
    }
    final lastUid = prefs.getString(kLastSignedInUidPrefsKey);
    final hasLocalData =
        contactsRepo.contacts.isNotEmpty || profileRepo.hasCustomProfile;

    if (lastUid != null && lastUid != uid && hasLocalData) {
      if (!context.mounted) return;
      final replace = await _showAccountSwitchDialog(context);
      if (replace == true) {
        await contactsRepo.clearLocal();
        await profileRepo.clearLocal();
        await contactsRepo.forceRestoreFromServer(uid);
        await profileRepo.forceRestoreFromServer(uid);
      }
      // "유지하고 계속 쓰기"를 선택했어도(또는 다이얼로그가 그대로 닫혀도)
      // uid는 갱신해둔다 — 사용자가 이미 한 번 명시적으로 다룬 상태이므로
      // 다음부터는 다시 묻지 않는다.
      await prefs.setString(kLastSignedInUidPrefsKey, uid);
      return;
    }

    await contactsRepo.restoreFromServerIfEmpty(uid);
    await profileRepo.restoreFromServerIfEmpty(uid);
    // 다기기 동기화(P1-39): 로컬이 이미 있어도 서버에만 있는 명함을 더한다.
    // 같은 계정으로 다른 기기에서 등록한 명함이 이 기기에 뜨지 않던 문제 해결.
    // 계정 전환("유지") 경로(위 return)에는 넣지 않는다 — 다른 계정 데이터가
    // 섞일 수 있어서다. 여기는 같은 계정(또는 최초/로컬없음)만 도달한다.
    await contactsRepo.mergeFromServer(uid);
    await prefs.setString(kLastSignedInUidPrefsKey, uid);
  }

  Future<bool?> _showAccountSwitchDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('다른 계정으로 로그인했습니다'),
        content: const Text(
          '이 기기에는 이전에 쓰던 계정의 명함·프로필 데이터가 남아 있습니다.\n\n'
          '지금 로그인한 계정의 서버 데이터로 교체할까요, 아니면 기존 데이터를 '
          '유지한 채 계속 쓸까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('유지하고 계속 쓰기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '현재 계정 데이터로 교체',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthRepository>();
    if (auth.isLoading) {
      return const Scaffold(backgroundColor: AppColors.bgBase);
    }
    if (!auth.isSignedIn) {
      _syncUidAndRestore(context, null);
      return const LoginView();
    }
    _syncUidAndRestore(context, auth.firebaseUid);
    return widget.child;
  }
}

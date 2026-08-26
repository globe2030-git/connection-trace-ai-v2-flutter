import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/account_bootstrap_service.dart';
import '../../core/services/ad_consent_service.dart';
import '../../core/theme/app_colors.dart';
import '../../data/repositories/auth_repository.dart';
import '../../core/utils/account_switch_policy.dart';
import '../../data/services/data_backup_service.dart';
import '../../data/repositories/contacts_repository.dart';
import '../../data/repositories/groups_repository.dart';
import '../../data/repositories/my_profile_repository.dart';
import '../features/auth/views/ad_consent_notice_dialog.dart';
import '../features/auth/views/ad_consent_view.dart';
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
    // 그룹(추가 427) — 프로필과 같은 방식(users/{uid} 문서 필드)으로 우선
    // 복호화 재로드가 필요하다. 명함처럼 경합 방지를 위해 기다릴 필요는
    // 없다 — 그룹 목록은 명함 목록과 달리 "비었다"고 오판해도 통째로
    // 덮어쓰는 위험이 없는 별도 필드라(restoreFromServerIfEmpty가 그룹
    // 쪽만 본다), profileRepo와 동일한 수준으로 다룬다.
    final groupsRepo = context.read<GroupsRepository>();
    // 복호화 재로드가 시작되도록 uid를 알리고, 그 완료(Future)를 붙잡는다.
    // 아래 동기화 전에 이 로드를 기다려야 로컬을 "비었다"고 오판하지 않는다
    // (2026-08-09 실기기에서 확인된 경합 — 추가 120, P1-39 A안).
    final contactsLoaded = contactsRepo.setCurrentUid(uid);
    profileRepo.setCurrentUid(uid);
    groupsRepo.setCurrentUid(uid);
    if (uid == null) return;
    // 계정 전환 다이얼로그를 띄울 수도 있으므로, 이번 프레임의 build가
    // 끝난 뒤(Navigator가 안전하게 쓸 수 있는 시점)로 미룬다.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // 복호화 로드가 끝난 뒤에 동기화한다(경합 수정).
      await contactsLoaded;
      if (!context.mounted) return;
      _handleAccountSync(context, uid, contactsRepo, profileRepo, groupsRepo);
    });
  }

  Future<void> _handleAccountSync(
    BuildContext context,
    String uid,
    ContactsRepository contactsRepo,
    MyProfileRepository profileRepo,
    GroupsRepository groupsRepo,
  ) async {
    // 로그인마다(uid 변경마다, 이 메서드는 `_syncUidAndRestore`의
    // `_lastHandledUid` 가드로 uid당 한 번만 호출됨) 서버 부트스트랩을
    // 부른다 — 무료체험 크레딧 지급 + 리퍼럴 코드 발급(둘 다 서버가 멱등
    // 가드를 걸어 두므로 재로그인해도 중복 지급 안 됨). 명함/프로필
    // 복원과는 독립적인 부가 기능이라, 그 흐름을 기다리게 하지 않고
    // 실패해도 로그인 자체를 막지 않는다(AccountBootstrapService 내부에서
    // 이미 모든 예외를 삼킴 — rebackupAllContacts류 부가호출과 동일 패턴).
    unawaited(AccountBootstrapService.call());

    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('마지막 로그인 uid 확인 실패: $e');
      // ⚠️ 마지막 uid를 못 읽으면 **계정 전환인지 알 수 없다.** 모르는 채로
      // 서버에 올리면 남의 명함을 올릴 수 있으므로, 이 경로에서는 일회성
      // 마이그레이션을 건너뛴다. 다음 로그인에 다시 기회가 온다.
      await contactsRepo.restoreFromServerIfEmpty(uid);
      await profileRepo.restoreFromServerIfEmpty(uid);
      await groupsRepo.restoreFromServerIfEmpty(uid);
      await contactsRepo.runPostSyncMaintenance(
        skipServerMigration: !mayMigrateToServer(
          lastUidKnown: false,
          isAccountSwitch: false,
          replaced: false,
        ),
      );
      return;
    }
    final lastUid = prefs.getString(kLastSignedInUidPrefsKey);
    // 그룹(추가 427)도 여기 넣는다 — 안 넣으면 명함·프로필은 비어 있고
    // 그룹만 남은 상태로 계정을 바꿨을 때 전환 확인 없이 새 계정 문맥으로
    // 넘어가, 이전 계정의 그룹명(제3자를 특정할 수 있는 값일 수 있음)이
    // 새 계정 쪽에 그대로 남는 교차 오염이 생긴다 — 명함/프로필에서 이미
    // 겪은 것과 같은 유형의 사고(위 조건이 원래 이걸 막으려고 있다).
    final hasLocalData =
        contactsRepo.contacts.isNotEmpty ||
        profileRepo.hasCustomProfile ||
        groupsRepo.groups.isNotEmpty;

    if (lastUid != null && lastUid != uid && hasLocalData) {
      if (!context.mounted) return;
      final replace = await _showAccountSwitchDialog(context);
      if (replace == true) {
        // ⚠️ **이전 계정의 기기 잔존물(명함 사진 암호문·로컬 암호화 키)은
        // 일부러 지우지 않는다.** clearLocal은 shared_preferences만 비운다.
        //
        // 서버 사진 백업이 꺼져 있어(kCardPhotoBackupEnabled = false)
        // **지우면 되살릴 방법이 없다.** 개인정보 최소화와 데이터 보전이
        // 정면으로 부딪히는 자리라, 지금은 보전을 택한다(법무 회신 질문 9-④6).
        // 사진 서버 백업을 켤 때 이 판단을 다시 봐야 한다.
        await contactsRepo.clearLocal();
        await profileRepo.clearLocal();
        await groupsRepo.clearLocal();
        await contactsRepo.forceRestoreFromServer(uid);
        await profileRepo.forceRestoreFromServer(uid);
        await groupsRepo.forceRestoreFromServer(uid);
      }
      // ⚠️ **여기서 처음으로 서버 쓰기가 허용된다.** 선택이 끝났기 때문이다.
      //
      // "유지"를 골랐으면 일회성 마이그레이션을 **건너뛴다** — 그 명함들은
      // 이 계정이 수집한 것이 아니라 이 기기에 남아 있던 것이고, 통째로
      // 이 계정의 서버 백업에 올리면 **제3자 개인정보가 두 계정에 이중으로
      // 존재하게 된다.** ("교체"를 고른 경우는 위에서 이미 이 계정 자신의
      // 데이터로 갈아 끼운 뒤라 올려도 자기 것이다.)
      await contactsRepo.runPostSyncMaintenance(
        skipServerMigration: !mayMigrateToServer(
          lastUidKnown: true,
          isAccountSwitch: true,
          replaced: replace == true,
        ),
      );
      // ⚠️ 무엇을 골랐는지 남긴다. 나중에 "이 명함들이 왜 이 계정에 있느냐"는
      // 물음에 답하려면 **두 계정이 같은 사람이었다는 것을 회사가 보여야
      // 한다**(개인정보 보호법 §16①의 입증책임). 명함 내용은 넣지 않는다.
      await DataBackupService.recordAccountSwitch(
        uid,
        previousUid: lastUid,
        replaced: replace == true,
      );
      // "유지하고 계속 쓰기"를 선택했어도(또는 다이얼로그가 그대로 닫혀도)
      // uid는 갱신해둔다 — 사용자가 이미 한 번 명시적으로 다룬 상태이므로
      // 다음부터는 다시 묻지 않는다.
      await prefs.setString(kLastSignedInUidPrefsKey, uid);
      return;
    }

    // 다기기 동기화(P1-39 A안): 서버와 로컬을 결정적으로 병합한다 — 추가·편집·
    // 삭제 전파 + 오프라인 로컬 손실 방지(updatedAt LWW + tombstone). 위
    // _syncUidAndRestore가 복호화 로드 완료를 기다린 뒤 여기 도달하므로 로컬을
    // 빈 것으로 오판하지 않는다. 계정 전환("유지") 경로(위 return)엔 넣지 않는다
    // — 다른 계정 데이터가 섞일 수 있어서다. 여기는 같은 계정(또는 최초)만 도달.
    await contactsRepo.syncWithServer(uid);
    await profileRepo.restoreFromServerIfEmpty(uid);
    await groupsRepo.restoreFromServerIfEmpty(uid);
    // 같은 계정(또는 최초 로그인)이라 올려도 자기 데이터다.
    await contactsRepo.runPostSyncMaintenance(
      skipServerMigration: !mayMigrateToServer(
        lastUidKnown: true,
        isAccountSwitch: false,
        replaced: false,
      ),
    );
    await prefs.setString(kLastSignedInUidPrefsKey, uid);

    // 광고 수신 동의(추가 472) — **복원이 끝난 뒤에** 묻는다.
    //
    // 여기 두는 이유 둘.
    //  1) 빈 화면 위에 동의 시트가 뜨면 **가입 절차로 읽힌다.** 선택 동의인데
    //     필수처럼 보이면 자유로운 동의(시행령 §17①1호)에서 멀어진다.
    //  2) 복원 중에 뜨면 뒤에서 목록이 바뀌어 산만하다.
    //
    // ⚠️ 위쪽 두 return 경로(마지막 uid를 못 읽음 · 계정 전환)에서는 묻지
    //    않는다. 앞은 "모르는 상태"이고 뒤는 이용자가 방금 무거운 선택을 한
    //    직후다. **다음 로그인에 다시 기회가 온다** — 이 파일이 이미 같은
    //    판단을 여러 번 한다.
    if (!context.mounted) return;
    await _maybeAskAdConsent(context, uid);
  }

  /// 아직 답한 적 없는 계정에게 광고 수신 동의를 **한 번** 묻는다.
  ///
  /// 신규·기존 이용자가 **한 경로로** 처리된다 — 기준이 "가입한 지 얼마나
  /// 됐나"가 아니라 **"이 계정에 응답 기록이 있나"**이기 때문이다.
  Future<void> _maybeAskAdConsent(BuildContext context, String uid) async {
    final service = AdConsentService();
    // 읽기에 실패하면 묻지 않는다 — 이미 답한 사람에게 또 묻는 것보다
    // 한 번 건너뛰는 편이 낫다(AdConsentService.shouldAsk 주석).
    if (!await service.shouldAsk(uid)) return;
    if (!context.mounted) return;

    final provider = context.read<AuthRepository>().provider;
    var saved = false;
    var savedEmail = false;
    var savedPush = false;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AdConsentView(
          provider: provider,
          // 🚨 **저장에 실패해도 닫는다.** 여기서 머물면 앱에 들어갈 길이
          //    없다 — `firestore.rules` 가 배포되기 전에는 서버가 쓰기를
          //    거부하므로 [submitLabel] 을 몇 번 눌러도 제자리다
          //    (2026-08-26 폴드 실측, `AdConsentView.dismissOnSaveFailure`).
          dismissOnSaveFailure: true,
          onSubmit: ({required email, required push}) async {
            final ok = await service.save(
              uid: uid,
              email: email,
              push: push,
              firstAnswer: true,
            );
            if (ok) {
              saved = true;
              savedEmail = email;
              savedPush = push;
            }
            return ok;
          },
        ),
      ),
    );

    if (!saved || !context.mounted) return;

    // ⚠️ 처리결과 통지는 **하나라도 켠 경우에만** 띄운다. 아무것도 안 고른
    //    것은 "동의를 받은 사실"이 없어 §50⑦의 통지 대상이 아니고, 굳이
    //    띄우면 거부한 사람에게 팝업을 하나 더 보이는 셈이 된다.
    if (!savedEmail && !savedPush) return;

    await showAdConsentNotice(
      context,
      email: savedEmail,
      push: savedPush,
      consented: true,
    );
    // 통지 증적을 남긴다. 실패해도 통지는 이미 보였으므로 되돌리지 않는다.
    await service.markNotified(uid);
  }

  Future<bool?> _showAccountSwitchDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('다른 계정으로 로그인했습니다'),
        // ⚠️ 문구가 이 화면의 핵심이다. 예전에는 "기존 데이터를 유지한 채
        // 계속 쓸까요?" 였는데, **유지가 무슨 일인지 말하지 않았다** — 그
        // 명함들이 지금 계정의 데이터가 되어 지금 계정의 서버 백업에
        // 올라간다는 사실이 빠져 있었다.
        //
        // 📌 "교체해도 이전 계정 백업은 남는다"도 반드시 함께 말한다.
        // 이 한 줄이 없으면 이용자는 잃을까 봐 **안전한 쪽(교체)을 못 고른다.**
        // 실물 확인 결과 clearLocal 은 서버를 건드리지 않는다.
        content: const Text(
          '이 기기에는 이전에 쓰던 계정의 명함·프로필 데이터가 남아 있습니다.\n\n'
          '유지하면 이 기기의 명함이 지금 로그인한 계정의 데이터가 되고, '
          '이후 저장·수정할 때 지금 계정의 서버 백업에 함께 저장됩니다. '
          '이전 계정과 지금 계정이 같은 분이 아니라면 교체를 선택해 주세요.\n\n'
          '교체해도 이전 계정에 백업된 명함은 지워지지 않으며, '
          '그 계정으로 다시 로그인하면 복원됩니다.',
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

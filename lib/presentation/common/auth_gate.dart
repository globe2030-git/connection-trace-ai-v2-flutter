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
import '../features/auth/views/phone_verify_view.dart';
import '../../core/services/phone_verification_service.dart';
import '../../core/services/card_photo_backup_state.dart';
import '../../core/services/carried_over_contacts.dart';

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

  /// 이 계정이 휴대전화번호 확인을 마쳤는가(추가 565).
  ///
  /// ```
  /// null   아직 모른다 — 조회 중이거나 조회에 실패했다
  /// false  안 했다 — 인증 화면을 그린다
  /// true   했다 — 앱 본체로 간다
  /// ```
  ///
  /// 🚨 **`null`과 `false`를 갈라 둔 것이 중요하다.** 모르는 것을 「안 했다」로
  /// 다루면 **조회가 한 번 실패한 사람이 인증 화면에 갇힌다.** 그래서 모를
  /// 때는 막지 않고 지나보낸다 — 다음 실행에 다시 기회가 온다.
  ///
  /// ⚠️ 이 판단은 이 파일이 이미 여러 번 한 것과 같다(광고 동의도 읽기에
  /// 실패하면 묻지 않는다).
  bool? _phoneVerified;
  String? _phoneCheckedForUid;

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
        // 🚨 사진 백업 장부도 비운다 (추가 518).
        //
        // 이 장부는 **앞 계정이 무엇을 백업했는지**를 기록한다. 안 비우면
        // 새 계정 설정 화면에 **앞 사람 숫자가 그대로 뜬다** —
        // `CardPhotoBackupStateService.clear()` 주석이 정확히 그 경우를
        // 위해 만들어졌다고 적고 있는데, **부르는 곳이 0건이었다**(추가 79와
        // 같은 모양).
        //
        // ⚠️ 위 주석대로 **기기의 사진 파일 자체는 여기서 안 지운다.** 그건
        //    개인정보 최소화와 데이터 보전이 부딪히는 별개 판단이고,
        //    사진 서버 백업이 켜진 지금 다시 봐야 한다(아래 ⚠️ 참고).
        await CardPhotoBackupStateService().clear();
        // 「교체」는 로컬을 이 계정 것으로 갈아 끼운다 — 넘어온 명함 표시가
        // 남으면 **자기 명함을 서버에 안 올리게 된다**(추가 556).
        await CarriedOverContactsService().clear();
        await contactsRepo.forceRestoreFromServer(uid);
        await profileRepo.forceRestoreFromServer(uid);
        await groupsRepo.forceRestoreFromServer(uid);
      } else {
        // 🚨 "유지"를 골랐다 — 이 명함들의 사진은 **이 계정으로 올리지
        //    않는다.** 그런데 장부에는 앞 계정이 남긴 「백업됨」이 그대로
        //    남아 있다(같은 기기, 같은 contactId). 그래서 설정 화면이
        //    **한 장도 안 올라간 명함을 「백업됨」이라고 말한다.**
        //
        // ✅ 실물(2026-08-28, 추가 555): 아이폰 장부 130장 · 새 계정 서버
        //    0장이었고, 그 130은 **앞 계정 서버의 사진 수와 정확히 같았다.**
        //    기기에 기록된 계정 전환 이력도 `choice: keep` 두 건이었다.
        //
        // ⚠️ **처음에는 "장부를 비워 다시 올리게 하자"고 했는데 그것이
        //    틀렸다.** 명함 본문을 일부러 안 올리는 자리에서 사진만 올리는
        //    꼴이 되고(바로 아래 주석), 사진에도 이름·전화·회사가 인쇄돼
        //    있으니 실질은 같은 개인정보다. 게다가 **암호화 키가 계정마다
        //    달라** 새 계정은 그 파일을 열지도 못한다 — 못 여는 개인정보만
        //    한 벌 더 쌓인다.
        //
        // 📌 그래서 **올리는 쪽이 아니라 말하는 쪽을 고친다.** 여기서는
        //    장부만 사실에 맞게 적고, 서버는 부르지 않는다.
        await CardPhotoBackupStateService().markCarriedOverAll(
          contactsRepo.contacts.map((c) => c.id),
        );
        // 🚨 **본문도 같이 표시한다**(추가 556). 위 사진 장부만으로는
        //    부족했다 — 명함 본문은 다음 로그인의 `syncWithServer`가
        //    올려 버렸고, 그 함수는 사진 장부를 보지 않는다.
        await CarriedOverContactsService().markAll(
          contactsRepo.contacts.map((c) => c.id),
        );
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
    // 🚨 **휴대전화번호 확인이 끝나기 전에는 묻지 않는다**(추가 560의 순서).
    //
    // 이 함수는 `_syncUidAndRestore`의 postFrameCallback에서 불리는데, 그
    // 경로는 게이트와 무관하게 돈다. 막지 않으면 **인증 화면 위로 동의
    // 시트가 얹힌다** — 실기기에서 실제로 그랬다(추가 573).
    //
    // ⚠️ 건너뛰는 것이지 없애는 것이 아니다. 인증을 마치면 다음 로그인에
    // 다시 기회가 온다 — 이 파일이 이미 여러 번 하는 판단이다.
    if (_phoneVerified != true) return;

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
          // 🚨 **답을 내면 성공이든 실패든 닫는다.** 여기서 머물면 앱에 들어갈
          //    길이 없다 — 이 자리에서 두 번 겪었다(저장 실패 → 제자리,
          //    고친 뒤에는 저장 성공 → 그래도 제자리).
          //    `AdConsentView.dismissOnSubmit` 주석 참고.
          dismissOnSubmit: true,
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

    // 🚨 **뒤로가기로 빠져나가면 화면이 아무 말도 안 했다**(2026-08-30,
    //    globe2030님 실기기 제보).
    //
    // 이 화면에서 나가는 길은 둘인데 **하나만 화면에 있었다.**
    //
    // ```
    // 화면에 있는 길   아무것도 안 고르고 「시작하기」  →  「거부」로 답이 기록된다
    // 화면에 없는 길   뒤로가기                      →  답 없이 넘어간다 · 안내 없음
    // ```
    //
    // ⭐ **저장은 `onSubmit` 에서만 일어나므로 동의로 기록되지는 않는다.**
    //    그런데 **이용자 눈에는 동의로 보인다** — 동의 화면이 사라지고 앱이
    //    열리는데 아무 말이 없으면 「동의됐다」로 읽는다.
    //
    // 📌 **이 저장소가 반복해서 겪은 모양이다** — 로직은 맞는데 화면이 틀린
    //    것(CLAUDE.md 4절 F-10·F-15). 자동 테스트는 규칙을 보고 사람은 화면을
    //    본다.
    //
    // ⚠️ **뒤로가기를 막지 않는다.** 광고 수신 동의는 선택이고(시행령
    //    §17①1호), 못 나가게 만들면 그 동의는 「자유로운 동의」가 아니게 된다.
    //    이 저장소는 휴대폰 인증에서 `PopScope` 로 막았다가 **앱에 갇히는**
    //    사고를 낼 뻔했다(추가 573). **막는 대신 말한다.**
    //
    // ⚠️ **「거부」로 저장하지도 않는다.** 답한 적이 없는데 답했다고 적는 것은
    //    사실과 다르고, 실수로 뒤로 누른 사람에게 다시 물을 기회가 사라진다.
    if (!saved) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '광고 수신에 동의하지 않은 상태로 시작합니다. '
            '설정에서 언제든 바꾸실 수 있어요.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    if (!context.mounted) return;

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
    final uid = auth.firebaseUid;
    _syncUidAndRestore(context, uid);

    // 휴대전화번호 확인(추가 565). SNS 로그인 **뒤**, 광고 동의 **앞**이다
    // (docs/planning/specs/account-device-policy-2026-08-28.md).
    //
    // 🚨 건너뛰기가 없으므로 **여기서 막는다.** 광고 동의처럼 push했다
    // 사라지는 방식이면 뒤로가기 한 번으로 뚫린다.
    if (uid != null) {
      if (_phoneCheckedForUid != uid) {
        _phoneCheckedForUid = uid;
        _phoneVerified = null;
        // 🚨 **스위치를 먼저 본다.** 꺼져 있으면 인증 여부를 볼 필요도 없다.
        //
        // 이 순서가 중요하다 — 스위치가 꺼져 있는데 `phoneVerifiedAt`을 먼저
        // 읽어 `false`로 두면, 나중에 누가 스위치 검사를 빼먹었을 때 곧바로
        // 사람이 갇힌다. **꺼져 있으면 `true`로 둬서 「막을 이유가 없음」을
        // 명시한다.**
        () async {
          final enabled = await PhoneVerificationService.isGateEnabled();
          if (!mounted || _phoneCheckedForUid != uid) return;
          if (!enabled) {
            setState(() => _phoneVerified = true);
            return;
          }
          final v = await PhoneVerificationService.isVerified(uid);
          if (!mounted || _phoneCheckedForUid != uid) return;
          setState(() => _phoneVerified = v);
        }();
      }
      if (_phoneVerified == false) {
        return PhoneVerifyView(
          onVerified: () {
            if (!mounted) return;
            setState(() => _phoneVerified = true);
          },
        );
      }
      // 🚨 **판정이 끝나기 전에는 앱 본체를 만들지 않는다.**
      //
      // 실기기에서 잡은 것이다(추가 573). 판정 중(`null`)에 `widget.child`를
      // 만들었더니 **본체가 뜨면서 자기 시트들을 띄웠고**, 그 뒤에 인증
      // 화면이 그려져 **광고 동의와 위치 안내가 인증 화면 위에 얹혔다.**
      //
      // 확정 순서(추가 560)는 인증이 광고 동의 **앞**인데, 화면에서는
      // 광고 동의가 먼저 보였다. `auth.isLoading`을 빈 화면으로 두는 것과
      // 같은 이유로 여기도 기다린다.
      if (_phoneVerified == null) {
        return const Scaffold(backgroundColor: AppColors.bgBase);
      }
    }

    return widget.child;
  }
}

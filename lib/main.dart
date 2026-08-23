import 'dart:async';
import 'dart:io' show Directory;
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'core/app_version.dart';
import 'core/services/app_check_service.dart';
import 'core/services/fresh_install_service.dart';
import 'core/utils/scan_temp_cleanup.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/contacts_repository.dart';
import 'data/repositories/groups_repository.dart';
import 'data/repositories/my_profile_repository.dart';
import 'presentation/common/auth_gate.dart';
import 'presentation/common/splash_gate.dart';
import 'presentation/common/version_gate.dart';
import 'presentation/features/radar/view_models/radar_view_model.dart';
import 'presentation/features/wallet/view_models/groups_view_model.dart';
import 'presentation/features/wallet/view_models/wallet_view_model.dart';
import 'presentation/navigation/main_tab_screen.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  // 명함/프로필 서버 백업·복원(backlog 추가 66)의 기반 — Firebase Auth로
  // 로그인 사용자를 식별하고 Cloud Firestore에 데이터를 백업한다.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // 실사용자 크래시를 Crashlytics로 모은다(P1-13). 지금까지는 크래시가 나도
  // 아무 데도 안 남아, 테스터 피드백이 "가끔 죽어요"에서 멈췄다. Flutter
  // 프레임워크 예외(FlutterError)와 그 바깥의 비동기/플랫폼 예외
  // (PlatformDispatcher) 둘 다 잡는다.
  //
  // 디버그 빌드에서는 걸지 않는다 — 개발 중 예외는 콘솔에 그대로 찍히는 게
  // 낫고, 개발용 예외까지 리포트에 쌓이면 노이즈가 된다. 개인정보 원칙상
  // 크래시 스택에 개인정보를 남기지 않는다(로그에 이름·전화 등을 찍지 않는
  // 기존 원칙이 그대로 스택 안전성으로 이어진다).
  if (!kDebugMode) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }
  // AI 브리핑 서버 프록시가 회사 명의 유료 Gemini 키를 쓰므로, 호출이 진짜
  // 우리 앱에서 온 것인지 증명하는 토큰을 받아 둔다(backlog 추가 82).
  //
  // ⚠️ **기다리지 않는다.** 2026-08-08에 이걸 `await`로 걸어뒀다가 실기기에서
  // 앱이 통째로 안 뜨는 사고가 났다 — 디버그 토큰이 Firebase 등록분과
  // 달라지자 토큰 교환이 끝없이 재시도됐고, 예외가 아니라 "응답 없음"이라
  // try/catch로도 못 잡았다. runApp()에 도달하지 못해 UI가 하나도 없는
  // 네이티브 스플래시만 영원히 떠 있었다(사용자 눈에는 무한 로딩).
  //
  // App Check 토큰은 AI 브리핑을 부를 때 필요하지 앱을 켜는 데 필요하지
  // 않다. 시작 경로에서 떼어내는 것이 맞다.
  unawaited(AppCheckService.activate());
  // iOS Keychain은 앱을 삭제해도 지워지지 않아, 재설치하면 이전 로그인
  // 세션과 암호화 키가 되살아난다(backlog 추가 78). 저장소를 읽는 리포지토리
  // 들이 생성되기 전에 정리해야 하므로 runApp보다 먼저 호출한다.
  await FreshInstallService.purgeIfReinstalled();
  // 촬영·선택이 남긴 **평문 임시 파일**을 쓸어 담는다(2026-08-16, 추가 243).
  //
  // 지우는 자리는 각 화면에 이미 있지만(#222), 앱이 중간에 죽거나 예상 못 한
  // 경로로 빠지면 남는다. 쓸어담기가 **카메라 화면 진입 때만** 돌고 있어서
  // 갤러리로만 넣는 사용자는 한 번도 돌지 않았다 — 앱 시작에 두면 경로와
  // 무관하게 돈다.
  //
  // ⚠️ **기다리지 않는다.** 정리는 앱을 켜는 데 필요한 일이 아니고, 이 시작
  // 경로에 `await`를 더 얹었다가 앱이 통째로 안 뜬 전례가 있다(위 App Check).
  // 1시간이 지난 것만 지우므로 지금 쓰는 파일을 건드릴 일도 없다.
  unawaited(sweepScanTemp(Directory.systemTemp));
  // 그리고 **이미 쌓여 있던 것**을 걷어낸다(추가 248). 위 정리는 `code_cache`를
  // 보는데, 촬영 원본(`CAP*.jpg`)과 갤러리 사본(`<UUID>/사진`)은 **`cache`**에
  // 있다 — 다른 폴더다. 실기기에서 촬영 원본만 83장·198.5MB였다.
  unawaited(_sweepAccumulatedScanCache());
  _registerBundledFontLicense();
  // 설정 화면에 지금 실행 중인 빌드를 표시하기 위해 미리 읽어 둔다
  // (backlog 추가 77 — 낡은 빌드를 버그로 오인한 전례).
  await AppVersion.initialize();
  runApp(const ConnectionTraceApp());
}

/// 앱 캐시에 쌓인 **평문 촬영 원본·갤러리 사본**을 걷어낸다(추가 248).
///
/// 경로를 얻는 것부터 실패할 수 있어(플랫폼·초기화 시점) 따로 감싼다. 정리는
/// 앱을 켜는 데 필요한 일이 아니므로 **실패해도 조용히 넘긴다** — 다음 실행에서
/// 다시 시도한다.
Future<void> _sweepAccumulatedScanCache() async {
  // ⚠️ **폴더를 둘 다 훑는다** (2026-08-17).
  //
  // 원래는 `getTemporaryDirectory()` 하나만 봤다. 그런데 실기기(아이폰)에서
  // **59장·262.7MB가 그대로 남아 있었다** — 같은 실행에서 `sweepScanTemp(
  // Directory.systemTemp)`는 파일을 지웠는데 이쪽만 아무것도 못 지웠다.
  //
  // | | 안드로이드 | 아이폰 |
  // |---|---|---|
  // | `Directory.systemTemp` | `code_cache` | `<컨테이너>/tmp` |
  // | `getTemporaryDirectory()` | `cache` | `<컨테이너>/tmp` |
  //
  // 안드로이드에서는 **다른 폴더**라 둘 다 봐야 하고, 아이폰에서는 같은
  // 폴더라 한 번만 돌면 된다. **둘 다 넘기고 같으면 한 번만 돈다.**
  //
  // ⚠️ `getTemporaryDirectory()`는 플러그인을 거치므로 **실패할 수 있다.**
  // 그때 예전 코드는 조용히 아무것도 안 했다 — 그러면 정리가 통째로 멈추는데
  // **화면상으로는 아무 표시가 없다.** `Directory.systemTemp`는 플러그인 없이
  // 얻으므로 그 경우에도 남는다.
  final seen = <String>{};
  for (final dir in <Directory?>[
    Directory.systemTemp,
    await _temporaryDirectoryOrNull(),
  ]) {
    if (dir == null || !seen.add(dir.path)) continue;
    try {
      await sweepPickerAndCameraLeftovers(dir);
    } catch (_) {
      // 한 폴더가 실패해도 나머지는 계속 본다.
    }
  }
}

/// 플러그인으로 얻는 임시 폴더. 실패하면 null.
Future<Directory?> _temporaryDirectoryOrNull() async {
  try {
    return await getTemporaryDirectory();
  } catch (_) {
    return null;
  }
}

/// 앱에 번들한 Pretendard 폰트의 라이선스를 "오픈소스 라이선스" 화면에
/// 함께 표시되게 등록한다.
///
/// SIL Open Font License 1.1은 폰트를 재배포할 때 라이선스 원문과 저작권
/// 고지를 함께 제공하도록 요구한다. pub 패키지들의 라이선스는 Flutter가
/// 자동으로 모아주지만, 우리가 직접 넣은 에셋은 그 대상이 아니라서 이렇게
/// 직접 등록해야 화면에 나온다.
void _registerBundledFontLicense() {
  LicenseRegistry.addLicense(() async* {
    try {
      final text = await rootBundle.loadString('assets/fonts/OFL.txt');
      yield LicenseEntryWithLineBreaks(const ['Pretendard'], text);
    } catch (e) {
      debugPrint('폰트 라이선스 등록 실패: $e');
    }
  });
}

class ConnectionTraceApp extends StatelessWidget {
  const ConnectionTraceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ContactsRepository()),
        ChangeNotifierProvider(create: (_) => MyProfileRepository()),
        // 명함 그룹(추가 427) — 그룹 목록 자체는 ContactsRepository와 별개
        // 저장소다(users/{uid} 문서의 다른 필드). AuthGate가 로그인 시점에
        // 프로필과 같은 방식으로 uid를 알리고 서버와 동기화한다.
        ChangeNotifierProvider(create: (_) => GroupsRepository()),
        ChangeNotifierProvider(create: (_) => AuthRepository()),
        ChangeNotifierProxyProvider<ContactsRepository, RadarViewModel>(
          create: (ctx) => RadarViewModel(
            contactsRepository: ctx.read<ContactsRepository>(),
          ),
          update: (ctx, repo, prev) =>
              prev ?? RadarViewModel(contactsRepository: repo),
        ),
        ChangeNotifierProxyProvider<ContactsRepository, WalletViewModel>(
          create: (ctx) => WalletViewModel(
            contactsRepository: ctx.read<ContactsRepository>(),
          ),
          update: (ctx, repo, prev) =>
              prev ?? WalletViewModel(contactsRepository: repo),
        ),
        ChangeNotifierProxyProvider2<
          ContactsRepository,
          GroupsRepository,
          GroupsViewModel
        >(
          create: (ctx) => GroupsViewModel(
            groupsRepository: ctx.read<GroupsRepository>(),
            contactsRepository: ctx.read<ContactsRepository>(),
          ),
          update: (ctx, contactsRepo, groupsRepo, prev) =>
              prev ??
              GroupsViewModel(
                groupsRepository: groupsRepo,
                contactsRepository: contactsRepo,
              ),
        ),
      ],
      child: MaterialApp(
        title: '커넥션센스',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        // 스플래시 뒤, 로그인 이전에 버전을 확인한다(P1-45) — 강제 업데이트면
        // 로그인·본 화면으로 들어가기 전에 막아야 하기 때문.
        home: const SplashGate(
          child: VersionGate(child: AuthGate(child: MainTabScreen())),
        ),
      ),
    );
  }
}

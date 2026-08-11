import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'core/app_version.dart';
import 'core/services/app_check_service.dart';
import 'core/services/fresh_install_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/contacts_repository.dart';
import 'data/repositories/my_profile_repository.dart';
import 'presentation/common/auth_gate.dart';
import 'presentation/common/splash_gate.dart';
import 'presentation/common/version_gate.dart';
import 'presentation/features/radar/view_models/radar_view_model.dart';
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
  _registerBundledFontLicense();
  // 설정 화면에 지금 실행 중인 빌드를 표시하기 위해 미리 읽어 둔다
  // (backlog 추가 77 — 낡은 빌드를 버그로 오인한 전례).
  await AppVersion.initialize();
  runApp(const ConnectionTraceApp());
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

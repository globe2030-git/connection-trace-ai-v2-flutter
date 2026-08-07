import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'core/app_version.dart';
import 'core/services/fresh_install_service.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/contacts_repository.dart';
import 'data/repositories/my_profile_repository.dart';
import 'presentation/common/auth_gate.dart';
import 'presentation/common/splash_gate.dart';
import 'presentation/features/radar/view_models/radar_view_model.dart';
import 'presentation/features/wallet/view_models/wallet_view_model.dart';
import 'presentation/navigation/main_tab_screen.dart';

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  // 명함/프로필 서버 백업·복원(backlog 추가 66)의 기반 — Firebase Auth로
  // 로그인 사용자를 식별하고 Cloud Firestore에 데이터를 백업한다.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
        home: const SplashGate(child: AuthGate(child: MainTabScreen())),
      ),
    );
  }
}

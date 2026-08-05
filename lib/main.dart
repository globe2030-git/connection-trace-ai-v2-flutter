import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
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
  runApp(const ConnectionTraceApp());
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

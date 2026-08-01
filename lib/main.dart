import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/contacts_repository.dart';
import 'presentation/common/splash_gate.dart';
import 'presentation/features/radar/view_models/radar_view_model.dart';
import 'presentation/features/wallet/view_models/wallet_view_model.dart';
import 'presentation/navigation/main_tab_screen.dart';

void main() {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const ConnectionTraceApp());
}

class ConnectionTraceApp extends StatelessWidget {
  const ConnectionTraceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ContactsRepository()),
        ChangeNotifierProxyProvider<ContactsRepository, RadarViewModel>(
          create: (ctx) => RadarViewModel(
            contactsRepository: ctx.read<ContactsRepository>(),
          ),
          update: (ctx, repo, prev) => prev ?? RadarViewModel(contactsRepository: repo),
        ),
        ChangeNotifierProxyProvider<ContactsRepository, WalletViewModel>(
          create: (ctx) => WalletViewModel(
            contactsRepository: ctx.read<ContactsRepository>(),
          ),
          update: (ctx, repo, prev) => prev ?? WalletViewModel(contactsRepository: repo),
        ),
      ],
      child: MaterialApp(
        title: 'Connection Trace AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const SplashGate(child: MainTabScreen()),
      ),
    );
  }
}

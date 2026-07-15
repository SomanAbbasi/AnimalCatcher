import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'services/audio_manager.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'state/session_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Supabase only when public credentials are provided (via
  // --dart-define). Otherwise the app runs in a fully explorable offline mode.
  if (AppConfig.supabaseEnabled) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // The public publishable/anon key is safe to ship in the client.
      // ignore: deprecated_member_use
      anonKey: AppConfig.supabaseAnonKey,
    );
  }

  runApp(const FaunaBattlerApp());
}

class FaunaBattlerApp extends StatelessWidget {
  const FaunaBattlerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SessionProvider()..bootstrap(),
        ),
        ChangeNotifierProvider(create: (_) => AudioManager()),
      ],
      child: MaterialApp(
        title: 'FAUNA BATTLER AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const _RootGate(),
      ),
    );
  }
}

/// Chooses between onboarding/login and the home hub based on session state.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    if (session.initializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.neonGreen),
        ),
      );
    }

    // Start the lobby ambience once we know where the player is headed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AudioManager>().playBgm(Bgm.lobby);
    });

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: session.isLoggedIn ? const MainShell() : const LoginScreen(),
    );
  }
}

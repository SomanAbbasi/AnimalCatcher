// Basic smoke test for FAUNA BATTLER AI.
//
// Boots the app and confirms it reaches the onboarding lore screen. The app
// starts signed-out in offline mode (no Supabase dart-defines in tests), so the
// first lore slide should appear once session bootstrap completes.
//
// In the headless test environment the platform plugins (secure storage, audio,
// vibration) are not registered, so we install lightweight mock channel
// handlers on the binding's messenger to let SessionProvider.bootstrap()
// finish deterministically.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animal_catcher/main.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  setUp(() {
    // Secure storage: report no stored session.
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        return null;
      },
    );
    // Audioplayers + vibration: no-op so startup BGM/haptics don't error.
    for (final name in const [
      'xyz.luan.audioplayers.global/methods',
      'xyz.luan.audioplayers/methods',
      'vibration',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('App boots to onboarding lore screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FaunaBattlerApp());

    // Let SessionProvider.bootstrap() resolve and the root gate settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('THE RIFT IS OPEN'), findsOneWidget);
  });
}

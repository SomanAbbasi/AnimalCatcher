import 'package:animal_catcher/models/catalog_entry.dart';
import 'package:animal_catcher/models/fauna_card_model.dart';
import 'package:animal_catcher/models/profile_model.dart';
import 'package:animal_catcher/screens/achievements_screen.dart';
import 'package:animal_catcher/screens/collection_screen.dart';
import 'package:animal_catcher/state/session_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        return null;
      },
    );
  });

  SessionProvider seededSession() {
    final session = SessionProvider();
    session.debugSeed(
      profile: const PlayerProfile(
        userId: 'test-user',
        username: 'Tester',
        xp: 50,
        level: 1,
      ),
      catalog: const [
        CatalogEntry(
          taxonId: 1,
          dexNumber: 1,
          name: 'Domestic Cat',
          scientificName: 'Felis catus',
          category: 'Mammal',
          rarity: Rarity.common,
        ),
        CatalogEntry(
          taxonId: 2,
          dexNumber: 2,
          name: 'Rock Pigeon',
          scientificName: 'Columba livia',
          category: 'Bird',
          rarity: Rarity.common,
        ),
        CatalogEntry(
          taxonId: 3,
          dexNumber: 3,
          name: 'Tiger',
          scientificName: 'Panthera tigris',
          category: 'Mammal',
          rarity: Rarity.legendary,
        ),
      ],
      collection: const [
        FaunaCard(
          name: 'Domestic Cat',
          rarity: Rarity.common,
          taxonId: 1,
          category: 'Mammal',
        ),
      ],
    );
    return session;
  }

  Widget wrap(Widget child, SessionProvider session) {
    return ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(home: child),
    );
  }

  Future<void> setTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Awards screen', () {
    testWidgets('shows summary and filters unlocked vs in progress',
        (tester) async {
      await setTallSurface(tester);
      final session = seededSession();
      await tester.pumpWidget(wrap(const AchievementsScreen(), session));
      await tester.pumpAndSettle();

      expect(find.text('Awards'), findsOneWidget);
      expect(find.textContaining('unlocked'), findsOneWidget);
      expect(find.text('First Catch'), findsOneWidget);

      await tester.tap(find.text('Unlocked'));
      await tester.pumpAndSettle();
      expect(find.text('First Catch'), findsOneWidget);
      expect(find.text('Getting Started'), findsNothing);

      await tester.tap(find.text('In progress'));
      await tester.pumpAndSettle();
      expect(find.text('First Catch'), findsNothing);
      expect(find.text('Getting Started'), findsOneWidget);
    });
  });

  group('Collection screen', () {
    testWidgets('search keeps locked names secret', (tester) async {
      await setTallSurface(tester);
      final session = seededSession();
      await tester.pumpWidget(wrap(const CollectionScreen(), session));
      await tester.pumpAndSettle();

      expect(find.text('???'), findsWidgets);
      expect(
        find.descendant(of: find.byType(GridView), matching: find.text('Tiger')),
        findsNothing,
      );
      expect(find.text('Domestic Cat'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Tiger');
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(GridView), matching: find.text('Tiger')),
        findsNothing,
      );
      expect(find.text('No species match your filters.'), findsOneWidget);

      await tester.tap(find.text('CLEAR FILTERS'));
      await tester.pumpAndSettle();
      expect(find.text('Domestic Cat'), findsOneWidget);
    });

    testWidgets('category progress filters the grid', (tester) async {
      await setTallSurface(tester);
      final session = seededSession();
      await tester.pumpWidget(wrap(const CollectionScreen(), session));
      await tester.pumpAndSettle();

      expect(find.text('Domestic Cat'), findsOneWidget);
      await tester.tap(find.text('Bird').first);
      await tester.pumpAndSettle();
      expect(find.text('Domestic Cat'), findsNothing);
      expect(find.text('???'), findsOneWidget);
    });

    testWidgets('sort menu exposes rarity option', (tester) async {
      tester.view.physicalSize = const Size(480, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = seededSession();
      await tester.pumpWidget(wrap(const CollectionScreen(), session));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byTooltip('Sort'));
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      expect(find.text('Rarity'), findsOneWidget);
      await tester.tap(find.text('Rarity').last);
      await tester.pumpAndSettle();
      expect(find.text('Sort: Rarity'), findsOneWidget);
    });

    testWidgets('name sort does not leak locked species order', (tester) async {
      await setTallSurface(tester);
      // Catalog deliberately ordered so alphabetical name order differs from
      // dex order: Zebra (#1 locked), Ant (#2 locked), Cat (#3 caught).
      final session = SessionProvider();
      session.debugSeed(
        profile: const PlayerProfile(
          userId: 'test-user',
          username: 'Tester',
        ),
        catalog: const [
          CatalogEntry(
            taxonId: 10,
            dexNumber: 1,
            name: 'Zebra',
            category: 'Mammal',
          ),
          CatalogEntry(
            taxonId: 20,
            dexNumber: 2,
            name: 'Ant',
            category: 'Insect',
          ),
          CatalogEntry(
            taxonId: 30,
            dexNumber: 3,
            name: 'Cat',
            category: 'Mammal',
          ),
        ],
        collection: const [
          FaunaCard(name: 'Cat', rarity: Rarity.common, taxonId: 30),
        ],
      );

      await tester.pumpWidget(wrap(const CollectionScreen(), session));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byTooltip('Sort'));
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name').last);
      await tester.pumpAndSettle();
      expect(find.text('Sort: Name'), findsOneWidget);

      // Caught "Cat" comes first (alphabetical among caught). Locked tiles
      // stay in dex order (#001 Zebra, #002 Ant) — never Ant-before-Zebra
      // which would leak that Ant sorts before Zebra by real name.
      final labels = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(GridView),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .whereType<String>()
          .toList();

      final catIdx = labels.indexOf('Cat');
      final firstMystery = labels.indexOf('???');
      final secondMystery = labels.indexOf('???', firstMystery + 1);
      expect(catIdx, greaterThanOrEqualTo(0));
      expect(firstMystery, greaterThan(catIdx));
      expect(secondMystery, greaterThan(firstMystery));

      // Dex numbers of the two locked tiles must appear in ascending order.
      final dexOne = labels.indexOf('#001');
      final dexTwo = labels.indexOf('#002');
      expect(dexOne, lessThan(dexTwo));
    });

    testWidgets('locked hint offers Scan when onOpenScan is set',
        (tester) async {
      await setTallSurface(tester);
      final session = seededSession();
      var scanned = false;
      await tester.pumpWidget(
        wrap(
          CollectionScreen(onOpenScan: () => scanned = true),
          session,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('???').first);
      await tester.tap(find.text('???').first);
      await tester.pumpAndSettle();
      expect(find.text('Not yet discovered'), findsOneWidget);
      expect(find.text('SCAN'), findsOneWidget);

      await tester.tap(find.text('SCAN'));
      await tester.pumpAndSettle();
      expect(scanned, isTrue);
    });
  });
}

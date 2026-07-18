import 'package:animal_catcher/models/catalog_entry.dart';
import 'package:animal_catcher/models/fauna_card_model.dart';
import 'package:animal_catcher/models/profile_model.dart';
import 'package:animal_catcher/state/session_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Guest dex unlock', () {
    test('stamps taxonId from catalog when card lacks one', () {
      final session = SessionProvider();
      session.debugSeed(
        profile: const PlayerProfile(
          userId: 'guest',
          username: 'Guest',
        ),
        catalog: const [
          CatalogEntry(
            taxonId: 41944,
            dexNumber: 1,
            name: 'Domestic Cat',
            category: 'Mammal',
          ),
          CatalogEntry(
            taxonId: 42069,
            dexNumber: 2,
            name: 'Red Fox',
            category: 'Mammal',
          ),
        ],
      );

      // Simulate an offline / seed card with no taxon id.
      session.addToCollection(
        const FaunaCard(name: 'Domestic Cat', rarity: Rarity.common),
      );

      expect(session.caughtTaxonIds, contains(41944));
      expect(session.isCaughtTaxon(41944), isTrue);
      expect(session.cardForTaxon(41944)?.name, 'Domestic Cat');
      expect(session.collection.single.taxonId, 41944);
      expect(session.dexProgress.caught, 1);
    });

    test('cardForTaxon matches name when taxonId was never stamped', () {
      final session = SessionProvider();
      session.debugSeed(
        profile: const PlayerProfile(
          userId: 'guest',
          username: 'Guest',
        ),
        catalog: const [
          CatalogEntry(
            taxonId: 7,
            dexNumber: 7,
            name: 'Koala',
            category: 'Mammal',
          ),
        ],
        // Collection already seeded without taxonId (legacy guest path).
        collection: const [
          FaunaCard(name: 'Koala', rarity: Rarity.rare),
        ],
      );

      expect(session.caughtTaxonIds, contains(7));
      expect(session.cardForTaxon(7)?.name, 'Koala');
      expect(session.dexProgress.caught, 1);
    });
  });
}

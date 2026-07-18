import 'package:animal_catcher/models/catalog_entry.dart';
import 'package:animal_catcher/models/dex_progress.dart';
import 'package:animal_catcher/models/fauna_card_model.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogEntry _entry({
  required int taxonId,
  required int dex,
  required String name,
  required String category,
  Rarity rarity = Rarity.common,
}) {
  return CatalogEntry(
    taxonId: taxonId,
    dexNumber: dex,
    name: name,
    category: category,
    rarity: rarity,
  );
}

void main() {
  group('DexProgress', () {
    test('aggregates overall and per-category counts', () {
      final catalog = [
        _entry(taxonId: 1, dex: 1, name: 'Cat', category: 'Mammal'),
        _entry(taxonId: 2, dex: 2, name: 'Dog', category: 'Mammal'),
        _entry(taxonId: 3, dex: 3, name: 'Pigeon', category: 'Bird'),
        _entry(
          taxonId: 4,
          dex: 4,
          name: 'Tiger',
          category: 'Mammal',
          rarity: Rarity.legendary,
        ),
      ];
      final progress = DexProgress.from(
        catalog: catalog,
        caughtTaxonIds: {1, 4},
      );

      expect(progress.total, 4);
      expect(progress.caught, 2);
      expect(progress.caughtInCategory('Mammal'), 2);
      expect(progress.caughtInCategory('Bird'), 0);
      expect(progress.rarityCount(Rarity.legendary), 1);
      expect(progress.rarityCount(Rarity.common), 1);
    });

    test('normalizes category casing', () {
      expect(DexProgress.normalizeCategory('mammal'), 'Mammal');
      expect(DexProgress.normalizeCategory('BIRD'), 'Bird');
      expect(DexProgress.normalizeCategory('wildlife'), 'Wildlife');
    });

    test('canonicalCategoriesTouched ignores unknown Wildlife', () {
      final catalog = [
        _entry(taxonId: 1, dex: 1, name: 'Cat', category: 'Mammal'),
        _entry(taxonId: 2, dex: 2, name: 'Weird', category: 'Wildlife'),
        _entry(taxonId: 3, dex: 3, name: 'Bee', category: 'Insect'),
      ];
      final progress = DexProgress.from(
        catalog: catalog,
        caughtTaxonIds: {1, 2},
      );

      // Only Mammal counts toward the 8 seeded categories.
      expect(progress.canonicalCategoriesTouched, 1);
      expect(
        progress.presentCategories.map((c) => c.category).toList(),
        containsAll(['Mammal', 'Insect', 'Wildlife']),
      );
      // Canonical list still leads the ordered byCategory.
      expect(progress.byCategory.first.category, 'Mammal');
    });

    test('skips taxonId 0 and never double-counts', () {
      final catalog = [
        _entry(taxonId: 0, dex: 0, name: 'Bad', category: 'Mammal'),
        _entry(taxonId: 10, dex: 1, name: 'Fox', category: 'Mammal'),
      ];
      final progress = DexProgress.from(catalog: catalog, caughtTaxonIds: {10});
      expect(progress.total, 1);
      expect(progress.caught, 1);
    });

    test('presentCategories omits empty canonical slots', () {
      final catalog = [
        _entry(taxonId: 1, dex: 1, name: 'Cat', category: 'Mammal'),
      ];
      final progress = DexProgress.from(
        catalog: catalog,
        caughtTaxonIds: const {},
      );
      expect(progress.presentCategories.length, 1);
      expect(progress.presentCategories.single.category, 'Mammal');
      expect(progress.presentCategories.single.total, 1);
      expect(progress.presentCategories.single.caught, 0);
    });
  });
}

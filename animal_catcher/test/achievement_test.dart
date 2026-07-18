import 'package:animal_catcher/models/achievement.dart';
import 'package:animal_catcher/models/catalog_entry.dart';
import 'package:animal_catcher/models/dex_progress.dart';
import 'package:animal_catcher/models/fauna_card_model.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogEntry _e({
  required int id,
  required String cat,
  Rarity rarity = Rarity.common,
}) {
  return CatalogEntry(
    taxonId: id,
    dexNumber: id,
    name: 'Species $id',
    category: cat,
    rarity: rarity,
  );
}

void main() {
  group('Achievements', () {
    test('definitions have unique stable ids', () {
      final ids = buildAchievements().map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('first catch and species thresholds', () {
      final catalog = [for (var i = 1; i <= 12; i++) _e(id: i, cat: 'Mammal')];
      final progress = DexProgress.from(
        catalog: catalog,
        caughtTaxonIds: {1, 2, 3, 4, 5},
      );
      final ctx = AchievementContext(progress: progress, xp: 0, level: 1);
      final byId = {for (final a in buildAchievements()) a.id: a};

      expect(byId['first_catch']!.isUnlocked(ctx), isTrue);
      expect(byId['species_5']!.isUnlocked(ctx), isTrue);
      expect(byId['species_10']!.isUnlocked(ctx), isFalse);
      expect(byId['species_10']!.progress(ctx), 5);
    });

    test('level and xp milestones', () {
      final progress = DexProgress.from(
        catalog: const [],
        caughtTaxonIds: const {},
      );
      final ctx = AchievementContext(progress: progress, xp: 600, level: 6);
      final byId = {for (final a in buildAchievements()) a.id: a};

      expect(byId['level_5']!.isUnlocked(ctx), isTrue);
      expect(byId['level_10']!.isUnlocked(ctx), isFalse);
      expect(byId['xp_500']!.isUnlocked(ctx), isTrue);
      expect(byId['xp_1000']!.isUnlocked(ctx), isFalse);
    });

    test('rarity and all_categories use canonical set only', () {
      final catalog = [
        _e(id: 1, cat: 'Mammal', rarity: Rarity.uncommon),
        _e(id: 2, cat: 'Bird', rarity: Rarity.rare),
        _e(id: 3, cat: 'Fish'),
        _e(id: 4, cat: 'Insect'),
        _e(id: 5, cat: 'Reptile'),
        _e(id: 6, cat: 'Amphibian'),
        _e(id: 7, cat: 'Arachnid'),
        _e(id: 8, cat: 'Mollusk'),
        _e(id: 9, cat: 'Wildlife'),
        _e(id: 10, cat: 'Mammal', rarity: Rarity.legendary),
      ];
      // Catch all 8 seeded + wildlife, but miss legendary until we add it.
      final progress = DexProgress.from(
        catalog: catalog,
        caughtTaxonIds: {1, 2, 3, 4, 5, 6, 7, 8, 9},
      );
      final ctx = AchievementContext(progress: progress, xp: 0, level: 1);
      final byId = {for (final a in buildAchievements()) a.id: a};

      expect(byId['first_uncommon']!.isUnlocked(ctx), isTrue);
      expect(byId['first_rare']!.isUnlocked(ctx), isTrue);
      expect(byId['first_legendary']!.isUnlocked(ctx), isFalse);
      expect(byId['all_categories']!.isUnlocked(ctx), isTrue);
      expect(byId['all_categories']!.progress(ctx), 8);
    });

    test('progress clamps to target', () {
      final catalog = [for (var i = 1; i <= 20; i++) _e(id: i, cat: 'Mammal')];
      final progress = DexProgress.from(
        catalog: catalog,
        caughtTaxonIds: {for (var i = 1; i <= 20; i++) i},
      );
      final ctx = AchievementContext(progress: progress, xp: 0, level: 1);
      final first = buildAchievements().firstWhere(
        (a) => a.id == 'first_catch',
      );
      expect(first.progress(ctx), 1);
      expect(first.fraction(ctx), 1.0);
    });
  });
}

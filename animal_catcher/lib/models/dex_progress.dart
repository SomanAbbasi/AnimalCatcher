import 'catalog_entry.dart';
import 'fauna_card_model.dart';

/// The eight seeded dex categories. Open-dex entries outside this set are
/// still tracked, but "one of every category" awards only count these.
const List<String> kCanonicalCategories = [
  'Mammal',
  'Bird',
  'Fish',
  'Insect',
  'Reptile',
  'Amphibian',
  'Arachnid',
  'Mollusk',
];

/// Caught/total for one category (or overall).
class CategoryProgress {
  const CategoryProgress({
    required this.category,
    required this.caught,
    required this.total,
  });

  final String category;
  final int caught;
  final int total;

  bool get isComplete => total > 0 && caught >= total;

  double get fraction => total <= 0 ? 0 : (caught / total).clamp(0.0, 1.0);
}

/// Immutable one-pass snapshot of dex discovery state.
///
/// Built from the catalog + the player's caught taxon ids so Awards and
/// Collection never re-scan `catalog × collection` independently.
class DexProgress {
  const DexProgress({
    required this.total,
    required this.caught,
    required this.byCategory,
    required this.byRarity,
    required this.canonicalCategoriesTouched,
  });

  final int total;
  final int caught;

  /// Ordered: canonical categories first (even if total == 0), then any
  /// unknown open-dex categories sorted alphabetically.
  final List<CategoryProgress> byCategory;

  final Map<Rarity, int> byRarity;

  /// How many of the eight seeded categories have at least one catch.
  final int canonicalCategoriesTouched;

  double get fraction => total <= 0 ? 0 : (caught / total).clamp(0.0, 1.0);

  int rarityCount(Rarity rarity) => byRarity[rarity] ?? 0;

  int caughtInCategory(String category) {
    final key = normalizeCategory(category);
    for (final c in byCategory) {
      if (c.category == key) return c.caught;
    }
    return 0;
  }

  /// Normalize a free-text category to Title Case canonical form when known.
  static String normalizeCategory(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Wildlife';
    final lower = trimmed.toLowerCase();
    for (final c in kCanonicalCategories) {
      if (c.toLowerCase() == lower) return c;
    }
    // Title-case unknown categories for stable grouping.
    return trimmed[0].toUpperCase() +
        (trimmed.length > 1 ? trimmed.substring(1).toLowerCase() : '');
  }

  /// Build a snapshot from the master catalog and the player's caught taxon ids.
  ///
  /// Duplicate taxon ids in [caughtTaxonIds] are ignored (set semantics).
  /// Catalog entries with taxonId 0 are skipped.
  factory DexProgress.from({
    required List<CatalogEntry> catalog,
    required Set<int> caughtTaxonIds,
  }) {
    final totals = <String, int>{};
    final caught = <String, int>{};
    final rarityCaught = <Rarity, int>{for (final r in Rarity.values) r: 0};
    var overallCaught = 0;
    var overallTotal = 0;

    for (final entry in catalog) {
      if (entry.taxonId == 0) continue;
      overallTotal++;
      final cat = normalizeCategory(entry.category);
      totals[cat] = (totals[cat] ?? 0) + 1;

      if (caughtTaxonIds.contains(entry.taxonId)) {
        overallCaught++;
        caught[cat] = (caught[cat] ?? 0) + 1;
        rarityCaught[entry.rarity] = (rarityCaught[entry.rarity] ?? 0) + 1;
      }
    }

    final byCategory = <CategoryProgress>[];
    final seen = <String>{};

    for (final cat in kCanonicalCategories) {
      seen.add(cat);
      byCategory.add(
        CategoryProgress(
          category: cat,
          caught: caught[cat] ?? 0,
          total: totals[cat] ?? 0,
        ),
      );
    }

    final extras = totals.keys.where((k) => !seen.contains(k)).toList()..sort();
    for (final cat in extras) {
      byCategory.add(
        CategoryProgress(
          category: cat,
          caught: caught[cat] ?? 0,
          total: totals[cat] ?? 0,
        ),
      );
    }

    var touched = 0;
    for (final cat in kCanonicalCategories) {
      if ((caught[cat] ?? 0) > 0) touched++;
    }

    return DexProgress(
      total: overallTotal,
      caught: overallCaught,
      byCategory: byCategory,
      byRarity: rarityCaught,
      canonicalCategoriesTouched: touched,
    );
  }

  /// Categories that actually appear in the catalog (total > 0), for UI strips.
  List<CategoryProgress> get presentCategories =>
      byCategory.where((c) => c.total > 0).toList();
}

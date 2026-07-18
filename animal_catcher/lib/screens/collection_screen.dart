import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/catalog_entry.dart';
import '../models/dex_progress.dart';
import '../models/fauna_card_model.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/neon_button.dart';
import '../widgets/safe_network_image.dart';

enum DexFilter { all, caught, missing }

enum DexSort { dexNumber, rarity, name }

/// Collector directory driven by the shared species catalog.
/// Undiscovered species show as blurred "secret" tiles that unlock on scan.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, this.onOpenScan});

  /// When provided (shell mode), switch to the Scan tab from a locked hint.
  final VoidCallback? onOpenScan;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  DexFilter _filter = DexFilter.all;
  DexSort _sort = DexSort.dexNumber;
  String? _categoryFilter;
  final TextEditingController _search = TextEditingController();
  String _query = '';

  static const _rarityRank = {
    Rarity.legendary: 0,
    Rarity.rare: 1,
    Rarity.uncommon: 2,
    Rarity.common: 3,
  };

  bool get _hasActiveFilters =>
      _filter != DexFilter.all ||
      _categoryFilter != null ||
      _query.isNotEmpty ||
      _sort != DexSort.dexNumber;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _filter = DexFilter.all;
      _sort = DexSort.dexNumber;
      _categoryFilter = null;
      _query = '';
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final catalog = session.catalog;
    final caughtIds = session.caughtTaxonIds;
    final progress = session.dexProgress;
    final categoryStats = progress.presentCategories;

    final entries = _filteredSorted(catalog, caughtIds);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'My Collection',
                          style: AppTheme.heading(AppColors.accent, size: 26),
                        ),
                      ),
                      _filtersButton(catalog),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${progress.caught} caught / ${progress.total} species known',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (categoryStats.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _categoryProgressRow(categoryStats),
                  ],
                  const SizedBox(height: 12),
                  _searchField(),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chip('All', DexFilter.all),
                        _chip('Caught', DexFilter.caught),
                        _chip('Missing', DexFilter.missing),
                        const SizedBox(width: 4),
                        _sortMenu(),
                      ],
                    ),
                  ),
                  if (_categoryFilter != null) ...[
                    const SizedBox(height: 10),
                    _activeCategoryPill(),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(
              child: catalog.isEmpty
                  ? RefreshIndicator(
                      color: AppColors.accent,
                      backgroundColor: AppColors.surface,
                      onRefresh: () => session.loadCatalog(force: true),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text(
                              'Loading catalog...',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    )
                  : entries.isEmpty
                  ? RefreshIndicator(
                      color: AppColors.accent,
                      backgroundColor: AppColors.surface,
                      onRefresh: () => session.loadCatalog(force: true),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.45,
                            child: _emptyResults(),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.accent,
                      backgroundColor: AppColors.surface,
                      onRefresh: () => session.loadCatalog(force: true),
                      child: GridView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.74,
                            ),
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final entry = entries[i];
                          final owned = session.cardForTaxon(entry.taxonId);
                          return _SpeciesTile(
                            entry: entry,
                            owned: owned,
                            onTap: () {
                              if (owned != null) {
                                _openDetail(context, owned);
                              } else {
                                _openLockedHint(context, entry);
                              }
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<CatalogEntry> _filteredSorted(
    List<CatalogEntry> catalog,
    Set<int> caughtIds,
  ) {
    final q = _query.toLowerCase();
    final list = catalog.where((entry) {
      final caught = caughtIds.contains(entry.taxonId);
      if (_categoryFilter != null &&
          DexProgress.normalizeCategory(entry.category) != _categoryFilter) {
        return false;
      }
      if (q.isNotEmpty) {
        final dexPad = entry.dexNumber.toString().padLeft(3, '0');
        final dexMatch =
            '#${entry.dexNumber}'.contains(q) || dexPad.contains(q);
        if (!caught) {
          // Locked tiles: category + dex number only (name stays secret).
          final cat = entry.category.toLowerCase();
          if (!cat.contains(q) && !dexMatch) return false;
        } else {
          final hay = '${entry.name} ${entry.scientificName} ${entry.category}'
              .toLowerCase();
          if (!hay.contains(q) && !dexMatch) return false;
        }
      }
      switch (_filter) {
        case DexFilter.all:
          return true;
        case DexFilter.caught:
          return caught;
        case DexFilter.missing:
          return !caught;
      }
    }).toList();

    list.sort((a, b) {
      switch (_sort) {
        case DexSort.dexNumber:
          return a.dexNumber.compareTo(b.dexNumber);
        case DexSort.name:
          // Caught tiles sort alphabetically. Locked tiles stay in dex order
          // so the real hidden names never leak through sort position.
          final aCaught = caughtIds.contains(a.taxonId);
          final bCaught = caughtIds.contains(b.taxonId);
          if (aCaught && bCaught) {
            final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return cmp != 0 ? cmp : a.dexNumber.compareTo(b.dexNumber);
          }
          if (aCaught != bCaught) return aCaught ? -1 : 1;
          return a.dexNumber.compareTo(b.dexNumber);
        case DexSort.rarity:
          final ra = _rarityRank[a.rarity] ?? 99;
          final rb = _rarityRank[b.rarity] ?? 99;
          final cmp = ra.compareTo(rb);
          return cmp != 0 ? cmp : a.dexNumber.compareTo(b.dexNumber);
      }
    });
    return list;
  }

  Widget _emptyResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'No species match your filters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_hasActiveFilters) ...[
              const SizedBox(height: 16),
              NeonButton(
                label: 'Clear filters',
                icon: Icons.filter_alt_off_rounded,
                onPressed: _clearFilters,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _categoryProgressRow(List<CategoryProgress> stats) {
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: stats.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final s = stats[i];
            final selected = _categoryFilter == s.category;
            return GestureDetector(
              onTap: () => setState(() {
                _categoryFilter = selected ? null : s.category;
              }),
              child: Container(
                width: 112,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: selected
                      ? AppColors.accent.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: s.isComplete
                        ? AppColors.accent
                        : selected
                        ? AppColors.accent
                        : AppColors.textMuted.withValues(alpha: 0.35),
                    width: s.isComplete || selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _iconForCategory(s.category),
                          size: 12,
                          color: selected || s.isComplete
                              ? AppColors.accent
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            s.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected || s.isComplete
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        if (s.isComplete)
                          const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: AppColors.accent,
                          )
                        else
                          Text(
                            '${s.caught}/${s.total}',
                            style: TextStyle(
                              color: selected
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: s.fraction,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          selected || s.isComplete
                              ? AppColors.accent
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v.trim()),
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: 'Search species, category, #…',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textMuted,
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.textMuted.withValues(alpha: 0.35),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.textMuted.withValues(alpha: 0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }

  Widget _sortMenu() {
    final label = switch (_sort) {
      DexSort.dexNumber => 'Sort: #',
      DexSort.rarity => 'Sort: Rarity',
      DexSort.name => 'Sort: Name',
    };
    return PopupMenuButton<DexSort>(
      tooltip: 'Sort',
      initialValue: _sort,
      color: AppColors.surface,
      onSelected: (v) => setState(() => _sort = v),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: DexSort.dexNumber,
          child: Text(
            'Dex number',
            style: TextStyle(color: AppColors.textPrimary),
          ),
        ),
        const PopupMenuItem(
          value: DexSort.name,
          child: Text('Name', style: TextStyle(color: AppColors.textPrimary)),
        ),
        const PopupMenuItem(
          value: DexSort.rarity,
          child: Text('Rarity', style: TextStyle(color: AppColors.textPrimary)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: AppColors.textMuted),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sort_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtersButton(List<CatalogEntry> catalog) {
    return GestureDetector(
      onTap: () => _openCategorySheet(catalog),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.textMuted),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 16,
              color: _categoryFilter != null
                  ? AppColors.accent
                  : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              'Filters',
              style: TextStyle(
                color: _categoryFilter != null
                    ? AppColors.accent
                    : AppColors.textMuted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeCategoryPill() {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => setState(() => _categoryFilter = null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: AppColors.accent.withValues(alpha: 0.15),
            border: Border.all(color: AppColors.accent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _categoryFilter!,
                style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.close_rounded,
                size: 15,
                color: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openCategorySheet(List<CatalogEntry> catalog) {
    final categories =
        <String>{
          for (final e in catalog) DexProgress.normalizeCategory(e.category),
        }.toList()..sort((a, b) {
          final ia = kCanonicalCategories.indexOf(a);
          final ib = kCanonicalCategories.indexOf(b);
          if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
          if (ia >= 0) return -1;
          if (ib >= 0) return 1;
          return a.compareTo(b);
        });

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Filter by category', style: AppTheme.label),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.clear_all_rounded,
                  color: AppColors.accent,
                ),
                title: const Text(
                  'All categories',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                trailing: _categoryFilter == null
                    ? const Icon(Icons.check, color: AppColors.accent)
                    : null,
                onTap: () {
                  setState(() => _categoryFilter = null);
                  Navigator.pop(ctx);
                },
              ),
              for (final cat in categories)
                ListTile(
                  leading: Icon(_iconForCategory(cat), color: AppColors.accent),
                  title: Text(
                    cat,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  trailing: _categoryFilter == cat
                      ? const Icon(Icons.check, color: AppColors.accent)
                      : null,
                  onTap: () {
                    setState(() => _categoryFilter = cat);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, DexFilter value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: selected
                ? AppColors.accent
                : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.textMuted,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : AppColors.textMuted,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  void _openLockedHint(BuildContext context, CatalogEntry entry) {
    final rarityColor = AppColors.forRarity(entry.rarity);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Large mystery silhouette so the player can study the shape
                // of the animal they still need to find.
                if (entry.hasReferencePhoto)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          SpeciesSilhouette(url: entry.referencePhotoUrl),
                          Positioned(
                            top: 8,
                            right: 10,
                            child: Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.textMuted.withValues(alpha: 0.12),
                      border: Border.all(color: AppColors.textMuted),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 34,
                      color: AppColors.textMuted,
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  'Not yet discovered',
                  textAlign: TextAlign.center,
                  style: AppTheme.heading(AppColors.textPrimary, size: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  '#${entry.dexNumber.toString().padLeft(3, '0')}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _teaserChip(
                      icon: _iconForCategory(entry.category),
                      label: DexProgress.normalizeCategory(entry.category),
                      color: AppColors.accent,
                    ),
                    _teaserChip(
                      icon: Icons.star_outline_rounded,
                      label: entry.rarity.label,
                      color: rarityColor,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Scan this animal in the wild to unlock its tile.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                if (widget.onOpenScan != null) ...[
                  NeonButton(
                    label: 'Scan',
                    icon: Icons.camera_alt_rounded,
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onOpenScan!();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                NeonButton(
                  label: 'Got it',
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _teaserChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(BuildContext context, FaunaCard card) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.55,
          maxChildSize: 0.96,
          builder: (_, controller) {
            return GlassContainer(
              borderColor: card.rarityColor,
              borderRadius: 24,
              margin: const EdgeInsets.all(10),
              padding: EdgeInsets.zero,
              child: Stack(
                children: [
                  ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
                    children: [
                      Text('YOUR CAPTURE', style: AppTheme.label),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: _OwnPhoto(card: card),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        card.name,
                        textAlign: TextAlign.center,
                        style: AppTheme.heading(
                          AppColors.textPrimary,
                          size: 22,
                        ),
                      ),
                      if (card.scientificName.isNotEmpty)
                        Text(
                          card.scientificName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Center(child: _rarityTag(card)),
                      const SizedBox(height: 20),
                      Text('SPECIES REFERENCE', style: AppTheme.label),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: SafeNetworkImage(
                            url: card.referencePhotoUrl,
                            iconSize: 64,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(child: _categoryChip(card)),
                      if (card.lore.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          card.lore,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            height: 1.45,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      if (card.wikiUrl.isNotEmpty)
                        NeonButton(
                          label: 'Read on Wikipedia',
                          icon: Icons.open_in_new_rounded,
                          onPressed: () => _openWiki(card.wikiUrl),
                        ),
                      const SizedBox(height: 12),
                      NeonButton(
                        label: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openWiki(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _rarityTag(FaunaCard card) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: card.rarityColor, width: 1.5),
      ),
      child: Text(
        card.rarity.label.toUpperCase(),
        style: TextStyle(
          color: card.rarityColor,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _categoryChip(FaunaCard card) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(card.categoryIcon, size: 16, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(
            card.category.toUpperCase(),
            style: const TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconForCategory(String category) {
  switch (category.trim().toLowerCase()) {
    case 'mammal':
      return Icons.pets;
    case 'bird':
      return Icons.flutter_dash;
    case 'insect':
      return Icons.bug_report;
    case 'fish':
      return Icons.water;
    case 'reptile':
      return Icons.egg_alt;
    case 'amphibian':
      return Icons.water_drop;
    case 'mollusk':
      return Icons.set_meal;
    case 'arachnid':
      return Icons.bug_report;
    default:
      return Icons.pets;
  }
}

class _OwnPhoto extends StatelessWidget {
  const _OwnPhoto({required this.card});

  final FaunaCard card;

  @override
  Widget build(BuildContext context) {
    if (card.hasLocalPhoto) {
      return Image.file(
        File(card.photoPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (card.hasReferencePhoto) {
      return SafeNetworkImage(url: card.referencePhotoUrl, iconSize: 64);
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    color: AppColors.surfaceAlt,
    alignment: Alignment.center,
    child: const Icon(Icons.pets, size: 64, color: AppColors.textMuted),
  );
}

class _SpeciesTile extends StatelessWidget {
  const _SpeciesTile({
    required this.entry,
    required this.owned,
    required this.onTap,
  });

  final CatalogEntry entry;
  final FaunaCard? owned;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final caught = owned != null;
    final rarityColor = AppColors.forRarity(entry.rarity);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppColors.surface,
          border: Border.all(
            color: caught
                ? rarityColor
                : AppColors.textMuted.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (caught)
                    SafeNetworkImage(
                      url: owned!.hasReferencePhoto
                          ? owned!.referencePhotoUrl
                          : entry.referencePhotoUrl,
                    )
                  else
                    _lockedArt(),
                  Positioned(
                    top: 6,
                    left: 8,
                    child: Text(
                      '#${entry.dexNumber.toString().padLeft(3, '0')}',
                      style: TextStyle(
                        color: caught
                            ? Colors.white.withValues(alpha: 0.9)
                            : AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                children: [
                  Text(
                    caught ? entry.name : '???',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: caught
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        caught
                            ? Icons.check_circle_outline
                            : Icons.lock_outline,
                        size: 13,
                        color: caught ? AppColors.accent : AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          caught ? entry.rarity.label : 'Not observed',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: caught ? rarityColor : AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lockedArt() {
    if (entry.hasReferencePhoto) {
      return Stack(
        fit: StackFit.expand,
        children: [
          SpeciesSilhouette(url: entry.referencePhotoUrl),
          // Small corner lock so the animal's shape stays fully visible.
          Positioned(
            top: 6,
            right: 8,
            child: Icon(
              Icons.lock_outline,
              size: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      );
    }
    return Container(
      color: AppColors.surfaceAlt,
      child: Center(
        child: Icon(
          _iconForCategory(entry.category),
          size: 56,
          color: AppColors.textMuted.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// "Who's that animal?" silhouette: the reference photo rendered as a dark
/// monochrome shadow. The shape and pose stay recognizable so the player
/// knows what to hunt, but colors and details remain hidden until caught.
///
/// A color matrix is far cheaper on the GPU than a live blur, so this also
/// improves grid scroll performance.
class SpeciesSilhouette extends StatelessWidget {
  const SpeciesSilhouette({super.key, required this.url});

  final String url;

  /// Luminance crushed to a dark grey-green so the subject reads as a
  /// shadow against the tile background.
  static const List<double> _silhouetteMatrix = <double>[
    0.2126 * 0.30, 0.7152 * 0.30, 0.0722 * 0.30, 0, 12, // R
    0.2126 * 0.34, 0.7152 * 0.34, 0.0722 * 0.34, 0, 16, // G
    0.2126 * 0.30, 0.7152 * 0.30, 0.0722 * 0.30, 0, 13, // B
    0, 0, 0, 1, 0, // A
  ];

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_silhouetteMatrix),
      // A light blur softens texture (fur/feathers) without hiding the
      // outline, keeping the "mystery shadow" readable.
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: SafeNetworkImage(url: url),
      ),
    );
  }
}

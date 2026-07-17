import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/catalog_entry.dart';
import '../models/fauna_card_model.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/neon_button.dart';
import '../widgets/safe_network_image.dart';

enum _DexFilter { all, caught, missing }

/// Snapfari-style collector directory driven by the shared species catalog.
/// Undiscovered species show as blurred "secret" tiles that unlock on scan.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  _DexFilter _filter = _DexFilter.all;
  String? _categoryFilter; // null = all categories

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final catalog = session.catalog;

    final total = catalog.length;
    final caughtCount =
        catalog.where((e) => session.isCaughtTaxon(e.taxonId)).length;

    final entries = catalog.where((entry) {
      final caught = session.isCaughtTaxon(entry.taxonId);
      if (_categoryFilter != null && entry.category != _categoryFilter) {
        return false;
      }
      switch (_filter) {
        case _DexFilter.all:
          return true;
        case _DexFilter.caught:
          return caught;
        case _DexFilter.missing:
          return !caught;
      }
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                    '$caughtCount / $total species discovered',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _chip('All', _DexFilter.all),
                      _chip('Caught', _DexFilter.caught),
                      _chip('Missing', _DexFilter.missing),
                    ],
                  ),
                  if (_categoryFilter != null) ...[
                    const SizedBox(height: 10),
                    _activeCategoryPill(),
                  ],
                ],
              ),
            ),
            Expanded(
              child: total == 0
                  ? const Center(
                      child: Text(
                        'Loading catalog...',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : GridView.builder(
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
                          onTap: owned != null
                              ? () => _openDetail(context, owned)
                              : null,
                        );
                      },
                    ),
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
              const Icon(Icons.close_rounded,
                  size: 15, color: AppColors.accent),
            ],
          ),
        ),
      ),
    );
  }

  void _openCategorySheet(List<CatalogEntry> catalog) {
    final categories = <String>{for (final e in catalog) e.category}.toList()
      ..sort();
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
                leading: const Icon(Icons.clear_all_rounded,
                    color: AppColors.accent),
                title: const Text('All categories',
                    style: TextStyle(color: AppColors.textPrimary)),
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
                  title: Text(cat,
                      style: const TextStyle(color: AppColors.textPrimary)),
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

  Widget _chip(String label, _DexFilter value) {
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
                        style: AppTheme.heading(AppColors.textPrimary, size: 22),
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
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
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

/// The player's own photo with a safe fallback chain: file -> reference -> pets.
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
    final rarityColor = _rarityColor(entry.rarity);
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
                      color:
                          caught ? AppColors.textPrimary : AppColors.textMuted,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        caught ? Icons.check_circle_outline : Icons.lock_outline,
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

  /// A blurred + darkened reference photo keeps the species a "secret" until
  /// the player scans it. Falls back to a muted category icon when no photo.
  Widget _lockedArt() {
    if (entry.hasReferencePhoto) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: SafeNetworkImage(url: entry.referencePhotoUrl),
          ),
          Container(color: Colors.black.withValues(alpha: 0.55)),
          Center(
            child: Icon(
              Icons.lock_outline,
              size: 34,
              color: Colors.white.withValues(alpha: 0.55),
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

  Color _rarityColor(Rarity rarity) {
    switch (rarity) {
      case Rarity.common:
        return const Color(0xFF4B5563);
      case Rarity.uncommon:
        return const Color(0xFF10B981);
      case Rarity.rare:
        return const Color(0xFFD946EF);
      case Rarity.legendary:
        return const Color(0xFFF59E0B);
    }
  }
}

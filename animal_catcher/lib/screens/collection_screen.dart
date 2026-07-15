import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../debug/dummy_data.dart';
import '../models/fauna_card_model.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/neon_button.dart';
import '../widgets/wiki_image.dart';

enum _DexFilter { all, mammals, ocean, insects, avians }

/// Snapfari-style collector directory — high-contrast green progress UI.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  _DexFilter _filter = _DexFilter.all;

  static const int _dexCatalogSize = 164;

  bool _matchesFilter(FaunaCard seed) {
    final h = seed.habitat.toLowerCase();
    switch (_filter) {
      case _DexFilter.all:
        return true;
      case _DexFilter.mammals:
        return h == 'mammal' || h == 'land';
      case _DexFilter.ocean:
        return h == 'ocean';
      case _DexFilter.insects:
        return h == 'insect';
      case _DexFilter.avians:
        return h == 'avian';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final discovered = session.collection.length;
    final entries = kSpeciesDexSeed.where(_matchesFilter).toList();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.25,
            colors: [Color(0xFF12301C), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Collection',
                      style: AppTheme.heading(AppColors.neonGreen, size: 26),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$discovered / $_dexCatalogSize species discovered',
                      style: const TextStyle(
                        color: AppColors.neonGreen,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _chip('All', _DexFilter.all),
                          _chip('Mammals', _DexFilter.mammals),
                          _chip('Ocean', _DexFilter.ocean),
                          _chip('Insects', _DexFilter.insects),
                          _chip('Avians', _DexFilter.avians),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.74,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final seed = entries[i];
                    final owned = session.cardForSpecies(seed.name);
                    return _SpeciesTile(
                      seed: seed,
                      owned: owned,
                      deckCount: owned == null
                          ? 0
                          : session.collection
                              .where((c) =>
                                  c.name.toLowerCase() ==
                                  owned.name.toLowerCase())
                              .length,
                      onTap: () {
                        if (owned != null) {
                          _openDetail(context, owned, session);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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
            color:
                selected ? AppColors.neonGreen : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: selected ? AppColors.neonGreen : AppColors.textMuted,
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

  void _openDetail(
    BuildContext context,
    FaunaCard card,
    SessionProvider session,
  ) {
    final deckCount = session.collection
        .where((c) => c.name.toLowerCase() == card.name.toLowerCase())
        .length;

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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: card.hasRemoteImage
                              ? WikiImage(url: card.imageUrl, fit: BoxFit.cover)
                              : Container(
                                  color: AppColors.surfaceAlt,
                                  child: Icon(card.habitatIcon,
                                      size: 64, color: card.rarityColor),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        card.name,
                        textAlign: TextAlign.center,
                        style: AppTheme.heading(card.rarityColor, size: 22),
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
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: card.rarityColor),
                            color: card.rarityColor.withValues(alpha: 0.12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(card.habitatIcon,
                                  size: 16, color: card.rarityColor),
                              const SizedBox(width: 6),
                              Text(
                                'HABITAT: ${card.habitat.toUpperCase()}',
                                style: TextStyle(
                                  color: card.rarityColor,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Combat Power ${card.combatPower.toStringAsFixed(0)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Current active population in your deck: $deckCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.neonGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _statGrid(card),
                      const SizedBox(height: 16),
                      Text(
                        card.lore,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),
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

  Widget _statGrid(FaunaCard card) {
    final items = [
      (Icons.favorite, 'HP', '${card.maxHp}', AppColors.neonPink),
      (Icons.bolt, 'ATK', '${card.attack}', AppColors.warning),
      (Icons.speed, 'SPD', '${card.speed}', AppColors.neonCyan),
      (Icons.shield, 'DEF', '${card.defense}', AppColors.neonPurple),
    ];
    return Row(
      children: items
          .map(
            (e) => Expanded(
              child: Column(
                children: [
                  Icon(e.$1, color: e.$4),
                  const SizedBox(height: 4),
                  Text(e.$3,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  Text(e.$2, style: AppTheme.label),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SpeciesTile extends StatelessWidget {
  const _SpeciesTile({
    required this.seed,
    required this.owned,
    required this.deckCount,
    required this.onTap,
  });

  final FaunaCard seed;
  final FaunaCard? owned;
  final int deckCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final caught = owned != null;
    final display = owned ?? seed;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0xFF122018),
          border: Border.all(
            color: caught
                ? display.rarityColor
                : AppColors.textMuted.withValues(alpha: 0.35),
            width: caught ? 2 : 1.5,
          ),
          boxShadow: caught
              ? [
                  BoxShadow(
                    color: display.rarityColor.withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: caught
                  ? (display.hasRemoteImage
                      ? WikiImage(url: display.imageUrl, fit: BoxFit.cover)
                      : Center(
                          child: Icon(display.habitatIcon,
                              size: 48, color: display.rarityColor),
                        ))
                  : Container(
                      color: const Color(0xFF0C1610),
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2, 0.2, 0.2, 0, 0,
                          0.35, 0.35, 0.35, 0, 0,
                          0.2, 0.2, 0.2, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                        child: Center(
                          child: Icon(
                            seed.habitatIcon,
                            size: 56,
                            color: AppColors.neonGreen.withValues(alpha: 0.35),
                          ),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                children: [
                  Text(
                    caught ? display.name : '???',
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
                        color: caught
                            ? AppColors.neonGreen
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          caught
                              ? display.rarity.label
                              : 'Not Observed',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: caught
                                ? display.rarityColor
                                : AppColors.textMuted,
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
}

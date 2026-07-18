import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'dex_progress.dart';
import 'fauna_card_model.dart';

/// Grouping used by the Awards screen sections.
enum AchievementGroup { discovery, experience, rarity, category }

extension AchievementGroupX on AchievementGroup {
  String get label {
    switch (this) {
      case AchievementGroup.discovery:
        return 'Discovery';
      case AchievementGroup.experience:
        return 'Experience';
      case AchievementGroup.rarity:
        return 'Rarity';
      case AchievementGroup.category:
        return 'Category';
    }
  }
}

/// Inputs needed to evaluate achievements without coupling to SessionProvider.
class AchievementContext {
  const AchievementContext({
    required this.progress,
    required this.xp,
    required this.level,
  });

  final DexProgress progress;
  final int xp;
  final int level;
}

/// One badge-only milestone with stable id and progress evaluation.
class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.group,
    required this.target,
    required this.progressOf,
  });

  final String id;
  final String title;
  final String description;
  final IconData icon;
  final AchievementGroup group;
  final int target;
  final int Function(AchievementContext ctx) progressOf;

  int progress(AchievementContext ctx) => progressOf(ctx).clamp(0, target);

  bool isUnlocked(AchievementContext ctx) => progress(ctx) >= target;

  double fraction(AchievementContext ctx) =>
      target <= 0 ? 0 : progress(ctx) / target;

  String semanticsLabel(AchievementContext ctx) {
    final state = isUnlocked(ctx) ? 'unlocked' : 'locked';
    return '$title, $state, ${progress(ctx)} of $target. $description';
  }
}

/// Curated badge-only milestones. Progress is derived from inventory/profile —
/// no separate persistence and no claimable rewards.
List<Achievement> buildAchievements() {
  return [
    // -- Discovery ---------------------------------------------------------
    Achievement(
      id: 'first_catch',
      title: 'First Catch',
      description: 'Scan and collect your first species.',
      icon: Icons.pets_rounded,
      group: AchievementGroup.discovery,
      target: 1,
      progressOf: (c) => c.progress.caught,
    ),
    Achievement(
      id: 'species_5',
      title: 'Getting Started',
      description: 'Collect 5 species in the dex.',
      icon: Icons.filter_5_rounded,
      group: AchievementGroup.discovery,
      target: 5,
      progressOf: (c) => c.progress.caught,
    ),
    Achievement(
      id: 'species_10',
      title: 'Apprentice Naturalist',
      description: 'Collect 10 species in the dex.',
      icon: Icons.filter_9_plus_rounded,
      group: AchievementGroup.discovery,
      target: 10,
      progressOf: (c) => c.progress.caught,
    ),
    Achievement(
      id: 'species_25',
      title: 'Field Researcher',
      description: 'Collect 25 species in the dex.',
      icon: Icons.science_rounded,
      group: AchievementGroup.discovery,
      target: 25,
      progressOf: (c) => c.progress.caught,
    ),
    Achievement(
      id: 'species_50',
      title: 'Seasoned Collector',
      description: 'Collect 50 species in the dex.',
      icon: Icons.collections_bookmark_rounded,
      group: AchievementGroup.discovery,
      target: 50,
      progressOf: (c) => c.progress.caught,
    ),
    Achievement(
      id: 'species_100',
      title: 'Dex Devotee',
      description: 'Collect 100 species in the dex.',
      icon: Icons.workspace_premium_rounded,
      group: AchievementGroup.discovery,
      target: 100,
      progressOf: (c) => c.progress.caught,
    ),

    // -- Experience --------------------------------------------------------
    Achievement(
      id: 'level_5',
      title: 'Rising Star',
      description: 'Reach level 5.',
      icon: Icons.trending_up_rounded,
      group: AchievementGroup.experience,
      target: 5,
      progressOf: (c) => c.level,
    ),
    Achievement(
      id: 'level_10',
      title: 'Veteran',
      description: 'Reach level 10.',
      icon: Icons.military_tech_rounded,
      group: AchievementGroup.experience,
      target: 10,
      progressOf: (c) => c.level,
    ),
    Achievement(
      id: 'xp_500',
      title: 'Half-Thousand XP',
      description: 'Earn 500 total XP.',
      icon: Icons.bolt_rounded,
      group: AchievementGroup.experience,
      target: 500,
      progressOf: (c) => c.xp,
    ),
    Achievement(
      id: 'xp_1000',
      title: 'Thousand Club',
      description: 'Earn 1,000 total XP.',
      icon: Icons.flash_on_rounded,
      group: AchievementGroup.experience,
      target: 1000,
      progressOf: (c) => c.xp,
    ),

    // -- Rarity ------------------------------------------------------------
    Achievement(
      id: 'first_uncommon',
      title: 'Uncommon Find',
      description: 'Collect an Uncommon species.',
      icon: Icons.star_half_rounded,
      group: AchievementGroup.rarity,
      target: 1,
      progressOf: (c) => c.progress.rarityCount(Rarity.uncommon),
    ),
    Achievement(
      id: 'first_rare',
      title: 'Rare Sighting',
      description: 'Collect a Rare species.',
      icon: Icons.star_rounded,
      group: AchievementGroup.rarity,
      target: 1,
      progressOf: (c) => c.progress.rarityCount(Rarity.rare),
    ),
    Achievement(
      id: 'first_legendary',
      title: 'Legendary Encounter',
      description: 'Collect a Legendary species.',
      icon: Icons.auto_awesome_rounded,
      group: AchievementGroup.rarity,
      target: 1,
      progressOf: (c) => c.progress.rarityCount(Rarity.legendary),
    ),

    // -- Category ----------------------------------------------------------
    Achievement(
      id: 'cat_mammal',
      title: 'Mammal Watcher',
      description: 'Collect 5 mammals.',
      icon: Icons.pets,
      group: AchievementGroup.category,
      target: 5,
      progressOf: (c) => c.progress.caughtInCategory('Mammal'),
    ),
    Achievement(
      id: 'cat_bird',
      title: 'Bird Watcher',
      description: 'Collect 5 birds.',
      icon: Icons.flutter_dash,
      group: AchievementGroup.category,
      target: 5,
      progressOf: (c) => c.progress.caughtInCategory('Bird'),
    ),
    Achievement(
      id: 'cat_fish',
      title: 'Angler',
      description: 'Collect 3 fish.',
      icon: Icons.water,
      group: AchievementGroup.category,
      target: 3,
      progressOf: (c) => c.progress.caughtInCategory('Fish'),
    ),
    Achievement(
      id: 'cat_insect',
      title: 'Entomologist',
      description: 'Collect 5 insects.',
      icon: Icons.bug_report,
      group: AchievementGroup.category,
      target: 5,
      progressOf: (c) => c.progress.caughtInCategory('Insect'),
    ),
    Achievement(
      id: 'all_categories',
      title: 'Wide Horizons',
      description: 'Collect at least one species in every seeded category.',
      icon: Icons.public_rounded,
      group: AchievementGroup.category,
      target: kCanonicalCategories.length,
      progressOf: (c) => c.progress.canonicalCategoriesTouched,
    ),
  ];
}

Color achievementAccent(bool unlocked) =>
    unlocked ? AppColors.accent : AppColors.textMuted;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/achievement.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

enum _AwardFilter { all, inProgress, unlocked }

/// Awards tab: badge-only milestones with filters and grouped sections.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  _AwardFilter _filter = _AwardFilter.all;
  late final List<Achievement> _all = buildAchievements();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final ctx = AchievementContext(
      progress: session.dexProgress,
      xp: session.xp,
      level: session.level,
    );

    final unlockedCount = _all.where((a) => a.isUnlocked(ctx)).length;
    final filtered = _all.where((a) {
      switch (_filter) {
        case _AwardFilter.all:
          return true;
        case _AwardFilter.inProgress:
          return !a.isUnlocked(ctx);
        case _AwardFilter.unlocked:
          return a.isUnlocked(ctx);
      }
    }).toList();

    final groups = <AchievementGroup, List<Achievement>>{};
    for (final a in filtered) {
      groups.putIfAbsent(a.group, () => []).add(a);
    }

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
                  Text(
                    'Awards',
                    style: AppTheme.heading(AppColors.accent, size: 26),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$unlockedCount / ${_all.length} unlocked',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _all.isEmpty ? 0 : unlockedCount / _all.length,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('All', _AwardFilter.all),
                        _filterChip('In progress', _AwardFilter.inProgress),
                        _filterChip('Unlocked', _AwardFilter.unlocked),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No awards match this filter.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        for (final group in AchievementGroup.values)
                          if (groups[group]?.isNotEmpty ?? false) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                              child: Text(
                                group.label.toUpperCase(),
                                style: AppTheme.label.copyWith(
                                  color: AppColors.accent,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                            for (final a in groups[group]!)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _AchievementTile(
                                  achievement: a,
                                  ctx: ctx,
                                ),
                              ),
                          ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, _AwardFilter value) {
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
}

class _AchievementTile extends StatelessWidget {
  const _AchievementTile({required this.achievement, required this.ctx});

  final Achievement achievement;
  final AchievementContext ctx;

  @override
  Widget build(BuildContext context) {
    final unlocked = achievement.isUnlocked(ctx);
    final current = achievement.progress(ctx);
    final accent = achievementAccent(unlocked);

    return Semantics(
      label: achievement.semanticsLabel(ctx),
      child: GlassContainer(
        borderColor: accent,
        glow: false,
        borderWidth: unlocked ? 1.5 : 1,
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: unlocked ? 0.18 : 0.08),
                border: Border.all(color: accent, width: 1.5),
              ),
              child: Icon(
                unlocked ? achievement.icon : Icons.lock_outline,
                color: accent,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          achievement.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unlocked
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (unlocked)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.accent,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    achievement.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: achievement.fraction(ctx),
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$current / ${achievement.target}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
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

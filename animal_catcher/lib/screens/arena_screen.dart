import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../debug/dummy_data.dart';
import '../models/fauna_card_model.dart';
import '../services/audio_manager.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import 'battle_screen.dart';

/// Arena hub — pick a fighter then duel the Battle Bot.
class ArenaScreen extends StatelessWidget {
  const ArenaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.3,
            colors: [Color(0xFF1A1020), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('ARENA',
                    style: AppTheme.heading(AppColors.neonMagenta, size: 26)),
                const SizedBox(height: 8),
                const Text(
                  'Select a card and face the Battle Bot.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 28),
                _modeTile(
                  context,
                  title: 'BATTLE BOT',
                  subtitle: 'Heuristic AI opponent with AP economy.',
                  icon: Icons.smart_toy_rounded,
                  color: AppColors.neonCyan,
                  onTap: () {
                    if (session.battleTeam.isEmpty &&
                        session.collection.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Capture or sandbox-load cards before battling.',
                          ),
                        ),
                      );
                      return;
                    }
                    context.read<AudioManager>().tap();
                    final roster = session.battleTeam.isNotEmpty
                        ? session.battleTeam
                        : session.collection;
                    _pickThenBattle(context, roster);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickThenBattle(
    BuildContext context,
    List<FaunaCard> team,
  ) async {
    final chosen = await showModalBottomSheet<FaunaCard>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('PICK YOUR FIGHTER',
                  style: AppTheme.heading(AppColors.neonCyan, size: 18)),
              const SizedBox(height: 12),
              ...team.map(
                (c) => ListTile(
                  tileColor: AppColors.surfaceAlt,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(c.habitatIcon, color: c.rarityColor),
                  title: Text(c.name, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    '${c.habitat} • HP ${c.maxHp}',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  onTap: () => Navigator.pop(ctx, c),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (chosen == null || !context.mounted) return;

    final botPool = kSpeciesDexSeed
        .where((c) => c.name.toLowerCase() != chosen.name.toLowerCase())
        .toList();
    final bot = botPool.isEmpty
        ? kSpeciesDexSeed.first
        : botPool[math.Random().nextInt(botPool.length)];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          playerCard: chosen,
          enemyCard: bot,
          vsBot: true,
        ),
      ),
    );
  }

  Widget _modeTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        borderColor: color,
        child: Row(
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }
}

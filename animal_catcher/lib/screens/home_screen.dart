import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/profile_model.dart';
import '../services/audio_manager.dart';
import '../state/session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/neon_button.dart';
import 'arena_screen.dart';
import 'camera_screen.dart';

/// Profile / hub tab: currencies, quick actions, and settings.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    this.onOpenScan,
    this.onOpenArena,
  });

  /// When provided (shell mode), switch tabs instead of pushing routes.
  final VoidCallback? onOpenScan;
  final VoidCallback? onOpenArena;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final profile = session.profile;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.4,
            colors: [Color(0xFF1A241C), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, session),
                const SizedBox(height: 20),
                _currencyRow(session),
                const SizedBox(height: 24),
                Text('OPERATIONS',
                    style: AppTheme.heading(AppColors.neonGreen, size: 18)),
                const SizedBox(height: 14),
                _actionTile(
                  context,
                  title: 'SCAN WILDLIFE',
                  subtitle: 'Capture real animals into battle cards',
                  icon: Icons.center_focus_strong,
                  color: AppColors.neonGreen,
                  onTap: () {
                    context.read<AudioManager>().tap();
                    if (onOpenScan != null) {
                      onOpenScan!();
                    } else {
                      _go(context, const CameraScreen());
                    }
                  },
                ),
                const SizedBox(height: 12),
                _actionTile(
                  context,
                  title: 'ENTER ARENA',
                  subtitle: 'Battle wild bosses in turn-based combat',
                  icon: Icons.sports_kabaddi,
                  color: AppColors.neonPink,
                  onTap: () {
                    context.read<AudioManager>().tap();
                    if (onOpenArena != null) {
                      onOpenArena!();
                    } else {
                      _go(context, const ArenaScreen());
                    }
                  },
                ),
                const SizedBox(height: 12),
                _teamPanel(session),
                const SizedBox(height: 24),
                _profilePanel(context, profile?.username ?? 'Player'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _header(BuildContext context, SessionProvider session) {
    final cls = session.profile?.startingClass;
    return Row(
      children: [
        Icon(
          cls?.emblemIcon ?? Icons.person,
          size: 40,
          color: AppColors.neonPurple,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.profile?.username ?? 'Player',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(AppColors.neonPurple, size: 22),
              ),
              Text(
                cls?.label ??
                    'Recruit  •  Rank ${session.profile?.playerRank ?? 1}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.label,
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: AppColors.textMuted),
          onPressed: () => context.read<SessionProvider>().logout(),
        ),
      ],
    );
  }

  Widget _currencyRow(SessionProvider session) {
    return Row(
      children: [
        Expanded(
          child: _currencyChip(
            'GOLD',
            session.gold,
            AppColors.rarityLegendary,
            Icons.monetization_on_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _currencyChip(
            'WILD ESSENCE',
            session.wildEssence,
            AppColors.neonCyan,
            Icons.eco_rounded,
          ),
        ),
      ],
    );
  }

  Widget _currencyChip(String label, int value, Color color, IconData icon) {
    return GlassContainer(
      borderColor: color,
      glow: false,
      borderWidth: 1.5,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.label,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(
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
        glow: false,
        borderWidth: 1.5,
        child: Row(
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    );
  }

  Widget _teamPanel(SessionProvider session) {
    final team = session.battleTeam;
    return GlassContainer(
      borderColor: AppColors.neonGreen,
      glow: false,
      borderWidth: 1.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded,
                  color: AppColors.neonGreen, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  session.isGuest
                      ? 'BATTLE TEAM (${team.length})'
                      : 'BATTLE TEAM (${team.length}/6)',
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.label.copyWith(color: AppColors.neonGreen),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (team.isEmpty)
            const Text(
              'No cards yet — scan wildlife to build your team.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: team
                  .map(
                    (c) => Chip(
                      backgroundColor: AppColors.forRarity(c.rarity)
                          .withValues(alpha: 0.2),
                      side: BorderSide(color: AppColors.forRarity(c.rarity)),
                      label: Text(
                        c.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _profilePanel(BuildContext context, String username) {
    final audio = context.watch<AudioManager>();
    return GlassContainer(
      borderColor: AppColors.neonPurple,
      glow: false,
      borderWidth: 1.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SETTINGS',
            style: AppTheme.label.copyWith(color: AppColors.neonPurple),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.neonPurple,
            secondary: const Icon(Icons.volume_up, color: AppColors.neonPurple),
            title: const Text(
              'Sound',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'Music & effects',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            value: !audio.muted,
            onChanged: (v) => audio.setMuted(!v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.neonPurple,
            secondary:
                const Icon(Icons.vibration, color: AppColors.neonPurple),
            title: const Text(
              'Vibration',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'Haptic feedback',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            value: audio.vibrationEnabled,
            onChanged: audio.setVibrationEnabled,
          ),
          const SizedBox(height: 8),
          NeonButton(
            label: 'Play Lobby Theme',
            color: AppColors.neonPurple,
            icon: Icons.music_note_rounded,
            onPressed: () => audio.playBgm(Bgm.lobby),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/neon_button.dart';

/// Handles OS permission requests preceded by a beautiful custom rationale
/// popup explaining WHY the game needs each permission.
///
/// Showing a rationale *before* the system prompt is a store-review best
/// practice (helps avoid App Store / Play Store rejections for camera + GPS).
class PermissionService {
  /// Show a themed rationale card, then trigger the real OS permission prompt.
  /// Returns true if the permission ends up granted.
  static Future<bool> requestWithRationale(
    BuildContext context, {
    required Permission permission,
    required String title,
    required String reason,
    required IconData icon,
    Color accent = AppColors.neonCyan,
  }) async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _RationaleDialog(
        title: title,
        reason: reason,
        icon: icon,
        accent: accent,
      ),
    );

    if (proceed != true) return false;

    final status = await permission.request();
    return status.isGranted || status.isLimited;
  }

  /// Convenience for the onboarding flow: camera THEN location, each gated by
  /// its own rationale card.
  static Future<void> runOnboardingRequests(BuildContext context) async {
    await requestWithRationale(
      context,
      permission: Permission.camera,
      title: 'Camera Access',
      reason:
          'The rift scanner uses your camera to capture real-world animals and '
          'mint them into battle cards. We never store photos without your action.',
      icon: Icons.camera_alt_rounded,
      accent: AppColors.neonGreen,
    );

    if (!context.mounted) return;

    await requestWithRationale(
      context,
      permission: Permission.locationWhenInUse,
      title: 'Location Access',
      reason:
          'Your GPS reveals nearby biomes and spawn arenas, so the wildlife you '
          'encounter matches the world around you.',
      icon: Icons.public_rounded,
      accent: AppColors.neonPurple,
    );
  }
}

class _RationaleDialog extends StatelessWidget {
  const _RationaleDialog({
    required this.title,
    required this.reason,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String reason;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: GlassContainer(
        borderColor: accent,
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.15),
                border: Border.all(color: accent, width: 1.4),
              ),
              child: Icon(icon, color: accent, size: 34),
            ),
            const SizedBox(height: 18),
            Text(title, style: AppTheme.heading(accent, size: 20)),
            const SizedBox(height: 12),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                height: 1.4,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 22),
            NeonButton(
              label: 'Allow',
              color: accent,
              icon: Icons.check_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Not now',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

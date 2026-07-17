import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Placeholder Achievements tab. Full implementation lands in a later prompt.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Achievements',
                style: AppTheme.heading(AppColors.accent, size: 26),
              ),
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events_outlined,
                          size: 56, color: AppColors.textMuted),
                      SizedBox(height: 12),
                      Text(
                        'Coming soon',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

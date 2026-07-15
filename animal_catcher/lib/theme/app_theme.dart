import 'package:flutter/material.dart';

import '../models/fauna_card_model.dart';

/// Dark cyberpunk palette — neon green interactivity, magenta hazards.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF05060B);
  static const Color surface = Color(0xFF0C0F1A);
  static const Color surfaceAlt = Color(0xFF141926);

  static const Color neonGreen = Color(0xFF39FF14);
  static const Color neonPink = Color(0xFFFF2E88);
  static const Color neonMagenta = Color(0xFFFF2E88);
  static const Color neonPurple = Color(0xFFB026FF);
  static const Color neonCyan = Color(0xFF00E5FF);

  static const Color accent = neonGreen;
  static const Color danger = neonMagenta;
  static const Color warning = Color(0xFFF59E0B);

  static const Color textPrimary = Color(0xFFEAF2FF);
  static const Color textMuted = Color(0xFF8592AD);

  static const Color rarityCommon = Color(0xFF4B5563);
  static const Color rarityUncommon = Color(0xFF10B981);
  static const Color rarityRare = Color(0xFFD946EF);
  static const Color rarityLegendary = Color(0xFFF59E0B);

  static Color forRarity(Rarity rarity) {
    switch (rarity) {
      case Rarity.common:
        return rarityCommon;
      case Rarity.uncommon:
        return rarityUncommon;
      case Rarity.rare:
        return rarityRare;
      case Rarity.legendary:
        return rarityLegendary;
    }
  }

  static LinearGradient rarityGradient(Rarity rarity) {
    final base = forRarity(rarity);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        base.withValues(alpha: 0.45),
        surface.withValues(alpha: 0.95),
      ],
    );
  }

  static Color hpColor(double fraction) {
    if (fraction > 0.55) return neonGreen;
    if (fraction > 0.25) return warning;
    return danger;
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.neonGreen,
        secondary: AppColors.neonCyan,
        surface: AppColors.surface,
        error: AppColors.neonMagenta,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
      ),
    );
  }

  static TextStyle heading(Color glow, {double size = 26}) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: AppColors.textPrimary,
        shadows: [
          Shadow(color: glow, blurRadius: 14),
          Shadow(color: glow.withValues(alpha: 0.5), blurRadius: 28),
        ],
      );

  static const TextStyle label = TextStyle(
    fontSize: 12,
    letterSpacing: 1.4,
    color: AppColors.textMuted,
    fontWeight: FontWeight.w600,
  );
}

import 'package:flutter/material.dart';

import '../models/fauna_card_model.dart';

/// Pure-collection palette: near-black background with a single green accent.
/// Rarity colors exist ONLY for the thin border + small tag on cards.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0E1410);
  static const Color surface = Color(0xFF141A16);
  static const Color surfaceAlt = Color(0xFF1B231D);

  /// The one and only interactive accent.
  static const Color accent = Color(0xFF39E75F);

  // Legacy neon names retained as aliases so existing widgets stay on-palette.
  // Every one now resolves to the single green accent.
  static const Color neonGreen = accent;
  static const Color neonPink = accent;
  static const Color neonMagenta = accent;
  static const Color neonPurple = accent;
  static const Color neonCyan = accent;

  static const Color danger = accent;
  static const Color warning = accent;

  static const Color textPrimary = Color(0xFFEAF3EC);
  static const Color textMuted = Color(0xFF8A968C);

  // Rarity: Slate / Emerald / Purple / Gold — used only for card border + tag.
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
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.accent,
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

  /// Flat heading — no glow/shadow. [accentColor] is accepted for call-site
  /// compatibility but the text always renders in the primary text color.
  static TextStyle heading(Color accentColor, {double size = 26}) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
        color: AppColors.textPrimary,
      );

  static const TextStyle label = TextStyle(
    fontSize: 12,
    letterSpacing: 1.4,
    color: AppColors.textMuted,
    fontWeight: FontWeight.w600,
  );
}

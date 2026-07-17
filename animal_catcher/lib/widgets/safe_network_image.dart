import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Some image CDNs (e.g. Wikimedia) block anonymous clients without a
/// descriptive User-Agent. Harmless for other hosts like iNaturalist.
const Map<String, String> kImageHeaders = {
  'User-Agent': 'FaunaBattlerAI/1.0 (Flutter; contact@local.dev)',
};

/// Network image with mandatory, error-safe fallback handling.
///
/// An empty URL or any load error falls back to a muted `Icons.pets`
/// placeholder so a missing image can never render as a blank tile.
class SafeNetworkImage extends StatelessWidget {
  const SafeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.iconSize = 48,
  });

  final String url;
  final BoxFit fit;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return _fallback();
    }
    return Image.network(
      url,
      fit: fit,
      headers: kImageHeaders,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: AppColors.surfaceAlt,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
        );
      },
      errorBuilder: (context, _, _) => _fallback(),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.surfaceAlt,
        alignment: Alignment.center,
        child: Icon(
          Icons.pets,
          size: iconSize,
          color: AppColors.textMuted,
        ),
      );
}

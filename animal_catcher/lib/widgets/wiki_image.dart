import 'package:flutter/material.dart';

/// Wikimedia blocks anonymous clients without a descriptive User-Agent.
const Map<String, String> kWikiImageHeaders = {
  'User-Agent': 'FaunaBattlerAI/1.0 (Flutter; contact@local.dev)',
};

/// Network image tuned for Wikipedia Commons CDN thumbnails.
class WikiImage extends StatelessWidget {
  const WikiImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.error,
  });

  final String url;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? error;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return error ?? placeholder ?? const SizedBox.shrink();
    }
    return Image.network(
      url,
      fit: fit,
      headers: kWikiImageHeaders,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return placeholder ??
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
      },
      errorBuilder: (context, _, __) =>
          error ?? placeholder ?? const Icon(Icons.broken_image_outlined),
    );
  }
}

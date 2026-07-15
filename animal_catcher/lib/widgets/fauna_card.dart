import 'dart:io';
import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import '../models/fauna_card_model.dart';
import '../theme/app_theme.dart';
import 'glass_container.dart';
import 'wiki_image.dart';

/// Collectible card with Wikipedia (or local) photograph as the hero art.
class FaunaCardWidget extends StatefulWidget {
  const FaunaCardWidget({
    super.key,
    required this.card,
    this.flip = true,
    this.width = 260,
    this.height = 380,
    this.compact = false,
  });

  final FaunaCard card;
  final bool flip;
  final double width;
  final double height;
  final bool compact;

  @override
  State<FaunaCardWidget> createState() => _FaunaCardWidgetState();
}

class _FaunaCardWidgetState extends State<FaunaCardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.flip) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final angle = _controller.value * math.pi;
        final showFront = _controller.value > 0.5;
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY(angle);

        return Transform(
          alignment: Alignment.center,
          transform: transform,
          child: showFront
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _CardFront(
                    card: widget.card,
                    w: widget.width,
                    h: widget.height,
                    compact: widget.compact,
                  ),
                )
              : _CardBack(w: widget.width, h: widget.height),
        );
      },
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({required this.w, required this.h});
  final double w;
  final double h;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      width: w,
      height: h,
      borderColor: AppColors.neonCyan,
      child: const Center(
        child: Icon(Icons.blur_on_rounded, size: 80, color: AppColors.neonCyan),
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({
    required this.card,
    required this.w,
    required this.h,
    required this.compact,
  });
  final FaunaCard card;
  final double w;
  final double h;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final trim = card.rarityColor;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.surface,
        border: Border.all(color: trim, width: 2),
        boxShadow: [
          BoxShadow(color: trim.withValues(alpha: 0.45), blurRadius: 18),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: compact ? 5 : 6, child: _art()),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 12,
              8,
              compact ? 8 : 12,
              compact ? 8 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AutoSizeText(
                        card.name,
                        maxLines: 1,
                        minFontSize: 10,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 13 : 16,
                        ),
                      ),
                    ),
                    Icon(card.habitatIcon, size: 16, color: trim),
                    const SizedBox(width: 6),
                    _pill(trim),
                  ],
                ),
                if (!compact && card.scientificName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    card.scientificName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                _statsRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _art() {
    Widget image;
    if (card.hasLocalPhoto) {
      image = Image.file(File(card.photoPath!), fit: BoxFit.cover);
    } else if (card.hasRemoteImage) {
      image = WikiImage(
        url: card.imageUrl,
        fit: BoxFit.cover,
        error: _placeholder(),
      );
    } else {
      image = _placeholder();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.surface.withValues(alpha: 0.9),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.surfaceAlt,
        child: Icon(
          Icons.pets,
          size: compact ? 42 : 64,
          color: Colors.white24,
        ),
      );

  Widget _pill(Color trim) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: trim),
          color: trim.withValues(alpha: 0.18),
        ),
        child: Text(
          card.rarity.label.toUpperCase(),
          style: TextStyle(
            color: trim,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _statsRow() {
    return Row(
      children: [
        _stat(Icons.favorite, '${card.maxHp}', AppColors.neonPink),
        _stat(Icons.bolt, '${card.attack}', AppColors.warning),
        _stat(Icons.speed, '${card.speed}', AppColors.neonCyan),
        _stat(Icons.shield, '${card.defense}', AppColors.neonPurple),
      ],
    );
  }

  Widget _stat(IconData icon, String value, Color color) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

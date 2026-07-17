import 'package:flutter/material.dart';

/// Rarity tiers matching backend / Supabase schema labels.
enum Rarity { common, uncommon, rare, legendary }

extension RarityX on Rarity {
  String get label {
    switch (this) {
      case Rarity.common:
        return 'Common';
      case Rarity.uncommon:
        return 'Uncommon';
      case Rarity.rare:
        return 'Rare';
      case Rarity.legendary:
        return 'Legendary';
    }
  }

  static Rarity fromString(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'uncommon':
        return Rarity.uncommon;
      case 'rare':
        return Rarity.rare;
      case 'legendary':
        return Rarity.legendary;
      case 'common':
      default:
        return Rarity.common;
    }
  }
}

/// Immutable collected species card — mirrors Supabase `user_cards` + scan JSON.
///
/// A pure collection card: identity (name/rarity), the shared species reference
/// (photo/category/wiki, identical for everyone), and the player's personal
/// capture metadata (their own photo + date + optional location). No combat.
@immutable
class FaunaCard {
  const FaunaCard({
    this.cardId,
    this.userId,
    required this.name,
    this.scientificName = '',
    required this.rarity,
    this.taxonId,
    this.referencePhotoUrl = '',
    this.category = 'Wildlife',
    this.wikiUrl = '',
    this.lore = '',
    this.photoPath,
    this.capturedAt,
    this.captureLat,
    this.captureLng,
  });

  final String? cardId;
  final String? userId;
  final String name;
  final String scientificName;
  final Rarity rarity;

  /// Stable iNaturalist taxon id — the conflict-free key for dex matching.
  final int? taxonId;

  /// Shared, consistent-for-everyone species reference image.
  final String referencePhotoUrl;

  /// High-level category (Mammal, Bird, Insect, Fish, Reptile, ... Wildlife).
  final String category;

  /// Wikipedia article URL for the species.
  final String wikiUrl;

  final String lore;

  /// The player's OWN captured photo (on-device path). Their personal trophy.
  final String? photoPath;

  final DateTime? capturedAt;
  final double? captureLat;
  final double? captureLng;

  Color get rarityColor {
    switch (rarity) {
      case Rarity.common:
        return const Color(0xFF4B5563); // Slate
      case Rarity.uncommon:
        return const Color(0xFF10B981); // Emerald
      case Rarity.rare:
        return const Color(0xFFD946EF); // Purple
      case Rarity.legendary:
        return const Color(0xFFF59E0B); // Gold
    }
  }

  IconData get categoryIcon {
    switch (category.trim().toLowerCase()) {
      case 'mammal':
        return Icons.pets;
      case 'bird':
        return Icons.flutter_dash;
      case 'insect':
        return Icons.bug_report;
      case 'fish':
        return Icons.water;
      case 'reptile':
        return Icons.egg_alt;
      case 'amphibian':
        return Icons.water_drop;
      case 'mollusk':
        return Icons.set_meal;
      case 'arachnid':
        return Icons.bug_report;
      default:
        return Icons.pets;
    }
  }

  bool get hasReferencePhoto => referencePhotoUrl.trim().isNotEmpty;
  bool get hasLocalPhoto =>
      photoPath != null && photoPath!.trim().isNotEmpty;

  factory FaunaCard.fromJson(Map<String, dynamic> json) {
    return FaunaCard(
      cardId: json['card_id']?.toString() ?? json['cardId']?.toString(),
      userId: json['user_id']?.toString() ?? json['userId']?.toString(),
      name: (json['name'] ?? 'Unknown Species').toString(),
      scientificName: (json['scientific_name'] ?? json['scientificName'] ?? '')
          .toString(),
      rarity: RarityX.fromString(json['rarity']?.toString()),
      taxonId: _asInt(json['taxon_id'] ?? json['taxonId']),
      referencePhotoUrl: (json['reference_photo_url'] ??
              json['referencePhotoUrl'] ??
              '')
          .toString(),
      category: (json['category'] ?? 'Wildlife').toString(),
      wikiUrl: (json['wiki_url'] ?? json['wikiUrl'] ?? '').toString(),
      lore: (json['lore'] ?? '').toString(),
      photoPath: json['photo_path']?.toString() ?? json['photoPath']?.toString(),
      capturedAt: _asDate(json['captured_at'] ?? json['capturedAt']),
      captureLat: _asDouble(json['capture_lat'] ?? json['captureLat']),
      captureLng: _asDouble(json['capture_lng'] ?? json['captureLng']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (cardId != null) 'card_id': cardId,
        if (userId != null) 'user_id': userId,
        'name': name,
        'scientific_name': scientificName,
        if (taxonId != null) 'taxon_id': taxonId,
        'rarity': rarity.label,
        'reference_photo_url': referencePhotoUrl,
        'category': category,
        'wiki_url': wikiUrl,
        'lore': lore,
        if (photoPath != null) 'photo_path': photoPath,
        if (capturedAt != null) 'captured_at': capturedAt!.toIso8601String(),
        if (captureLat != null) 'capture_lat': captureLat,
        if (captureLng != null) 'capture_lng': captureLng,
      };

  FaunaCard copyWith({
    String? photoPath,
    String? referencePhotoUrl,
    String? category,
    String? wikiUrl,
    DateTime? capturedAt,
    double? captureLat,
    double? captureLng,
  }) {
    return FaunaCard(
      cardId: cardId,
      userId: userId,
      name: name,
      scientificName: scientificName,
      rarity: rarity,
      taxonId: taxonId,
      referencePhotoUrl: referencePhotoUrl ?? this.referencePhotoUrl,
      category: category ?? this.category,
      wikiUrl: wikiUrl ?? this.wikiUrl,
      lore: lore,
      photoPath: photoPath ?? this.photoPath,
      capturedAt: capturedAt ?? this.capturedAt,
      captureLat: captureLat ?? this.captureLat,
      captureLng: captureLng ?? this.captureLng,
    );
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

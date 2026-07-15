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

/// Immutable Fauna card — mirrors Supabase `user_cards` + scan JSON.
@immutable
class FaunaCard {
  const FaunaCard({
    this.cardId,
    this.userId,
    required this.name,
    this.scientificName = '',
    this.imageUrl = '',
    this.habitat = 'Mammal',
    required this.rarity,
    required this.maxHp,
    int? currentHp,
    required this.attack,
    required this.speed,
    required this.defense,
    this.lore = '',
    this.photoPath,
  }) : currentHp = currentHp ?? maxHp;

  final String? cardId;
  final String? userId;
  final String name;
  final String scientificName;
  final String imageUrl;
  final String habitat;
  final Rarity rarity;
  final int maxHp;
  final int currentHp;
  final int attack;
  final int speed;
  final int defense;
  final String lore;

  /// Optional on-device capture path (gallery / camera).
  final String? photoPath;

  /// Back-compat alias used by older UI.
  int get hp => currentHp;

  double get statMultiplier {
    switch (rarity) {
      case Rarity.common:
        return 1.0;
      case Rarity.uncommon:
        return 1.2;
      case Rarity.rare:
        return 1.5;
      case Rarity.legendary:
        return 2.0;
    }
  }

  Color get rarityColor {
    switch (rarity) {
      case Rarity.common:
        return const Color(0xFF4B5563); // Slate Blue
      case Rarity.uncommon:
        return const Color(0xFF10B981); // Emerald Green
      case Rarity.rare:
        return const Color(0xFFD946EF); // Purple-Pink
      case Rarity.legendary:
        return const Color(0xFFF59E0B); // Glowing Gold
    }
  }

  IconData get habitatIcon {
    switch (habitat.trim().toLowerCase()) {
      case 'ocean':
        return Icons.water;
      case 'insect':
        return Icons.bug_report;
      case 'mammal':
        return Icons.pets;
      case 'avian':
        return Icons.air;
      case 'reptile':
        return Icons.healing;
      case 'desert':
        return Icons.wb_sunny;
      case 'land':
        return Icons.forest;
      default:
        return Icons.pets;
    }
  }

  /// Aggregated combat rating scaled by rarity multiplier.
  double get combatPower {
    final raw = (maxHp * 0.35) + (attack * 1.1) + (speed * 0.75) + (defense * 0.9);
    return raw * statMultiplier;
  }

  bool get hasRemoteImage => imageUrl.trim().isNotEmpty;
  bool get hasLocalPhoto =>
      photoPath != null && photoPath!.trim().isNotEmpty;

  factory FaunaCard.fromJson(Map<String, dynamic> json) {
    final maxHp = _asInt(json['max_hp'] ?? json['hp'] ?? json['maxHp'], 50);
    return FaunaCard(
      cardId: json['card_id']?.toString() ?? json['cardId']?.toString(),
      userId: json['user_id']?.toString() ?? json['userId']?.toString(),
      name: (json['name'] ?? 'Unknown Beast').toString(),
      scientificName: (json['scientific_name'] ?? json['scientificName'] ?? '')
          .toString(),
      imageUrl: (json['image_url'] ?? json['imageUrl'] ?? '').toString(),
      habitat: (json['habitat'] ?? 'Mammal').toString(),
      rarity: RarityX.fromString(json['rarity']?.toString()),
      maxHp: maxHp,
      currentHp: _asInt(json['current_hp'] ?? json['currentHp'], maxHp),
      attack: _asInt(json['attack'], 30),
      speed: _asInt(json['speed'], 30),
      defense: _asInt(json['defense'], 30),
      lore: (json['lore'] ?? '').toString(),
      photoPath: json['photo_path']?.toString() ?? json['photoPath']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (cardId != null) 'card_id': cardId,
        if (userId != null) 'user_id': userId,
        'name': name,
        'scientific_name': scientificName,
        'image_url': imageUrl,
        'habitat': habitat,
        'rarity': rarity.label,
        'max_hp': maxHp,
        'hp': maxHp,
        'current_hp': currentHp,
        'attack': attack,
        'speed': speed,
        'defense': defense,
        'lore': lore,
        if (photoPath != null) 'photo_path': photoPath,
      };

  FaunaCard copyWith({
    int? currentHp,
    int? maxHp,
    String? photoPath,
    String? imageUrl,
  }) {
    return FaunaCard(
      cardId: cardId,
      userId: userId,
      name: name,
      scientificName: scientificName,
      imageUrl: imageUrl ?? this.imageUrl,
      habitat: habitat,
      rarity: rarity,
      maxHp: maxHp ?? this.maxHp,
      currentHp: currentHp ?? this.currentHp,
      attack: attack,
      speed: speed,
      defense: defense,
      lore: lore,
      photoPath: photoPath ?? this.photoPath,
    );
  }

  static int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

import 'package:flutter/material.dart';


/// The three stylised Starting Class Emblems chosen during onboarding.
enum StartingClass { apexHunter, swarmWhisperer, aerialScavenger }

extension StartingClassX on StartingClass {
  String get label {
    switch (this) {
      case StartingClass.apexHunter:
        return 'Apex Hunter';
      case StartingClass.swarmWhisperer:
        return 'Swarm Whisperer';
      case StartingClass.aerialScavenger:
        return 'Aerial Scavenger';
    }
  }

  IconData get emblemIcon {
    switch (this) {
      case StartingClass.apexHunter:
        return Icons.pets;
      case StartingClass.swarmWhisperer:
        return Icons.hive_outlined;
      case StartingClass.aerialScavenger:
        return Icons.flight;
    }
  }

  /// Deprecated emoji emblem — prefer [emblemIcon].
  String get emblem {
    switch (this) {
      case StartingClass.apexHunter:
        return 'Apex';
      case StartingClass.swarmWhisperer:
        return 'Swarm';
      case StartingClass.aerialScavenger:
        return 'Aerial';
    }
  }

  String get tagline {
    switch (this) {
      case StartingClass.apexHunter:
        return 'Raw power. Dominate through overwhelming force.';
      case StartingClass.swarmWhisperer:
        return 'Numbers and status effects bleed enemies dry.';
      case StartingClass.aerialScavenger:
        return 'Speed and evasion. Strike before they react.';
    }
  }

  static StartingClass fromString(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'swarm whisperer':
      case 'swarmwhisperer':
        return StartingClass.swarmWhisperer;
      case 'aerial scavenger':
      case 'aerialscavenger':
        return StartingClass.aerialScavenger;
      case 'apex hunter':
      case 'apexhunter':
      default:
        return StartingClass.apexHunter;
    }
  }
}

/// Dart representation of the Supabase `profiles` PostgreSQL table.
///
/// PostgreSQL schema (see backend/schema.sql):
///   user_id       UUID  (Primary Key)
///   username      TEXT  (Unique)
///   player_rank   INTEGER (default 1)
///   gold          INTEGER (default 100)
///   wild_essence  INTEGER (default 50)
///   starting_class TEXT
///   location_lat  DOUBLE PRECISION
///   location_lng  DOUBLE PRECISION
///   created_at    TIMESTAMPTZ
@immutable
class PlayerProfile {
  const PlayerProfile({
    required this.userId,
    required this.username,
    this.playerRank = 1,
    this.gold = 100,
    this.wildEssence = 50,
    this.startingClass = StartingClass.apexHunter,
    this.locationLat,
    this.locationLng,
    this.createdAt,
  });

  final String userId;
  final String username;
  final int playerRank;
  final int gold;
  final int wildEssence;
  final StartingClass startingClass;
  final double? locationLat;
  final double? locationLng;
  final DateTime? createdAt;

  factory PlayerProfile.fromJson(Map<String, dynamic> json) {
    return PlayerProfile(
      userId: (json['user_id'] ?? '').toString(),
      username: (json['username'] ?? 'Player').toString(),
      playerRank: _asInt(json['player_rank'], 1),
      gold: _asInt(json['gold'], 100),
      wildEssence: _asInt(json['wild_essence'], 50),
      startingClass: StartingClassX.fromString(json['starting_class']?.toString()),
      locationLat: _asDouble(json['location_lat']),
      locationLng: _asDouble(json['location_lng']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'username': username,
        'player_rank': playerRank,
        'gold': gold,
        'wild_essence': wildEssence,
        'starting_class': startingClass.label,
        'location_lat': locationLat,
        'location_lng': locationLng,
        'created_at': createdAt?.toIso8601String(),
      };

  PlayerProfile copyWith({
    String? username,
    int? playerRank,
    int? gold,
    int? wildEssence,
    StartingClass? startingClass,
    double? locationLat,
    double? locationLng,
  }) {
    return PlayerProfile(
      userId: userId,
      username: username ?? this.username,
      playerRank: playerRank ?? this.playerRank,
      gold: gold ?? this.gold,
      wildEssence: wildEssence ?? this.wildEssence,
      startingClass: startingClass ?? this.startingClass,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      createdAt: createdAt,
    );
  }

  static int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

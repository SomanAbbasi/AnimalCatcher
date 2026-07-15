import 'package:flutter/material.dart';

/// Creature combat archetype — drives the shared movepool lookup.
enum CreatureClass { apex, swarm, scavenger }

extension CreatureClassX on CreatureClass {
  String get wire {
    switch (this) {
      case CreatureClass.apex:
        return 'apex';
      case CreatureClass.swarm:
        return 'swarm';
      case CreatureClass.scavenger:
        return 'scavenger';
    }
  }

  String get label {
    switch (this) {
      case CreatureClass.apex:
        return 'Apex';
      case CreatureClass.swarm:
        return 'Swarm';
      case CreatureClass.scavenger:
        return 'Scavenger';
    }
  }

  static CreatureClass fromString(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'swarm':
        return CreatureClass.swarm;
      case 'scavenger':
        return CreatureClass.scavenger;
      case 'apex':
      default:
        return CreatureClass.apex;
    }
  }
}

/// Move categories for the hand-of-cards system.
enum MoveType { basic, defense, status, signature, ultimate }

extension MoveTypeX on MoveType {
  String get label {
    switch (this) {
      case MoveType.basic:
        return 'Basic';
      case MoveType.defense:
        return 'Defense';
      case MoveType.status:
        return 'Status';
      case MoveType.signature:
        return 'Signature';
      case MoveType.ultimate:
        return 'Ultimate';
    }
  }

  static MoveType fromString(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'defense':
        return MoveType.defense;
      case 'status':
        return MoveType.status;
      case 'signature':
        return MoveType.signature;
      case 'ultimate':
        return MoveType.ultimate;
      case 'basic':
      default:
        return MoveType.basic;
    }
  }
}

/// A playable move card dealt into the battle hand.
@immutable
class MoveCard {
  const MoveCard({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.type,
    required this.energyDelta,
  });

  final String id;
  final String name;
  final String description;

  /// Material icon for the hand UI.
  final IconData icon;
  final MoveType type;

  /// Positive = generates energy; negative = costs energy.
  final int energyDelta;

  bool get costsEnergy => energyDelta < 0;
  int get energyCost => energyDelta.abs();
}

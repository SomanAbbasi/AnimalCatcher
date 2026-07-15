import 'package:flutter/material.dart';

import '../models/move_card_model.dart';

/// Shared movepools — exactly 6 moves per [CreatureClass]:
/// 2 basic + 1 defense + 1 status + 1 signature + 1 ultimate.
class ClassMovepools {
  ClassMovepools._();

  static List<MoveCard> forClass(CreatureClass cls) {
    switch (cls) {
      case CreatureClass.apex:
        return List<MoveCard>.unmodifiable(_apex);
      case CreatureClass.swarm:
        return List<MoveCard>.unmodifiable(_swarm);
      case CreatureClass.scavenger:
        return List<MoveCard>.unmodifiable(_scavenger);
    }
  }

  // --- Apex (worked example from design brief) ---------------------------
  static const _apex = <MoveCard>[
    MoveCard(
      id: 'apex_quick_strike',
      name: 'Quick Strike',
      description: '12 dmg • +1 Energy',
      icon: Icons.flash_on,
      type: MoveType.basic,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'apex_claw_rake',
      name: 'Claw Rake',
      description: '15 dmg • +1 Energy',
      icon: Icons.pets,
      type: MoveType.basic,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'apex_predator_stance',
      name: 'Predator Stance',
      description: '+30% Dodge 1 turn • +1 Energy',
      icon: Icons.shield,
      type: MoveType.defense,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'apex_rend',
      name: 'Rend',
      description: 'Bleed 6 dmg/turn for 2 turns • -1 Energy',
      icon: Icons.water_drop,
      type: MoveType.status,
      energyDelta: -1,
    ),
    MoveCard(
      id: 'apex_pounce',
      name: 'Pounce',
      description: '20 dmg, ignores 50% defense • +1 Energy',
      icon: Icons.keyboard_double_arrow_up,
      type: MoveType.signature,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'apex_fury',
      name: 'Apex Fury',
      description: '40 dmg cinematic blast • -3 Energy',
      icon: Icons.auto_awesome,
      type: MoveType.ultimate,
      energyDelta: -3,
    ),
  ];

  // --- Swarm (poison / numbers-over-power) -------------------------------
  static const _swarm = <MoveCard>[
    MoveCard(
      id: 'swarm_nibble',
      name: 'Nibble Tide',
      description: '10 dmg • +1 Energy',
      icon: Icons.bug_report,
      type: MoveType.basic,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'swarm_overwhelm',
      name: 'Overwhelm',
      description: '14 dmg • +1 Energy',
      icon: Icons.groups,
      type: MoveType.basic,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'swarm_hive_wall',
      name: 'Hive Wall',
      description: '+30% Dodge 1 turn • +1 Energy',
      icon: Icons.shield_moon,
      type: MoveType.defense,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'swarm_venom',
      name: 'Venom Cloud',
      description: 'Poison 5 dmg/turn for 3 turns • -1 Energy',
      icon: Icons.science,
      type: MoveType.status,
      energyDelta: -1,
    ),
    MoveCard(
      id: 'swarm_colony_crush',
      name: 'Colony Crush',
      description: '22 dmg, ignores 25% defense • +1 Energy',
      icon: Icons.crisis_alert,
      type: MoveType.signature,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'swarm_endless_horde',
      name: 'Endless Horde',
      description: '38 dmg swarm surge • -3 Energy',
      icon: Icons.cyclone,
      type: MoveType.ultimate,
      energyDelta: -3,
    ),
  ];

  // --- Scavenger (speed / dodge / steal) ---------------------------------
  static const _scavenger = <MoveCard>[
    MoveCard(
      id: 'scav_peck',
      name: 'Peck',
      description: '11 dmg • +1 Energy',
      icon: Icons.flight,
      type: MoveType.basic,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'scav_dart',
      name: 'Dart',
      description: '13 dmg • +1 Energy',
      icon: Icons.speed,
      type: MoveType.basic,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'scav_feint',
      name: 'Feint',
      description: '+35% Dodge 1 turn • +1 Energy',
      icon: Icons.visibility_off,
      type: MoveType.defense,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'scav_steal',
      name: 'Pilfer',
      description: 'Steal 1 Energy + 8 dmg • -1 Energy',
      icon: Icons.swipe,
      type: MoveType.status,
      energyDelta: -1,
    ),
    MoveCard(
      id: 'scav_divebomb',
      name: 'Divebomb',
      description: '18 dmg, ignores 40% defense • +1 Energy',
      icon: Icons.arrow_downward,
      type: MoveType.signature,
      energyDelta: 1,
    ),
    MoveCard(
      id: 'scav_sky_plunder',
      name: 'Sky Plunder',
      description: '36 dmg aerial finish • -3 Energy',
      icon: Icons.storm,
      type: MoveType.ultimate,
      energyDelta: -3,
    ),
  ];
}

/// Resolve combat numbers for a move id (hand UI stays descriptive-only).
class MoveCombatData {
  const MoveCombatData({
    this.damage = 0,
    this.defensePierce = 0,
    this.dodgeBonus = 0,
    this.dotDamage = 0,
    this.dotTurns = 0,
    this.stealEnergy = 0,
    this.cinematic = false,
  });

  final int damage;
  final double defensePierce;
  final double dodgeBonus;
  final int dotDamage;
  final int dotTurns;
  final int stealEnergy;
  final bool cinematic;

  static MoveCombatData forId(String id) {
    switch (id) {
      case 'apex_quick_strike':
        return const MoveCombatData(damage: 12);
      case 'apex_claw_rake':
        return const MoveCombatData(damage: 15);
      case 'apex_predator_stance':
        return const MoveCombatData(dodgeBonus: 0.30);
      case 'apex_rend':
        return const MoveCombatData(dotDamage: 6, dotTurns: 2);
      case 'apex_pounce':
        return const MoveCombatData(damage: 20, defensePierce: 0.50);
      case 'apex_fury':
        return const MoveCombatData(damage: 40, cinematic: true);

      case 'swarm_nibble':
        return const MoveCombatData(damage: 10);
      case 'swarm_overwhelm':
        return const MoveCombatData(damage: 14);
      case 'swarm_hive_wall':
        return const MoveCombatData(dodgeBonus: 0.30);
      case 'swarm_venom':
        return const MoveCombatData(dotDamage: 5, dotTurns: 3);
      case 'swarm_colony_crush':
        return const MoveCombatData(damage: 22, defensePierce: 0.25);
      case 'swarm_endless_horde':
        return const MoveCombatData(damage: 38, cinematic: true);

      case 'scav_peck':
        return const MoveCombatData(damage: 11);
      case 'scav_dart':
        return const MoveCombatData(damage: 13);
      case 'scav_feint':
        return const MoveCombatData(dodgeBonus: 0.35);
      case 'scav_steal':
        return const MoveCombatData(damage: 8, stealEnergy: 1);
      case 'scav_divebomb':
        return const MoveCombatData(damage: 18, defensePierce: 0.40);
      case 'scav_sky_plunder':
        return const MoveCombatData(damage: 36, cinematic: true);

      default:
        return const MoveCombatData(damage: 10);
    }
  }
}

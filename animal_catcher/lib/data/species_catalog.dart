import '../models/fauna_card_model.dart';

/// A single entry in the species dex. Seed roster — grow this list over time
/// as more animals are added to the game.
class SpeciesEntry {
  const SpeciesEntry({
    required this.id,
    required this.name,
    required this.rarity,
  });

  /// Dex number, e.g. 1 → displayed as #001.
  final int id;
  final String name;
  final Rarity rarity;

  String get paddedId => '#${id.toString().padLeft(3, '0')}';
}

/// Seed catalog of 10 species (#001–#010). Mirror of [kDummyFaunaCards] names.
const List<SpeciesEntry> kSpeciesCatalog = [
  SpeciesEntry(id: 1, name: 'Street Pigeon', rarity: Rarity.common),
  SpeciesEntry(id: 2, name: 'Garden Ant Swarm', rarity: Rarity.common),
  SpeciesEntry(id: 3, name: 'House Cat', rarity: Rarity.uncommon),
  SpeciesEntry(id: 4, name: 'Urban Crow', rarity: Rarity.uncommon),
  SpeciesEntry(id: 5, name: 'Raccoon Bandit', rarity: Rarity.uncommon),
  SpeciesEntry(id: 6, name: 'Red Fox', rarity: Rarity.rare),
  SpeciesEntry(id: 7, name: 'Golden Eagle', rarity: Rarity.rare),
  SpeciesEntry(id: 8, name: 'Timber Wolf Alpha', rarity: Rarity.rare),
  SpeciesEntry(id: 9, name: 'Dire Wolf', rarity: Rarity.legendary),
  SpeciesEntry(id: 10, name: 'Snow Leopard', rarity: Rarity.legendary),
];

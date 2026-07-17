import '../models/fauna_card_model.dart';

/// Lightweight test seeds — name + rarity only.
///
/// No combat stats and no hardcoded image paths: the real, shared reference
/// photo / category / Wikipedia link are fetched live from the backend
/// (`/api/species` -> iNaturalist) at guest-login time, so test data exercises
/// the actual production path instead of a mock.
///
/// Names are chosen to be reliably resolvable by iNaturalist so every tile
/// gets a real reference photo.
const List<FaunaCard> kSpeciesSeeds = [
  FaunaCard(name: 'Domestic Cat', rarity: Rarity.uncommon),
  FaunaCard(name: 'Red Fox', rarity: Rarity.uncommon),
  FaunaCard(name: 'Raccoon', rarity: Rarity.uncommon),
  FaunaCard(name: 'Rock Pigeon', rarity: Rarity.common),
  FaunaCard(name: 'American Crow', rarity: Rarity.uncommon),
  FaunaCard(name: 'Red Kangaroo', rarity: Rarity.uncommon),
  FaunaCard(name: 'Koala', rarity: Rarity.rare),
  FaunaCard(name: 'Green Sea Turtle', rarity: Rarity.rare),
  FaunaCard(name: 'Golden Eagle', rarity: Rarity.rare),
  FaunaCard(name: 'Snow Leopard', rarity: Rarity.legendary),
];

/// The species shown in the Collection dex grid.
const List<FaunaCard> kSpeciesDexSeed = kSpeciesSeeds;

/// Offline fallback pool used by the scanner when the backend is unreachable.
const List<FaunaCard> kSandboxStarterCards = kSpeciesSeeds;

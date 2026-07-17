import 'fauna_card_model.dart';

/// One species in the fixed master catalog (the dex). Mirrors the backend
/// `CatalogEntry` and the bundled `assets/data/species_catalog.json` schema.
class CatalogEntry {
  const CatalogEntry({
    required this.taxonId,
    required this.dexNumber,
    required this.name,
    this.scientificName = '',
    this.category = 'Wildlife',
    this.rarity = Rarity.common,
    this.referencePhotoUrl = '',
  });

  final int taxonId;
  final int dexNumber;
  final String name;
  final String scientificName;
  final String category;
  final Rarity rarity;
  final String referencePhotoUrl;

  bool get hasReferencePhoto => referencePhotoUrl.trim().isNotEmpty;

  factory CatalogEntry.fromJson(Map<String, dynamic> json) {
    return CatalogEntry(
      taxonId: _asInt(json['taxon_id'] ?? json['taxonId']) ?? 0,
      dexNumber: _asInt(json['dex_number'] ?? json['dexNumber']) ?? 0,
      name: (json['name'] ?? '').toString(),
      scientificName:
          (json['scientific_name'] ?? json['scientificName'] ?? '').toString(),
      category: (json['category'] ?? 'Wildlife').toString(),
      rarity: RarityX.fromString(json['rarity']?.toString()),
      referencePhotoUrl:
          (json['reference_photo_url'] ?? json['referencePhotoUrl'] ?? '')
              .toString(),
    );
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../debug/dummy_data.dart';
import '../models/catalog_entry.dart';
import '../models/fauna_card_model.dart';
import '../models/profile_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class _StorageKeys {
  static const session = 'fauna_session_v1';
}

/// Global session state: profile, currencies, and the player's collection.
class SessionProvider extends ChangeNotifier {
  SessionProvider({
    AuthService? authService,
    FlutterSecureStorage? storage,
    ApiService? apiService,
  })  : _auth = authService ?? AuthService(),
        _storage = storage ?? const FlutterSecureStorage(),
        _api = apiService ?? ApiService();

  final AuthService _auth;
  final FlutterSecureStorage _storage;
  final ApiService _api;

  PlayerProfile? _profile;
  bool _initializing = true;
  bool _isGuest = false;

  final List<FaunaCard> _collection = [];
  List<CatalogEntry> _catalog = [];

  PlayerProfile? get profile => _profile;
  bool get isLoggedIn => _profile != null;
  bool get initializing => _initializing;
  bool get isGuest => _isGuest;
  List<FaunaCard> get collection => List.unmodifiable(_collection);

  /// The fixed master catalog (the dex), ordered by dex number.
  List<CatalogEntry> get catalog => List.unmodifiable(_catalog);

  /// Taxon ids the player has collected (for dex unlock matching).
  Set<int> get caughtTaxonIds => {
        for (final c in _collection)
          if (c.taxonId != null) c.taxonId!,
      };

  bool isCaughtTaxon(int taxonId) =>
      _collection.any((c) => c.taxonId == taxonId);

  FaunaCard? cardForTaxon(int taxonId) {
    for (final c in _collection) {
      if (c.taxonId == taxonId) return c;
    }
    return null;
  }

  int get gold => _profile?.gold ?? 0;
  int get wildEssence => _profile?.wildEssence ?? 0;

  int get xp => _profile?.xp ?? 0;
  int get level => _profile?.level ?? 1;
  int get xpIntoLevel => _profile?.xpIntoLevel ?? 0;
  int get xpForNextLevel => _profile?.nextLevelThreshold ?? 100;
  double get levelProgress => _profile?.levelProgress ?? 0.0;

  /// Level curve mirrored from the backend: level = floor(sqrt(xp/100)) + 1.
  static int _levelForXp(int xp) {
    if (xp <= 0) return 1;
    return (math.sqrt(xp / 100)).floor() + 1;
  }

  bool hasCaught(String speciesName) =>
      _collection.any((c) => c.name.toLowerCase() == speciesName.toLowerCase());

  FaunaCard? cardForSpecies(String speciesName) {
    for (final c in _collection) {
      if (c.name.toLowerCase() == speciesName.toLowerCase()) return c;
    }
    return null;
  }

  Future<void> bootstrap() async {
    try {
      final raw = await _storage.read(key: _StorageKeys.session);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _profile = PlayerProfile.fromJson(json);
      }
    } catch (_) {
      _profile = null;
    } finally {
      _initializing = false;
      notifyListeners();
    }
    // Catalog is public; load it regardless of auth so the dex is ready.
    await loadCatalog();
    // Restore a returning player's collection so the dex reflects reality.
    if (_profile != null && !_isGuest) {
      await _hydrateInventory(_profile!.userId);
    }
  }

  /// Load the master catalog: backend first, bundled asset as a fallback so
  /// the dex works offline / in guest mode. Identical data either way.
  Future<void> loadCatalog() async {
    if (_catalog.isNotEmpty) return;
    try {
      final remote = await _api.fetchCatalog();
      if (remote.isNotEmpty) {
        _catalog = remote;
        notifyListeners();
        return;
      }
    } catch (_) {
      // Fall through to the bundled asset.
    }
    try {
      final raw =
          await rootBundle.loadString('assets/data/species_catalog.json');
      final list = jsonDecode(raw) as List<dynamic>;
      _catalog = list
          .map((e) => CatalogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {
      // No catalog available; the dex will simply be empty.
    }
  }

  /// Pull the player's saved cards from the backend into `_collection`.
  Future<void> _hydrateInventory(String userId) async {
    try {
      final cards = await _api.fetchInventory(userId);
      _collection
        ..clear()
        ..addAll(cards);
      notifyListeners();
    } catch (_) {
      // Non-fatal: keep whatever is already in memory.
    }
  }

  /// Debug guest path (kDebugMode button).
  Future<void> enterGuestMode() {
    return enterSandboxLogin(username: 'Guest Hunter');
  }

  /// Automatic sandbox profile when Supabase is unavailable.
  ///
  /// The profile is set immediately (so the UI advances into the app), then the
  /// 10 seed species are hydrated via the real `/api/species` lookup so testing
  /// exercises the live path. Each species is added as it resolves.
  Future<void> enterSandboxLogin({String username = 'Soman_Test_ID'}) async {
    _isGuest = true;
    _profile = PlayerProfile(
      userId: 'Soman_Test_ID',
      username: username,
      gold: 150,
      wildEssence: 30,
      startingClass: StartingClass.apexHunter,
      createdAt: DateTime.now(),
    );
    _collection.clear();
    notifyListeners();
    await _hydrateSeedSpecies();
  }

  /// Fetch the shared reference data for each seed species from the backend
  /// and add the resulting cards to the collection. Degrades gracefully: if a
  /// lookup fails the card is still added (SafeNetworkImage shows a placeholder).
  Future<void> _hydrateSeedSpecies() async {
    for (final seed in kSpeciesSeeds) {
      FaunaCard card = seed;
      try {
        final info = await _api.fetchSpeciesInfo(seed.name);
        card = seed.copyWith(
          referencePhotoUrl: info.referencePhotoUrl,
          category: info.category,
          wikiUrl: info.wikiUrl,
        );
      } catch (_) {
        // Keep the bare seed; the tile falls back to a muted pets placeholder.
      }
      _addToCollection(card);
      notifyListeners();
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String username,
    required StartingClass startingClass,
  }) async {
    try {
      final result = await _auth.signUp(
        email: email,
        password: password,
        username: username,
        startingClass: startingClass.label,
      );
      _isGuest = false;
      _profile = PlayerProfile(
        userId: result.userId,
        username: username,
        startingClass: startingClass,
        gold: 150,
        wildEssence: 30,
        createdAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
      await _hydrateProfile(result.userId);
      await _hydrateInventory(result.userId);
    } catch (_) {
      // Supabase down — fall through to sandbox so onboarding never bricks.
      await enterSandboxLogin(
        username: username.isEmpty ? 'Soman_Test_ID' : username,
      );
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    try {
      final result = await _auth.signIn(email: email, password: password);
      _isGuest = false;
      _profile ??= PlayerProfile(
        userId: result.userId,
        username: email.split('@').first,
        gold: 150,
        wildEssence: 30,
        createdAt: DateTime.now(),
      );
      await _persist();
      notifyListeners();
      await _hydrateProfile(result.userId);
      await _hydrateInventory(result.userId);
    } catch (_) {
      await enterSandboxLogin(username: email.split('@').first);
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      await _auth.signInWithGoogle();
    } catch (_) {
      await enterSandboxLogin();
    }
  }

  Future<void> logout() async {
    if (!_isGuest) {
      await _auth.signOut();
      await _storage.delete(key: _StorageKeys.session);
    }
    _profile = null;
    _isGuest = false;
    _collection.clear();
    notifyListeners();
  }

  /// Apply the XP outcome of a scan to the profile.
  ///
  /// For authenticated players the server is authoritative, so [xp]/[level]
  /// from the [ScanResult] are applied directly. In guest/sandbox mode the
  /// server returns zeros, so XP is computed locally (+50 if the species is new
  /// to the collection, otherwise +5) to keep the bar animating.
  void applyScanXp({
    required int awarded,
    required int xp,
    required int level,
    required bool wasNew,
  }) {
    if (_profile == null) return;
    if (!_isGuest && (xp > 0 || awarded > 0)) {
      _profile = _profile!.copyWith(xp: xp, level: level);
      _persist();
    } else {
      final delta = wasNew ? 50 : 5;
      final newXp = _profile!.xp + delta;
      _profile = _profile!.copyWith(xp: newXp, level: _levelForXp(newXp));
    }
    notifyListeners();
  }

  /// Pull authoritative xp/level from the backend after auth.
  Future<void> _hydrateProfile(String userId) async {
    try {
      final summary = await _api.fetchProfile(userId);
      if (_profile != null && _profile!.userId == userId) {
        _profile = _profile!.copyWith(
          xp: summary.xp,
          level: summary.level,
        );
        await _persist();
        notifyListeners();
      }
    } catch (_) {
      // Non-fatal: keep local defaults if the profile fetch fails.
    }
  }

  void updateLocation(double lat, double lng) {
    if (_profile == null) return;
    _profile = _profile!.copyWith(locationLat: lat, locationLng: lng);
    _persist();
    notifyListeners();
  }

  void addRewards({int gold = 0, int wildEssence = 0}) {
    if (_profile == null) return;
    _profile = _profile!.copyWith(
      gold: _profile!.gold + gold,
      wildEssence: _profile!.wildEssence + wildEssence,
    );
    if (!_isGuest) _persist();
    notifyListeners();
  }

  void addToCollection(FaunaCard card) {
    _addToCollection(card);
    notifyListeners();
  }

  void _addToCollection(FaunaCard card) {
    final idx = _collection.indexWhere((c) {
      if (card.taxonId != null && c.taxonId != null) {
        return c.taxonId == card.taxonId;
      }
      return c.name.toLowerCase() == card.name.toLowerCase();
    });
    if (idx >= 0) {
      _collection[idx] = card;
    } else {
      _collection.add(card);
    }
  }

  Future<void> _persist() async {
    if (_profile == null || _isGuest) return;
    await _storage.write(
      key: _StorageKeys.session,
      value: jsonEncode(_profile!.toJson()),
    );
  }
}

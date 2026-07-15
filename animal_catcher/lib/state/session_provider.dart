import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../debug/dummy_data.dart';
import '../models/fauna_card_model.dart';
import '../models/profile_model.dart';
import '../services/auth_service.dart';

class _StorageKeys {
  static const session = 'fauna_session_v1';
}

/// Global lobby state: profile, currencies, inventory, battle team.
class SessionProvider extends ChangeNotifier {
  SessionProvider({AuthService? authService, FlutterSecureStorage? storage})
      : _auth = authService ?? AuthService(),
        _storage = storage ?? const FlutterSecureStorage();

  final AuthService _auth;
  final FlutterSecureStorage _storage;

  PlayerProfile? _profile;
  bool _initializing = true;
  bool _isGuest = false;

  final List<FaunaCard> _battleTeam = [];
  final List<FaunaCard> _collection = [];

  PlayerProfile? get profile => _profile;
  bool get isLoggedIn => _profile != null;
  bool get initializing => _initializing;
  bool get isGuest => _isGuest;
  List<FaunaCard> get battleTeam => List.unmodifiable(_battleTeam);
  List<FaunaCard> get collection => List.unmodifiable(_collection);

  int get gold => _profile?.gold ?? 0;
  int get wildEssence => _profile?.wildEssence ?? 0;

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
  }

  /// Debug guest path (kDebugMode button).
  void enterGuestMode() {
    enterSandboxLogin(username: 'Guest Hunter');
  }

  /// Automatic sandbox profile when Supabase is unavailable.
  void enterSandboxLogin({String username = 'Soman_Test_ID'}) {
    _isGuest = true;
    _profile = PlayerProfile(
      userId: 'Soman_Test_ID',
      username: username,
      gold: 150,
      wildEssence: 30,
      startingClass: StartingClass.apexHunter,
      createdAt: DateTime.now(),
    );
    _collection
      ..clear()
      ..addAll(kSandboxStarterCards);
    _battleTeam
      ..clear()
      ..addAll(kSandboxStarterCards);
    notifyListeners();
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
    } catch (_) {
      // Supabase down — fall through to sandbox so onboarding never bricks.
      enterSandboxLogin(username: username.isEmpty ? 'Soman_Test_ID' : username);
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
    } catch (_) {
      enterSandboxLogin(username: email.split('@').first);
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      await _auth.signInWithGoogle();
    } catch (_) {
      enterSandboxLogin();
    }
  }

  Future<void> logout() async {
    if (!_isGuest) {
      await _auth.signOut();
      await _storage.delete(key: _StorageKeys.session);
    }
    _profile = null;
    _isGuest = false;
    _battleTeam.clear();
    _collection.clear();
    notifyListeners();
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

  void addToTeam(FaunaCard card) {
    _addToCollection(card);
    if (_battleTeam.length < 6) {
      _battleTeam.add(card);
    }
    notifyListeners();
  }

  void _addToCollection(FaunaCard card) {
    final idx = _collection.indexWhere(
      (c) => c.name.toLowerCase() == card.name.toLowerCase(),
    );
    if (idx >= 0) {
      _collection[idx] = card;
    } else {
      _collection.add(card);
    }
  }

  void removeFromTeam(FaunaCard card) {
    _battleTeam.remove(card);
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_profile == null || _isGuest) return;
    await _storage.write(
      key: _StorageKeys.session,
      value: jsonEncode(_profile!.toJson()),
    );
  }
}

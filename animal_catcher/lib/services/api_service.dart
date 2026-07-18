import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/catalog_entry.dart';
import '../models/fauna_card_model.dart';

/// Distinguishes the different failure modes the scanning UI must handle
/// distinctly (network vs anti-cheat vs generic).
enum ScanErrorType { network, timeout, antiCheat, server, unknown }

/// Typed error thrown by [ApiService] so the UI can branch on [type].
class ApiException implements Exception {
  ApiException(this.type, this.message);

  final ScanErrorType type;
  final String message;

  @override
  String toString() => 'ApiException($type): $message';
}

/// Result of a successful scan, including whether it is a Mystery Spawn.
class ScanResult {
  ScanResult({
    required this.card,
    required this.saved,
    required this.isMystery,
    this.localSandbox = false,
    this.xpAwarded = 0,
    this.xp = 0,
    this.level = 1,
    this.taxonId,
  });

  final FaunaCard card;
  final bool saved;
  final bool isMystery;
  final bool localSandbox;
  final int xpAwarded;
  final int xp;
  final int level;
  final int? taxonId;
}

/// A player's dex completion, overall and per category.
class CollectionProgress {
  CollectionProgress({
    this.total = 0,
    this.caught = 0,
    this.caughtTaxonIds = const {},
    this.byCategory = const {},
  });

  final int total;
  final int caught;
  final Set<int> caughtTaxonIds;

  /// Category -> (caught, total).
  final Map<String, ({int caught, int total})> byCategory;

  factory CollectionProgress.fromJson(Map<String, dynamic> json) {
    final ids = <int>{};
    for (final v in (json['caught_taxon_ids'] as List<dynamic>? ?? [])) {
      final id = ProfileSummary._asInt(v);
      if (id != 0) ids.add(id);
    }
    final byCat = <String, ({int caught, int total})>{};
    final raw = json['by_category'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map) {
          byCat[key.toString()] = (
            caught: ProfileSummary._asInt(value['caught']),
            total: ProfileSummary._asInt(value['total']),
          );
        }
      });
    }
    return CollectionProgress(
      total: ProfileSummary._asInt(json['total']),
      caught: ProfileSummary._asInt(json['caught']),
      caughtTaxonIds: ids,
      byCategory: byCat,
    );
  }
}

/// Read-only profile summary returned by `/api/profile/{id}` and used for
/// friend profiles (`FriendSummary` on the backend).
class ProfileSummary {
  ProfileSummary({
    required this.userId,
    required this.username,
    this.xp = 0,
    this.level = 1,
    this.speciesCount = 0,
  });

  final String userId;
  final String username;
  final int xp;
  final int level;
  final int speciesCount;

  factory ProfileSummary.fromJson(Map<String, dynamic> json) => ProfileSummary(
        userId: (json['user_id'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
        xp: _asInt(json['xp']),
        level: _asInt(json['level'], 1),
        speciesCount: _asInt(json['species_count']),
      );

  static int _asInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  static int? _asIntOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}

/// Lightweight user record for search results and incoming friend requests.
class UserSearchResult {
  UserSearchResult({
    required this.userId,
    required this.username,
    this.level = 1,
  });

  final String userId;
  final String username;
  final int level;

  factory UserSearchResult.fromJson(Map<String, dynamic> json) =>
      UserSearchResult(
        userId: (json['user_id'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
        level: ProfileSummary._asInt(json['level'], 1),
      );
}

/// Shared, consistent-for-everyone reference data for one species.
class SpeciesInfo {
  SpeciesInfo({
    required this.name,
    required this.referencePhotoUrl,
    required this.category,
    required this.wikiUrl,
    this.taxonId,
    this.scientificName = '',
  });

  final String name;
  final String referencePhotoUrl;
  final String category;
  final String wikiUrl;
  final int? taxonId;
  final String scientificName;
}

/// REST client for the FastAPI backend (`/api/scan`, `/api/inventory/...`).
class ApiService {
  ApiService({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? ApiConfig.scanTimeout;

  final http.Client _client;
  final Duration _timeout;

  Uri _uri(String path) => Uri.parse('${ApiConfig.baseUrl}$path');

  /// Send a base64 image to the backend and mint a card.
  ///
  /// Throws [ApiException] with:
  ///  - [ScanErrorType.antiCheat] on HTTP 400 (non-living target)
  ///  - [ScanErrorType.network]/[ScanErrorType.timeout] on connectivity issues
  ///  - [ScanErrorType.server] on other non-2xx responses
  Future<ScanResult> scan({
    required String userId,
    required String imageBase64,
    double? lat,
    double? lng,
  }) async {
    http.Response response;
    try {
      response = await _client
          .post(
            _uri('/api/scan'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': userId,
              'image_base64': imageBase64,
              'location_lat': lat,
              'location_lng': lng,
            }),
          )
          .timeout(_timeout);
    } on Exception catch (e) {
      // SocketException, TimeoutException, ClientException all land here.
      final isTimeout = e.toString().toLowerCase().contains('timeout');
      throw ApiException(
        isTimeout ? ScanErrorType.timeout : ScanErrorType.network,
        isTimeout
            ? 'Scan timed out. The scanner needs a clearer photo or a longer wait — try again.'
            : 'Could not reach the scanner. Start the backend and run: adb reverse tcp:8000 tcp:8000',
      );
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ScanResult(
        card: FaunaCard.fromJson(body['card'] as Map<String, dynamic>),
        saved: body['saved'] == true,
        isMystery: body['is_mystery'] == true,
        localSandbox: body['local_sandbox'] == true,
        xpAwarded: ProfileSummary._asInt(body['xp_awarded']),
        xp: ProfileSummary._asInt(body['xp']),
        level: ProfileSummary._asInt(body['level'], 1),
        taxonId: ProfileSummary._asIntOrNull(body['taxon_id']),
      );
    }

    if (response.statusCode == 400) {
      // Anti-cheat: non-living target.
      throw ApiException(
        ScanErrorType.antiCheat,
        _extractDetail(response.body) ??
            'Anomaly Detected: Non-Living Target.',
      );
    }

    if (response.statusCode == 503) {
      throw ApiException(
        ScanErrorType.server,
        _extractDetail(response.body) ??
            'Species scanner unavailable. Check the backend is running '
            'and try again.',
      );
    }

    throw ApiException(
      ScanErrorType.server,
      _extractDetail(response.body) ??
          'The scanner malfunctioned (code ${response.statusCode}).',
    );
  }

  /// Fetch the shared reference data (photo/category/wiki) for a species name.
  ///
  /// Hits the cache-first `/api/species` endpoint so every player receives the
  /// identical reference photo and category for a given species.
  Future<SpeciesInfo> fetchSpeciesInfo(String name) async {
    http.Response response;
    try {
      response = await _client
          .get(_uri('/api/species?name=${Uri.encodeQueryComponent(name)}'))
          .timeout(_timeout);
    } on Exception {
      throw ApiException(
        ScanErrorType.network,
        'Could not reach the species service.',
      );
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return SpeciesInfo(
        name: (body['name'] ?? name).toString(),
        referencePhotoUrl: (body['reference_photo_url'] ?? '').toString(),
        category: (body['category'] ?? 'Wildlife').toString(),
        wikiUrl: (body['wiki_url'] ?? '').toString(),
        taxonId: ProfileSummary._asIntOrNull(body['taxon_id']),
        scientificName: (body['scientific_name'] ?? '').toString(),
      );
    }

    throw ApiException(
      ScanErrorType.server,
      'Failed to load species info (code ${response.statusCode}).',
    );
  }

  /// Fetch the player's full collection.
  Future<List<FaunaCard>> fetchInventory(String userId) async {
    http.Response response;
    try {
      response =
          await _client.get(_uri('/api/inventory/$userId')).timeout(_timeout);
    } on Exception {
      throw ApiException(
        ScanErrorType.network,
        'Could not load your collection. Check your connection.',
      );
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final cards = (body['cards'] as List<dynamic>? ?? [])
          .map((c) => FaunaCard.fromJson(c as Map<String, dynamic>))
          .toList();
      return cards;
    }

    throw ApiException(
      ScanErrorType.server,
      'Failed to load inventory (code ${response.statusCode}).',
    );
  }

  /// Fetch a player's profile summary (xp/level/species count).
  Future<ProfileSummary> fetchProfile(String userId) async {
    http.Response response;
    try {
      response =
          await _client.get(_uri('/api/profile/$userId')).timeout(_timeout);
    } on Exception {
      throw ApiException(
        ScanErrorType.network,
        'Could not load profile. Check your connection.',
      );
    }
    if (response.statusCode == 200) {
      return ProfileSummary.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw ApiException(
      ScanErrorType.server,
      'Failed to load profile (code ${response.statusCode}).',
    );
  }

  // --------------------------------------------------------------------
  // Species catalog / dex
  // --------------------------------------------------------------------
  /// Fetch the fixed master catalog (the dex), ordered by dex number.
  Future<List<CatalogEntry>> fetchCatalog() async {
    http.Response response;
    try {
      response = await _client.get(_uri('/api/catalog')).timeout(_timeout);
    } on Exception {
      throw ApiException(ScanErrorType.network, 'Could not load catalog.');
    }
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((e) => CatalogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(
      ScanErrorType.server,
      'Could not load catalog (code ${response.statusCode}).',
    );
  }

  /// Fetch a player's dex completion (overall + per category).
  Future<CollectionProgress> fetchCollectionProgress(String userId) async {
    http.Response response;
    try {
      response = await _client
          .get(_uri('/api/collection/progress/$userId'))
          .timeout(_timeout);
    } on Exception {
      throw ApiException(ScanErrorType.network, 'Could not load progress.');
    }
    if (response.statusCode == 200) {
      return CollectionProgress.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw ApiException(
      ScanErrorType.server,
      'Could not load progress (code ${response.statusCode}).',
    );
  }

  // --------------------------------------------------------------------
  // Friends
  // --------------------------------------------------------------------
  /// Search players by (partial) username, excluding the requester.
  Future<List<UserSearchResult>> searchUsers(
    String username,
    String requesterId,
  ) async {
    final uri = _uri(
      '/api/users/search?username=${Uri.encodeQueryComponent(username)}'
      '&requester_id=${Uri.encodeQueryComponent(requesterId)}',
    );
    http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on Exception {
      throw ApiException(ScanErrorType.network, 'Search failed.');
    }
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((e) => UserSearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(
      ScanErrorType.server,
      'Search failed (code ${response.statusCode}).',
    );
  }

  /// Send a pending friend request from [userId] -> [friendId].
  Future<void> sendFriendRequest(String userId, String friendId) =>
      _friendAction('/api/friends/request', userId, friendId);

  /// Accept the pending request that [friendId] sent to [userId].
  Future<void> acceptFriendRequest(String userId, String friendId) =>
      _friendAction('/api/friends/accept', userId, friendId);

  Future<void> _friendAction(
    String path,
    String userId,
    String friendId,
  ) async {
    http.Response response;
    try {
      response = await _client
          .post(
            _uri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'user_id': userId, 'friend_id': friendId}),
          )
          .timeout(_timeout);
    } on Exception {
      throw ApiException(ScanErrorType.network, 'Request failed.');
    }
    if (response.statusCode == 200) return;
    throw ApiException(
      ScanErrorType.server,
      _extractDetail(response.body) ??
          'Request failed (code ${response.statusCode}).',
    );
  }

  /// List a player's accepted friends.
  Future<List<ProfileSummary>> fetchFriends(String userId) async {
    return _fetchProfileList('/api/friends/$userId');
  }

  /// List pending friend requests addressed to this player.
  Future<List<UserSearchResult>> fetchIncomingRequests(String userId) async {
    http.Response response;
    try {
      response = await _client
          .get(_uri('/api/friends/$userId/requests'))
          .timeout(_timeout);
    } on Exception {
      throw ApiException(ScanErrorType.network, 'Could not load requests.');
    }
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((e) => UserSearchResult.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(
      ScanErrorType.server,
      'Could not load requests (code ${response.statusCode}).',
    );
  }

  /// The read-only friend profile is the same shape as a profile summary.
  Future<ProfileSummary> fetchFriendProfile(String userId) =>
      fetchProfile(userId);

  Future<List<ProfileSummary>> _fetchProfileList(String path) async {
    http.Response response;
    try {
      response = await _client.get(_uri(path)).timeout(_timeout);
    } on Exception {
      throw ApiException(ScanErrorType.network, 'Could not load friends.');
    }
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list
          .map((e) => ProfileSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(
      ScanErrorType.server,
      'Could not load friends (code ${response.statusCode}).',
    );
  }

  /// Pull the human-readable `detail` field out of a FastAPI error body.
  String? _extractDetail(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {
      // Non-JSON body -> ignore.
    }
    return null;
  }

  void dispose() => _client.close();
}

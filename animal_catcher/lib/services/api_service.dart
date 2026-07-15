import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
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
  });

  final FaunaCard card;
  final bool saved;
  final bool isMystery;
  final bool localSandbox;
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
        'Could not reach the Rift servers. Check your connection.',
      );
    }

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ScanResult(
        card: FaunaCard.fromJson(body['card'] as Map<String, dynamic>),
        saved: body['saved'] == true,
        isMystery: body['is_mystery'] == true,
        localSandbox: body['local_sandbox'] == true,
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

    throw ApiException(
      ScanErrorType.server,
      _extractDetail(response.body) ??
          'The Rift scanner malfunctioned (code ${response.statusCode}).',
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

import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// A resolved device location.
class DeviceLocation {
  const DeviceLocation(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// Location acquisition + a zoo/aquarium geofence backed by the public
/// Overpass API (no API key required).
///
/// The geofence deliberately **fails open**: any timeout, network error, or
/// non-200 response resolves to `false` (not near a zoo) so a flaky connection
/// never blocks a legitimate wild scan.
class GeofenceService {
  GeofenceService({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 6);

  final http.Client _client;
  final Duration _timeout;

  static final Uri _overpassUri =
      Uri.parse('https://overpass-api.de/api/interpreter');

  /// Best-effort current device location. Returns `null` when location
  /// services are disabled or permission is denied (caller should fail open).
  Future<DeviceLocation?> currentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(_timeout);
      return DeviceLocation(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Returns `true` when the coordinates are within ~1.5km of a zoo or
  /// aquarium. Fails open (`false`) on any timeout/error/non-200.
  Future<bool> isNearZooOrAquarium(double lat, double lng) async {
    final query = '[out:json];'
        '('
        'node["tourism"="zoo"](around:1500,$lat,$lng);'
        'way["tourism"="zoo"](around:1500,$lat,$lng);'
        'node["tourism"="aquarium"](around:1500,$lat,$lng);'
        'way["tourism"="aquarium"](around:1500,$lat,$lng);'
        ');'
        'out center;';
    try {
      final response = await _client
          .post(_overpassUri, body: {'data': query})
          .timeout(_timeout);
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return false;
      final elements = decoded['elements'];
      return elements is List && elements.isNotEmpty;
    } catch (_) {
      // Fail open: never block a legitimate wild scan on a flaky network.
      return false;
    }
  }

  void dispose() => _client.close();
}

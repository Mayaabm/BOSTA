import 'dart:convert';
import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TripService {
  // IMPORTANT: For production, this should be loaded from a secure configuration
  // (e.g., --dart-define) rather than being hardcoded.
  static const String _mapboxAccessToken =
      'pk.eyJ1IjoibWF5YWJlMzMzIiwiYSI6ImNtaWcxZmV6ZTAyOXozY3FzMHZqYzhrYzgifQ.qJnThdfDGW9MUkDNrvoEoA';

  /// Returns the Mapbox access token.
  static String getMapboxAccessToken() {
    return _mapboxAccessToken;
  }

  /// Checks if the authenticated driver has an active trip.
  /// Returns the trip ID if active, otherwise null.
  static Future<String?> checkForActiveTrip(String token) async {
    // This is a placeholder implementation. You would typically have an endpoint
    // like /api/driver/me/active-trip/ that returns the active trip details.
    // For now, we'll assume a trip is active if the driver has a profile.
    // A real implementation would be more robust.
    final uri = Uri.parse(ApiEndpoints.driverProfile);
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      // Assuming the driver profile response includes an 'active_trip_id'
      return data['active_trip_id']?.toString();
    }
    return null;
  }

  /// Ends the specified trip.
  static Future<void> endTrip(String token, String tripId) async {
    final uri = Uri.parse(ApiEndpoints.endTrip(tripId));
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      debugPrint("Trip $tripId ended successfully.");
    } else {
      String errorMessage = 'Failed to end trip. Status: ${response.statusCode}';
      try {
        final body = json.decode(response.body);
        errorMessage += ' - ${body['detail'] ?? response.body}';
      } catch (_) {
        errorMessage += ' - ${response.body}';
      }
      throw Exception(errorMessage);
    }
  }
}
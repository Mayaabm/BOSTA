import 'dart:convert';
import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

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

  /// Starts a new trip based on the driver's saved setup.
  /// Returns the new trip ID on success.
  static Future<String> startNewTrip(AuthService authService, {
    String? startStopId,
    String? endStopId,
  }) async {
    final requestBody = {
      // The new endpoint derives the route from the driver's profile,
      // so we don't need to send stop IDs. It's simpler.
    };

    final token = authService.currentState.token;
    if (token == null) {
      throw Exception('Authentication token not found.');
    }

    // --- FIX: Use the correct endpoint for creating a trip ---
    // The `create_and_start_trip` endpoint is designed for this exact purpose.
    debugPrint("[TripService.startNewTrip] Sending request to create new trip via create_and_start_trip endpoint.");
    final uri = Uri.parse(ApiEndpoints.createAndStartTrip);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(requestBody), // Body can be empty, but we send it for consistency
    );

    if (response.statusCode == 201) { // Expect 201 Created
      final responseData = json.decode(response.body);
      final finalTripId = responseData['trip_id']?.toString();
      debugPrint("[TripService.startNewTrip] Received 201 Created. New trip ID: $finalTripId");

      // --- FIX: After creating the trip, immediately re-fetch the driver's profile. ---
      // This ensures the AuthState is updated with the new active_trip_id before
      // navigating to the dashboard.
      debugPrint("[TripService.startNewTrip] Refreshing driver profile to get the new active_trip_id...");
      await authService.fetchAndSetDriverProfile();

      // After polling, if the trip ID is still null, then creation has failed.
      if (finalTripId == null) {
        throw Exception('Failed to confirm active trip ID from backend after creation.');
      }
      return finalTripId;
    } else {
      final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
      throw Exception('Failed to create trip. Status: ${response.statusCode}. Reason: ${errorBody['error'] ?? response.body}');
    }
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

  /// Fetch ETA from driver's current position to rider's location.
  /// Returns a map with distance_m and estimated_arrival_minutes, or null if failed.
  static Future<Map<String, dynamic>?> fetchEta({
    required String busId,
    required double riderLat,
    required double riderLon,
    required String token,
  }) async {
    debugPrint("\n=== FETCH ETA DEBUG ===");
    debugPrint("[TripService.fetchEta] Bus ID: $busId");
    debugPrint("[TripService.fetchEta] Rider position: LAT=$riderLat, LON=$riderLon");

    final uri = Uri.parse(
      '${ApiEndpoints.eta}?bus_id=$busId&target_lat=$riderLat&target_lon=$riderLon',
    );
    
    debugPrint("[TripService.fetchEta] URI: $uri");

    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint("[TripService.fetchEta] Response status: ${response.statusCode}");
      debugPrint("[TripService.fetchEta] Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        debugPrint("[TripService.fetchEta] Parsed ETA data: $data");
        debugPrint("=== FETCH ETA DEBUG (SUCCESS) ===\n");
        return data;
      } else {
        debugPrint("[TripService.fetchEta] Failed with status ${response.statusCode}");
        debugPrint("=== FETCH ETA DEBUG (FAILED) ===\n");
        return null;
      }
    } catch (e) {
      debugPrint("[TripService.fetchEta] Exception: $e");
      debugPrint("=== FETCH ETA DEBUG (EXCEPTION) ===\n");
      return null;
    }
  }
}
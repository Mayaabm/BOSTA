import 'dart:convert';
import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'logger.dart';

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
    // Include route and stop choices to ensure the backend creates the trip
    // with the driver's currently-selected route and stops.
    final requestBody = <String, dynamic>{};
    final selectedRouteId = authService.currentState.assignedRoute?.id;
    final selectedStart = authService.currentState.selectedStopId ?? startStopId;
    final selectedEnd = authService.currentState.selectedEndStopId ?? endStopId;
    if (selectedRouteId != null) requestBody['route_id'] = selectedRouteId;
    if (selectedStart != null) requestBody['start_stop_id'] = selectedStart;
    if (selectedEnd != null) requestBody['end_stop_id'] = selectedEnd;

    final token = authService.currentState.token;
    if (token == null) {
      throw Exception('Authentication token not found.');
    }

    // --- FIX: Use the correct endpoint for creating a trip ---
    // The `create_and_start_trip` endpoint is designed for this exact purpose.
    Logger.info('TripService', 'createAndStartTrip body=${requestBody}');
    final uri = Uri.parse(ApiEndpoints.createAndStartTrip);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 201) { // Expect 201 Created
      final responseData = json.decode(response.body);
      final finalTripId = responseData['trip_id']?.toString();
      Logger.info('TripService', 'created trip_id=$finalTripId');

      // --- FIX: After creating the trip, immediately re-fetch the driver's profile. ---
      // This ensures the AuthState is updated with the new active_trip_id before
      // navigating to the dashboard.
      Logger.debug('TripService', 'refreshing profile to get active_trip_id');
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
    try {
      // Step 1: Fetch the bus's current location from our backend.
      final busDetailsUri = Uri.parse(ApiEndpoints.busDetails(busId));
      final busResponse = await http.get(
        busDetailsUri,
        headers: {'Authorization': 'Bearer $token'},
      );
  
      if (busResponse.statusCode != 200) {
        throw Exception('Failed to fetch bus location: ${busResponse.body}');
      }
  
      final busData = json.decode(busResponse.body);
      final busLat = busData['latitude'];
      final busLon = busData['longitude'];
  
      if (busLat == null || busLon == null) {
        throw Exception('Bus location not available from backend.');
      }
  
      // Step 2: Use bus location to call Mapbox for ETA to the rider.
      final originCoords = "$busLon,$busLat";
      final destCoords = "$riderLon,$riderLat";
      final mapboxUrl =
          'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$originCoords;$destCoords?access_token=${getMapboxAccessToken()}&overview=full&geometries=geojson';
  
      final mapboxResponse = await http.get(Uri.parse(mapboxUrl));
  
      if (mapboxResponse.statusCode == 200) {
        final mapboxData = json.decode(mapboxResponse.body);
        if (mapboxData['routes'] != null && mapboxData['routes'].isNotEmpty) {
          final route = mapboxData['routes'][0];
          final double durationSeconds = route['duration']?.toDouble() ?? 0.0;
          final double distanceMeters = route['distance']?.toDouble() ?? 0.0;
  
          // Return the data in the format expected by BusDetailsModal
          return {
            'estimated_arrival_minutes': durationSeconds / 60,
            'distance_m': distanceMeters,
          };
        }
      }
      // If any step fails, return null.
      return null;
    } catch (e) {
      Logger.error('TripService', 'fetchEta exception: $e');
      return null;
    }
  }
}
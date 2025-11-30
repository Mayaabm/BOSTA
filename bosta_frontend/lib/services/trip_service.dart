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

  /// Starts a new trip based on the driver's saved setup.
  /// Returns the new trip ID on success.
  static Future<String> startNewTrip(String token, {
    required String tripId, // We need the ID of the trip to start.
    String? startStopId,
    String? endStopId,
    String? startTime,
    double? startLat,
    double? startLon,
  }) async {
    // Correctly build the URL for starting a specific trip.
    // This was causing the "invocation_of_non_function_expression" error.
    final uri = Uri.parse(ApiEndpoints.startTrip(tripId));
    
    debugPrint("\n=== TRIP SERVICE DEBUG ===");
    debugPrint("[TripService.startNewTrip] URI: $uri");
    debugPrint("[TripService.startNewTrip] Token: ${token.substring(0, 20)}...");
    debugPrint("[TripService.startNewTrip] Trip ID: $tripId");
    
    final requestBody = {
      'start_stop_id': startStopId,
      'end_stop_id': endStopId,
      'start_time': startTime,
      'start_lat': startLat,
      'start_lon': startLon,
    };
    debugPrint("[TripService.startNewTrip] Request body: $requestBody");
    
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(requestBody),
    );

    debugPrint("[TripService.startNewTrip] Response status: ${response.statusCode}");
    debugPrint("[TripService.startNewTrip] Response body: ${response.body}");
    debugPrint("[TripService.startNewTrip] Response headers: ${response.headers}");

    if (response.statusCode == 201 || response.statusCode == 200) { // 201 Created or 200 OK
      final data = json.decode(response.body);
      debugPrint("[TripService.startNewTrip] Parsed response data: $data");
      debugPrint("[TripService.startNewTrip] Response data keys: ${data.keys.toList()}");
      
      final startedTripId = data['trip_id']?.toString();
      debugPrint("[TripService.startNewTrip] Extracted trip_id: $startedTripId");
      
      if (startedTripId != null) {
        debugPrint("New trip started successfully. Trip ID: $startedTripId");
        debugPrint("=== TRIP SERVICE DEBUG (SUCCESS) ===");
        return startedTripId;
      } else {
        debugPrint("=== TRIP SERVICE DEBUG (FAILED - NO TRIP_ID) ===");
        throw Exception('Failed to start trip: trip_id not found in response.');
      }
    } else if (response.statusCode == 400) {
      // Common case: trip already started on the server. Try to fetch the
      // active trip from the profile and return that id so the UI can resume.
      try {
        final existing = await checkForActiveTrip(token);
        if (existing != null) return existing;
      } catch (_) {}
      debugPrint("=== TRIP SERVICE DEBUG (FAILED - 400) ===");
      throw Exception('Failed to start trip. Status: 400, Body: ${response.body}');
    } else {
      debugPrint("=== TRIP SERVICE DEBUG (FAILED - BAD STATUS) ===");
      throw Exception('Failed to start trip. Status: ${response.statusCode}, Body: ${response.body}');
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
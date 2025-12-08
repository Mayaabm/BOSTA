import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus.dart';
import '../models/user_location.dart';
import '../models/trip_suggestion.dart';
import 'auth_service.dart'; // Import AuthService
// Import Provider
import 'api_endpoints.dart';
import 'package:flutter/foundation.dart';

class BusService {
  /// Fetches detailed information for a single bus, including ETA if location is provided.
  static Future<Bus> getBusDetails(String busId, {UserLocation? userLocation}) async {
    // Correctly call the busDetails method to get the base URL for the specific bus.
    String url = ApiEndpoints.busDetails(busId);

    if (userLocation != null) {
      url += '?lat=${userLocation.latitude}&lon=${userLocation.longitude}';
    }
    final Uri uri = Uri.parse(url);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Bus.fromJson(data);
    } else {
      throw Exception('Failed to load details for bus $busId: ${response.body}');
    }
  }

  /// Sends the bus's current location to the backend.
  static Future<void> updateLocation({
    required String busId,
    required double latitude,
    required double longitude,
    required String token, // Add token parameter
    AuthService? authService, // Make AuthService available
  }) async {
    final uri = Uri.parse(ApiEndpoints.updateLocation); // Use the correct endpoint from ApiEndpoints

    Future<http.Response> doPost(String currentToken) {
      return http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $currentToken',
        },
        body: json.encode({
          'bus_id': busId,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );
    }

    var response = await doPost(token);

    // If the token is expired, try to refresh it and retry the request.
    if (response.statusCode == 401 && response.body.contains('token_not_valid')) {
      if (authService != null && authService.currentState.refreshToken != null) {
        final newAccessToken = await authService.refreshAccessToken(authService.currentState.refreshToken!);
        if (newAccessToken != null) {
          // Retry the request with the new token
          response = await doPost(newAccessToken);
        } else {
          // If refresh fails, throw an exception to indicate a logout is needed.
          throw Exception('Session expired. Please log in again.');
        }
      }
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to update bus location: ${response.body}');
    }
  }

  /// Fetches buses near a given coordinate.
  static Future<List<Bus>> getNearbyBuses({required double latitude, required double longitude, double radius = 10000}) async {
    final uri = Uri.parse('${ApiEndpoints.nearbyBuses}?lat=$latitude&lon=$longitude&radius=$radius');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Bus.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load nearby buses');
    }
  }

  /// Finds buses that can serve a trip from a start to an end point.
  static Future<List<TripSuggestion>> findTripSuggestions({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    final uri = Uri.parse(ApiEndpoints.planTrip).replace(queryParameters: {
      'start_lat': startLat.toString(),
      'start_lon': startLon.toString(),
      'end_lat': endLat.toString(),
      'end_lon': endLon.toString(),
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        // The endpoint returns a list of suggestions, where each suggestion is a list of legs.
        final List<dynamic> suggestionsJson = json.decode(response.body);
        return suggestionsJson
            .map((suggestionJson) =>
                TripSuggestion.fromJson(suggestionJson as List<dynamic>))
            .toList();
      } else {
        debugPrint(
            'BusService.findTripSuggestions failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('BusService.findTripSuggestions Exception: $e');
    }
    return [];
  }
}
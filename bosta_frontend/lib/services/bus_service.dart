import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus.dart';
import '../models/user_location.dart';
import '../models/trip_suggestion.dart';
import 'auth_service.dart'; // Import AuthService
// Import Provider
import '../services/api_endpoints.dart';
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
    // Older implementation expected a GET planTrip endpoint. Instead, use
    // the backend `plan_trip` POST API which accepts a destination stop id
    // or the `buses/to_destination/` endpoint. For now call `buses/to_destination`
    // to get nearby active buses and ETA to the target point.
    final uri = Uri.parse('${ApiEndpoints.busesToDestination}?lat=$endLat&lon=$endLon');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        // Map the simple buses-to-destination format into a single-leg TripSuggestion
        return data.map((item) {
          final int? eta = item['eta_min'] != null ? (item['eta_min'] as num).round() : null;
          return TripSuggestion(legs: [
            TripLeg(
              routeName: item['route']?.toString() ?? 'Unknown Route',
              boardAt: 'Nearby',
              exitAt: 'Destination',
              available: true,
              etaMinutes: eta,
              destLat: endLat,
              destLon: endLon,
            )
          ]);
        }).toList();
      } else {
        debugPrint('BusService.findTripSuggestions failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('BusService.findTripSuggestions Exception: $e');
    }
    return [];
  }

  /// Call the backend plan_trip API to get ETA and plan info for a selected stop.
  static Future<Map<String, dynamic>?> planTripToStop({
    required String destinationStopId,
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(ApiEndpoints.planTrip);
    try {
      final response = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: json.encode({
        'destination_stop_id': int.parse(destinationStopId),
        'latitude': latitude,
        'longitude': longitude,
      }));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('BusService.planTripToStop Exception: $e');
    }
    return null;
  }

  /// Finds all active buses for a specific route ID.
  static Future<List<Bus>> findBusesForRoute(String routeId) async {
    // Use the correct endpoint and append the routeId.
    final uri = Uri.parse('${ApiEndpoints.busesForRoute}$routeId/');
    debugPrint('[BusService.findBusesForRoute] Fetching buses for route: $uri');

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final buses = data.map((json) => Bus.fromJson(json)).toList();
        debugPrint('[BusService.findBusesForRoute] Found ${buses.length} buses for route $routeId.');
        return buses;
      } else {
        debugPrint('[BusService.findBusesForRoute] Failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[BusService.findBusesForRoute] Exception: $e');
    }
    return []; // Return empty list on failure
  }
}
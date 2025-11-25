import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_endpoints.dart';

class TripService {
  /// Checks if the currently authenticated driver has an active trip.
  /// Returns the trip ID if active, otherwise null.
  static Future<String?> checkForActiveTrip(String token) async {
    final uri = Uri.parse(ApiEndpoints.driverProfile); // Changed to use the existing driver profile endpoint
    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Assuming the backend returns { "active_trip_id": "some-id" } or { "active_trip_id": null }
        return data['active_trip_id']?.toString();
      } else if (response.statusCode == 404) {
        // 404 is a valid response meaning "no active trip found"
        return null;
      } else {
        // Other status codes indicate an error.
        throw Exception('Failed to check for active trip: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      // Rethrow to be handled by the caller
      rethrow;
    }
  }

  /// Notifies the backend that a trip has ended.
  static Future<void> endTrip(String token, String tripId) async {
    final uri = Uri.parse(ApiEndpoints.endTrip(tripId));
    try {
      final response = await http.post( // Using POST to signify a state change
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to end trip: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
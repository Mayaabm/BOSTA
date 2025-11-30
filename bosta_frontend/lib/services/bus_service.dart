import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus.dart';
import '../models/eta_response.dart';
import '../models/user_location.dart';
import 'auth_service.dart'; // Import AuthService
// Import Provider
import 'api_endpoints.dart';

class BusService {
  /// Fetches detailed information for a single bus, including ETA if location is provided.
  static Future<Bus> getBusDetails(String busId, {UserLocation? userLocation}) async {
    String url = ApiEndpoints.busDetails(busId);
    if (userLocation != null) {
      url += '?lat=${userLocation.latitude}&lon=${userLocation.longitude}';
    }
    final uri = Uri.parse(url);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Bus.fromJson(data);
    } else {
      throw Exception('Failed to load details for bus $busId: ${response.body}');
    }
  }

  static Future<Bus> getBusById(String busId) async {
    final uri = Uri.parse(ApiEndpoints.busDetails(busId));
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Bus.fromJson(data);
    } else {
      throw Exception('Failed to load bus with ID $busId: ${response.body}');
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
    final uri = Uri.parse(ApiEndpoints.updateLocation);

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

  /// Fetches all buses assigned to a specific route.
  static Future<List<Bus>> getBusesForRoute(String routeId) async {
    final uri = Uri.parse('${ApiEndpoints.busesForRoute}?route_id=$routeId');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Bus.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load buses for route $routeId');
    }
  }

  /// Fetches buses that are heading towards a destination.
  static Future<List<Bus>> getBusesToDestination({required double latitude, required double longitude}) async {
    final uri = Uri.parse('${ApiEndpoints.busesToDestination}?lat=$latitude&lon=$longitude');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Bus.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load buses to destination');
    }
  }

  /// Fetches ETA for a bus to a target location.
  static Future<EtaResponse> getEta({
    required String busId,
    required double targetLat,
    required double targetLon,
  }) async {
    final uri = Uri.parse(
        '${ApiEndpoints.eta}?bus_id=$busId&target_lat=$targetLat&target_lon=$targetLon');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return EtaResponse.fromJson(data);
    } else {
      throw Exception(
          'Failed to get ETA for bus $busId: ${response.statusCode} ${response.body}');
    }
  }
}
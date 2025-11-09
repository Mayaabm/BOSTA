import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus.dart';
import '../models/user_location.dart';
import 'api_endpoints.dart';

class BusService {
  /// Fetches detailed information for a single bus, including ETA if location is provided.
  static Future<Bus> getBusDetails(String busId, {UserLocation? userLocation}) async {
    String url = ApiEndpoints.busById(busId);
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
    final uri = Uri.parse(ApiEndpoints.busById(busId));
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
  }) async {
    final uri = Uri.parse(ApiEndpoints.updateBusLocation);
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'bus_id': busId,
        'latitude': latitude,
        'longitude': longitude,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update bus location: ${response.body}');
    }
  }

  /// Fetches buses near a given coordinate.
  static Future<List<Bus>> getNearbyBuses({required double latitude, required double longitude, double radius = 10000}) async {
    final uri = Uri.parse('${ApiEndpoints.busesNearby}?lat=$latitude&lon=$longitude&radius=$radius');
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
}
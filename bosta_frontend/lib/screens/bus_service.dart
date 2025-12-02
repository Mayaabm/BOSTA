import 'dart:convert';
import 'package:bosta_frontend/models/bus.dart';
import 'package:bosta_frontend/models/user_location.dart';
import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BusService {
  /// Fetches buses near a given location.
  static Future<List<Bus>> getNearbyBuses({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
        '${ApiEndpoints.nearbyBuses}?lat=$latitude&lon=$longitude');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Bus.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('BusService.getNearbyBuses Exception: $e');
    }
    return [];
  }

  /// Fetches detailed information for a single bus, including ETA.
  static Future<Bus> getBusDetails(String busId, {UserLocation? userLocation}) async {
    String url = '${ApiEndpoints.busDetails}/$busId/';
    if (userLocation != null) {
      url += '?user_lat=${userLocation.latitude}&user_lon=${userLocation.longitude}';
    }

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      return Bus.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load bus details for bus $busId');
    }
  }

  /// Finds buses that can serve a trip from a start to an end point.
  static Future<List<Bus>> findBusesForTrip({
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
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Bus.fromJson(json)).toList();
      } else {
        debugPrint('BusService.findBusesForTrip failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('BusService.findBusesForTrip Exception: $e');
    }
    return [];
  }
}
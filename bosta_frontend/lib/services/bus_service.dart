import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus.dart';
import 'package:bosta_frontend/services/api_endpoints.dart';

class BusService {
  static Future<List<Bus>> getNearbyBuses({
    required double latitude,
    required double longitude,
    double radius = 1000,
  }) async {
    final url = Uri.parse(
      '${ApiEndpoints.busesNearby}?lat=$latitude&lon=$longitude&radius=$radius',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Bus.fromJson(json)).toList();
      }
      throw Exception('Failed to load nearby buses');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<BusEta> getEta({
    required String busId,
    required double targetLat,
    required double targetLon,
  }) async {
    final url = Uri.parse(
      '${ApiEndpoints.eta}?bus_id=$busId&target_lat=$targetLat&target_lon=$targetLon',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return BusEta.fromJson(json.decode(response.body));
      }
      throw Exception('Failed to get ETA');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static Future<List<Bus>> getBusesToDestination({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse(
      '${ApiEndpoints.busesToDestination}?lat=$latitude&lon=$longitude',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Bus.fromJson(json)).toList();
      }
      throw Exception('Failed to load buses to destination');
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}
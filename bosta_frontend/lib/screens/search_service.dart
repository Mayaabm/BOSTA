import 'dart:async';
import 'dart:convert';

import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:bosta_frontend/screens/destination_result.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as fm;

class SearchService {
  /// Searches for places from both Mapbox and the local bus stop API.
  ///
  /// Returns a merged list of [DestinationResult] objects.
  /// Optionally uses [proximity] to bias Mapbox results.
  static Future<List<DestinationResult>> searchDestinations(String query, {fm.LatLng? proximity}) async {
    if (query.isEmpty) {
      return [];
    }

    // Only search for bus stops now.
    return await searchBusStops(query);
  }

  /// Searches the backend API for bus stops.
  static Future<List<DestinationResult>> searchBusStops(String query) async {
    final uri = Uri.parse('${ApiEndpoints.searchStops}?search=${Uri.encodeComponent(query)}');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) {
          // Assuming the backend now returns a dictionary with stop and route info
          final location = json['location']?['coordinates'] as List?;
          if (location == null || location.length < 2) return null;

          return DestinationResult(
            name: json['name'] ?? 'Unknown Stop',
            address: json['route_name'] ?? 'Unknown Route',
            stopId: json['id']?.toString(),
            routeId: json['route_id']?.toString(),
            routeName: json['route_name']?.toString(),
            latitude: (location[1] as num).toDouble(),
            longitude: (location[0] as num).toDouble(),
            source: 'bus_stop',
          );
        }).whereType<DestinationResult>().toList(); // Filter out any nulls from parsing errors
      }
    } catch (e) {
      debugPrint('Bus Stop Search Service Exception: $e');
    }
    return [];
  }

  /// Fetches all bus stops from the backend API.
  static Future<List<DestinationResult>> getAllBusStops() async {
    final uri = Uri.parse(ApiEndpoints.searchStops); // No query parameter
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) {
          final location = json['location']?['coordinates'] as List?;
          if (location == null || location.length < 2) return null;

          return DestinationResult(
            name: json['name'] ?? 'Unknown Stop',
            address: json['route_name'] ?? 'Unknown Route',
            stopId: json['id']?.toString(),
            routeId: json['route_id']?.toString(),
            routeName: json['route_name']?.toString(),
            latitude: (location[1] as num).toDouble(),
            longitude: (location[0] as num).toDouble(),
            source: 'bus_stop',
          );
        }).whereType<DestinationResult>().toList();
      }
    } catch (e) {
      debugPrint('Bus Stop All Stops Service Exception: $e');
    }
    return [];
  }
}
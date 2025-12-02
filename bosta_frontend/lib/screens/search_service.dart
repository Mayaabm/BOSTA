import 'dart:async';
import 'dart:convert';

import 'package:bosta_frontend/models/app_route.dart';
import 'package:bosta_frontend/screens/destination_result.dart';
import 'package:bosta_frontend/services/trip_service.dart';
import 'package:bosta_frontend/screens/api_endpoints.dart';
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

    // Fire off both API calls at the same time.
    final mapboxFuture = _searchMapbox(query, proximity: proximity);
    final stopsFuture = _searchBusStops(query);

    // Wait for both to complete.
    final results = await Future.wait([mapboxFuture, stopsFuture]);

    final mapboxResults = results[0];
    final stopResults = results[1];

    // Combine the lists, you can prioritize one over the other if needed.
    return [...stopResults, ...mapboxResults];
  }

  /// Searches the Mapbox Geocoding API.
  static Future<List<DestinationResult>> _searchMapbox(String query, {fm.LatLng? proximity}) async {
    final accessToken = TripService.getMapboxAccessToken();
    String url = 'https://api.mapbox.com/geocoding/v5/mapbox.places/${Uri.encodeComponent(query)}.json?access_token=$accessToken&autocomplete=true';

    if (proximity != null) {
      url += '&proximity=${proximity.longitude},${proximity.latitude}';
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        return features.map((feature) {
          final properties = feature['properties'];
          final geometry = feature['geometry'];
          final coords = geometry['coordinates'] as List;

          return DestinationResult(
            name: feature['text'] ?? 'Unknown Name',
            address: properties['address'] ?? feature['place_name'] ?? 'No address',
            latitude: (coords[1] as num).toDouble(),
            longitude: (coords[0] as num).toDouble(),
            source: 'mapbox',
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Mapbox Geocoding Service Exception: $e');
    }
    return [];
  }

  /// Searches the backend API for bus stops.
  static Future<List<DestinationResult>> _searchBusStops(String query) async {
    final uri = Uri.parse('${ApiEndpoints.searchStops}?search=${Uri.encodeComponent(query)}');
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) {
          final stop = RouteStop.fromJson(json);
          return DestinationResult(
            name: 'Stop ${stop.order ?? stop.id}',
            address: 'Bus Stop',
            latitude: stop.location.latitude,
            longitude: stop.location.longitude,
            source: 'bus_stop',
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Bus Stop Search Service Exception: $e');
    }
    return [];
  }
}
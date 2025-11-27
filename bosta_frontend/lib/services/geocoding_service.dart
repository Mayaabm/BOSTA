import 'dart:convert';
import 'package:bosta_frontend/models/place.dart';
import 'package:bosta_frontend/services/trip_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as fm;

class GeocodingService {
  static const String _baseUrl = 'https://api.mapbox.com/geocoding/v5/mapbox.places';

  /// Searches for places using the Mapbox Geocoding API.
  ///
  /// Returns a list of [Place] objects matching the [query].
  /// Optionally uses [proximity] to bias results towards a specific location.
  static Future<List<Place>> searchPlaces(String query, {fm.LatLng? proximity}) async {
    if (query.isEmpty) {
      return [];
    }

    final accessToken = TripService.getMapboxAccessToken(); // This now correctly calls the new method
    String url = '$_baseUrl/${Uri.encodeComponent(query)}.json?access_token=$accessToken&autocomplete=true';

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

          return Place(
            id: feature['id'],
            name: feature['text'] ?? 'Unknown Name',
            address: properties['address'] ?? feature['place_name'] ?? 'No address',
            coordinates: fm.LatLng(
              (coords[1] as num).toDouble(),
              (coords[0] as num).toDouble(),
            ),
          );
        }).toList();
      } else {
        debugPrint('Geocoding API Error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Geocoding Service Exception: $e');
      return [];
    }
  }
}
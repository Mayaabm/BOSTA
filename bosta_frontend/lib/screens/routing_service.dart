import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

class RoutingService {
  static Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final geometry = data['routes'][0]['geometry']['coordinates'];
        return geometry
            .map<LatLng>((coord) => LatLng(coord[1], coord[0]))
            .toList();
      } else {
        throw Exception('Failed to load route: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
      // Return a straight line as a fallback
      return [start, end];
    }
  }
}
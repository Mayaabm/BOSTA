import 'package:latlong2/latlong.dart';

class RouteStop {
  final String id;
  final int? order;
  final LatLng location;

  RouteStop({required this.id, this.order, required this.location});

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    // Expecting {"id":..., "order":..., "location": {"type":"Point","coordinates":[lon, lat]}}
    final loc = json['location'];
    double lat = 0.0, lng = 0.0;
    if (loc is Map && loc.containsKey('coordinates')) {
      final coords = loc['coordinates'] as List;
      lng = (coords[0] as num).toDouble();
      lat = (coords[1] as num).toDouble();
    }
    return RouteStop(
      id: json['id'].toString(),
      order: json['order'] != null ? int.tryParse(json['order'].toString()) : null,
      location: LatLng(lat, lng),
    );
  }
}

class AppRoute {
  final String id;
  final String name;
  final List<LatLng> geometry;
  final List<RouteStop> stops;

  AppRoute({required this.id, required this.name, required this.geometry, required this.stops});

  factory AppRoute.fromJson(Map<String, dynamic> json) {
    // Parse geometry (GeoJSON LineString or plain list)
    dynamic geom = json['geometry'];
    List coords = [];
    if (geom is Map && geom.containsKey('coordinates')) {
      coords = geom['coordinates'] as List;
    } else if (geom is List) {
      coords = geom;
    }

    var geometryList = coords
        .map((point) => LatLng(
              (point[1] as num).toDouble(), // latitude
              (point[0] as num).toDouble(), // longitude
            ))
        .toList();

    // Parse stops if available
    List<RouteStop> stopsList = [];
    if (json.containsKey('stops') && json['stops'] is List) {
      stopsList = (json['stops'] as List)
          .map((s) => RouteStop.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
    }

    return AppRoute(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      geometry: geometryList,
      stops: stopsList,
    );
  }
}
import 'package:latlong2/latlong.dart';
import 'stop_model.dart';

class AppRoute {
  final int id;
  final String name;
  final String description;
  final List<LatLng> geometry;
  final List<AppStop> stops;

  AppRoute({
    required this.id,
    required this.name,
    required this.description,
    required this.geometry,
    required this.stops,
  });

  factory AppRoute.fromJson(Map<String, dynamic> json) {
    // Parse LineString geometry
    var coords = json['geometry']['coordinates'] as List;
    List<LatLng> points = coords.map((c) => LatLng(c[1], c[0])).toList();

    // Parse nested stops
    var stopList = json['stops'] as List;
    List<AppStop> stops = stopList.map((s) => AppStop.fromJson(s)).toList();

    return AppRoute(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      geometry: points,
      stops: stops,
    );
  }
}
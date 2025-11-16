import 'package:latlong2/latlong.dart';

class AppRoute {
  final String id;
  final String name;
  final List<LatLng> geometry;

  AppRoute({required this.id, required this.name, required this.geometry});

  factory AppRoute.fromJson(Map<String, dynamic> json) {
    var geometryList = (json['geometry'] as List)
        .map((point) => LatLng(
              (point[1] as num).toDouble(), // latitude
              (point[0] as num).toDouble(), // longitude
            ))
        .toList();

    return AppRoute(
        id: json['id'], name: json['name'], geometry: geometryList);
  }
}
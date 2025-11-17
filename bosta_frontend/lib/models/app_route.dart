import 'package:latlong2/latlong.dart';

class AppRoute {
  final String id;
  final String name;
  final List<LatLng> geometry;

  AppRoute({required this.id, required this.name, required this.geometry});

  factory AppRoute.fromJson(Map<String, dynamic> json) {
    // Support both GeoJSON-style object {"type":"LineString","coordinates":[...]}
    // and a plain coordinates list. The backend serializes geometry as GeoJSON.
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

    return AppRoute(
      id: json['id'].toString(), name: (json['name'] ?? '').toString(), geometry: geometryList);
  }
}
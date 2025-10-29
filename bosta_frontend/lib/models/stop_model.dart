import 'package:latlong2/latlong.dart';

class AppStop {
  final int id;
  final int order;
  final LatLng location;

  AppStop({required this.id, required this.order, required this.location});

  factory AppStop.fromJson(Map<String, dynamic> json) {
    var coords = json['location']['coordinates'] as List;

    return AppStop(
      id: json['id'],
      order: json['order'],
      location: LatLng(coords[1], coords[0]), // lat, lon
    );
  }
}
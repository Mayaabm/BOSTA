import 'package:latlong2/latlong.dart' as fm;

/// Represents a geographical place returned from a geocoding search.
class Place {
  final String id;
  final String name;
  final String address;
  final fm.LatLng coordinates;

  Place({
    required this.id,
    required this.name,
    required this.address,
    required this.coordinates,
  });
}
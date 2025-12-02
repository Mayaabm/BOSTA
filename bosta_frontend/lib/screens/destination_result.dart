class DestinationResult {
  final String name;
  final String? address; // Optional address/subtitle
  final double latitude;
  final double longitude;
  final String source; // "mapbox" or "bus_stop"

  DestinationResult({
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    required this.source,
  });

  @override
  String toString() {
    return 'DestinationResult(name: $name, lat: $latitude, lon: $longitude, source: $source)';
  }
}
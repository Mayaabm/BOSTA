class DestinationResult {
  final String name;
  final String? address; // Optional address/subtitle
  final String? stopId;
  final int? order;
  final String? routeId;
  final String? routeName;
  final double latitude;
  final double longitude;
  final String source; // "mapbox" or "bus_stop"

  DestinationResult({
    required this.name,
    this.address,
    this.order,
    this.stopId,
    this.routeId,
    this.routeName,
    required this.latitude,
    required this.longitude,
    required this.source,
  });

  @override
  String toString() {
    return 'DestinationResult(name: $name, stopId: $stopId, order: $order, routeId: $routeId, lat: $latitude, lon: $longitude, source: $source)';
  }
}
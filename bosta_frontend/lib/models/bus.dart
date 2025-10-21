class Bus {
  final String id;
  final String plateNumber;
  final double latitude;
  final double longitude;
  final double speed;
  final double? distanceMeters;
  final String? routeName;

  Bus({
    required this.id,
    required this.plateNumber,
    required this.latitude,
    required this.longitude,
    required this.speed,
    this.distanceMeters,
    this.routeName,
  });

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      id: json['id'].toString(),
      plateNumber: json['plate_number'],
      latitude: json['current_point']['coordinates'][1],
      longitude: json['current_point']['coordinates'][0],
      speed: json['speed_mps'] ?? 0.0,
      distanceMeters: json['distance_m']?.toDouble(),
      routeName: json['route'],
    );
  }
}

class BusEta {
  final String busId;
  final double distanceMeters;
  final double estimatedMinutes;
  final DateTime lastReported;

  BusEta({
    required this.busId,
    required this.distanceMeters,
    required this.estimatedMinutes,
    required this.lastReported,
  });

  factory BusEta.fromJson(Map<String, dynamic> json) {
    return BusEta(
      busId: json['bus_id'].toString(),
      distanceMeters: json['distance_m'].toDouble(),
      estimatedMinutes: json['estimated_arrival_minutes'].toDouble(),
      lastReported: DateTime.parse(json['last_reported']),
    );
  }
}
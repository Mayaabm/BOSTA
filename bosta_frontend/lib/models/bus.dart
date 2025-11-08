class Bus {
  final String id;
  final String plateNumber;
  final double latitude;
  final double longitude;
  final double speed;
  final double? distanceMeters;
  final String? routeName;
  final String? driverName;
  final double? driverRating;

  Bus({
    required this.id,
    required this.plateNumber,
    required this.latitude,
    required this.longitude,
    required this.speed,
    this.distanceMeters,
    this.routeName,
    this.driverName,
    this.driverRating,
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
      driverName: json['driver_name'], // Assuming these fields might come from the API
      driverRating: json['driver_rating']?.toDouble(),
    );
  }
}

class BusEta {
  final String busId;
  final double distanceMeters;
  final EtaDuration duration;
  final DateTime lastReported;

  BusEta({
    required this.busId,
    required this.distanceMeters,
    required this.duration,
    required this.lastReported,
  });

  factory BusEta.fromJson(Map<String, dynamic> json) {
    return BusEta(
      busId: json['bus_id'].toString(),
      distanceMeters: json['distance_m'].toDouble(),
      duration: EtaDuration.fromJson(json['eta']),
      lastReported: DateTime.parse(json['last_reported']),
    );
  }
}

class EtaDuration {
  final int hours;
  final int minutes;
  final int seconds;

  EtaDuration({required this.hours, required this.minutes, required this.seconds});

  factory EtaDuration.fromJson(Map<String, dynamic> json) {
    return EtaDuration(
      hours: json['hours'] ?? 0,
      minutes: json['minutes'] ?? 0,
      seconds: json['seconds'] ?? 0,
    );
  }
}
import 'app_route.dart';

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

  String toMinutesString() {
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '$minutes min';
    return '<1 min';
  }
}

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
  final String? lastReportedAt;
  final AppRoute? route;
  final EtaDuration? eta;

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
    this.lastReportedAt,
    this.route,
    this.eta,
  });

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      id: json['id'].toString(),
      plateNumber: json['plate_number'] ?? 'N/A',
      latitude: (json['current_point']?['coordinates']?[1] ?? 0.0).toDouble(),
      longitude: (json['current_point']?['coordinates']?[0] ?? 0.0).toDouble(),
      speed: (json['speed_mps'] != null) ? (json['speed_mps'] * 3.6) : 0.0, // Convert m/s to km/h
      distanceMeters: json['distance_m']?.toDouble(),
      routeName: json['route_name'],
      driverName: json['driver']?['name'], // Assuming nested driver object
      driverRating: (json['driver']?['rating'] as num?)?.toDouble(),
      lastReportedAt: json['last_reported_at'],
      route: json['route'] != null ? AppRoute.fromJson(json['route']) : null,
      eta: json['eta'] != null ? EtaDuration.fromJson(json['eta']) : null,
    );
  }
}
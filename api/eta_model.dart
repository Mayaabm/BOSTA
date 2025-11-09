class Eta {
  final String busId;
  final double distanceMeters;
  final EtaDuration duration;
  final DateTime lastReported;

  Eta({
    required this.busId,
    required this.distanceMeters,
    required this.duration,
    required this.lastReported,
  });

  factory Eta.fromJson(Map<String, dynamic> json) {
    return Eta(
      busId: json['bus_id'],
      distanceMeters: (json['distance_m'] as num).toDouble(),
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
    return EtaDuration(hours: json['hours'], minutes: json['minutes'], seconds: json['seconds']);
  }
}
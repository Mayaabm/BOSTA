import 'bus.dart'; // For EtaDuration

class EtaResponse {
  final String busId;
  final double distanceMeters;
  final EtaDuration duration;

  EtaResponse({
    required this.busId,
    required this.distanceMeters,
    required this.duration,
  });

  factory EtaResponse.fromJson(Map<String, dynamic> json) {
    return EtaResponse(
      busId: json['bus_id'],
      distanceMeters: (json['distance_m'] as num).toDouble(),
      duration: EtaDuration.fromJson(json['eta']),
    );
  }
}
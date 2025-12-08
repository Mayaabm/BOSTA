class TripSuggestion {
  final List<TripLeg> legs;

  TripSuggestion({required this.legs});

  factory TripSuggestion.fromJson(List<dynamic> json) {
    return TripSuggestion(
      legs: json.map((legJson) => TripLeg.fromJson(legJson)).toList(),
    );
  }
}

class TripLeg {
  final String routeName;
  final String boardAt;
  final String exitAt;
  final bool available;
  final int? etaMinutes;
  final double? destLat;
  final double? destLon;

  TripLeg({
    required this.routeName,
    required this.boardAt,
    required this.exitAt,
    required this.available,
    this.etaMinutes,
    this.destLat,
    this.destLon,
  });

  factory TripLeg.fromJson(Map<String, dynamic> json) {
    return TripLeg(
      routeName: json['route_name'] ?? 'Unknown Route',
      boardAt: json['board_at'] ?? 'Unknown Stop',
      exitAt: json['exit_at'] ?? 'Unknown Stop',
      available: json['available'] ?? false,
      etaMinutes: json['eta_minutes'],
      destLat: json['dest_lat']?.toDouble(),
      destLon: json['dest_lon']?.toDouble(),
    );
  }
}
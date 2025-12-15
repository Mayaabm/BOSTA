String formatEtaMinutes(int? minutes) {
  if (minutes == null) return '--';
  if (minutes <= 0) return '<1 min';
  if (minutes >= 60) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m > 0) return '${h}h ${m}m';
    return '${h}h';
  }
  return '${minutes} min';
}

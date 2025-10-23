import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// A class to hold the animation state for a single bus.
class BusSimulation {
  final String id;
  final String plateNumber;
  final AnimationController controller;
  final Animation<LatLng> animation;
  final List<LatLng> route;
  final double speedKph;

  // ValueNotifier to hold the dynamically calculated ETA string.
  final ValueNotifier<String> etaNotifier;

  BusSimulation({
    required this.id,
    required this.plateNumber,
    required this.controller,
    required this.animation,
    required this.route,
    required this.speedKph,
  }) : etaNotifier = ValueNotifier<String>('Calculating...');

  void dispose() {
    controller.dispose();
    etaNotifier.dispose();
  }
}
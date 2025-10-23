import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/bus_service.dart';
import 'routing_service.dart';
import 'transit_tokens.dart';
import '../models/bus.dart';
import 'bus_simulation.dart';

const _simulationMode = true; // Set to false to use live API data

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final mapController = MapController();
  Position? _currentPosition;
  List<Bus> _nearbyBuses = [];
  Bus? _selectedBus;
  Timer? _busUpdateTimer;
  StreamSubscription<Position>? _positionStream;

  // --- Simulation and Routing State ---
  final List<BusSimulation> _simulatedBuses = [];
  List<LatLng> _routePoints = [];
  final LatLng _startPoint = const LatLng(34.1292207, 35.6860806);
  final LatLng _destinationPoint = const LatLng(34.147900, 35.643100);
  static const _busIconSize = 30.0;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();

    if (_simulationMode) {
      _setupSimulation();
    } else {
      _startPeriodicUpdates(); // Use live data
    }
  }

  @override
  void dispose() {
    _busUpdateTimer?.cancel();
    _positionStream?.cancel();
    for (var sim in _simulatedBuses) {
      sim.dispose();
    }
    super.dispose();
  }

  // --- Location and Data Fetching ---

  void _centerOnRoute() {
    if (_routePoints.isNotEmpty) {
      mapController.fitCamera(
          CameraFit.coordinates(coordinates: _routePoints, padding: const EdgeInsets.all(50)));
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _currentPosition = position);
        if (!_simulationMode) {
          _updateNearbyBuses(); // Initial bus fetch for live mode
          mapController.move(LatLng(position.latitude, position.longitude), 13);
        }
      }

      // Start listening for continuous location updates
      _startListeningToLocation();
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _startListeningToLocation() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = position);
      }
    });
  }

  void _startPeriodicUpdates() {
    _busUpdateTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _updateNearbyBuses(),
    );
  }

  Future<void> _updateNearbyBuses() async {
    if (_currentPosition == null) return;

    try {
      final buses = await BusService.getNearbyBuses(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
      );
      setState(() => _nearbyBuses = buses);
    } catch (e) {
      debugPrint('Error updating buses: $e');
    }
  }

  // --- ETA Logic ---

  Future<void> _checkEta() async {
    if (_selectedBus == null || _currentPosition == null) return;

    try {
      final eta = await BusService.getEta(
        busId: _selectedBus!.id,
        targetLat: _currentPosition!.latitude,
        targetLon: _currentPosition!.longitude,
      );

      // Helper to format the duration into a readable string
      String formatEta(EtaDuration duration) {
        if (duration.hours > 0) {
          return '${duration.hours}h ${duration.minutes}m';
        }
        if (duration.minutes > 0) {
          return '${duration.minutes}m ${duration.seconds}s';
        }
        if (duration.seconds > 0) {
          return '${duration.seconds} seconds';
        }
        return 'Arriving now';
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('ETA for Bus ${_selectedBus!.plateNumber}'),
            content: Text('Estimated arrival: ${formatEta(eta.duration)}'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting ETA: $e');
    }
  }

  // --- Simulation Logic ---

  Future<void> _setupSimulation() async {
    // 1. Fetch the route from OSRM
    final route = await RoutingService.getRoute(_startPoint, _destinationPoint);
    if (route.isEmpty || !mounted) return;

    setState(() {
      _routePoints = route;
    });

    _centerOnRoute();

    // 2. Create and start simulated buses
    _startBusSimulations(3);
  }

  void _startBusSimulations(int count) {
    // Clear previous simulations
    for (var sim in _simulatedBuses) {
      sim.dispose();
    }
    _simulatedBuses.clear();

    for (int i = 0; i < count; i++) {
      final busId = 'SIM-${i + 1}';
      final speedKph = 40.0 + (i * 10); // e.g., 40, 50, 60 km/h
      final totalDistance = _calculateRouteDistance(_routePoints);
      final durationSeconds = (totalDistance / (speedKph / 3.6)).round();

      final controller = AnimationController(
        vsync: this,
        duration: Duration(seconds: durationSeconds),
      );

      final animation = Tween<double>(begin: 0.0, end: 1.0).animate(controller)
        ..addListener(() {
          // Update ETA dynamically during animation
          final remainingDistance = totalDistance * (1.0 - controller.value);          
          final remainingSeconds = (remainingDistance / (speedKph / 3.6));
          final sim = _simulatedBuses.firstWhere((s) => s.id == busId);
          sim.etaNotifier.value = _formatDuration(Duration(seconds: remainingSeconds.round()));
          setState(() {}); // Redraw marker on screen
        });

      final animatedPosition = _createPathAnimation(animation, _routePoints);

      // Stagger the start times
      Future.delayed(Duration(seconds: i * 10), () {
        if (mounted) controller.repeat();
      });

      _simulatedBuses.add(BusSimulation(
        id: busId,
        plateNumber: 'SIM-${101 + i}',
        controller: controller,
        animation: animatedPosition,
        route: _routePoints,
        speedKph: speedKph,
      ));
    }
    setState(() {});
  }

  Animation<LatLng> _createPathAnimation(Animation<double> parent, List<LatLng> points) {
    return TweenSequence<LatLng>(
      List.generate(points.length - 1, (i) {
        return TweenSequenceItem(
          tween: LatLngTween(begin: points[i], end: points[i + 1]),
          weight: const Distance().distance(points[i], points[i + 1]),
        );
      }),
    ).animate(parent);
  }

  double _calculateRouteDistance(List<LatLng> points) {
    double totalDistance = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += const Distance().as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return totalDistance;
  }

  // --- UI Build Method ---
  @override
  Widget build(BuildContext context) {
    // Access the theme extensions and color scheme
    final transitTokens = Theme.of(context).extension<TransitTokens>()!;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [          _currentPosition == null && !_simulationMode              ? const Center(child: CircularProgressIndicator())              : FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: _simulationMode ? _startPoint : LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
              initialZoom: 13,
              onTap: (_, _) {
                setState(() => _selectedBus = null);
              },
              onMapReady: () {
                // Move map to current location only after it's ready.
                if (!_simulationMode && _currentPosition != null) {
                  mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 13);
                } 
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bosta_frontend',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                        points: _routePoints,
                        color: transitTokens.routePrimary ?? Colors.deepPurple,
                        strokeWidth: 5),
            ]),
              MarkerLayer(
                markers: [
                  if (_currentPosition != null)
                    Marker(
                      point: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      width: 30,
                      height: 30,                      
                      child: Icon(Icons.my_location, color: colorScheme.primary, size: 30),
                    ),

                  // Show live buses OR simulated buses
                  if (!_simulationMode) ..._buildLiveBusMarkers(transitTokens),
                  if (_simulationMode) ..._buildSimulatedBusMarkers(colorScheme),

                  // Markers for start and destination
                  if (_routePoints.isNotEmpty) ...[
                    Marker(
                      point: _startPoint,
                      width: 80, height: 50,
                      child: Column(children: [Icon(Icons.flag, color: transitTokens.etaPositive), const Text("Start")]),
                    ),
                    Marker(
                      point: _destinationPoint,
                      width: 80, height: 50,
                      child: Column(children: [Icon(Icons.flag, color: colorScheme.error), const Text("End")]),
                    ),
                  ]
                ],
              ),
            ],
          ),
          // Bus info card for LIVE bus
          if (!_simulationMode && _selectedBus != null)
            _buildLiveBusInfoCard(_selectedBus!, transitTokens),

          // Info card for SIMULATED bus
          if (_simulationMode && _simulatedBuses.isNotEmpty)
            _buildSimulatedBusInfoCard(_simulatedBuses.first, transitTokens),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _simulationMode ? _centerOnRoute : _getCurrentLocation,
        child: Icon(_simulationMode ? Icons.route : Icons.my_location),
      ),
    );
  }

  // --- UI Helper Widgets ---

  Widget _buildSimulatedBusInfoCard(BusSimulation sim, TransitTokens transitTokens) {
    return Positioned(
      bottom: 16, left: 16, right: 16,
      child: Card(
        color: transitTokens.sheetSurface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions_bus_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bus ${sim.plateNumber}', style: Theme.of(context).textTheme.titleMedium),
                        Text('Route: Jbeil -> Batroun (Sim)', style: Theme.of(context).textTheme.bodyMedium),
                        Text('Speed: ${sim.speedKph.toStringAsFixed(0)} km/h', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('ETA to End', style: Theme.of(context).textTheme.bodySmall),
                      ValueListenableBuilder<String>(
                        valueListenable: sim.etaNotifier,
                        builder: (context, eta, child) {
                          return Text(eta, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
                        },
                      ),
                    ],
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBusInfoCard(Bus bus, TransitTokens transitTokens) {
    return Positioned(
      bottom: 16, left: 16, right: 16,
      child: Card(
        color: transitTokens.sheetSurface,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions_bus),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bus ${bus.plateNumber}', style: Theme.of(context).textTheme.titleMedium),
                        if (bus.routeName != null) Text('Route: ${bus.routeName}', style: Theme.of(context).textTheme.bodyMedium),
                        Text('Distance: ${(bus.distanceMeters! / 1000).toStringAsFixed(1)} km', style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                  ElevatedButton(onPressed: _checkEta, child: const Text('Check ETA')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Marker> _buildLiveBusMarkers(TransitTokens transitTokens) {
    return _nearbyBuses.map((bus) {
      return Marker(
        point: LatLng(bus.latitude, bus.longitude),
        width: _busIconSize, height: _busIconSize,
        child: GestureDetector(
          onTap: () => setState(() => _selectedBus = bus),
          child: Icon(
            Icons.directions_bus,
            color: _selectedBus?.id == bus.id ? transitTokens.markerSelected : transitTokens.markerNormal,
            size: _busIconSize,
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildSimulatedBusMarkers(ColorScheme colorScheme) {
    return _simulatedBuses.map((sim) {
      return Marker(
        point: sim.animation.value, // This is safe as animation is not nullable
        width: _busIconSize, height: _busIconSize,
        child: Icon(Icons.directions_bus, color: colorScheme.secondary, size: _busIconSize),
      );
    }).toList();
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    if (d.inSeconds > 0) return '${d.inSeconds}s';
    return 'Now';
  }
}
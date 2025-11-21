import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as fm;
import 'package:bosta_frontend/models/app_route.dart';
import '../services/api_endpoints.dart';
import '../services/auth_service.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final MapController _mapController = MapController();
  AppRoute? _assignedRoute;
  bool _isLoading = true;
  String? _errorMessage;

  // --- Simulation State ---
  Timer? _simulationTimer;
  bool _isTripActive = false;
  fm.LatLng? _simulatedBusPosition;
  double _distanceTraveledMeters = 0.0;
  static const double _simulatedSpeedMps = 11.1; // ~40 km/h

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeDashboard());
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }

  /// Start trip from UI (test): calls POST /api/trips/<id>/start/
  Future<void> _startTripFromUI() async {
    // First, call the backend to start the trip simulation session
    final error = await _startBackendTrip();
    if (error != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start trip: $error')));
      return;
    }

    // If successful, start the location simulation
    _startSimulation();
  }

  Future<String?> _startBackendTrip() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.currentState.token;
    final tripId = authService.lastCreatedTripId;

    final startStopId = authService.currentState.selectedStopId;
    final startTime = authService.currentState.selectedStartTime;

    if (token == null) {
      return 'No auth token. Please log in.';
    }
    if (tripId == null) {
      return 'No Trip found. Was one created during onboarding?';
    }

    // Use the start details saved during onboarding.
    final body = <String, dynamic>{
      if (startStopId != null) 'start_stop_id': startStopId,
      if (startTime != null) 'start_time': startTime,
      'speed_mps': 8.0,
      'interval_seconds': 2.0,
    };

    final uri = Uri.parse(ApiEndpoints.startTrip(tripId));
    debugPrint("--- 'Start Trip (test)' button pressed on Dashboard screen ---");
    debugPrint("Attempting to start trip...");
    debugPrint("URL: $uri");
    debugPrint("Request Body: ${json.encode(body)}");
    debugPrint("Authorization Token: Bearer $token");

    try {
      final res = await http.post(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}, body: json.encode(body));
      debugPrint("Response Status Code: ${res.statusCode}");
      debugPrint("Response Body: ${res.body}");
      if (res.statusCode == 200) {
        return null; // Success
      } else {
        final msg = res.body.isNotEmpty ? res.body : 'Failed to start simulation';
        return msg;
      }
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> _initializeDashboard() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final routeId = authService.currentState.driverInfo?.routeId;
    final token = authService.currentState.token;

    if (routeId == null || token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Driver has no assigned route.";
      });
      return;
    }

    // Prevent making a request with an invalid route ID.
    if (routeId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = "No valid route ID found for this driver.";
      });
      return;
    }
    try {
      final uri = Uri.parse('${ApiEndpoints.routes}$routeId/');
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _assignedRoute = AppRoute.fromJson(json.decode(response.body));
            _isLoading = false;
          });
          _centerOnRoute();
        }
      } else {
        throw Exception('Failed to load route details: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not load route details: $e';
        });
      }
    }
  }

  void _startSimulation() {
    if (_assignedRoute == null || _assignedRoute!.geometry.isEmpty) return;

    setState(() {
      _isTripActive = true;
      _distanceTraveledMeters = 0.0;
      _simulatedBusPosition = _assignedRoute!.geometry.first;
    });

    // The timer will "tick" every second to update the bus's position.
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _distanceTraveledMeters += _simulatedSpeedMps; // distance = speed * time (1s)

      final newPosition = _getPointAtDistance(_distanceTraveledMeters);

      if (mounted) {
        setState(() {
          _simulatedBusPosition = newPosition;
        });

        // Send location update to the backend every few seconds
        if (timer.tick % 5 == 0) {
          _updateBusLocation(newPosition);
        }
      }

      // Stop the simulation if we've reached the end of the route
      if (_distanceTraveledMeters >= _calculateRouteDistance(_assignedRoute!.geometry)) {
        _stopSimulation();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Simulation finished: Reached end of route.")),
          );
        }
      }
    });
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    setState(() {
      _isTripActive = false;
      // Keep the last position on the map
    });
  }

  double _calculateRouteDistance(List<fm.LatLng> points) {
    double totalDistance = 0;
    for (int i = 0; i < points.length - 1; i++) {
      totalDistance += const fm.Distance().as(fm.LengthUnit.Meter, points[i], points[i + 1]);
    }
    return totalDistance;
  }

  /// Calculates the LatLng point at a specific distance along the route polyline.
  fm.LatLng _getPointAtDistance(double distance) {
    final points = _assignedRoute!.geometry;
    if (distance <= 0) return points.first;

    double distanceSoFar = 0;
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final segmentDistance = const fm.Distance().as(fm.LengthUnit.Meter, p1, p2);

      if (distanceSoFar + segmentDistance >= distance) {
        // The point is on this segment
        final distanceIntoSegment = distance - distanceSoFar;
        final fraction = distanceIntoSegment / segmentDistance;

        final lat = p1.latitude + (p2.latitude - p1.latitude) * fraction;
        final lon = p1.longitude + (p2.longitude - p1.longitude) * fraction;

        return fm.LatLng(lat, lon);
      }
      distanceSoFar += segmentDistance;
    }

    // If distance is beyond the route length, return the last point.
    return points.last;
  }

  Future<void> _updateBusLocation(fm.LatLng position) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.currentState.token;
    final busId = authService.currentState.driverInfo?.busId;

    if (token == null || busId == null) {
      debugPrint('Cannot update location: missing token or busId.');
      return;
    }

    final uri = Uri.parse(ApiEndpoints.updateBusLocation);
    final body = json.encode({
      'bus_id': busId,
      'latitude': position.latitude,
      'longitude': position.longitude,
    });

    try {
      final res = await http.post(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}, body: body);
      if (res.statusCode == 200) {
        debugPrint('Simulated location update sent successfully.');
      } else {
        debugPrint('Failed to send simulated location. Status: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('Error sending simulated location update: $e');
    }
  }

  void _centerOnRoute() {
    if (_assignedRoute != null && _assignedRoute!.geometry.isNotEmpty) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: _assignedRoute!.geometry,
          padding: const EdgeInsets.all(50),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _assignedRoute?.geometry.first ?? const fm.LatLng(33.8938, 35.5018); // Fallback

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.route), onPressed: _centerOnRoute, tooltip: 'Center on Route'),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Provider.of<AuthService>(context, listen: false).logout();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_errorMessage != null)
            Center(child: Text('Error: $_errorMessage'))
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: initialCenter, initialZoom: 13.0),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                ),
                if (_assignedRoute != null)
                  PolylineLayer(polylines: [
                    Polyline(points: _assignedRoute!.geometry, color: Colors.orangeAccent, strokeWidth: 5.0),
                  ]),
                if (_simulatedBusPosition != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _simulatedBusPosition!,
                      width: 80,
                      height: 80,
                      child: const Icon(Icons.directions_bus, color: Colors.tealAccent, size: 40),
                    ),
                  ]),
              ],
            ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: _isLoading ? null : (_isTripActive ? _stopSimulation : _startTripFromUI),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isTripActive ? Colors.red.shade700 : Theme.of(context).primaryColor,
                foregroundColor: _isTripActive ? Colors.white : Colors.black,
              ),
              child: Text(
                _isTripActive ? 'Stop Trip' : 'Start Trip (Simulated)',
                style: GoogleFonts.urbanist(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
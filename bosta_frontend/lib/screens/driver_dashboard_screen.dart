import 'dart:async';
import 'dart:convert';
import 'package:bosta_frontend/services/trip_service.dart';
import 'package:bosta_frontend/services/bus_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as fm;
import '../services/api_endpoints.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final MapController _mapController = MapController();

  Timer? _busPositionPollTimer;
  bool _isTripActive = false;
  fm.LatLng? _currentBusPosition;
  String? _tripStatusMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (mounted) {
        setState(() {
          _currentBusPosition = authService.currentState.initialBusPosition;
        });
        if (!_isTripActive) {
          _startTripFromUI();
        }
      }
      _centerOnRoute();
    });
  }

  @override
  void dispose() {
    _busPositionPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startTripFromUI() async {
    setState(() => _tripStatusMessage = "Starting trip...");
    final error = await _startBackendTrip();
    if (error != null) {
      if (mounted) setState(() => _tripStatusMessage = 'Failed to start trip: $error');
      return;
    }
    _startPollingForBusLocation();
  }

  Future<String?> _startBackendTrip() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    var token = authService.currentState.token;
    final refreshToken = authService.currentState.refreshToken;
    final tripId = authService.lastCreatedTripId;
    final startStopId = authService.currentState.selectedStopId;
    final startTime = authService.currentState.selectedStartTime;
    final startLat = authService.currentState.selectedStartLat;
    final startLon = authService.currentState.selectedStartLon;

    if (token == null) return 'No auth token. Please log in.';
    if (tripId == null) return 'No Trip found. Was one created during onboarding?';

    Future<String?> doStartTrip(String currentToken) async {
      final body = <String, dynamic>{
        if (startStopId != null) 'start_stop_id': startStopId,
        if (startTime != null) 'start_time': startTime,
        if (startLat != null) 'start_lat': startLat,
        if (startLon != null) 'start_lon': startLon,
        'speed_mps': 8.0,
        'interval_seconds': 2.0,
      };

      final uri = Uri.parse(ApiEndpoints.startTrip(tripId));

      try {
        final res = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $currentToken'
          },
          body: json.encode(body),
        );

        if (res.statusCode == 200) return null;
        return res.body.isNotEmpty ? res.body : 'Failed to start simulation';
      } catch (e) {
        return e.toString();
      }
    }

    var result = await doStartTrip(token);

    if (result != null && result.contains('token_not_valid') && refreshToken != null) {
      final newAccessToken = await authService.refreshAccessToken(refreshToken);
      if (newAccessToken != null) {
        return await doStartTrip(newAccessToken);
      } else {
        return "Your session has expired. Please log in again.";
      }
    }

    return result;
  }

  void _startPollingForBusLocation() {
    setState(() {
      _isTripActive = true;
      _tripStatusMessage = "Trip in progress...";
    });

    _busPositionPollTimer?.cancel();
    _busPositionPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchBusPosition();
    });
    _fetchBusPosition();
  }

  Future<void> _fetchBusPosition() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final busId = authService.currentState.driverInfo?.busId;
    if (busId == null) return;

    try {
      final bus = await BusService.getBusDetails(busId);
      if (mounted) {
        setState(() {
          _currentBusPosition = fm.LatLng(bus.latitude, bus.longitude);
        });
      }
    } catch (e) {}
  }

  Future<void> _endTrip() async {
    setState(() => _tripStatusMessage = "Ending trip...");
    _busPositionPollTimer?.cancel();

    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.currentState.token;
    final tripId = authService.lastCreatedTripId;

    if (token != null && tripId != null) {
      try {
        await TripService.endTrip(token, tripId);
        if (mounted) {
          setState(() {
            _isTripActive = false;
            _tripStatusMessage = "Trip ended successfully.";
          });
          GoRouter.of(context).go('/driver/home');
        }
      } catch (e) {
        if (mounted) setState(() => _tripStatusMessage = "Failed to end trip: $e");
      }
    } else {
      if (mounted) {
        setState(() => _tripStatusMessage = "Could not end trip: missing token or trip ID.");
      }
    }
  }

  void _centerOnRoute() {
    final assignedRoute =
        Provider.of<AuthService>(context, listen: false).currentState.assignedRoute;
    if (assignedRoute != null && assignedRoute.geometry.isNotEmpty) {
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: assignedRoute.geometry,
          padding: const EdgeInsets.all(50),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final assignedRoute = authService.currentState.assignedRoute;
        final isLoading =
            assignedRoute == null && authService.currentState.driverInfo?.routeId != null;

        final errorMessage = authService.currentState.driverInfo?.routeId == null
            ? "Driver has no assigned route."
            : (assignedRoute == null && !isLoading
                ? "Could not load route details."
                : null);

        final initialCenter = authService.currentState.initialBusPosition ??
            assignedRoute?.geometry.first ??
            const fm.LatLng(33.8938, 35.5018);

        final busMarkerPosition =
            _currentBusPosition ?? authService.currentState.initialBusPosition;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Driver Dashboard'),
            actions: [
              IconButton(
                icon: const Icon(Icons.route),
                onPressed: _centerOnRoute,
                tooltip: 'Center on Route',
              ),
              IconButton(
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                onPressed: _isTripActive ? _endTrip : null,
                tooltip: 'End Trip',
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Stack(
            children: [
              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else if (errorMessage != null)
                Center(child: Text('Error: $errorMessage'))
              else
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: 13.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                    ),
                    if (assignedRoute != null)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: assignedRoute.geometry,
                          color: Colors.orangeAccent,
                          strokeWidth: 5.0,
                        )
                      ]),
                    if (busMarkerPosition != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: busMarkerPosition,
                          width: 80,
                          height: 80,
                          child: const Icon(
                            Icons.directions_bus,
                            color: Colors.tealAccent,
                            size: 40,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 15.0)
                            ],
                          ),
                        ),
                      ]),
                  ],
                ),
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_tripStatusMessage != null)
                      Text(
                        _tripStatusMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

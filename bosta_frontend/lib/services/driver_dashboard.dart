import 'dart:async';
import 'dart:convert';

import 'package:bosta_frontend/models/app_route.dart';
import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';


enum DriverStatus { offline, online }
// Enum to manage the screen's state
enum _DashboardState { loading, success, error }
class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  _DashboardState _screenState = _DashboardState.loading;
  String? _errorMessage;

  final MapController _mapController = MapController();
  DriverStatus _status = DriverStatus.offline;
  AppRoute? _assignedRoute; // Will hold the fetched route geometry

  // --- Location Tracking ---
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _locationUpdateTimer;

  @override
  void initState() {
    super.initState();
    // Use a post-frame callback to ensure the context is available for Provider.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadDriverProfile();
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDriverProfile() async {
    // Set state to loading at the beginning of a fetch attempt.
    if (mounted) {
      setState(() {
        _screenState = _DashboardState.loading;
      });
    }

    final authService = Provider.of<AuthService>(context, listen: false);

    // If driver info is already loaded, just show success.
    if (authService.currentState.driverInfo != null) {
      if (mounted) {
        // First, update the state synchronously.
        setState(() => _screenState = _DashboardState.success);
        await _fetchRouteDetails(authService.currentState.driverInfo!.routeId);
        // Then, perform the async operation.
      }
      return;
    }

    // Otherwise, fetch the profile from the backend.
    final error = await authService.fetchAndSetDriverProfile();

    if (mounted) {
      setState(() {
        if (error == null) {
          _screenState = _DashboardState.success;
          _errorMessage = null;
        } else {
          _screenState = _DashboardState.error;
          _errorMessage = error;
        }
      });
      await _fetchRouteDetails(authService.currentState.driverInfo?.routeId);
    }
  }


  /// Fetches route geometry from the backend.
  Future<void> _fetchRouteDetails(String? routeId) async {
    if (routeId == null) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.currentState.token;

    try {
      // Assuming an endpoint like /api/routes/{id}/
      final uri = Uri.parse('${ApiEndpoints.routes}$routeId/');
      // Add authorization header if the endpoint is protected
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _assignedRoute = AppRoute.fromJson(data);
            _centerOnRoute(); // Center map once route is loaded
          });
        }
      } else {
        debugPrint('Failed to load route details: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching route details: $e');
    }
  }

  // --- Location Tracking (Placeholder/Commented out for now) ---
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Location services are disabled. Please enable the services')));
      return false;
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')));
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Location permissions are permanently denied, we cannot request permissions.')));
      return false;
    }
    return true;
  }

  void _startTrip() async {
    final hasPermission = await _handleLocationPermission();
    final driverInfo = Provider.of<AuthService>(context, listen: false).currentState.driverInfo;

    if (!hasPermission || driverInfo == null) {
      debugPrint("Permission denied or driver info not available.");
      return;
    }

    setState(() => _status = DriverStatus.online);

    // Start listening to position updates for the UI
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = position);
        _mapController.move(LatLng(position.latitude, position.longitude), 16.0);
      }
    });

    // Start a timer to send updates to the backend every 10 seconds
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_currentPosition != null) {
        try {
          final token = Provider.of<AuthService>(context, listen: false).currentState.token;
          await http.post(
            Uri.parse(ApiEndpoints.updateBusLocation),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode({
              'bus_id': driverInfo.busId,
              'latitude': _currentPosition!.latitude,
              'longitude': _currentPosition!.longitude,
            }),
          );
          debugPrint("Location update sent successfully.");
        } catch (e) {
          debugPrint("Failed to send location update: $e");
        }
      }
    });
  }

  void _stopTrip() {
    _positionStreamSubscription?.cancel();
    _locationUpdateTimer?.cancel();
    setState(() {
      _status = DriverStatus.offline;
      // Keep the last known position on the map but stop updating
    });
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
  Widget _buildBody() {
    switch (_screenState) {
      case _DashboardState.loading:
        return const Center(child: CircularProgressIndicator());
      case _DashboardState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 60),
                const SizedBox(height: 16),
                Text(
                  'Failed to Load Driver Profile',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'An unknown error occurred.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  onPressed: _loadDriverProfile,
                ),
              ],
            ),
          ),
        );
      case _DashboardState.success:
        // Use a Consumer here to get the latest driverInfo after it's loaded.
        return Consumer<AuthService>(
          builder: (context, auth, child) {
            final info = auth.currentState.driverInfo;
            if (info == null) {
              // This case should ideally not be hit if logic is correct,
              // but it's a good fallback.
              return _buildErrorUI('Driver info became null unexpectedly.');
            }
            final bool isOnline = _status == DriverStatus.online;

            return Stack(
              children: [
                _buildMap(),
                _buildStatusCard(info, isOnline),
              ],
            );
          },
        );
    }
  }

  // Helper to build an error UI from anywhere
  Widget _buildErrorUI(String message) {
    _errorMessage = message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Text('An Error Occurred', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 24), // Changed to white70 for dark background
            ElevatedButton.icon(icon: const Icon(Icons.refresh), label: const Text('Try Again'), onPressed: _loadDriverProfile),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E11),
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.route),
            onPressed: _screenState == _DashboardState.loading ? null : _centerOnRoute,
            tooltip: 'Center on Route',
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(_status == DriverStatus.online),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _assignedRoute?.geometry.first ?? const LatLng(30.0444, 31.2357), // Default to Cairo
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
        ),
        if (_assignedRoute != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _assignedRoute!.geometry,
                strokeWidth: 5.0,
                color: Colors.blue.withOpacity(0.8),
              ),
            ],
          ),
        if (_currentPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                width: 80.0,
                height: 80.0,
                point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                child: const Icon(Icons.directions_bus, color: Colors.black, size: 30),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStatusCard(DriverInfo info, bool isOnline) {
    return Positioned(
      top: 10,
      left: 16,
      right: 16,
      child: Card(
        color: const Color(0xFF1F2327),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? const Color(0xFF2ED8C3) : Colors.grey,
                  boxShadow: [
                    if (isOnline)
                      BoxShadow(
                        color: const Color(0xFF2ED8C3).withOpacity(0.7),
                        blurRadius: 8,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bus ID: ${info.busId} | Route ID: ${info.routeId ?? 'N/A'}',
                    style: GoogleFonts.urbanist(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isOnline ? 'Online - Streaming Location' : 'Offline',
                    style: GoogleFonts.urbanist(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool isOnline) {
    return BottomAppBar(
      color: const Color(0xFF0B0E11),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ElevatedButton(
          onPressed: _screenState == _DashboardState.loading ? null : (isOnline ? _stopTrip : _startTrip),
          style: ElevatedButton.styleFrom(
            backgroundColor: isOnline ? Colors.red.shade700 : const Color(0xFF2ED8C3),
            foregroundColor: isOnline ? Colors.white : Colors.black,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(
            isOnline ? 'Stop Trip' : 'Start Trip',
            style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
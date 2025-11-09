import 'dart:async';

import 'package:bosta_frontend/models/bus.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:bosta_frontend/models/route_model.dart';
import 'package:bosta_frontend/services/bus_service.dart';
import 'package:bosta_frontend/services/route_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

enum DriverStatus { offline, online }

class DriverDashboardScreen extends StatefulWidget {
  final DriverInfo? driverInfo;

  const DriverDashboardScreen({super.key, this.driverInfo});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final MapController _mapController = MapController();
  DriverStatus _status = DriverStatus.offline;
  bool _isLoading = true;
  String? _errorMessage;

  Bus? _assignedBus;
  AppRoute? _assignedRoute;

  // --- Location Tracking ---
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Timer? _locationUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDriverData() async {
    if (widget.driverInfo == null) {
      setState(() {
        _errorMessage = "Driver information not available. Please log in again.";
        _isLoading = false;
      });
      return;
    }
    try {
      // Fetch assigned bus and route concurrently
      final results = await Future.wait([
        BusService.getBusById(widget.driverInfo!.busId),
        RouteService.getRouteById(widget.driverInfo!.routeId),
      ]);

      if (mounted) {
        setState(() {
          _assignedBus = results[0] as Bus;
          _assignedRoute = results[1] as AppRoute;
          _isLoading = false;
        });
        _centerOnRoute();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Failed to load driver data. Please try again.";
        });
        debugPrint("Error loading driver data: $e");
      }
    }
  }

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
    if (!hasPermission || _assignedBus == null) return;

    setState(() => _status = DriverStatus.online);

    // Start listening to position updates for the UI
    _positionStream =
        Geolocator.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = position);
        _mapController.move(LatLng(position.latitude, position.longitude), 16.0);
      }
    });

    // Start a timer to send updates to the backend every 10 seconds
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_currentPosition != null) {
        BusService.updateLocation(
          busId: _assignedBus!.id,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
        ).catchError((e) {
          debugPrint("Failed to send location update: $e");
          // Optionally show a transient error indicator
        });
      }
    });
  }

  void _stopTrip() {
    _positionStream?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final isOnline = _status == DriverStatus.online;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E11),
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.route),
            onPressed: _isLoading ? null : _centerOnRoute,
            tooltip: 'Center on Route',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)))
              : Stack(
                  children: [
                    _buildMap(),
                    _buildStatusCard(),
                  ],
                ),
      bottomNavigationBar: _buildBottomBar(isOnline),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _assignedRoute?.geometry.first ?? const LatLng(34.1216, 35.6489),
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
        ),
        if (_assignedRoute != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _assignedRoute!.geometry,
                color: Colors.grey.withOpacity(0.6),
                strokeWidth: 5,
              )
            ],
          ),
        if (_currentPosition != null && _status == DriverStatus.online)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2ED8C3),
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStatusCard() {
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
                  color: _status == DriverStatus.online ? const Color(0xFF2ED8C3) : Colors.grey,
                  boxShadow: [
                    if (_status == DriverStatus.online)
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
                    'Bus: ${_assignedBus?.plateNumber ?? 'N/A'} | Route: ${widget.driverInfo?.routeId ?? 'N/A'}',
                    style: GoogleFonts.urbanist(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _status == DriverStatus.online ? 'Online - Streaming Location' : 'Offline',
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
          onPressed: _isLoading ? null : (isOnline ? _stopTrip : _startTrip),
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
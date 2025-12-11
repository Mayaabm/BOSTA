import 'dart:async';

import 'package:bosta_frontend/models/app_route.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' as fm;
import 'package:provider/provider.dart';

class DriverDashboardScreen extends StatefulWidget {
  final String? tripId;
  const DriverDashboardScreen({super.key, this.tripId});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final MapController _mapController = MapController();
  geo.Position? _currentPosition;
  StreamSubscription<geo.Position>? _positionStream;
  Timer? _updateTimer;

  String _tripStatus = "Starting Trip...";
  String _eta = "-- min";
  String _distanceRemaining = "-- km";
  String? _destinationName;
  String? _routeName;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTrip();
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeTrip() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.fetchAndSetDriverProfile();
    final authState = authService.currentState;

    if (authState.assignedRoute == null || authState.driverInfo?.busId == null || authState.token == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Missing required trip data.";
      });
      return;
    }

    setState(() {
      _destinationName = authState.assignedRoute?.stops.last.name;
      _routeName = authState.assignedRoute?.name;
      _isLoading = false;
    });

    await _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        setState(() {
          _errorMessage = "Location permission denied.";
        });
        return;
      }
    }

    if (permission == geo.LocationPermission.deniedForever) {
      setState(() {
        _errorMessage = "Location permission permanently denied.";
      });
      return;
    }

    await _getInitialLocationAndStartUpdates();
  }

  Future<void> _getInitialLocationAndStartUpdates() async {
    try {
      final position = await geo.Geolocator.getCurrentPosition();
      setState(() => _currentPosition = position);
      _startLocationListener();
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to get initial location.";
      });
    }
  }

  void _startLocationListener() {
    const geo.LocationSettings locationSettings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStream = geo.Geolocator.getPositionStream(locationSettings: locationSettings).listen((position) {
      setState(() => _currentPosition = position);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Dashboard"),
        backgroundColor: const Color(0xFF1F2327),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF12161A),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2ED8C3)),
            )
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.urbanist(fontSize: 16, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                )
              : Stack(
                  children: [
                    _buildMap(),
                    _buildTripInfoCard(),
                  ],
                ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        center: _currentPosition != null
            ? fm.LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : const fm.LatLng(34.1216, 35.6489),
        zoom: 15.0,
      ),
      children: [
        TileLayer(
          urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
          subdomains: ['a', 'b', 'c'],
        ),
        MarkerLayer(
          markers: [
            if (_currentPosition != null)
              Marker(
                point: fm.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.red,
                  size: 40,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildTripInfoCard() {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Card(
        color: const Color(0xFF1F2327),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _tripStatus,
                style: GoogleFonts.urbanist(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoTile("ETA", _eta),
                  _buildInfoTile("Distance", _distanceRemaining),
                ],
              ),
              const SizedBox(height: 8),
              if (_destinationName != null)
                Text(
                  "Destination: $_destinationName",
                  style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[400]),
                ),
              if (_routeName != null)
                Text(
                  "Route: $_routeName",
                  style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[400]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.urbanist(fontSize: 14, color: Colors.grey[400]),
        ),
        Text(
          value,
          style: GoogleFonts.urbanist(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
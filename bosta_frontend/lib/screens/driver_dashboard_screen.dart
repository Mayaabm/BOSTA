
import 'dart:async';

import 'package:bosta_frontend/models/app_route.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' as fm;
import 'package:provider/provider.dart';
import '../services/bus_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bosta_frontend/services/trip_service.dart';
import 'package:bosta_frontend/services/trip_service.dart' as TS;

class DriverDashboardScreen extends StatefulWidget {
  final String? tripId;
  const DriverDashboardScreen({super.key, this.tripId});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  geo.Position? _currentPosition;
  StreamSubscription<geo.Position>? _positionStream;
  Timer? _updateTimer;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  AppRoute? _assignedRoute;

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
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.6).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTrip();
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _updateTimer?.cancel();
    _pulseController.dispose();
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
      _assignedRoute = authState.assignedRoute;
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

      // Fetch route info immediately and then periodically
      await _fetchRouteAndUpdateInfo();
      _updateTimer?.cancel();
      _updateTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
        await _fetchRouteAndUpdateInfo();
      });
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
      // Send the new location to the backend so riders can see this bus
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        final token = authService.currentState.token;
        final busId = authService.currentState.driverInfo?.busId;
        if (token != null && busId != null) {
          BusService.updateLocation(
            busId: busId.toString(),
            latitude: position.latitude,
            longitude: position.longitude,
            token: token,
          );
        }
      } catch (e) {
        debugPrint('Failed to post driver location: $e');
      }

      // Update route info when position changes (distanceFilter reduces frequency)
      _fetchRouteAndUpdateInfo();
    });
  }

  Future<void> _updateTripInfoFromRoute(Map<String, dynamic> routeData) async {
    try {
      // Safely extract distance and duration (Mapbox may return int or double)
      final routes = routeData['routes'];
      if (routes is List && routes.isNotEmpty) {
        final first = routes.first as Map<String, dynamic>;
        final num distanceMetersNum = (first['distance'] is num) ? first['distance'] as num : num.parse(first['distance'].toString());
        final num durationSecondsNum = (first['duration'] is num) ? first['duration'] as num : num.parse(first['duration'].toString());

        final distanceKm = (distanceMetersNum.toDouble() / 1000).toStringAsFixed(2);
        final etaMinutes = (durationSecondsNum.toDouble() / 60).round();

        setState(() {
          _distanceRemaining = "$distanceKm km";
          _eta = "$etaMinutes min";
        });
        return;
      }
      debugPrint("No routes found in routeData: $routeData");
    } catch (e) {
      debugPrint("Error updating trip info: $e");
    }
  }

  Future<void> _fetchRouteAndUpdateInfo() async {
    try {
      // Simulate fetching route data from Mapbox Directions API
      final routeData = await _getRouteDataFromMapbox(); // Replace with actual API call
      await _updateTripInfoFromRoute(routeData);
    } catch (e) {
      debugPrint("Error fetching route: $e");
    }
  }

  Future<Map<String, dynamic>> _getRouteDataFromMapbox() async {
    try {
      if (_currentPosition == null || _assignedRoute == null || _assignedRoute!.stops.isEmpty) {
        return {'routes': []};
      }

      final origin = '${_currentPosition!.longitude},${_currentPosition!.latitude}';
      final destStop = _assignedRoute!.stops.last.location;
      final dest = '${destStop.longitude},${destStop.latitude}';

      final token = TripService.getMapboxAccessToken();
      final url = 'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$origin;$dest?access_token=$token&overview=full&geometries=geojson';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        return data;
      } else {
        debugPrint('Mapbox directions error: ${resp.statusCode} ${resp.body}');
        return {'routes': []};
      }
    } catch (e) {
      debugPrint('Exception fetching Mapbox directions: $e');
      return {'routes': []};
    }
  }
  Widget _buildMap() {
    final String cartoUrl = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
    // Stadia dark tiles are CORS-friendly and visually similar to CartoDB dark
    final String stadiaDarkUrl = 'https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png';

    final String tileUrl = kIsWeb ? stadiaDarkUrl : cartoUrl;

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
          urlTemplate: tileUrl,
          subdomains: kIsWeb ? const <String>[] : const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.bosta.app',
          additionalOptions: kIsWeb
              ? const <String, String>{}
              : const <String, String>{
                  'userAgent': 'com.bosta.app',
                },
        ),
        if (_assignedRoute != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _assignedRoute!.geometry,
                color: const Color(0xFF2ED8C3),
                strokeWidth: 5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (_currentPosition != null)
              Marker(
                point: fm.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                width: 80,
                height: 80,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    final double scale = _pulseAnimation.value;
                    return Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 24 * scale,
                            height: 24 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue.withOpacity(0.25 * (2 - scale)),
                            ),
                          ),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                              boxShadow: [
                                BoxShadow(color: Colors.blue.withOpacity(0.6), blurRadius: 8, spreadRadius: 1),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Dashboard"),
        backgroundColor: const Color(0xFF1F2327),
        foregroundColor: Colors.white,
        actions: [
          // Show Stop Trip button when we have a tripId or route assigned
          if (widget.tripId != null)
            TextButton.icon(
              onPressed: _stopTrip,
              icon: const Icon(Icons.stop, color: Colors.white),
              label: const Text('Stop Trip', style: TextStyle(color: Colors.white)),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
        ],
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

  Future<void> _stopTrip() async {
    // Confirm with the driver first
    final should = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Trip'),
        content: const Text('Are you sure you want to end this trip?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('End Trip')),
        ],
      ),
    );

    if (should != true) return;

    setState(() => _tripStatus = 'Ending trip...');

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.currentState.token;
      String? tripId = widget.tripId;
      if (token == null) throw Exception('Missing auth token');

      // If tripId wasn't passed in, try to discover it from backend/profile
      if (tripId == null) {
        tripId = await TS.TripService.checkForActiveTrip(token);
        if (tripId == null) throw Exception('No active trip found');
      }

      await TripService.endTrip(token, tripId);

      // Stop updates and listeners
      _positionStream?.cancel();
      _updateTimer?.cancel();

      setState(() {
        _tripStatus = 'Trip ended';
        _eta = '-- min';
        _distanceRemaining = '-- km';
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip ended successfully')));
    } catch (e) {
      debugPrint('Error ending trip: $e');
      setState(() => _tripStatus = 'Error ending trip');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to end trip: $e')));
    }
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

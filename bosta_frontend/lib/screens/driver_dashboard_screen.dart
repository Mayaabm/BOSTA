import 'dart:async';
import 'dart:convert';

import 'package:bosta_frontend/models/app_route.dart';
import 'package:bosta_frontend/screens/rider_home_screen.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:bosta_frontend/services/trip_service.dart';
import 'package:bosta_frontend/services/bus_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as fm;
import 'package:provider/provider.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final MapController _mapController = MapController();
  geo.Position? _currentPosition;
  StreamSubscription<geo.Position>? _positionStream;
  Timer? _updateTimer;

  // State for ETA and trip details
  String _tripStatus = "Starting Trip...";
  String _eta = "-- min";
  String _distanceRemaining = "-- km";
  String? _destinationName;

  bool _isLoading = true;
  String? _errorMessage;
  bool _isTripEnded = false;

  // Store route and bus info from AuthService
  AppRoute? _assignedRoute;
  String? _busId;
  RouteStop? _destinationStop;
  String? _authToken;
  String? _activeTripId;
  List<fm.LatLng> _tripRouteGeometry = []; // To store the specific part of the route for this trip

  @override
  void initState() {
    super.initState();
    // Use a post-frame callback to ensure the context is ready for Provider.
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

  /// Initializes the map, location services, and fetches initial trip data.
  Future<void> _initializeTrip() async {
    if (!mounted) return;

    final authState = Provider.of<AuthService>(context, listen: false).currentState;
    if (authState.assignedRoute == null || authState.driverInfo == null || authState.token == null) {
      setState(() {
        _errorMessage = "Could not load trip data. Please go back and set up the trip again.";
        _isLoading = false;
      });
      return;
    }

    // Fetch the active trip ID.
    final tripId = await TripService.checkForActiveTrip(authState.token!);
    if (tripId == null) {
      setState(() {
        _errorMessage = "No active trip found. Please start a new trip from the onboarding screen.";
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _assignedRoute = authState.assignedRoute;
      _busId = authState.driverInfo!.busId;
      _authToken = authState.token;
      if (_assignedRoute != null && authState.selectedEndStopId != null) {
        try {
          _destinationStop = _assignedRoute!.stops.firstWhere((stop) => stop.id == authState.selectedEndStopId);
          _destinationName = 'Stop ${_destinationStop!.order}';
        } catch (e) {
          // Fallback if the selected end stop ID is not found in the route's stops
          _destinationStop = _assignedRoute!.stops.last;
          _destinationName = 'Final Destination';
        }
      } else if (_assignedRoute != null && _assignedRoute!.stops.isNotEmpty) {
        _destinationStop = _assignedRoute!.stops.last;
        _destinationName = 'Final Destination';
      }
      _activeTripId = tripId;

      // Calculate the specific route segment for this trip
      _calculateTripGeometry();
    });

    // Check for location permissions before proceeding.
    await _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        setState(() {
          _errorMessage = "Location permissions are required to track your trip.";
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == geo.LocationPermission.deniedForever) {
      setState(() {
        _errorMessage = "Location permissions are permanently denied. Please enable them in your device settings.";
        _isLoading = false;
      });
    } else {
      // Permissions are granted, proceed with location-dependent setup.
      _startLocationListener();
      await _getInitialLocationAndStartUpdates();
    }
  }

  /// Calculates the portion of the route from the start point to the destination.
  void _calculateTripGeometry() {
    if (_assignedRoute == null || _assignedRoute!.geometry.isEmpty || _destinationStop == null) {
      return;
    }

    final authState = Provider.of<AuthService>(context, listen: false).currentState;
    final fullGeometry = _assignedRoute!.geometry;

    // Determine the start and end coordinates for the trip segment.
    final startPoint = authState.initialBusPosition;
    final endPoint = fm.LatLng(_destinationStop!.location.latitude, _destinationStop!.location.longitude);

    if (startPoint == null) {
      // If for some reason we don't have a start point, show the whole route.
      setState(() => _tripRouteGeometry = fullGeometry);
      return;
    }

    // Find the index of the point in the full geometry that is closest to our start and end points.
    int startIndex = _findClosestPointIndex(startPoint, fullGeometry);
    int endIndex = _findClosestPointIndex(endPoint, fullGeometry);

    if (startIndex == -1 || endIndex == -1 || startIndex >= endIndex) {
      // If points are not found or are in the wrong order, fallback to the full route.
      setState(() => _tripRouteGeometry = fullGeometry);
      return;
    }

    // Create the sub-list for the trip.
    // We also add the precise start and end points to make the line exact.
    final tripGeometry = [
      startPoint,
      ...fullGeometry.sublist(startIndex, endIndex + 1),
      endPoint,
    ];

    setState(() => _tripRouteGeometry = tripGeometry);
  }

  /// Finds the index of the closest point in a polyline to a given point.
  int _findClosestPointIndex(fm.LatLng point, List<fm.LatLng> polyline) {
    if (polyline.isEmpty) return -1;

    double minDistance = double.infinity;
    int closestIndex = -1;
    const distance = fm.Distance();

    for (int i = 0; i < polyline.length; i++) {
      final d = distance(point, polyline[i]);
      if (d < minDistance) {
        minDistance = d;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  /// Listens to continuous location updates from the device.
  void _startLocationListener() {
    const geo.LocationSettings locationSettings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionStream = geo.Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (position) {
        if (mounted && !_isTripEnded) {
          setState(() => _currentPosition = position);
          _updateDriverMarker(position);
        }
      },
      onError: (error) {
        debugPrint("Location stream error: $error");
        setState(() => _errorMessage = "Lost GPS signal.");
      },
    );
  }

  Future<void> _getInitialLocationAndStartUpdates() async {
    try {
      final geo.Position position = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high);
      if (!mounted) return;

      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });

      _mapController.move(
        fm.LatLng(position.latitude, position.longitude),
        15.0,
      );

      _fetchEtaAndUpdateBackend(); // Initial fetch
      // Start periodic updates
      _updateTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (!_isTripEnded) {
          _fetchEtaAndUpdateBackend();
        }
      });
    } catch (e) {
      debugPrint("Error getting initial location: $e");
      setState(() {
        _errorMessage = "Could not get initial location. Please ensure GPS is enabled.";
        _isLoading = false;
      });
    }
  }

  /// Updates the driver's marker on the map.
  Future<void> _updateDriverMarker(geo.Position position) async {
    // With flutter_map, we just need to call setState to rebuild the MarkerLayer
    // with the new _currentPosition. The listen callback in _startLocationListener
    // already does this.
  }

  /// Fetches ETA from Mapbox and updates the backend with the current location.
  Future<void> _fetchEtaAndUpdateBackend() async {
    if (_isTripEnded || _currentPosition == null ||
        _destinationStop == null ||
        _busId == null ||
        _authToken == null) {
      return;
    }

    // 1. Update our backend with the current location
    final authService = Provider.of<AuthService>(context, listen: false);
    
    debugPrint("\n=== ETA FETCH DEBUG ===");
    debugPrint("[ETA] Bus ID: $_busId");
    debugPrint("[ETA] Current position: LAT=${_currentPosition!.latitude.toStringAsFixed(6)}, LON=${_currentPosition!.longitude.toStringAsFixed(6)}");
    debugPrint("[ETA] Destination stop ID: ${_destinationStop!.id}");
    debugPrint("[ETA] Destination: LAT=${_destinationStop!.location.latitude.toStringAsFixed(6)}, LON=${_destinationStop!.location.longitude.toStringAsFixed(6)}");
    
    try {
      await BusService.updateLocation(
        busId: _busId!,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        token: _authToken!,
        authService: authService,
      );
      debugPrint("[ETA] Backend location updated successfully");
    } catch (e) {
      debugPrint("Failed to update backend location: $e");
      // Non-fatal, we can still try to get ETA.
    }

    // 2. Fetch ETA from Mapbox Directions API
    final destination = _destinationStop!.location;
    final originCoords =
        "${_currentPosition!.longitude},${_currentPosition!.latitude}";
    final destCoords = "${destination.longitude},${destination.latitude}";

    debugPrint("[ETA] Mapbox Origin coords: $originCoords");
    debugPrint("[ETA] Mapbox Destination coords: $destCoords");

    final url =
        'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$originCoords;$destCoords?access_token=${TripService.getMapboxAccessToken()}&overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint("[ETA] Mapbox response status: ${response.statusCode}");
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final double durationSeconds = route['duration']?.toDouble() ?? 0.0;
          final double distanceMeters = route['distance']?.toDouble() ?? 0.0;

          debugPrint("[ETA] Mapbox distance: ${(distanceMeters/1000).toStringAsFixed(2)} km");
          debugPrint("[ETA] Mapbox duration: ${(durationSeconds/60).toStringAsFixed(1)} min");
          debugPrint("=== ETA FETCH DEBUG (SUCCESS) ===\n");

          if (mounted) {
            setState(() {
              _eta = "${(durationSeconds / 60).ceil()} min";
              _distanceRemaining =
                  "${(distanceMeters / 1000).toStringAsFixed(1)} km";
              _tripStatus = "En Route";
              _errorMessage = null;
            });
          }
        }
      } else {
        throw Exception('Failed to load directions: ${response.body}');
      }
    } catch (e) {
      debugPrint("Error fetching Mapbox ETA: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "Could not calculate ETA.";
        });
      }
    }
  }

  Future<void> _endTrip() async {
    if (_authToken == null || _activeTripId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error: Cannot end trip, missing trip information.")),
      );
      return;
    }

    // Show confirmation dialog
    final bool? confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Trip?'),
        content: const Text('Are you sure you want to end the current trip?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('End Trip')),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await TripService.endTrip(_authToken!, _activeTripId!);
        setState(() {
          _isTripEnded = true;
          _isLoading = false;
          _tripStatus = "Completed";
        });
        _positionStream?.cancel();
        _updateTimer?.cancel();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Trip ended successfully.")),
        );
        // Navigate back to the driver home/onboarding screen
        if (mounted) GoRouter.of(context).go('/driver/home');
      } catch (e) {
        debugPrint("Failed to end trip: $e");
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to end trip: ${e.toString()}")),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12161A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2327),
        foregroundColor: Colors.white,
        title: Text('Driver Dashboard', style: GoogleFonts.urbanist()),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              if (_currentPosition != null) {
                _mapController.move(
                  fm.LatLng(
                      _currentPosition!.latitude, _currentPosition!.longitude),
                  15.0,
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
            onPressed: _isTripEnded ? null : _endTrip,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const fm.LatLng(33.8938, 35.5018), // Fallback to Beirut
              initialZoom: 12.0,
              onMapReady: () {
                if (_currentPosition != null) {
                  _mapController.move(
                      fm.LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      15.0);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.bosta.app',
              ),
              if (_tripRouteGeometry.isNotEmpty)
                PolylineLayer(polylines: [
                  Polyline(
                    points: _tripRouteGeometry,
                    color: const Color(0xFF2ED8C3),
                    strokeWidth: 5,
                  ),
                ]),
              if (_currentPosition != null)
                MarkerLayer(markers: [
                  _buildDriverMarker(),
                ]),
            ]),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF2ED8C3)),
              ),
            ),
          if (_errorMessage != null && !_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),
            ),
          _buildTripInfoCard(),
        ],
      ),
    );
  }

  Marker _buildDriverMarker() {
    return Marker(
      point: fm.LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      width: 60,
      height: 60,
      child: const _BusMarker(
        // Using the same marker style as the rider screen for consistency
        pulseController: null, // No pulse needed for the driver's own marker
        isSelected: true,
        busColor: Colors.white,
        iconColor: Color(0xFF12161A),
      ),
    );
  }

  Widget _buildTripInfoCard() {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Card(
        color: const Color(0xFF1F2327).withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trip to: ${_destinationName ?? "Final Stop"}',
                style: GoogleFonts.urbanist(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildInfoTile(
                    icon: Icons.timer_outlined,
                    label: 'ETA',
                    value: _eta,
                  ),
                  _buildInfoTile(
                    icon: Icons.space_dashboard_outlined,
                    label: 'Distance',
                    value: _distanceRemaining,
                  ),
                  _buildInfoTile(
                    icon: Icons.circle,
                    label: 'Status',
                    value: _tripStatus,
                    iconColor:
                        _tripStatus == "En Route" ? Colors.green : 
                        (_tripStatus == "Completed" ? Colors.grey : Colors.orange),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
  }) {
    return Column(
      children: [
        Icon(icon, color: iconColor ?? const Color(0xFF2ED8C3), size: 28),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.urbanist(color: Colors.grey[400], fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.urbanist(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// Re-using the bus marker from rider_home_screen for consistency.
// A better approach would be to extract this to its own file.
class _BusMarker extends StatelessWidget {
  final AnimationController? pulseController;
  final bool isSelected;
  final Color busColor;
  final Color iconColor;

  const _BusMarker({
    this.pulseController,
    this.isSelected = false,
    required this.busColor,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final controller = pulseController;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing animation, shown only when selected and controller is available
        if (isSelected && controller != null)
          FadeTransition(
            opacity:
                Tween<double>(begin: 0.7, end: 0.2).animate(controller),
            child: ScaleTransition(
              scale:
                  Tween<double>(begin: 1.0, end: 2.5).animate(controller),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: busColor.withOpacity(0.5),
                ),
              ),
            ),
          ),
        // Main bus icon container
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? busColor : const Color(0xFF12161A),
            border: Border.all(
              color: isSelected ? const Color(0xFF12161A) : busColor,
              width: isSelected ? 3 : 2,
            ),
          ),
          child: Icon(
            Icons.directions_bus,
            color: isSelected ? iconColor : busColor,
            size: 16,
          ),
        ),
      ],
    );
  }
}
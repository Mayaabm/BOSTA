import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bosta_frontend/models/app_route.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:bosta_frontend/services/trip_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:bosta_frontend/services/bus_service.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  PointAnnotation? _driverAnnotation;
  PolylineAnnotationManager? _polylineAnnotationManager;

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
  String? _authToken;
  String? _activeTripId;

  // IMPORTANT: For production, load this from a config file or via --dart-define.
  static const String _mapboxAccessToken =
      'pk.eyJ1IjoibWF5YWJlMzMzIiwiYSI6ImNtaWcxZmV6ZTAyOXozY3FzMHZqYzhrYzgifQ.qJnThdfDGW9MUkDNrvoEoA';

  static const String ROUTE_SOURCE_ID = "route-source";
  static const String ROUTE_LAYER_ID = "route-layer";
  static const String DRIVER_ICON_ID = "driver-icon";
  static const String DRIVER_MARKER_IMAGE_ID = "driver-marker-image";

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
      if (_assignedRoute!.stops.isNotEmpty) {
        final lastStop = _assignedRoute!.stops.last;
        // The RouteStop model has 'order' and 'location', but not 'name'.
        // We will construct a descriptive name from the available data.
        if (lastStop.order != null) {
          _destinationName = 'Stop ${lastStop.order}';
        } else {
          _destinationName = 'Final Destination';
        }
      }
      _activeTripId = tripId;
    });

    await _checkLocationPermission();
    _startLocationListener();
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
    }
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

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    
    // Setup map images first
    await _setupMapImages();
    
    // Initialize managers and then load assets and data.
    final managers = await Future.wait([
      _mapboxMap!.annotations.createPointAnnotationManager(),
      _mapboxMap!.annotations.createPolylineAnnotationManager(),
    ]);
    
    _pointAnnotationManager = managers[0] as PointAnnotationManager;
    _polylineAnnotationManager = managers[1] as PolylineAnnotationManager;
    await _drawRoute();
    
    // Once map is ready, get first location and start updates
    await _getInitialLocationAndStartUpdates();
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

      _mapboxMap?.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(position.longitude, position.latitude),
          ).toJson(),
          zoom: 15,
        ),
        MapAnimationOptions(duration: 1500),
      );

      _updateDriverMarker(position);
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

  /// Draws the assigned route on the map.
  Future<void> _drawRoute() async {
    if (_assignedRoute == null || _polylineAnnotationManager == null) return;

    final List<Position> routePositions = _assignedRoute!.geometry
        .map((latlng) => Position(latlng.longitude, latlng.latitude))
        .toList();

    _polylineAnnotationManager?.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: routePositions).toJson(),
        lineColor: Colors.teal.value,
        lineWidth: 5.0,
        lineOpacity: 0.8,
      ),
    );
  }

  /// Updates the driver's marker on the map.
  Future<void> _updateDriverMarker(geo.Position position) async {
    if (_pointAnnotationManager == null || !mounted) return;

    final newPoint = Point(
        coordinates: Position(position.longitude, position.latitude));

    if (_driverAnnotation == null) {
      // Create the annotation if it doesn't exist
      final options = PointAnnotationOptions(
        geometry: newPoint.toJson(),
        iconImage: DRIVER_MARKER_IMAGE_ID,
        iconSize: 1.5,
      );
      _driverAnnotation = await _pointAnnotationManager?.create(options);
    } else {
      // Otherwise, just update its geometry
      _driverAnnotation!.geometry = newPoint.toJson();
      _pointAnnotationManager?.update(_driverAnnotation!);
    }
  }

  /// Fetches ETA from Mapbox and updates the backend with the current location.
  Future<void> _fetchEtaAndUpdateBackend() async {
    if (_isTripEnded || _currentPosition == null ||
        _assignedRoute == null ||
        _assignedRoute!.stops.isEmpty ||
        _busId == null ||
        _authToken == null) {
      return;
    }

    // 1. Update our backend with the current location
    try {
      await BusService.updateLocation(
        busId: _busId!,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        token: _authToken!,
      );
    } catch (e) {
      debugPrint("Failed to update backend location: $e");
      // Non-fatal, we can still try to get ETA.
    }

    // 2. Fetch ETA from Mapbox Directions API
    final destination = _assignedRoute!.stops.last.location;
    final originCoords =
        "${_currentPosition!.longitude},${_currentPosition!.latitude}";
    final destCoords = "${destination.longitude},${destination.latitude}";


    final url =
        'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$originCoords;$destCoords?access_token=$_mapboxAccessToken&overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final double durationSeconds = route['duration']?.toDouble() ?? 0.0;
          final double distanceMeters = route['distance']?.toDouble() ?? 0.0;

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

  /// Loads the bus icon from assets and adds it to the map's style.
  Future<void> _setupMapImages() async {
    try {
      final ByteData byteData = await rootBundle.load('assets/bus-icon.png');
      final Uint8List list = byteData.buffer.asUint8List();
      await _mapboxMap?.style.addStyleImage(
        DRIVER_MARKER_IMAGE_ID,
        1.5,
        MbxImage(width: 50, height: 50, data: list),
        false,
        [],
        [],
        null,
      );
    } catch (e) {
      debugPrint("Error loading bus icon: $e");
      // Non-fatal, marker will use default icon
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
              if (_currentPosition != null && _mapboxMap != null) {
                _mapboxMap!.flyTo(
                  CameraOptions(
                    center: Point(
                      coordinates: Position(_currentPosition!.longitude,
                          _currentPosition!.latitude),
                    ).toJson(),
                    zoom: 15,
                  ),
                  MapAnimationOptions(duration: 1000),
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
          MapWidget(
            resourceOptions: ResourceOptions(accessToken: _mapboxAccessToken),
            key: const ValueKey("mapboxMap"),
            styleUri: MapboxStyles.DARK,
            onMapCreated: _onMapCreated,
            cameraOptions: CameraOptions(
              // Fallback center
              center: Point(
                      coordinates: Position(35.5018, 33.8938))
                  .toJson(),
              zoom: 12.0,
            ),
          ),
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
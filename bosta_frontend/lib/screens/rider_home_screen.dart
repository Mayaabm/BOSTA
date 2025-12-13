import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter_map/flutter_map.dart';
// Import for kDebugMode
import 'package:bosta_frontend/models/user_location.dart';
import 'package:bosta_frontend/screens/where_to_search_bar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:provider/provider.dart';

import '../models/bus.dart'; // Using the actual model
import '../services/api_endpoints.dart';
import '../models/app_route.dart'; // Using the unified route model
import '../models/trip_suggestion.dart';
import '../services/trip_service.dart';
import '../services/bus_service.dart'; // Using the actual service
import '../services/auth_service.dart'; // For getting auth token
import 'destination_result.dart';
// Using the actual service
import 'bus_bottom_sheet.dart';
import 'bus_details_modal.dart';

import 'package:http/http.dart' as http;
enum RiderView { planTrip, nearbyBuses }

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState(); // No longer nested
}

class _RiderHomeScreenState extends State<RiderHomeScreen> with TickerProviderStateMixin {
    // ETA state for selected bus
    String? _etaBusToRider;
    bool _isFetchingEta = false;
  final MapController mapController = MapController();
  final PanelController _panelController = PanelController();
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Timer? _busUpdateTimer;
  Timer? _mockLocationPollTimer;

  // State for Route 224
  // static const String _targetRouteId = '224'; // No longer needed for nearby buses
  AppRoute? _selectedBusRoute; // To store the route of the *selected* bus
  List<Bus> _displayedBuses = [];
  // bool _isNearRoute = false; // No longer needed, we fetch based on location

  RiderView _currentView = RiderView.planTrip;
  List<TripSuggestion> _tripSuggestions = []; // For trip planning
  Bus? _selectedBus;
  Timer? _selectedBusDetailsTimer;
  bool _isAutoCentering = false;
  bool _useMockLocation = false; // Dev toggle

  // State for route-filtered buses
  String? _selectedRouteId;

  // Animation for bus markers
  late final AnimationController _pulseController; // For bus marker pulse animation
  late final AnimationController _markerAnimationController;

  // Search controllers
  Animation<LatLng>? _markerAnimation;

  @override
  void initState() {
    super.initState();
    _markerAnimationController = AnimationController(vsync: this, duration: const Duration(seconds: 2));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _initializeUserLocation();
    _listenToMapEvents();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _busUpdateTimer?.cancel();
    _selectedBusDetailsTimer?.cancel();
    _mockLocationPollTimer?.cancel();
    _markerAnimationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initializeUserLocation() async {
    if (_useMockLocation) {
      _startMockLocationPoll();
      return;
    }
    // In release mode, or if the route isn't available for simulation, use real GPS.
    await Geolocator.requestPermission();
    final position = await Geolocator.getCurrentPosition();
    if (mounted) setState(() => _currentPosition = position);
    _startListeningToLocation(); // Start listening for real location updates.

    // Once location is set (real or mock), move the map and start fetching buses.
    if (_currentPosition != null) {
      mapController.move(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 14.0);
      // If the initial view is 'Nearby Buses', load them immediately.
      if (_currentView == RiderView.nearbyBuses) {
        _loadNearbyBuses();
      }
    }
  }

  /// Fetches the target route and checks for nearby buses.
  /// This is now called explicitly when the user wants to see nearby buses.
  Future<void> _loadNearbyBuses() async {
    // We just need to fetch buses and start the timer.
    // The route information is no longer needed upfront.
    await _fetchNearbyBuses();
    _startPeriodicBusUpdates();
  }

  void _startListeningToLocation() {
    // Don't listen to real GPS if we are using mock locations
    if (_useMockLocation) {
      _positionStream?.cancel();
      return;
    }
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          // If we are auto-centering on a bus, we might not want to move the map here.
          // For now, we just update the position data.
        });
      }
    });
  }

  /// Starts polling the backend for the mock rider location.
  void _startMockLocationPoll() {
    _mockLocationPollTimer?.cancel();

    Future<void> fetchAndApply() async {
      try {
        final uri = Uri.parse(ApiEndpoints.devRiderLocation);
        final response = await http.get(uri);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final lat = data['latitude'];
          final lon = data['longitude'];

          if (lat != null && lon != null) {
            final mockPosition = Position(
              latitude: lat,
              longitude: lon,
              timestamp: DateTime.now(),
              accuracy: 5.0, altitude: 0.0, heading: 0.0, speed: 0.0, speedAccuracy: 0.0,
              altitudeAccuracy: 0.0, headingAccuracy: 0.0,
            );

            if (mounted) {
              setState(() => _currentPosition = mockPosition);
              // If this is the first time, move the map.
              if (_mockLocationPollTimer == null) {
                mapController.move(LatLng(lat, lon), 14.0);
              }
              // --- FIX: Immediately fetch buses after location update ---
              // This ensures the "nearby buses" list updates as soon as the
              // mock location changes, instead of waiting for the next timer tick.
              _fetchNearbyBuses();
              _startPeriodicBusUpdates(); // Also ensure the timer is running.
            }
          }
        }
      } catch (e) {
        debugPrint("Failed to fetch mock rider location: $e");
      }
    }

    fetchAndApply(); // Fetch immediately
    _mockLocationPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => fetchAndApply());
  }

  void _stopMockLocationPoll() {
    _mockLocationPollTimer?.cancel();
    _mockLocationPollTimer = null;
  }
  void _listenToMapEvents() {
    mapController.mapEventStream.listen((event) {
      // If the user manually moves the map (e.g., pan or pinch zoom)
      // while auto-centering is active, disable it.
      if (_isAutoCentering &&
          (event is MapEventMove ||
              event is MapEventRotate ||
              event is MapEventDoubleTapZoom)) {
        // This function safely checks if the event was triggered by user input,
        // handling breaking changes across flutter_map versions.
        bool isUserInput(MapEvent event) {
          // flutter_map v6+ uses `MapEventSource.input`
          // flutter_map v5 used `MapEventSource.fromInput`
          // Older versions might use `MapEventSource.tap` or `MapEventSource.drag`
          final sourceName = event.source.toString().split('.').last;
          return sourceName == 'input' ||
                 sourceName == 'fromInput' ||
                 sourceName == 'tap' ||
                 sourceName == 'drag' ||
                 sourceName == 'doubleTap' ||
                 sourceName == 'longPress';
        }

        if (isUserInput(event)) {
          setState(() => _isAutoCentering = false);
        }
      }
    });
  }

  void _startPeriodicBusUpdates() {
    _busUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) {
        // Only fetch if the "Nearby Buses" view is active.
        if (_currentView == RiderView.nearbyBuses) {
          _fetchNearbyBuses();
        } else {
          timer.cancel(); // Stop polling if user switches away
        }
      },
    );
  }

  Future<void> _fetchNearbyBuses() async {
    if (_currentPosition == null) return;
    try {
      final buses = await BusService.getNearbyBuses(latitude: _currentPosition!.latitude, longitude: _currentPosition!.longitude);
      if (mounted) setState(() => _displayedBuses = buses);
    } catch (e) {
      debugPrint("Error fetching nearby buses: $e");
    }
  }

  void _onBusMarkerTapped(Bus bus) {
    setState(() {
      _selectedBus = bus;
      _isAutoCentering = true; // Enable auto-centering
      _centerOnSelectedBus(); // Immediately move map to the bus
      _fetchRouteForSelectedBus(bus.id); // Fetch the route for the selected bus
    });

    // Stop any previous timer
    _selectedBusDetailsTimer?.cancel();

    // Fetch ETA from bus to rider location
    _fetchEtaBusToRider(bus);

    // Show the modal with live updates
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // Get auth token from Provider
        final authToken = Provider.of<AuthService>(context, listen: false).currentState.token;
        
        return BusDetailsModal(
          busId: bus.id,
          userLocation: _currentPosition != null
              ? UserLocation(latitude: _currentPosition!.latitude, longitude: _currentPosition!.longitude)
              : null,
          authToken: authToken,
          onChooseBus: () {
            // This would be the action to confirm the trip
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Trip with Bus ${bus.plateNumber} confirmed!")),
            );
          },
        );
      },
    ).whenComplete(() {
      // When the modal is closed, deselect the bus and stop updates
      _deselectBus();
    });

    // Start polling for this specific bus's details
    _selectedBusDetailsTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchSelectedBusDetails(bus.id);
    });
  }

  void _deselectBus() {
    setState(() {
      _selectedBus = null;
      _selectedBusDetailsTimer?.cancel();
      _markerAnimation = null;
      _selectedBusRoute = null; // Clear the route when deselecting
      _isAutoCentering = false;
      _etaBusToRider = null;
      _selectedRouteId = null; // Clear selected route
      _isFetchingEta = false;
    });
  }

  Future<void> _fetchEtaBusToRider(Bus bus) async {
    if (_currentPosition == null) return;
    setState(() {
      _isFetchingEta = true;
      _etaBusToRider = null;
    });
    debugPrint("[Rider] Fetching ETA for bus ${bus.id} to rider...");
    try {
      final busLat = bus.latitude;
      final busLon = bus.longitude;
      final riderLat = _currentPosition!.latitude;
      final riderLon = _currentPosition!.longitude;
      final originCoords = "$busLon,$busLat";
      final destCoords = "$riderLon,$riderLat";
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$originCoords;$destCoords?access_token=${TripService.getMapboxAccessToken()}&overview=full&geometries=geojson';
      debugPrint("[Rider] Mapbox ETA bus→rider: $url");
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final double durationSeconds = route['duration']?.toDouble() ?? 0.0;
          final double distanceMeters = route['distance']?.toDouble() ?? 0.0;
          debugPrint("[Rider] ETA bus→rider: "+
              "${(durationSeconds/60).toStringAsFixed(1)} min, ${(distanceMeters/1000).toStringAsFixed(2)} km");
          setState(() {
            _etaBusToRider = "${(durationSeconds/60).ceil()} min";
          });
        } else {
          debugPrint("[Rider] No route found for bus→rider");
          setState(() {
            _etaBusToRider = "--";
          });
        }
      } else {
        debugPrint("[Rider] Mapbox error for bus→rider: ${resp.statusCode}");
        setState(() {
          _etaBusToRider = "--";
        });
      }
    } catch (e) {
      debugPrint("[Rider] Exception fetching ETA: $e");
      setState(() {
        _etaBusToRider = "--";
      });
    }
    if (mounted) setState(() { _isFetchingEta = false; });
  }

  Future<void> _fetchSelectedBusDetails(String busId) async {
    try {
      final updatedBus = await BusService.getBusDetails(busId,
          userLocation: _currentPosition != null
              ? UserLocation(latitude: _currentPosition!.latitude, longitude: _currentPosition!.longitude)
              : null);
      if (mounted && _selectedBus != null) {
        final oldPosition = LatLng(_selectedBus!.latitude, _selectedBus!.longitude);
        final newPosition = LatLng(updatedBus.latitude, updatedBus.longitude);

        setState(() {
          _selectedBus = updatedBus;
          _markerAnimation = LatLngTween(begin: oldPosition, end: newPosition).animate(
            CurvedAnimation(parent: _markerAnimationController, curve: Curves.linear),
          );
        });
        _markerAnimationController.forward(from: 0.0);

        if (_isAutoCentering) {
          _centerOnSelectedBus(animated: true);
        }
      }
    } catch (e) {
      debugPrint("Error fetching details for bus $busId: $e");
      // If the bus is no longer found, deselect it
      _deselectBus();
    }
  }

  Future<void> _fetchRouteForSelectedBus(String busId) async {
    try {
      // We get the bus details which should contain the route object
      final bus = await BusService.getBusDetails(busId);
      if (mounted && bus.route != null) {
        setState(() => _selectedBusRoute = bus.route);
      }
    } catch (e) {
      debugPrint("Could not fetch route for selected bus $busId: $e");
    }
  }

  /// Fetches suggested buses for a trip to the given destination.
  Future<void> _findBusesTo(LatLng destination) async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not determine your current location.")),
      );
      return;
    }

    // Show a loading indicator or message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Finding the best route...")),
    );

    final suggestions = await BusService.findTripSuggestions(
      startLat: _currentPosition!.latitude,
      startLon: _currentPosition!.longitude,
      endLat: destination.latitude,
      endLon: destination.longitude,
    );
    setState(() => _tripSuggestions = suggestions);
  }

  /// Handles the selection of a destination stop from the search bar.
  Future<void> _onDestinationSelected(DestinationResult result) async {
    debugPrint("Destination selected: ${result.name} at (${result.latitude}, ${result.longitude})");

    // Switch the view to "Plan Trip" to show the suggestions.
    _onViewChanged(RiderView.planTrip);

    // Call the service to find trip suggestions to the selected destination.
    await _findBusesTo(LatLng(result.latitude, result.longitude));

    // Also call the backend plan_trip API to compute ETA and transfer info for this stop.
    try {
      if (result.stopId != null && result.stopId!.isNotEmpty) {
        final plan = await BusService.planTripToStop(
          destinationStopId: result.stopId!,
          latitude: _currentPosition?.latitude ?? result.latitude,
          longitude: _currentPosition?.longitude ?? result.longitude,
        );
        if (plan != null && plan['eta_minutes'] != null) {
          final eta = plan['eta_minutes'];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Estimated arrival: ${eta} minutes')),
          );
        }
      }
    } catch (e) {
      debugPrint('planTripToStop failed: $e');
    }

    // If suggestions were found, show them.
    if (_tripSuggestions.isNotEmpty) {
      _panelController.open();
    }
    // Open the panel to show the results.
    _panelController.open();
  }

  /// Fetches and displays only the buses for a specific route.
  Future<void> _filterBusesByRoute(String routeId) async {
    final buses = await BusService.findBusesForRoute(routeId);
    setState(() => _displayedBuses = buses);
  }

  // --- UI Build Method ---
  @override
  Widget build(BuildContext context) {
    // Access the theme extensions and color scheme
    final colorScheme = Theme.of(context).colorScheme;
    final LatLng initialCenter = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(34.1216, 35.6489); // Fallback to Jbeil

    return Scaffold(
      backgroundColor: const Color(0xFF12161A),
      body: SlidingUpPanel(
        controller: _panelController,
        minHeight: 200,
        maxHeight: MediaQuery.of(context).size.height * 0.8,
        parallaxEnabled: true,
        parallaxOffset: 0.5,
        color: Colors.transparent,
        panelBuilder: (sc) => BusBottomSheet(
          scrollController: sc,
          currentView: _currentView,
          tripSuggestions: _tripSuggestions, // Pass the trip suggestions
          nearbyBuses: _displayedBuses, // Show displayed buses in the panel
          onBusSelected: (bus) {
            // When a bus is tapped in the list, treat it like a map marker tap.
            _onBusMarkerTapped(bus);
          },
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 14,
                onTap: (_, __) => _deselectBus(),
              ),
              children: [
                // Use CartoDB dark on mobile, Stadia dark on web (CORS-friendly)
                TileLayer(
                  urlTemplate: kIsWeb
                      ? 'https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png'
                      : 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: kIsWeb ? const <String>[] : const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.bosta.app',
                  additionalOptions: kIsWeb ? const <String, String>{} : const <String, String>{'userAgent': 'com.bosta.app'},
                ),
                if (_selectedBus != null && _selectedBusRoute != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _selectedBusRoute!.geometry,
                        color: _selectedBus != null
                            ? const Color(0xFF2ED8C3) // Highlight in solid teal when selected
                            : Colors.grey.withOpacity(0.5),
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                if (_markerAnimation != null)
                  AnimatedBuilder(
                    animation: _markerAnimation!,
                    builder: (context, _) {
                      return MarkerLayer(markers: [
                        if (_currentPosition != null) _buildUserLocationMarker(),
                        _buildSelectedBusMarker(animatedPosition: _markerAnimation!.value),
                      ]);
                    },
                  )
                else
                  MarkerLayer(markers: [
                      if (_selectedBus == null) ..._buildAllBusMarkers(),
                      if (_currentPosition != null) _buildUserLocationMarker(),
                      if (_selectedBus != null) _buildSelectedBusMarker(),
                    ]),
              ],
            ),
            _buildGradientOverlay(context),
            _buildHeaderUI(),
            if (_currentPosition == null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text("Finding your location...", style: GoogleFonts.urbanist(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerView,
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        child: Icon(_selectedBus != null ? Icons.route : Icons.my_location),
      ),
    );
  }

  void _centerView() {
    if (_selectedBus != null) {
      // If a bus is selected, re-enable auto-centering and move to it.
      setState(() => _isAutoCentering = true);
      _centerOnSelectedBus();
    } else if (_currentPosition != null) {
      // Center on user
      mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        15.0,
      );
    }
  }

  void _centerOnSelectedBus({bool animated = false}) {
    if (_selectedBus == null) return;
    final center = LatLng(_selectedBus!.latitude, _selectedBus!.longitude);
    if (animated) {
      mapController.move(center, mapController.camera.zoom);
    } else {
      mapController.move(
        center,
        16.0, // Use a closer zoom when first tapping
      );
    }
  }

  void _onViewChanged(RiderView newView) {
    setState(() {
      _selectedBus = null; // Deselect bus when switching views
      _selectedRouteId = null; // Clear route filter
      _currentView = newView;
      if (newView == RiderView.nearbyBuses) {
        _loadNearbyBuses(); // Fetch buses and start polling
      } else {
        _displayedBuses = []; // Clear buses when switching to plan trip
        _tripSuggestions = []; // Clear suggestions as well
      }
    });
  }

  // --- UI Helper Widgets ---

  List<Marker> _buildAllBusMarkers() {
    return _displayedBuses.map((bus) {
      return Marker(
        width: 30,
        height: 30,
        point: LatLng(bus.latitude, bus.longitude),
        child: GestureDetector(
          onTap: () => _onBusMarkerTapped(bus),
          child: _BusMarker(
            pulseController: _pulseController,
            isSelected: false,
            busColor: const Color(0xFF2ED8C3), // Use a static color as bus-specific color isn't available
          ),
        ),
      );
    }).toList();
  }

  Marker _buildSelectedBusMarker({LatLng? animatedPosition}) {
    final position = animatedPosition ?? (_selectedBus != null ? LatLng(_selectedBus!.latitude, _selectedBus!.longitude) : const LatLng(0, 0));
    return Marker(
      point: position, // The geographical point for the marker
      width: 150, // Increased width to accommodate text
      height: 80, // Increased height
      child: _buildStaticSelectedMarker(), // The custom marker widget
    );
  }

  Widget _buildStaticSelectedMarker() {
    // Show ETA from Mapbox fetch if available
    String etaText = _etaBusToRider ?? '...';
    final driverName = _selectedBus?.driverName ?? 'Loading...';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Custom info box above the marker
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2327),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2ED8C3), width: 1),
          ),
          child: Text('$driverName · $etaText', style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4), // Space between info box and marker
        _BusMarker(pulseController: _pulseController, isSelected: true, busColor: const Color(0xFF2ED8C3)),
      ],
    );
  }

  Marker _buildUserLocationMarker() {
    return Marker(
      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      width: 24,
      height: 24,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF2ED8C3),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2ED8C3).withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientOverlay(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF12161A).withOpacity(0.8),
              const Color(0xFF12161A).withOpacity(0.0),
            ],
            begin: Alignment.topCenter,
            end: Alignment.center,
            stops: const [0.0, 0.4],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderUI() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // We replace DualSearchBar with a TypeAheadField for interactive search.
            if (kDebugMode) // Only show this toggle in debug builds
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text("Mock Location", style: GoogleFonts.urbanist(color: Colors.white70, fontSize: 12)),
                  const SizedBox(width: 4),
                  Switch(
                    value: _useMockLocation,
                    onChanged: (value) {
                      setState(() => _useMockLocation = value);
                      if (value) {
                        _positionStream?.cancel(); // Stop real GPS
                        _busUpdateTimer?.cancel(); // Stop old bus polling
                        _startMockLocationPoll();
                      } else {
                        _stopMockLocationPoll();
                        _startListeningToLocation(); // Restart real GPS
                        _startPeriodicBusUpdates(); // Restart bus polling
                      }
                    },
                    activeColor: const Color(0xFF2ED8C3),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            WhereToSearchBar(
              userLocation: _currentPosition != null
                  ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                  : null,
              onDestinationSelected: _onDestinationSelected,
            ),
            const SizedBox(height: 16), // Spacing between search bar and segmented control
            CupertinoSlidingSegmentedControl<RiderView>(
              groupValue: _currentView,
              backgroundColor: Colors.black.withOpacity(0.4),
              thumbColor: const Color(0xFF2ED8C3),
              padding: const EdgeInsets.all(4),
              onValueChanged: (view) {
                if (view != null) {
                  // The view change itself is handled here
                  _onViewChanged(view);
                }
              },
              children: {
                RiderView.planTrip: _buildSegment("Plan Trip"),
                RiderView.nearbyBuses: _buildSegment("Nearby Buses"),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        text,
        style: GoogleFonts.urbanist(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BusMarker extends StatelessWidget {
  final AnimationController pulseController;
  final bool isSelected;
  final Color busColor; // Add this
  
  const _BusMarker({
    required this.pulseController,
    this.isSelected = false,
    required this.busColor, // Require it
  });

  @override
  Widget build(BuildContext context) {
    final markerSize = isSelected ? 40.0 : 30.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing animation, shown only when selected
        if (isSelected)
          FadeTransition(
            opacity:
                Tween<double>(begin: 0.7, end: 0.2).animate(pulseController),
            child: ScaleTransition(
              scale:
                  Tween<double>(begin: 1.0, end: 2.5).animate(pulseController),
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
          width: markerSize,
          height: markerSize,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? Colors.white : const Color(0xFF12161A),
            border: Border.all(
              color: isSelected ? const Color(0xFF2ED8C3) : busColor,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: busColor.withOpacity(0.7),
                blurRadius: isSelected ? 12 : 8,
                spreadRadius: isSelected ? 3 : 1,
              ),
            ],
          ),
          child: Icon(
            Icons.directions_bus,
            color: isSelected ? const Color(0xFF12161A) : busColor,
            size: 16,
          ),
        ),
      ],
    );
  }
}

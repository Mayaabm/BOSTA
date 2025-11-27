import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart'; // Import for kDebugMode
import 'package:bosta_frontend/models/place.dart';
import 'package:bosta_frontend/models/user_location.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bosta_frontend/services/geocoding_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

import '../models/bus.dart'; // Using the actual model
import '../models/app_route.dart'; // Using the unified route model
import '../services/bus_service.dart'; // Using the actual service
// Using the actual service
import 'bus_bottom_sheet.dart';
import 'bus_details_modal.dart';

enum RiderView { planTrip, nearbyBuses }

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState(); // No longer nested
}

class _RiderHomeScreenState extends State<RiderHomeScreen> with TickerProviderStateMixin {
  final MapController mapController = MapController();
  final PanelController _panelController = PanelController();
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Timer? _busUpdateTimer;

  // State for Route 224
  // static const String _targetRouteId = '224'; // No longer needed for nearby buses
  AppRoute? _selectedBusRoute; // To store the route of the *selected* bus
  List<Bus> _busesOnRoute = [];
  // bool _isNearRoute = false; // No longer needed, we fetch based on location

  RiderView _currentView = RiderView.planTrip;
  final List<Bus> _suggestedBuses = []; // For trip planning
  Bus? _selectedBus;
  Timer? _selectedBusDetailsTimer;
  bool _isAutoCentering = false;

  // Animation for bus markers
  late final AnimationController _pulseController; // For bus marker pulse animation
  late final AnimationController _markerAnimationController;

  // Search controllers
  final TextEditingController _destinationController = TextEditingController();
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
    _markerAnimationController.dispose();
    _pulseController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _initializeUserLocation() async {
    // In debug mode, simulate the rider's location to be near a stop for consistent testing.
    if (kDebugMode) {
      debugPrint("--- RIDER SIMULATION: ACTIVE (Debug Mode) ---");
      // Simulate a location in Jbeil for testing
      const mockLatitude = 34.1216;
      const mockLongitude = 35.6489;

      final mockPosition = Position(
        latitude: mockLatitude,
        longitude: mockLongitude,
        timestamp: DateTime.now(),
        accuracy: 5.0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0.0, headingAccuracy: 0.0
      );

      debugPrint("Simulating rider location at: (${mockPosition.latitude}, ${mockPosition.longitude})");
      if (mounted) setState(() => _currentPosition = mockPosition);
    } else {
      // In release mode, or if the route isn't available for simulation, use real GPS.
      await Geolocator.requestPermission();
      final position = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = position);
      _startListeningToLocation(); // Start listening for real location updates.
    }

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
      if (mounted) setState(() => _busesOnRoute = buses);
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

    // Show the modal with live updates
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BusDetailsModal(
        busId: bus.id,
        userLocation: _currentPosition != null
            ? UserLocation(latitude: _currentPosition!.latitude, longitude: _currentPosition!.longitude)
            : null,
        onChooseBus: () {
          // This would be the action to confirm the trip
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Trip with Bus ${bus.plateNumber} confirmed!")),
          );
        },
      ),
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
    });
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
          suggestedBuses: _suggestedBuses,
          nearbyBuses: _busesOnRoute, // Show buses from Route 224 in the panel
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
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.bosta.app',
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
                      if (_currentView == RiderView.nearbyBuses && _selectedBus == null) ..._buildAllBusMarkers(),
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
      _currentView = newView;
      if (newView == RiderView.nearbyBuses) {
        _loadNearbyBuses(); // Fetch buses and start polling
      }
    });
  }

  // --- UI Helper Widgets ---

  List<Marker> _buildAllBusMarkers() {
    return _busesOnRoute.map((bus) {
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
      point: position,
      width: 40,
      height: 40,
      child: _buildStaticSelectedMarker(),
    );
  }

  Widget _buildStaticSelectedMarker() {
    return _BusMarker(pulseController: _pulseController, isSelected: true, busColor: const Color(0xFF2ED8C3));
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
            TypeAheadField<Place>(
              controller: _destinationController,
              suggestionsCallback: (pattern) async {
                // Call our new geocoding service
                return await GeocodingService.searchPlaces(
                  pattern,
                  proximity: _currentPosition != null
                      ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                      : null,
                );
              },
              itemBuilder: (context, suggestion) {
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(suggestion.name),
                  subtitle: Text(suggestion.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
              onSelected: (suggestion) {
                _destinationController.text = suggestion.name;
                // Here you would trigger the logic to find buses to the destination
                debugPrint("Destination selected: ${suggestion.name} at ${suggestion.coordinates}");
                // Example: _findBusesTo(suggestion.coordinates);
              },
              decorationBuilder: (context, child) {
                return Material(
                  type: MaterialType.card,
                  elevation: 4.0,
                  borderRadius: BorderRadius.circular(30.0),
                  child: child,
                );
              },
              builder: (context, controller, focusNode) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: false,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF2ED8C3)),
                    hintText: 'Where to?',
                    filled: true,
                    fillColor: const Color(0xFF1F2327),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30.0),
                      borderSide: BorderSide.none,
                    ),
                  ),
                );
              },
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
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? Colors.white : const Color(0xFF12161A),
            border: Border.all(
              color: busColor,
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

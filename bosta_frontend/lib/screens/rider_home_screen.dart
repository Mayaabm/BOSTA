import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:bosta_frontend/models/user_location.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

import '../models/bus.dart'; // Using the actual model
import '../models/route_model.dart'; // Using the actual model
import '../services/bus_service.dart'; // Using the actual service
import '../services/route_service.dart'; // Using the actual service
import 'bus_bottom_sheet.dart';
import 'bus_details_modal.dart';
import 'dual_search_bar.dart';

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
  static const String _targetRouteId = '224';
  AppRoute? _route224;
  List<Bus> _busesOnRoute = [];
  bool _isNearRoute = false;

  RiderView _currentView = RiderView.planTrip;
  final List<Bus> _suggestedBuses = []; // For trip planning
  Bus? _selectedBus;
  Timer? _selectedBusDetailsTimer;
  bool _isAutoCentering = false;

  // Animation for bus markers
  late final AnimationController _pulseController; // For bus marker pulse animation
  late final AnimationController _markerAnimationController;
  Animation<LatLng>? _markerAnimation;

  @override
  void initState() {
    super.initState();
    _markerAnimationController = AnimationController(vsync: this, duration: const Duration(seconds: 2));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _initLocationAndRoute();
    _listenToMapEvents();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _busUpdateTimer?.cancel();
    _selectedBusDetailsTimer?.cancel();
    _markerAnimationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // --- Location and Data Fetching ---

  Future<void> _initLocationAndRoute() async {
    try {
      await Geolocator.requestPermission();
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _currentPosition = position);
        mapController.move(LatLng(position.latitude, position.longitude), 14.0);
        _startListeningToLocation(); // Start listening for continuous location updates
        _startPeriodicBusUpdates();
      }

      // 2. After location is successful, fetch the route data.
      // This is now in a separate try-catch so it doesn't block map initialization.
      try {
        final route = await RouteService.getRouteById(_targetRouteId);
        if (mounted) {
          setState(() => _route224 = route);
          // Check proximity now that we have both location and route
          _checkProximityToRoute();
        }
      } catch (e) {
        debugPrint("----------- ROUTE FETCH ERROR -----------");
        debugPrint("Could not fetch route '$_targetRouteId'. The map will function without it. Error: $e");
        // We don't show a snackbar here to avoid bothering the user if the backend is just down.
        // The app will still be usable.
      }

    } catch (e) {
      // This catch block now only handles critical location failures.
      debugPrint("----------- LOCATION ERROR -----------");
      debugPrint("Failed to get user location: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Could not get location. Please enable location services and grant permission."),
          ),
        );
      }
    }
  }

  void _startListeningToLocation() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = position);
        _checkProximityToRoute(); // Check proximity on every location update
      }
    });
  }

  void _checkProximityToRoute() {
    if (_currentPosition == null || _route224 == null) return;

    final userPoint = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    bool isCurrentlyNear = false;

    // Check if user is within 300m of any point on the route polyline
    for (final routePoint in _route224!.geometry) {
      final distance = const Distance().as(LengthUnit.Meter, userPoint, routePoint);
      if (distance <= 300) {
        isCurrentlyNear = true;
        break;
      }
    }

    if (isCurrentlyNear != _isNearRoute) {
      setState(() {
        _isNearRoute = isCurrentlyNear;
        if (!_isNearRoute) {
          _busesOnRoute.clear(); // Hide buses when user moves away
          _selectedBus = null; // Deselect bus
        } else {
          _fetchBusesForRoute(); // Fetch buses when user is near
        }
      });
    }
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
      (_) {
        if (_isNearRoute) {
          _fetchBusesForRoute();
        }
      },
    );
  }

  Future<void> _fetchBusesForRoute() async {
    try {
      final buses = await BusService.getBusesForRoute(_targetRouteId);
      if (mounted) {
        setState(() => _busesOnRoute = buses);
      }
    } catch (e) {
      debugPrint("Error fetching buses for route $_targetRouteId: $e");
    }
  }

  void _onBusMarkerTapped(Bus bus) {
    setState(() {
      _selectedBus = bus;
      _isAutoCentering = true; // Enable auto-centering
      _centerOnSelectedBus(); // Immediately move map to the bus
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
            // This is the "Choose Bus" action
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Starting trip with Bus ${bus.plateNumber}... (UI Placeholder)")),
            );
          },
        ),
        body: Stack(
          children: [
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 14,
                onTap: (_, _) => _deselectBus(),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.bosta.app',
                ),
                if (_isNearRoute && _route224 != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _route224!.geometry,
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
                      if (_isNearRoute && _selectedBus == null) ..._buildAllBusMarkers(),
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
      if (newView == RiderView.nearbyBuses && _isNearRoute) {
        _fetchBusesForRoute();
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
            busColor: const Color(0xFF2ED8C3),
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
          children: [
            DualSearchBar(
              onDestinationSubmitted: (destination) {
                // This would trigger a search for routes to the destination
                debugPrint("Destination submitted: $destination");
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
                  _onViewChanged(view); // This will now work
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
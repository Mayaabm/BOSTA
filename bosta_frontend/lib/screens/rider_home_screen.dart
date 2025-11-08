import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

import '../models/bus.dart'; // Using the actual model
import '../models/route_model.dart'; // Using the actual model
import '../services/bus_service.dart'; // Using the actual service
import '../services/route_service.dart'; // Using the actual service
import 'bus_bottom_sheet.dart';
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
  List<Bus> _suggestedBuses = []; // For trip planning
  Bus? _selectedBus;

  // Animation for bus markers
  late final AnimationController _pulseController; // For bus marker pulse animation

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _initLocationAndRoute();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _busUpdateTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // --- Location and Data Fetching ---

  Future<void> _initLocationAndRoute() async {
    try {
      // 1. Fetch the static route data first
      final route = await RouteService.getRouteById(_targetRouteId);
      if (mounted) {
        setState(() => _route224 = route);
      }

      // 2. Get user's location
      await Geolocator.requestPermission();
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() => _currentPosition = position);
        mapController.move(LatLng(position.latitude, position.longitude), 14.0);
        _startListeningToLocation(); // This will trigger the proximity check
        _startPeriodicBusUpdates();
      }
    } catch (e) {
      debugPrint("Error during initialization: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not initialize map. Please try again.")),
        );
      }
    }
  }

  void _startListeningToLocation() {
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = position);
        _checkProximityToRoute();
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
    setState(() => _selectedBus = bus);
    if (_route224 != null) {
      mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: _route224!.geometry,
          padding: const EdgeInsets.all(50),
        ),
      );
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
                initialZoom: 13,
                onTap: (_, __) => setState(() => _selectedBus = null),
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
                            ? const Color(0xFF2ED8C3).withOpacity(0.7)
                            : Colors.grey.withOpacity(0.4),
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_isNearRoute) ..._buildBusMarkers(),
                    if (_currentPosition != null) _buildUserLocationMarker(),
                  ],
                ),
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
    if (_selectedBus != null && _route224 != null) {
      // Center on the selected route
      mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: _route224!.geometry,
          padding: const EdgeInsets.all(50),
        ),
      );
    } else if (_currentPosition != null) {
      // Center on user
      mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        15.0,
      );
    }
  }

  // --- UI Helper Widgets ---

  List<Marker> _buildBusMarkers() {
    return _busesOnRoute.map((bus) {
      final isSelected = _selectedBus?.id == bus.id;
      return Marker(
        width: isSelected ? 40 : 30,
        height: isSelected ? 40 : 30,
        point: LatLng(bus.latitude, bus.longitude),
        child: GestureDetector(
          onTap: () => _onBusMarkerTapped(bus),
          child: _BusMarker(
            pulseController: _pulseController,
            isSelected: isSelected,
            busColor: const Color(0xFF2ED8C3),
          ),
        ),
      );
    }).toList();
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
        ],
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
        FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.5).animate(pulseController),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 1.5).animate(pulseController),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: busColor.withOpacity(0.5), // Use busColor
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? Colors.white : const Color(0xFF12161A),
            border: Border.all(
              color: busColor,
              width: isSelected ? 3 : 2,
            ), // Use busColor
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2ED8C3).withOpacity(0.7),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            Icons.directions_bus,
            color: isSelected ? const Color(0xFF12161A) : busColor,
            size: 20,
          ),
        ),
      ],
    );
  }
}
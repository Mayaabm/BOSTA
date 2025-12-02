import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

import '../../../models/trip_suggestion.dart';
import '../../../models/bus.dart';
import '../../../services/bus_service.dart';
import 'rider_home_screen.dart' show RiderView; // Import only the enum
import 'bus_bottom_sheet.dart'; // Keep other imports
import 'dual_search_bar.dart'; // Keep other imports

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final PanelController _panelController = PanelController();
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Timer? _busUpdateTimer;

  RiderView _currentView = RiderView.planTrip;
  List<Bus> _nearbyBuses = [];
  List<TripSuggestion> _tripSuggestions = []; // Updated to use the new model
  Bus? _selectedBus;

  // Animation for bus markers
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _initMapAndLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _busUpdateTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initMapAndLocation() async {
    try {
      await Geolocator.requestPermission();

      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
        // Animate map to the new user location
        _mapController.move(LatLng(position.latitude, position.longitude), 15.0);
        _startLocationListener();
        _fetchNearbyBuses(); // Initial fetch
        _startPeriodicBusUpdates();
      }
    } catch (e) {
      debugPrint("Error getting initial location: $e");
      // Optionally show a snackbar if location fails
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not get location. Please enable GPS.")),
      );
    }
  }

  void _startLocationListener() {
    _positionStream = Geolocator.getPositionStream().listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = position);
      }
    });
  }

  void _startPeriodicBusUpdates() {
    _busUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_currentView == RiderView.nearbyBuses) {
        _fetchNearbyBuses();
      }
      // Note: Trip suggestions are fetched on-demand, not periodically.
    });
  }

  Future<void> _fetchNearbyBuses() async {
    if (_currentPosition == null) return;
    try {
      final buses = await BusService.getNearbyBuses(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
      );
      if (mounted) {
        setState(() => _nearbyBuses = buses);
      }
    } catch (e) {
      // Silently fail on periodic updates to not bother the user
      debugPrint("Error fetching nearby buses: $e");
    }
  }

  Future<void> _fetchTripSuggestions(String from, String to) async {
    // This simulates fetching suggestions.
    // In a real app, you'd geocode 'from' and 'to' into coordinates
    // and call a service like `BusService.getSuggestions(from, to)`.
    if (_currentPosition == null) return;

    // This is a placeholder for geocoding the 'to' address.
    // For now, we'll use a hardcoded destination.
    const double destinationLat = 34.1216; // Example: Jbeil
    const double destinationLon = 35.6489; 

    try {
      final suggestions = await BusService.findTripSuggestions(
        startLat: _currentPosition!.latitude,
        startLon: _currentPosition!.longitude,
        endLat: destinationLat,
        endLon: destinationLon,
      );
      if (mounted) {
        setState(() {
          _tripSuggestions = suggestions;
        });
        _panelController.open();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not find routes. Please try again.")),
        );
      }
    }
  }

  void _onViewChanged(RiderView newView) {
    setState(() => _currentView = newView);
    if (newView == RiderView.nearbyBuses && _nearbyBuses.isEmpty) {
      _fetchNearbyBuses();
    }
    _panelController.open();
  }

  void _onBusSelected(Bus bus) {
    setState(() => _selectedBus = bus);
    _mapController.move(LatLng(bus.latitude, bus.longitude), 16.0);
    _panelController.open();
    // Here you would navigate to the trip screen
    // context.go('/rider/trip/${bus.id}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Starting trip with Bus ${bus.plateNumber}... (UI Placeholder)")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // Use a dark background that matches the map style
      backgroundColor: const Color(0xFF12161A),
      body: SlidingUpPanel(
        controller: _panelController,
        minHeight: 200, // Peek height (approx 30%)
        maxHeight: MediaQuery.of(context).size.height * 0.8,
        parallaxEnabled: true,
        parallaxOffset: 0.5,
        color: Colors.transparent, // Panel itself is transparent
        panelBuilder: (sc) => BusBottomSheet(
          scrollController: sc,
          currentView: _currentView,
          suggestedBuses: const [], // This needs to be adapted for TripSuggestion
          nearbyBuses: _nearbyBuses,
          onBusSelected: _onBusSelected,
        ),
        body: Stack(
          children: [
            _buildMap(),
            _buildGradientOverlay(context),
            _buildHeaderUI(),
            if (_currentPosition == null) _buildInitialLoadingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(34.1216, 35.6489), // Fallback to Jbeil
        initialZoom: 15.0,
        onTap: (_, __) {
          setState(() => _selectedBus = null);
          if (_panelController.isPanelOpen) {
            _panelController.close();
          }
        },
      ),
      children: [
        TileLayer(
          // Using a dark theme from CartoDB
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.bosta.app',
        ),
        if (_currentPosition != null) _buildUserLocationMarker(),
        if (_nearbyBuses.isNotEmpty) _buildBusMarkers(),
      ],
    );
  }

  MarkerLayer _buildBusMarkers() {
    final markers = _nearbyBuses.map((bus) {
      final isSelected = _selectedBus?.id == bus.id;
      return Marker(
        width: isSelected ? 80 : 60,
        height: isSelected ? 80 : 60,
        point: LatLng(bus.latitude, bus.longitude),
        child: GestureDetector(
          onTap: () => setState(() => _selectedBus = bus),
          child: _BusMarker(
            pulseController: _pulseController,
            isSelected: isSelected,
            busColor: const Color(0xFF2ED8C3), // Add the required color
          ),
        ),
      );
    }).toList();

    return MarkerLayer(markers: markers);
  }

  MarkerLayer _buildUserLocationMarker() {
    return MarkerLayer(
      markers: [
        Marker(
          width: 24,
          height: 24,
          point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
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
        ),
      ],
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

  Widget _buildInitialLoadingIndicator() {
    return Positioned(
      top: 160, // Position below the header UI
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text("Finding your location...",
              style: GoogleFonts.urbanist(color: Colors.white)),
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
                _fetchTripSuggestions("Current Location", destination);
              },
            ),
            const SizedBox(height: 16),
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
  final Color busColor;

  const _BusMarker({
    required this.pulseController,
    this.isSelected = false,
    required this.busColor,
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
                color: busColor.withOpacity(0.5),
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
            ),
            boxShadow: [
              BoxShadow(
                color: busColor.withOpacity(0.7),
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
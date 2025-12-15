import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/trip_service.dart';
import '../utils/formatters.dart';
import '../../../models/trip_suggestion.dart';
import '../../../models/bus.dart';
import '../../../services/bus_service.dart';
import 'rider_home_screen.dart' show RiderView;
import 'bus_bottom_sheet.dart';
import 'dual_search_bar.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> with TickerProviderStateMixin {
  String? _etaBusToRider;
  String? _etaBusToDestination;
  bool _isFetchingEta = false;
  final MapController _mapController = MapController();
  final PanelController _panelController = PanelController();
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  Timer? _busUpdateTimer;
  RiderView _currentView = RiderView.planTrip;
  List<Bus> _nearbyBuses = [];
  List<TripSuggestion> _tripSuggestions = [];
  Bus? _selectedBus;
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
        _mapController.move(LatLng(position.latitude, position.longitude), 15.0);
        _startLocationListener();
        _fetchNearbyBuses();
        _startPeriodicBusUpdates();
      }
    } catch (e) {
      debugPrint("Error getting initial location: $e");
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
      debugPrint("Error fetching nearby buses: $e");
    }
  }

  Future<void> _fetchTripSuggestions(String from, String to) async {
    if (_currentPosition == null) return;
    const double destinationLat = 34.1216;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Starting trip with Bus ${bus.plateNumber}... (UI Placeholder)")),
    );
    _fetchEtasForSelectedBus(bus);
  }

  Future<void> _fetchEtasForSelectedBus(Bus bus) async {
    if (_currentPosition == null) return;
    setState(() {
      _isFetchingEta = true;
      _etaBusToRider = null;
      _etaBusToDestination = null;
    });
    try {
      final busLat = bus.latitude;
      final busLon = bus.longitude;
      final riderLat = _currentPosition!.latitude;
      final riderLon = _currentPosition!.longitude;
      final originCoords = "$busLon,$busLat";
      final destCoords = "$riderLon,$riderLat";
      final url1 =
          'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$originCoords;$destCoords?access_token=${TripService.getMapboxAccessToken()}&overview=full&geometries=geojson';
      final resp1 = await http.get(Uri.parse(url1));
      if (resp1.statusCode == 200) {
        final data = json.decode(resp1.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final double durationSeconds = route['duration']?.toDouble() ?? 0.0;
          _etaBusToRider = formatEtaMinutes((durationSeconds / 60).ceil());
        } else {
          _etaBusToRider = "--";
        }
      } else {
        _etaBusToRider = "--";
      }
      if (_tripSuggestions.isNotEmpty) {
        final lastLeg = _tripSuggestions.last.legs.last;
        final destLat = lastLeg.destLat;
        final destLon = lastLeg.destLon;
        if (destLat != null && destLon != null) {
          final destCoords2 = "$destLon,$destLat";
          final url2 =
              'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/$originCoords;$destCoords2?access_token=${TripService.getMapboxAccessToken()}&overview=full&geometries=geojson';
          final resp2 = await http.get(Uri.parse(url2));
          if (resp2.statusCode == 200) {
            final data = json.decode(resp2.body);
            if (data['routes'] != null && data['routes'].isNotEmpty) {
              final route = data['routes'][0];
              final double durationSeconds = route['duration']?.toDouble() ?? 0.0;
              _etaBusToDestination = formatEtaMinutes((durationSeconds / 60).ceil());
            } else {
              _etaBusToDestination = "--";
            }
          } else {
            _etaBusToDestination = "--";
          }
        } else {
          _etaBusToDestination = "--";
        }
      } else {
        _etaBusToDestination = "--";
      }
    } catch (e) {
      _etaBusToRider = _etaBusToDestination = "--";
    }
    if (mounted) setState(() => _isFetchingEta = false);
  }

  @override
  Widget build(BuildContext context) {
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
          tripSuggestions: _tripSuggestions,
          nearbyBuses: _nearbyBuses,
          onBusSelected: _onBusSelected,
          selectedBus: _selectedBus,
          etaBusToRider: _etaBusToRider,
          etaBusToDestination: _etaBusToDestination,
          isFetchingEta: _isFetchingEta,
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
        initialCenter: const LatLng(34.1216, 35.6489),
        initialZoom: 15.0,
        onTap: (_, __) {},
      ),
      children: [
        TileLayer(
          urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
          subdomains: ['a', 'b', 'c'],
        ),
      ],
    );
  }

  Widget _buildGradientOverlay(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 120,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF12161A), Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderUI() {
    return Positioned(
      top: 40,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Plan Your Trip",
            textAlign: TextAlign.center,
            style: GoogleFonts.urbanist(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Find the best routes and buses near you.",
            textAlign: TextAlign.center,
            style: GoogleFonts.urbanist(
              fontSize: 16,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialLoadingIndicator() {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF2ED8C3)),
    );
  }
}
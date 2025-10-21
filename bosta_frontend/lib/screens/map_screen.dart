import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/bus_service.dart';
import '../models/bus.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final mapController = MapController();
  Position? _currentPosition;
  List<Bus> _nearbyBuses = [];
  Bus? _selectedBus;
  Timer? _busUpdateTimer;
  final _destinationController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _startBusUpdates();
  }

  @override
  void dispose() {
    _busUpdateTimer?.cancel();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() => _currentPosition = position);
      _updateNearbyBuses();
      
      mapController.move(
        LatLng(position.latitude, position.longitude),
        13,
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _startBusUpdates() {
    _busUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _updateNearbyBuses(),
    );
  }

  Future<void> _updateNearbyBuses() async {
    if (_currentPosition == null) return;

    try {
      final buses = await BusService.getNearbyBuses(
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
      );
      setState(() => _nearbyBuses = buses);
    } catch (e) {
      debugPrint('Error updating buses: $e');
    }
  }

  Future<void> _checkEta() async {
    if (_selectedBus == null || _currentPosition == null) return;

    try {
      final eta = await BusService.getEta(
        busId: _selectedBus!.id,
        targetLat: _currentPosition!.latitude,
        targetLon: _currentPosition!.longitude,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('ETA for Bus ${_selectedBus!.plateNumber}'),
            content: Text('Estimated arrival: ${eta.estimatedMinutes.toStringAsFixed(1)} minutes.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting ETA: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: LatLng(33.8886, 35.4955), // Beirut
              initialZoom: 13,
              onTap: (_, point) {
                setState(() => _selectedBus = null);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bosta_frontend',
              ),
              MarkerLayer(
                markers: [
                  if (_currentPosition != null)
                    Marker(
                      point: LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                      width: 30,
                      height: 30,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                      ),
                    ),
                  ..._nearbyBuses.map((bus) => Marker(
                        point: LatLng(bus.latitude, bus.longitude),
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedBus = bus),
                          child: Icon(
                            Icons.directions_bus,
                            color: _selectedBus?.id == bus.id
                                ? Colors.blue
                                : Colors.red,
                            size: 30,
                          ),
                        ),
                      )),
                ],
              ),
            ],
          ),
          // Search bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Card(
              child: TextField(
                controller: _destinationController,
                decoration: InputDecoration(
                  hintText: 'Where to?',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isSearching
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _destinationController.clear();
                            setState(() => _isSearching = false);
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onChanged: (value) => setState(() => _isSearching = value.isNotEmpty),
              ),
            ),
          ),
          // Bus info card
          if (_selectedBus != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.directions_bus),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Bus ${_selectedBus!.plateNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_selectedBus!.routeName != null)
                                  Text('Route: ${_selectedBus!.routeName}'),
                                Text(
                                  'Distance: ${(_selectedBus!.distanceMeters! / 1000).toStringAsFixed(1)} km',
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _checkEta,
                            child: const Text('Check ETA'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getCurrentLocation,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}
import 'dart:async';
import 'dart:convert';

import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as fm;
// google_fonts not needed here

class DriverTrackingScreen extends StatefulWidget {
  final String tripId;
  const DriverTrackingScreen({super.key, required this.tripId});

  @override
  State<DriverTrackingScreen> createState() => _DriverTrackingScreenState();
}

class _DriverTrackingScreenState extends State<DriverTrackingScreen> {
  final MapController _mapController = MapController();
  Timer? _pollTimer;
  fm.LatLng? _busLocation;
  String? _busId;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPolling());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startPolling() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    // Try to get bus id from auth state; if missing, refresh profile
    _busId = auth.currentState.driverInfo?.busId;
    if (_busId == null || _busId!.isEmpty) {
      await auth.fetchAndSetDriverProfile();
      _busId = auth.currentState.driverInfo?.busId;
    }

    if (_busId == null || _busId!.isEmpty) {
      setState(() => _error = 'No bus assigned to this driver.');
      return;
    }

    // Poll every 2 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _fetchBusLocation(_busId!);
    });
    // Fire first fetch immediately
    await _fetchBusLocation(_busId!);
  }

  Future<void> _fetchBusLocation(String busId) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.currentState.token;
    if (token == null) return;
    try {
      final uri = Uri.parse(ApiEndpoints.busById(busId));
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final current = data['current_point'];
        if (current != null && current['coordinates'] != null) {
          final coords = current['coordinates'];
          final lon = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();
          final loc = fm.LatLng(lat, lon);
          setState(() {
            _busLocation = loc;
            _error = null;
          });
          try {
            _mapController.move(loc, 15.0);
          } catch (_) {}
        }
      } else {
        setState(() => _error = 'Failed to fetch bus location (${res.statusCode})');
      }
    } catch (e) {
      setState(() => _error = 'Error fetching bus: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Map'), backgroundColor: Colors.transparent, elevation: 0),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: _busLocation ?? fm.LatLng(33.89365, 35.55166), initialZoom: 13.0),
              children: [
                TileLayer(urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c']),
                if (_busLocation != null)
                  MarkerLayer(markers: [
                    Marker(
                      width: 40,
                      height: 40,
                      point: _busLocation!,
                      child: const Icon(Icons.directions_bus, color: Colors.green, size: 36),
                    )
                  ])
              ],
            ),
    );
  }
}

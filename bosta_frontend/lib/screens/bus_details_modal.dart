import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/user_location.dart';
import '../models/bus.dart';
import '../services/bus_service.dart';
import '../services/trip_service.dart';

class BusDetailsModal extends StatefulWidget {
  final String busId;
  final VoidCallback onChooseBus;
  final UserLocation? userLocation;
  final String? authToken;

  const BusDetailsModal({
    super.key,
    required this.busId,
    required this.onChooseBus,
    this.userLocation,
    this.authToken,
  });

  @override
  State<BusDetailsModal> createState() => _BusDetailsModalState();
}

class _BusDetailsModalState extends State<BusDetailsModal> {
  Bus? _busDetails;
  String? _errorMessage;
  bool _isLoading = true;
  Timer? _updateTimer;

  // Trip status
  String _tripStatus = "On Route";
  double _tripProgress = 0.0;
  
  // ETA from driver to rider
  String? _etaFromDriver;
  double? _distanceFromDriver;

  @override
  void initState() {
    super.initState();
    _fetchBusDetails();
    // Start periodic updates
    _updateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchBusDetails(showLoading: false);
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchBusDetails({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _isLoading = true);
    try {
      final bus = await BusService.getBusDetails(widget.busId, userLocation: widget.userLocation);
      
      // Fetch ETA from driver to rider if user location and token are available
      String? etaFromDriver;
      double? distanceFromDriver;
      
      if (widget.userLocation != null && widget.authToken != null) {
        try {
          debugPrint('[BusDetailsModal] Fetching ETA from driver to rider...');
          debugPrint('[BusDetailsModal] Driver position: LAT=${bus.latitude}, LON=${bus.longitude}');
          debugPrint('[BusDetailsModal] Rider position: LAT=${widget.userLocation?.latitude}, LON=${widget.userLocation?.longitude}');
          
          final etaResponse = await TripService.fetchEta(
            busId: widget.busId,
            riderLat: widget.userLocation!.latitude,
            riderLon: widget.userLocation!.longitude,
            token: widget.authToken!,
          );
          
          if (etaResponse != null) {
            distanceFromDriver = etaResponse['distance_m']?.toDouble();
            final estimatedMinutes = etaResponse['estimated_arrival_minutes'];
            
            if (estimatedMinutes != null) {
              final minutes = estimatedMinutes.toInt();
              etaFromDriver = '$minutes min';
              debugPrint('[BusDetailsModal] ETA from driver to rider: $etaFromDriver (distance: ${distanceFromDriver?.toStringAsFixed(0)}m)');
            }
          }
        } catch (e) {
          debugPrint('[BusDetailsModal] Error fetching rider ETA: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _busDetails = bus;
          _isLoading = false;
          _errorMessage = null;
          _etaFromDriver = etaFromDriver;
          _distanceFromDriver = distanceFromDriver;
          _updateTripStatus(bus);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Bus has completed its trip or is offline.";
        });
      }
    }
  }

  void _updateTripStatus(Bus bus) {
    // Check for trip completion first
    if (bus.lastReportedAt != null) {
      final lastReportTime = DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'").parse(bus.lastReportedAt!, true).toLocal();
      // If bus hasn't reported in over 5 minutes, consider it offline/completed
      if (DateTime.now().difference(lastReportTime).inMinutes > 5) {
        _tripStatus = "Completed";
      }
    }

    // Determine status based on distance
    if (bus.distanceMeters != null && bus.distanceMeters! <= 300) {
      _tripStatus = "Arriving"; // Within 300m of the rider
    } else {
      _tripStatus = "On Route";
    }

    // This is a mock progress calculation assuming a 30-minute trip.
    // A real implementation would use total route distance vs. distance covered.
    if (bus.lastReportedAt != null) {
      try {
        final now = DateTime.now();
        // Assume the trip started within the last 30 minutes for this simulation.
        final tripStartTime = now.subtract(const Duration(minutes: 30));
        final lastReportTime = DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'").parse(bus.lastReportedAt!, true).toLocal();

        // Calculate progress based on how much of the 30-minute window has passed since the trip started.
        if (lastReportTime.isAfter(tripStartTime)) {
          final elapsedSeconds = lastReportTime.difference(tripStartTime).inSeconds;
          _tripProgress = elapsedSeconds / (30 * 60); // 30 minutes in seconds
          if (_tripProgress > 1.0) _tripProgress = 1.0;
          if (_tripProgress < 0.0) _tripProgress = 0.0;
        }
      } catch (e) {
        debugPrint("Could not parse lastReportedAt or calculate trip progress: $e");
        _tripProgress = 0.0; // Default to 0 on error
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E11).withOpacity(0.95),
        ),
        child: _isLoading
            ? _buildLoadingState()
            : _errorMessage != null
                ? _buildErrorState()
                : _busDetails != null
                    ? _buildLoadedState(_busDetails!)
                    : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2ED8C3)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: Colors.white54, size: 48),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Failed to load details',
            style: GoogleFonts.urbanist(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 16),
          if (_errorMessage != "Bus has completed its trip or is offline.") ElevatedButton(
            onPressed: _fetchBusDetails,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ED8C3)),
            child: const Text('Retry', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedState(Bus bus) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(12.0),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Header
          Text(
            bus.plateNumber,
            style: GoogleFonts.urbanist(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          Text(
            bus.routeName ?? 'Unknown Route',
            style: GoogleFonts.urbanist(fontSize: 16, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          // Progress Bar and Status
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _tripProgress,
                    backgroundColor: Colors.grey.shade800,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2ED8C3)),
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _tripStatus == "Completed" ? Colors.grey.shade700 : const Color(0xFF2ED8C3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_tripStatus, style: GoogleFonts.urbanist(color: _tripStatus == "Completed" ? Colors.white70 : Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Driver Info
          Text('Driver', style: GoogleFonts.urbanist(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFF2ED8C3),
                child: Icon(Icons.person_outline, color: Colors.black),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bus.driverName ?? 'N/A',
                    style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        (bus.driverRating ?? 0.0).toStringAsFixed(1),
                        style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.call_outlined, color: Color(0xFF2ED8C3)),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.message_outlined, color: Color(0xFF2ED8C3)),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Trip Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn('ETA to You', _etaFromDriver ?? bus.eta?.toMinutesString() ?? '...'),
                _buildStatColumn('Distance', _distanceFromDriver != null ? '${(_distanceFromDriver! / 1000).toStringAsFixed(1)} km' : (bus.distanceMeters != null ? '${(bus.distanceMeters! / 1000).toStringAsFixed(1)} km' : '...')),
                _buildStatColumn('Speed', '${bus.speed.toStringAsFixed(0)} km/h'),
              ],
            ),
          const Spacer(),
          // Actions
          Row(
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white30),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Close'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close modal first
                    widget.onChooseBus(); // Then trigger action
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2ED8C3),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Choose Bus', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.urbanist(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ],
    );
  }
}
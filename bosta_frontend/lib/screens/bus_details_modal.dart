import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/bus.dart';

class BusDetailsModal extends StatefulWidget {
  final String busId;
  final VoidCallback onChooseBus;

  const BusDetailsModal({
    super.key,
    required this.busId,
    required this.onChooseBus,
  });

  @override
  State<BusDetailsModal> createState() => _BusDetailsModalState();
}

class _BusDetailsModalState extends State<BusDetailsModal> {
  Future<Bus>? _busDetailsFuture;

  @override
  void initState() {
    super.initState();
    _fetchBusDetails();
  }

  void _fetchBusDetails() {
    setState(() {
      // This is a mock fetch. In a real app, you would call a service like:
      // _busDetailsFuture = BusService.getBusDetails(widget.busId);
      _busDetailsFuture = _mockFetchBusDetails(widget.busId);
    });
  }

  // Mock function to simulate fetching bus details.
  Future<Bus> _mockFetchBusDetails(String busId) async {
    await Future.delayed(const Duration(seconds: 1));
    // Simulate a potential error for demonstration
    // if (Random().nextDouble() < 0.3) {
    //   throw Exception("Failed to load bus details");
    // }
    return Bus(
      id: busId,
      plateNumber: 'B 12345',
      latitude: 34.12,
      longitude: 35.65,
      speed: 45.0,
      routeName: 'Jbeil - Batroun',
      // Mocked driver details
      driverName: 'John Doe',
      driverRating: 4.8,
    );
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
        child: FutureBuilder<Bus>(
          future: _busDetailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingState();
            } else if (snapshot.hasError) {
              return _buildErrorState();
            } else if (snapshot.hasData) {
              return _buildLoadedState(snapshot.data!);
            }
            return const SizedBox.shrink();
          },
        ),
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
            'Failed to load details',
            style: GoogleFonts.urbanist(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
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
              _buildStatColumn('ETA to Pickup', '5 min'),
              _buildStatColumn('ETA to Dest.', '25 min'),
              _buildStatColumn('Avg. Speed', '${bus.speed.toStringAsFixed(0)} km/h'),
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
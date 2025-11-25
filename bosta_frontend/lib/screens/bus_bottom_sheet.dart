import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bus.dart';
import 'rider_home_screen.dart';

class BusBottomSheet extends StatelessWidget {
  final ScrollController scrollController;
  final RiderView currentView;
  final List<Bus> suggestedBuses;
  final List<Bus> nearbyBuses;
  final Function(Bus) onBusSelected;

  const BusBottomSheet({
    super.key,
    required this.scrollController,
    required this.currentView,
    required this.suggestedBuses,
    required this.nearbyBuses,
    required this.onBusSelected,
  });

  @override
  Widget build(BuildContext context) {
    final busesToShow = currentView == RiderView.nearbyBuses ? nearbyBuses : suggestedBuses;
    final title = currentView == RiderView.nearbyBuses ? "Nearby Buses" : "Suggested Trips";

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1F2327),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
        boxShadow: [
          BoxShadow(
            blurRadius: 20.0,
            color: Colors.black54,
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: GoogleFonts.urbanist(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: busesToShow.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: scrollController,
                    itemCount: busesToShow.length,
                    itemBuilder: (context, index) {
                      final bus = busesToShow[index];
                      return _buildBusListItem(context, bus);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.directions_bus, color: Colors.white24, size: 48),
          const SizedBox(height: 16),
          Text(
            "No nearby buses found.",
            style: GoogleFonts.urbanist(color: Colors.white54, fontSize: 16),
          ),
          Text(
            "Try again in a moment.",
            style: GoogleFonts.urbanist(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildBusListItem(BuildContext context, Bus bus) {
    final distanceKm = bus.distanceMeters != null ? (bus.distanceMeters! / 1000).toStringAsFixed(1) : '...';

    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFF2ED8C3),
        child: Icon(Icons.directions_bus, color: Colors.black),
      ),
      title: Text(
        'Bus ${bus.plateNumber}',
        style: GoogleFonts.urbanist(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      subtitle: Text(
        bus.routeName ?? 'Unknown Route',
        style: GoogleFonts.urbanist(color: Colors.white70),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            bus.eta?.toMinutesString() ?? '...',
            style: GoogleFonts.urbanist(
              color: const Color(0xFF2ED8C3),
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          Text(
            '$distanceKm km away',
            style: GoogleFonts.urbanist(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
      onTap: () {
        // This is where you could potentially show the detailed modal,
        // but for now it just triggers the snackbar message.
        onBusSelected(bus);
      },
    );
  }
}
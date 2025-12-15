import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/formatters.dart';
import '../models/bus.dart';
import '../models/trip_suggestion.dart';
import 'rider_home_screen.dart';
import '../services/bus_service.dart';
import 'package:geolocator/geolocator.dart';

class BusBottomSheet extends StatelessWidget {
    final Bus? selectedBus;
    final String? etaBusToRider;
    final String? etaBusToDestination;
    final bool isFetchingEta;
  final ScrollController scrollController;
  final RiderView currentView;
  final List<TripSuggestion> tripSuggestions;
  final List<Bus> nearbyBuses;
  final Function(Bus) onBusSelected;
  final Function(TripSuggestion)? onTripSuggestionSelected;
  // Optional: snapped stop id (string) and rider coordinates for distance calc
  final String? snappedStopId;
  final double? riderLat;
  final double? riderLon;

  const BusBottomSheet({
    super.key,
    required this.scrollController,
    required this.currentView,
    required this.tripSuggestions,
    required this.nearbyBuses,
    required this.onBusSelected,
    this.onTripSuggestionSelected,
    this.snappedStopId,
    this.riderLat,
    this.riderLon,
    this.selectedBus,
    this.etaBusToRider,
    this.etaBusToDestination,
    this.isFetchingEta = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = currentView == RiderView.nearbyBuses ? "Nearby Buses" : "Trip Suggestions";

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
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (currentView == RiderView.planTrip) {
      return tripSuggestions.isEmpty
          ? _buildEmptyState("No trip suggestions found.", "Try a different destination.")
          : ListView.builder(
              controller: scrollController,
              itemCount: tripSuggestions.length,
              itemBuilder: (context, index) => _buildTripSuggestionItem(context, tripSuggestions[index], index + 1),
            );
    } else {
      return nearbyBuses.isEmpty
          ? _buildEmptyState("No nearby buses found.", "Try again in a moment.")
          : ListView.builder(
              controller: scrollController,
              itemCount: nearbyBuses.length,
              itemBuilder: (context, index) => _buildBusListItem(context, nearbyBuses[index]),
            );
    }
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.directions_bus, color: Colors.white24, size: 48),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.urbanist(color: Colors.white54, fontSize: 16),
          ),
          Text(
            subtitle,
            style: GoogleFonts.urbanist(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTripSuggestionItem(BuildContext context, TripSuggestion suggestion, int suggestionNumber) {
    return Card(
      color: const Color(0xFF2A2F33),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          if (onTripSuggestionSelected != null) onTripSuggestionSelected!(suggestion);
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Suggestion $suggestionNumber",
                style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF2ED8C3)),
              ),
              const SizedBox(height: 8),
              // Show a single centered distance line (simplified view).
              Builder(builder: (ctx) {
                String distanceLabel = '';
                try {
                  final first = suggestion.legs.isNotEmpty ? suggestion.legs.first : null;
                  if (first != null && first.destLat != null && first.destLon != null && riderLat != null && riderLon != null) {
                    final meters = Geolocator.distanceBetween(riderLat!, riderLon!, first.destLat!, first.destLon!);
                    if (meters < 1000) distanceLabel = '${meters.round()} m';
                    else distanceLabel = '${(meters / 1000).toStringAsFixed(1)} km';
                  }
                } catch (_) {}

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Center(
                    child: Text(distanceLabel.isNotEmpty ? distanceLabel : '', style: GoogleFonts.urbanist(color: Colors.white70, fontSize: 14)),
                  ),
                );
              }),
              ...suggestion.legs.map((leg) => _buildTripLegItem(leg)).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripLegItem(TripLeg leg) {
    // Show route name only (distance removed per request).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Center(
        child: Text(
          leg.routeName ?? 'Route',
          textAlign: TextAlign.center,
          style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildLegDetail(IconData icon, String label, String value) {
    return Row(
      children: [
        const SizedBox(width: 28), // Indent
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.urbanist(color: Colors.white54)),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: GoogleFonts.urbanist(color: Colors.white), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildBusListItem(BuildContext context, Bus bus) {
    final distanceKm = bus.distanceMeters != null ? (bus.distanceMeters! / 1000).toStringAsFixed(1) : '...';

    // Show ETAs and driver info only for the selected bus
    final bool showEtas = selectedBus != null && selectedBus!.id == bus.id;

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
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bus.routeName ?? 'Unknown Route',
            style: GoogleFonts.urbanist(color: Colors.white70),
          ),
          if (showEtas) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, color: Color(0xFF2ED8C3), size: 18),
                const SizedBox(width: 6),
                Text(
                  bus.driverName ?? 'N/A',
                  style: GoogleFonts.urbanist(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.star, color: Colors.amber, size: 16),
                Text(
                  (bus.driverRating ?? 0.0).toStringAsFixed(1),
                  style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showEtas && isFetchingEta)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2ED8C3)),
            ),
          if (showEtas && !isFetchingEta) ...[
            Text('Bus → You: ${etaBusToRider ?? '--'}',
                style: GoogleFonts.urbanist(color: Color(0xFF2ED8C3), fontWeight: FontWeight.bold, fontSize: 14)),
            Text('Bus → Dest: ${etaBusToDestination ?? '--'}',
                style: GoogleFonts.urbanist(color: Color(0xFF2ED8C3), fontWeight: FontWeight.bold, fontSize: 14)),
          ],
          if (!showEtas)
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
        onBusSelected(bus);
      },
    );
  }
}
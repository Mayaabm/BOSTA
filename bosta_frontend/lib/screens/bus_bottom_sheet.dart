import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../models/bus.dart';
import 'home_screen.dart';
import 'bus_suggestion_card.dart';

class BusBottomSheet extends StatelessWidget {
  final ScrollController scrollController;
  final RiderView currentView;
  final List<Bus> suggestedBuses;
  final List<Bus> nearbyBuses;
  final ValueChanged<Bus> onBusSelected;

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
    final isPlanTrip = currentView == RiderView.planTrip;
    final busesToShow = isPlanTrip ? suggestedBuses : nearbyBuses;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1A2025).withOpacity(0.95),
              const Color(0xFF12161A).withOpacity(0.98),
            ],
          ),
        ),
        child: Column(
          children: [
            _buildDragHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Text(
                isPlanTrip ? "Suggested Routes" : "Nearby Buses",
                style: GoogleFonts.urbanist(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: busesToShow.isEmpty
                  ? _buildEmptyState(isPlanTrip)
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: busesToShow.length,
                      itemBuilder: (context, index) {
                        final bus = busesToShow[index];
                        return BusSuggestionCard(
                          bus: bus,
                          onChooseBus: () => onBusSelected(bus),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      width: 40,
      height: 5,
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(12.0),
      ),
    );
  }

  Widget _buildEmptyState(bool isPlanTrip) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isPlanTrip ? Icons.search_off_rounded : Icons.bus_alert_rounded,
            size: 60,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            isPlanTrip
                ? "Enter a destination to find a bus."
                : "No buses found nearby.",
            textAlign: TextAlign.center,
            style: GoogleFonts.urbanist(
              fontSize: 18,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }
}
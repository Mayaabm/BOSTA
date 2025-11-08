// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../models/bus.dart';
import 'bus_details_modal.dart';

class BusSuggestionCard extends StatelessWidget {
  final Bus bus;
  final VoidCallback onChooseBus;

  const BusSuggestionCard({
    super.key,
    required this.bus,
    required this.onChooseBus,
  });

  @override
  Widget build(BuildContext context) {
    // Mock data for UI purposes as it's not in the model
    final rating = 3.5 + (Random().nextDouble() * 1.5);
    final occupancy = ['Low', 'Medium', 'High'][Random().nextInt(3)];
    final etaToPickup = Random().nextInt(10) + 2; // 2-12 min
    final etaToDest = etaToPickup + Random().nextInt(25) + 10; // 12-47 min

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
      color: const Color(0xFF0B0E11).withOpacity(0.7),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    bus.routeName ?? 'Route Unknown',
                    style: GoogleFonts.urbanist(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildOccupancyBadge(occupancy),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildEtaInfo("PICKUP", "$etaToPickup min"),
                Container(
                  height: 30,
                  width: 1,
                  color: Colors.white24,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                _buildEtaInfo("DESTINATION", "$etaToDest min"),
                const Spacer(),
                _buildRating(rating),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) {
                        return BusDetailsModal(
                          busId: bus.id,
                          onChooseBus: onChooseBus,
                        );
                      },
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('More Details'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onChooseBus,
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
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEtaInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.urbanist(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildRating(double rating) {
    return Row(
      children: [
        const Icon(Icons.star, color: Colors.amber, size: 18),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildOccupancyBadge(String occupancy) {
    Color color;
    switch (occupancy) {
      case 'Medium':
        color = Colors.orange;
        break;
      case 'High':
        color = Colors.red;
        break;
      default:
        color = Colors.green;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Text(occupancy, style: GoogleFonts.urbanist(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}
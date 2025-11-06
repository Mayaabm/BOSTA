// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DualSearchBar extends StatelessWidget {
  final ValueChanged<String> onDestinationSubmitted;

  const DualSearchBar({
    super.key,
    required this.onDestinationSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E11).withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSearchRow(
            icon: Icons.gps_fixed,
            iconColor: const Color(0xFF2ED8C3),
            text: "Current Location",
            isOrigin: true,
          ),
          Divider(height: 1, color: Colors.white.withOpacity(0.1)),
          _buildSearchRow(
            icon: Icons.search,
            iconColor: Colors.white,
            text: "Where to?",
            isOrigin: false,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow({
    required IconData icon,
    required Color iconColor,
    required String text,
    required bool isOrigin,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: isOrigin
                ? Text(
                    text,
                    style: GoogleFonts.urbanist(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : TextField(
                    onSubmitted: onDestinationSubmitted,
                    style: GoogleFonts.urbanist(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: text,
                      hintStyle: GoogleFonts.urbanist(
                        color: Colors.white54,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                    ),
                    textInputAction: TextInputAction.search,
                  ),
          ),
        ],
      ),
    );
  }
}
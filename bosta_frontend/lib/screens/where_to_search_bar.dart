import 'dart:async';

import 'package:bosta_frontend/screens/destination_result.dart';
import 'package:flutter/material.dart';
import 'package:bosta_frontend/screens/search_service.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:latlong2/latlong.dart';

class WhereToSearchBar extends StatefulWidget {
  final Function(DestinationResult) onDestinationSelected;
  final LatLng? userLocation; // To bias search results

  const WhereToSearchBar({
    super.key,
    required this.onDestinationSelected,
    this.userLocation,
  });

  @override
  State<WhereToSearchBar> createState() => _WhereToSearchBarState();
}

class _WhereToSearchBarState extends State<WhereToSearchBar> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TypeAheadField<DestinationResult>(
      controller: _controller,
      debounceDuration: const Duration(milliseconds: 500), // Handled by the package
      suggestionsCallback: (pattern) async {
        // Fetch all stops to act like a dropdown, then filter locally.
        final allStops = await SearchService.getAllBusStops();
        if (pattern.isEmpty) {
          return allStops; // Show all stops if search is empty
        }
        // Filter the list based on the user's input
        return allStops.where((stop) =>
            stop.name.toLowerCase().contains(pattern.toLowerCase())).toList();
      },
      itemBuilder: (context, suggestion) {
        return ListTile(
          leading: Icon(
            Icons.directions_bus,
            color: Colors.orangeAccent,
          ),
          title: Text(suggestion.name),
          subtitle: Text(
            suggestion.routeName ?? 'Unknown Route', // Show the route name
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
      onSelected: (suggestion) {
        _controller.text = suggestion.name;
        widget.onDestinationSelected(suggestion);
      },
      decorationBuilder: (context, child) {
        return Material(
          type: MaterialType.card,
          elevation: 4.0,
          color: const Color(0xFF1F2327),
          borderRadius: BorderRadius.circular(30.0),
          child: child,
        );
      },
      builder: (context, controller, focusNode) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          autofocus: false,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Color(0xFF2ED8C3)),
            hintText: 'Search for a bus stop...',
            hintStyle: TextStyle(color: Colors.grey[400]),
            filled: true,
            fillColor: const Color(0xFF1F2327),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30.0),
              borderSide: BorderSide.none,
            ),
          ),
        );
      },
      emptyBuilder: (context) => const ListTile(
        title: Text(
          "No bus stops found.",
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}
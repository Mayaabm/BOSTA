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
        // The package handles debouncing, so we can call the service directly.
        if (pattern.trim().isEmpty) {
          return [];
        }
        return await SearchService.searchDestinations(
          pattern,
          proximity: widget.userLocation,
        );
      },
      itemBuilder: (context, suggestion) {
        return ListTile(
          leading: Icon(
            suggestion.source == 'bus_stop' ? Icons.directions_bus : Icons.location_on_outlined,
            color: suggestion.source == 'bus_stop' ? Colors.orangeAccent : Theme.of(context).iconTheme.color,
          ),
          title: Text(suggestion.name),
          subtitle: Text(
            suggestion.address ?? '',
            maxLines: 1,
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
            hintText: 'Where to?',
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
        title: Text("No results found."),
      ),
    );
  }
}
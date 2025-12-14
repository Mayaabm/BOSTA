import 'dart:async';
import 'dart:convert';

import 'package:bosta_frontend/screens/destination_result.dart';
import 'package:flutter/material.dart';
import 'package:bosta_frontend/screens/search_service.dart';
import 'package:bosta_frontend/services/geocoding_service.dart';
import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:http/http.dart' as http;
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
        debugPrint('[WhereToSearchBar] suggestionsCallback: pattern="$pattern"');
        if (pattern.trim().length < 2) return <DestinationResult>[]; // Require min 2 chars

        // Primary: use Mapbox Places via GeocodingService
        try {
          final places = await GeocodingService.searchPlaces(pattern, proximity: widget.userLocation);
          debugPrint('[WhereToSearchBar] geocoding returned ${places.length} places');
          // Map Place -> DestinationResult
          final mapped = places.map((p) {
            return DestinationResult(
              name: p.name,
              address: p.address,
              order: null,
              stopId: null,
              routeId: null,
              routeName: null,
              latitude: p.coordinates.latitude,
              longitude: p.coordinates.longitude,
              source: 'mapbox',
            );
          }).toList();
          return mapped;
        } catch (e) {
          debugPrint('[WhereToSearchBar] GeocodingService failed: $e');
        }

        // Fallback: search local bus stops
        try {
          final stops = await SearchService.searchBusStops(pattern);
          return stops;
        } catch (e) {
          debugPrint('[WhereToSearchBar] fallback bus stop search failed: $e');
          return <DestinationResult>[];
        }
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
      onSelected: (suggestion) async {
        _controller.text = suggestion.name;
        debugPrint('[WhereToSearchBar] selected: ${suggestion.name} (${suggestion.latitude},${suggestion.longitude}) source=${suggestion.source}');

        // Call backend to snap this destination to nearest stops and get boarding options
        try {
          final uri = Uri.parse(ApiEndpoints.nearestForDestination).replace(queryParameters: {
            'dest_lat': suggestion.latitude.toString(),
            'dest_lon': suggestion.longitude.toString(),
            if (widget.userLocation != null) 'user_lat': widget.userLocation!.latitude.toString(),
            if (widget.userLocation != null) 'user_lon': widget.userLocation!.longitude.toString(),
            'n': '3',
          });
          debugPrint('[WhereToSearchBar] calling nearestForDestination: $uri');
          final resp = await http.get(uri);
          if (resp.statusCode == 200) {
            final Map<String, dynamic> data = resp.body.isNotEmpty ? (jsonDecode(resp.body) as Map<String, dynamic>) : {};
            // If backend returned destination_nearest_stops, attach first stop id and include full snapped data
            if (data['destination_nearest_stops'] is List && (data['destination_nearest_stops'] as List).isNotEmpty) {
              final first = (data['destination_nearest_stops'] as List)[0] as Map<String, dynamic>;
              suggestion = DestinationResult(
                name: suggestion.name,
                address: data['snapped_destination'] != null ? (data['snapped_destination']['properties']?['name'] ?? suggestion.address) : suggestion.address,
                order: suggestion.order,
                stopId: first['id']?.toString(),
                routeId: first['route']?.toString(),
                routeName: first['route']?.toString(),
                latitude: suggestion.latitude,
                longitude: suggestion.longitude,
                source: suggestion.source,
                snappedData: data,
              );
            } else {
              // If no nearest stops returned, still attach snapped if present
              suggestion = DestinationResult(
                name: suggestion.name,
                address: data['snapped_destination'] != null ? (data['snapped_destination']['properties']?['name'] ?? suggestion.address) : suggestion.address,
                order: suggestion.order,
                stopId: suggestion.stopId,
                routeId: suggestion.routeId,
                routeName: suggestion.routeName,
                latitude: suggestion.latitude,
                longitude: suggestion.longitude,
                source: suggestion.source,
                snappedData: data,
              );
            }
          } else {
            debugPrint('[WhereToSearchBar] nearestForDestination returned ${resp.statusCode}');
          }
        } catch (e) {
          debugPrint('[WhereToSearchBar] nearestForDestination call failed: $e');
        }

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
            hintText: 'Where do you want to go?',
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
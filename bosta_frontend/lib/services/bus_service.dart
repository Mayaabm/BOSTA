import 'dart:convert';
import 'dart:collection';
import 'package:http/http.dart' as http;
import '../models/bus.dart';
import '../models/user_location.dart';
import '../models/trip_suggestion.dart';
import 'auth_service.dart'; // Import AuthService
// Import Provider
import '../services/api_endpoints.dart';
import 'package:flutter/foundation.dart';

class BusService {
  /// Fetches detailed information for a single bus, including ETA if location is provided.
  static Future<Bus> getBusDetails(String busId, {UserLocation? userLocation}) async {
    // Correctly call the busDetails method to get the base URL for the specific bus.
    String url = ApiEndpoints.busDetails(busId);

    if (userLocation != null) {
      url += '?lat=${userLocation.latitude}&lon=${userLocation.longitude}';
    }
    final Uri uri = Uri.parse(url);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return Bus.fromJson(data);
    } else {
      throw Exception('Failed to load details for bus $busId: ${response.body}');
    }
  }

  /// Sends the bus's current location to the backend.
  static Future<void> updateLocation({
    required String busId,
    required double latitude,
    required double longitude,
    required String token, // Add token parameter
    AuthService? authService, // Make AuthService available
  }) async {
    final uri = Uri.parse(ApiEndpoints.updateLocation); // Use the correct endpoint from ApiEndpoints

    Future<http.Response> doPost(String currentToken) {
      return http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $currentToken',
        },
        body: json.encode({
          'bus_id': busId,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );
    }

    var response = await doPost(token);

    // If the token is expired, try to refresh it and retry the request.
    if (response.statusCode == 401 && response.body.contains('token_not_valid')) {
      if (authService != null && authService.currentState.refreshToken != null) {
        final newAccessToken = await authService.refreshAccessToken(authService.currentState.refreshToken!);
        if (newAccessToken != null) {
          // Retry the request with the new token
          response = await doPost(newAccessToken);
        } else {
          // If refresh fails, throw an exception to indicate a logout is needed.
          throw Exception('Session expired. Please log in again.');
        }
      }
    }

    if (response.statusCode != 200) {
      throw Exception('Failed to update bus location: ${response.body}');
    }
  }

  /// Fetches buses near a given coordinate.
  static Future<List<Bus>> getNearbyBuses({required double latitude, required double longitude, double radius = 10000}) async {
    final uri = Uri.parse('${ApiEndpoints.nearbyBuses}?lat=$latitude&lon=$longitude&radius=$radius');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Bus.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load nearby buses');
    }
  }

  /// Finds buses that can serve a trip from a start to an end point.
  static Future<List<TripSuggestion>> findTripSuggestions({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    // Older implementation expected a GET planTrip endpoint. Instead, use
    // the backend `plan_trip` POST API which accepts a destination stop id
    // or the `buses/to_destination/` endpoint. For now call `buses/to_destination`
    // to get nearby active buses and ETA to the target point.
    // The backend `buses/to_destination/` expects `lat` and `lon` for the target point.
    // Provide the end coordinates as `lat`/`lon`. Keep debug logs to inspect responses.
    // First, try to snap the destination to the nearest DB stop and use
    // that stop's coordinates for subsequent backend queries. This keeps
    // the UI and backend route-resolution consistent.
    double queryLat = endLat;
    double queryLon = endLon;
    List<dynamic> destNearest = [];
    try {
      final ndUri = Uri.parse('${ApiEndpoints.nearestForDestination}?dest_lat=$endLat&dest_lon=$endLon&user_lat=$startLat&user_lon=$startLon');
      debugPrint('[BusService.findTripSuggestions] snapping dest via nearestForDestination uri=$ndUri');
      final ndResp = await http.get(ndUri);
      debugPrint('[BusService.findTripSuggestions] nearestForDestination status=${ndResp.statusCode} body=${ndResp.body}');
      if (ndResp.statusCode == 200) {
        final js = json.decode(ndResp.body) as Map<String, dynamic>;
        destNearest = js['destination_nearest_stops'] is List ? js['destination_nearest_stops'] as List<dynamic> : [];

        // If the API returned a snapped_destination GeoJSON or similar, try to use it.
        final snapped = js['snapped_destination'];
        if (snapped != null) {
          try {
            if (snapped is Map<String, dynamic>) {
              if (snapped.containsKey('lat') && snapped.containsKey('lon')) {
                queryLat = (snapped['lat'] as num).toDouble();
                queryLon = (snapped['lon'] as num).toDouble();
              } else if (snapped.containsKey('y') && snapped.containsKey('x')) {
                queryLat = (snapped['y'] as num).toDouble();
                queryLon = (snapped['x'] as num).toDouble();
              } else if (snapped.containsKey('coordinates') && snapped['coordinates'] is List) {
                final coords = snapped['coordinates'] as List;
                if (coords.length >= 2) {
                  queryLon = (coords[0] as num).toDouble();
                  queryLat = (coords[1] as num).toDouble();
                }
              }
            }
          } catch (_) {}
        }

        // If snapping via snapped_destination didn't yield coords, fall back
        // to the nearest DB stop's stored coordinates (lookup via searchStops).
        if ((queryLat == endLat && queryLon == endLon) && destNearest.isNotEmpty) {
          try {
            final stopsUri = Uri.parse(ApiEndpoints.searchStops);
            final stopsResp = await http.get(stopsUri);
            if (stopsResp.statusCode == 200) {
              final List<dynamic> stops = json.decode(stopsResp.body) as List<dynamic>;
              final firstStopId = destNearest[0]['id'];
              final matched = stops.firstWhere((st) => st['id'] == firstStopId, orElse: () => null);
              if (matched != null) {
                if (matched.containsKey('latitude') && matched.containsKey('longitude')) {
                  queryLat = (matched['latitude'] as num).toDouble();
                  queryLon = (matched['longitude'] as num).toDouble();
                } else if (matched.containsKey('lat') && matched.containsKey('lon')) {
                  queryLat = (matched['lat'] as num).toDouble();
                  queryLon = (matched['lon'] as num).toDouble();
                } else if (matched.containsKey('location') && matched['location'] is Map) {
                  final loc = matched['location'] as Map<String, dynamic>;
                  if (loc.containsKey('coordinates') && loc['coordinates'] is List) {
                    final coords = loc['coordinates'] as List;
                    if (coords.length >= 2) {
                      queryLon = (coords[0] as num).toDouble();
                      queryLat = (coords[1] as num).toDouble();
                    }
                  }
                }
              }
            } else {
              debugPrint('[BusService.findTripSuggestions] searchStops failed status=${stopsResp.statusCode}');
            }
          } catch (e) {
            debugPrint('[BusService.findTripSuggestions] snapping fallback Exception: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[BusService.findTripSuggestions] snapping Exception: $e');
    }

    // Instead of searching for active buses, return route-only suggestions.
    // Use the `destination_nearest_stops` returned by `nearest_for_destination`
    // (populated earlier) to resolve route ids and names and present them
    // as route-only TripSuggestion entries (`available=false`). This keeps the
    // UI focused on route names only as requested.
    try {
      if (destNearest.isNotEmpty) {
        // Performance: fetch the stops list once and resolve all route details
        // in parallel, caching results to avoid duplicate network calls.
        final stopsUri = Uri.parse(ApiEndpoints.searchStops);
        final stopsResp = await http.get(stopsUri);
        if (stopsResp.statusCode != 200) {
          debugPrint('[BusService.findTripSuggestions] searchStops failed status=${stopsResp.statusCode}');
          return [];
        }

        final List<dynamic> stops = json.decode(stopsResp.body) as List<dynamic>;
        final Map<String, dynamic> stopsById = {};
        for (final st in stops) {
          try {
            final idKey = st['id']?.toString();
            if (idKey != null) stopsById[idKey] = st;
          } catch (_) {}
        }

        // Deduplicate nearest stops by id (some backends return duplicates).
        final List<dynamic> dedupedDestNearest = [];
        final Set<String> seenStopIds = {};
        for (final s in destNearest) {
          final sid = s['id']?.toString() ?? s.toString();
          if (seenStopIds.contains(sid)) continue;
          seenStopIds.add(sid);
          dedupedDestNearest.add(s);
        }

        // Collect all unique route ids referenced by the nearest stops
        final Set<String> allRouteIds = {};
        final Map<String, List<String>> stopToRouteIds = {};
        for (final s in dedupedDestNearest) {
          final stopIdKey = s['id']?.toString();
          final matched = stopIdKey != null ? stopsById[stopIdKey] : null;
          final List<String> rids = [];
          if (matched != null) {
            final List<dynamic>? ridsList = (matched['route_ids'] is List) ? (matched['route_ids'] as List<dynamic>) : null;
            if (ridsList != null && ridsList.isNotEmpty) {
              for (final ridEntry in ridsList) {
                final rid = ridEntry?.toString();
                if (rid != null) {
                  rids.add(rid);
                  allRouteIds.add(rid);
                }
              }
            } else if (matched['route_id'] != null) {
              final rid = matched['route_id'].toString();
              rids.add(rid);
              allRouteIds.add(rid);
            }
          } else {
            // Fallback to any route info in the destNearest payload
            if (s['route'] != null) {
              final rid = s['route'].toString();
              rids.add(rid);
              allRouteIds.add(rid);
            }
          }
          stopToRouteIds[s['id']?.toString() ?? s.toString()] = rids;
        }

        // Fetch route details in parallel for all unique route ids
        final Map<String, String> routeNameCache = {};
        final List<Future<void>> fetches = [];
        for (final rid in allRouteIds) {
          fetches.add(() async {
            try {
              final routeUri = Uri.parse(ApiEndpoints.routeDetails(rid));
              final rResp = await http.get(routeUri);
              if (rResp.statusCode == 200) {
                final Map<String, dynamic> rjson = json.decode(rResp.body) as Map<String, dynamic>;
                final rname = (rjson['name'] ?? rjson['title'] ?? rjson['display_name'])?.toString() ?? rid;
                routeNameCache[rid] = rname;
              } else {
                routeNameCache[rid] = rid;
              }
            } catch (_) {
              routeNameCache[rid] = rid;
            }
          }());
        }
        await Future.wait(fetches);

        // Build TripSuggestion list: one suggestion per nearest stop, listing
        // all unique route names (one per line).
        final List<TripSuggestion> routeOnly = [];
        final Set<String> seenSuggestions = {};
        // Keep track of seen route-name sets to avoid duplicate suggestion cards
        final Set<String> seenRouteSets = {};
        for (final s in dedupedDestNearest) {
          final stopKey = s['id']?.toString() ?? s.toString();
          final rids = stopToRouteIds[stopKey] ?? [];
          final List<String> names = [];
          for (final rid in rids) {
            var rn = routeNameCache[rid] ?? rid;
            if (rn != null) {
              rn = rn.toString().trim();
              if (rn.isNotEmpty) names.add(rn);
            }
          }

          // Fallback to textual fields if we couldn't resolve route ids
          if (names.isEmpty) {
            if (s['route_name'] != null) names.add(s['route_name'].toString());
            else if (s['route'] != null) names.add(s['route'].toString());
          }

          // Deduplicate while preserving order and normalize
          final uniqueNames = LinkedHashSet<String>.from(names).toList();
          if (uniqueNames.isEmpty) continue;

          // Avoid showing multiple suggestion cards with the identical set
          // of route names (different nearby stops can reference same routes).
          final namesKey = uniqueNames.join('|');
          if (seenRouteSets.contains(namesKey)) continue;
          seenRouteSets.add(namesKey);

          final legs = uniqueNames.map((n) => TripLeg(
            routeName: n,
            boardAt: 'Nearby',
            exitAt: 'Destination',
            available: false,
            etaMinutes: null,
            destLat: queryLat,
            destLon: queryLon,
          )).toList();

          routeOnly.add(TripSuggestion(legs: legs));
        }

        if (routeOnly.isNotEmpty) return routeOnly;
      }
    } catch (e) {
      debugPrint('[BusService.findTripSuggestions] route-only Exception: $e');
    }

    return [];
  }

  /// Call the backend plan_trip API to get ETA and plan info for a selected stop.
  static Future<Map<String, dynamic>?> planTripToStop({
    required String destinationStopId,
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(ApiEndpoints.planTrip);
    try {
      final response = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: json.encode({
        'destination_stop_id': int.parse(destinationStopId),
        'latitude': latitude,
        'longitude': longitude,
      }));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('BusService.planTripToStop Exception: $e');
    }
    return null;
  }

  /// Finds all active buses for a specific route ID.
  static Future<List<Bus>> findBusesForRoute(String routeId) async {
    // Backend expects a query param `route_id`, not a path segment.
    final uri = Uri.parse('${ApiEndpoints.busesForRoute}?route_id=$routeId');
    debugPrint('[BusService.findBusesForRoute] Fetching buses for route (query): $uri');

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final buses = data.map((json) => Bus.fromJson(json)).toList();
        debugPrint('[BusService.findBusesForRoute] Found ${buses.length} buses for route $routeId.');
        return buses;
      } else {
        debugPrint('[BusService.findBusesForRoute] Failed with status ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[BusService.findBusesForRoute] Exception: $e');
    }
    return []; // Return empty list on failure
  }

  /// Returns the list of route names that reference the given stop id.
  /// Uses the `searchStops` endpoint to find the stop's `route_ids`, then
  /// fetches route details for each id to obtain the human-readable name.
  static Future<List<String>> getRouteNamesForStop(int stopId) async {
    try {
      final stopsUri = Uri.parse(ApiEndpoints.searchStops);
      final stopsResp = await http.get(stopsUri);
      if (stopsResp.statusCode != 200) {
        debugPrint('[BusService.getRouteNamesForStop] failed to fetch stops: ${stopsResp.statusCode}');
        return [];
      }

      final List<dynamic> stops = json.decode(stopsResp.body) as List<dynamic>;
      final matched = stops.firstWhere((st) => st['id'] == stopId, orElse: () => null);
      if (matched == null) {
        debugPrint('[BusService.getRouteNamesForStop] stop $stopId not found in searchStops payload');
        return [];
      }

      final List<String> names = [];

      // If the stop payload already contains route names, prefer those.
      if (matched.containsKey('route_name') && matched['route_name'] != null) {
        names.add(matched['route_name'].toString());
      }

      // Collect route ids from 'route_ids' or 'route_id'
      final List<dynamic>? ridsList = (matched['route_ids'] is List) ? (matched['route_ids'] as List<dynamic>) : null;
      if (ridsList != null && ridsList.isNotEmpty) {
        for (final rid in ridsList) {
          final ridStr = rid?.toString();
          if (ridStr == null) continue;
          try {
            final routeUri = Uri.parse(ApiEndpoints.routeDetails(ridStr));
            final rResp = await http.get(routeUri);
            if (rResp.statusCode == 200) {
              final Map<String, dynamic> rjson = json.decode(rResp.body) as Map<String, dynamic>;
              final rname = (rjson['name'] ?? rjson['title'] ?? rjson['display_name'])?.toString();
              if (rname != null && !names.contains(rname)) names.add(rname);
            } else {
              debugPrint('[BusService.getRouteNamesForStop] route ${ridStr} details failed: ${rResp.statusCode}');
            }
          } catch (e) {
            debugPrint('[BusService.getRouteNamesForStop] exception fetching route $ridStr: $e');
          }
        }
      } else if (matched.containsKey('route_id') && matched['route_id'] != null) {
        final ridStr = matched['route_id'].toString();
        try {
          final routeUri = Uri.parse(ApiEndpoints.routeDetails(ridStr));
          final rResp = await http.get(routeUri);
          if (rResp.statusCode == 200) {
            final Map<String, dynamic> rjson = json.decode(rResp.body) as Map<String, dynamic>;
            final rname = (rjson['name'] ?? rjson['title'] ?? rjson['display_name'])?.toString();
            if (rname != null && !names.contains(rname)) names.add(rname);
          }
        } catch (e) {
          debugPrint('[BusService.getRouteNamesForStop] exception fetching route ${ridStr}: $e');
        }
      }

      return names;
    } catch (e) {
      debugPrint('[BusService.getRouteNamesForStop] Exception: $e');
      return [];
    }
  }
}
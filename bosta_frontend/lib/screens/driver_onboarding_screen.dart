import 'dart:async';
import 'dart:convert';

import 'package:bosta_frontend/models/app_route.dart';
import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as fm;
import 'package:bosta_frontend/services/driver_dashboard.dart';
import 'package:flutter/scheduler.dart';

class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _busPlateController = TextEditingController();
  final _busCapacityController = TextEditingController();

  List<AppRoute> _availableRoutes = []; // All routes from backend
  String? _selectedRouteId;
  AppRoute? _selectedRoute; // Will hold the full details of the chosen route
  String? _selectedStartLocation; // Will store the selected stop name
  String? _selectedStopId; // id of selected stop (robust choice for Dropdown)
  fm.LatLng? _selectedStartLatLng; // Point picked on the map
  final MapController _mapController = MapController();
  bool _forceShowMap = false; // debug toggle to force map rendering
  TimeOfDay? _selectedStartTime;
  // Polling state removed from onboarding — tracking handled on Driver map screen

  bool _isLoading = false;
  bool _isFetchingRoutes = true;
  String? _errorMessage;
  bool _isRouteSheetOpen = false;
  bool _isRouteListExpanded = false;
  bool _isTimeListExpanded = false;

  @override
  void initState() {
    super.initState();
    // Fetch routes once when the screen is first initialized.
    // Using a post-frame callback ensures the context is available for Provider
    // and avoids trying to fetch data during the initial build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAvailableRoutes());
  }
  
  Future<void> _fetchAvailableRoutes() async {
    setState(() {
      _isFetchingRoutes = true;
      _errorMessage = null;
    });
    try {
      // The user must be authenticated to reach this screen, so we need to include the auth token.
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.currentState.token;

      final uri = Uri.parse(ApiEndpoints.routes);
      // Routes are public; attempt to fetch without requiring authentication.
      final headers = <String, String>{};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        // Accept both list responses and paginated objects with a "results" list.
        List<dynamic> dataList;
        if (decoded is List) {
          dataList = decoded;
        } else if (decoded is Map && decoded['results'] is List) {
          dataList = List<dynamic>.from(decoded['results'] as List);
        } else {
          throw FormatException('Unexpected routes payload shape: ${decoded.runtimeType}');
        }

        try {
          final parsed = dataList.map((json) => AppRoute.fromJson(Map<String, dynamic>.from(json as Map))).toList();
          debugPrint('fetchAvailableRoutes: loaded ${parsed.length} routes');
          if (mounted) {
            setState(() {
              _availableRoutes = parsed;
              _isFetchingRoutes = false;
            });
          }
        } catch (e, st) {
          // Parsing error: surface details for debugging
          final bodyText = response.body.isNotEmpty ? response.body : '<empty body>';
          debugPrint('fetchAvailableRoutes: JSON parse error: $e');
          debugPrint('response size=${response.body.length} body (truncated 1024): ${bodyText.length > 1024 ? bodyText.substring(0,1024) : bodyText}');
          debugPrint(st.toString());
          if (mounted) {
            setState(() {
              _errorMessage = 'Failed to parse routes JSON: $e';
              _isFetchingRoutes = false;
            });
          }
        }
      } else {
        // Surface detailed error info for debugging
        final bodyText = response.body.isNotEmpty ? response.body : '<empty body>';
        debugPrint('fetchAvailableRoutes failed: status=${response.statusCode} body=$bodyText');
        throw Exception('Failed to load routes. Status: ${response.statusCode}. Body: $bodyText');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not fetch routes. Please try Refresh or check your network / server.';
          _isFetchingRoutes = false;
        });
      }
    }
  }

  /// Fetches the full details (including geometry) for a single, selected route.
  Future<void> _fetchRouteDetails(String routeId) async {
    setState(() {
      _isLoading = true; // Use the main loader while fetching details. Dependent state is cleared in onChanged.
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.currentState.token;
      final uri = Uri.parse('${ApiEndpoints.routes}$routeId/'); // e.g., /api/routes/route-1/
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _selectedRoute = AppRoute.fromJson(json.decode(response.body));
          });
          // Ensure the map recenters/fits the selected route after the frame renders
          WidgetsBinding.instance.addPostFrameCallback((_) => _centerMapOnRoute());
        }
      } else {
        throw Exception('Failed to load route details');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not load details for the selected route.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Start trip from UI (test): calls POST /api/trips/<id>/start/ with chosen start stop/time
  Future<void> _startTripFromUI() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.currentState.token;
    final tripId = authService.lastCreatedTripId;

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No auth token. Please log in.')));
      return;
    }
    if (tripId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Trip found. Save and Continue first.')));
      return;
    }

    // Build start_time ISO string if a time is selected
    String? isoStart;
    if (_selectedStartTime != null) {
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, _selectedStartTime!.hour, _selectedStartTime!.minute);
      isoStart = dt.toIso8601String();
    }

    final body = <String, dynamic>{
      if (_selectedStopId != null) 'start_stop_id': _selectedStopId,
      if (isoStart != null) 'start_time': isoStart,
      'speed_mps': 8.0,
      'interval_seconds': 2.0,
    };

    final uri = Uri.parse(ApiEndpoints.startTrip(tripId));
    try {
      final res = await http.post(uri, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'}, body: json.encode(body));
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulation started — opening driver map.')));
      } else {
        final msg = res.body.isNotEmpty ? res.body : 'Failed to start simulation';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Start failed: $msg')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error starting trip: $e')));
    }
  }

  

  void _centerMapOnRoute() {
    if (_selectedRoute == null || _selectedRoute!.geometry.isEmpty) return;
    try {
      final pts = _selectedRoute!.geometry;
      double minLat = pts.first.latitude, maxLat = pts.first.latitude;
      double minLng = pts.first.longitude, maxLng = pts.first.longitude;
      for (final p in pts) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final center = fm.LatLng((minLat + maxLat) / 2.0, (minLng + maxLng) / 2.0);
      // Move to center with a reasonable zoom; we avoid calling fitBounds for compatibility.
      _mapController.move(center, 13.0);
    } catch (e) {
      try {
        final p = _selectedRoute!.geometry.first;
        _mapController.move(p, 13.0);
      } catch (_) {}
    }
  }

  double _distanceToRouteMeters(fm.LatLng point) {
    // Compute minimum distance from point to any segment of the route polyline
    if (_selectedRoute == null || _selectedRoute!.geometry.isEmpty) return double.infinity;
    final fm.Distance dist = fm.Distance();
    double minMeters = double.infinity;

    final coords = _selectedRoute!.geometry;
    for (int i = 0; i < coords.length - 1; i++) {
      final a = coords[i];
      final b = coords[i + 1];
      // Convert to fm.LatLng
      final latlngA = fm.LatLng(a.latitude, a.longitude);
      final latlngB = fm.LatLng(b.latitude, b.longitude);
      // Approximate by sampling projection: compute distance to endpoints and to segment midpoint
      final d1 = dist(point, latlngA);
      final d2 = dist(point, latlngB);
      // rough segment distance: min(d1,d2)
      final segMin = d1 < d2 ? d1 : d2;
      if (segMin < minMeters) minMeters = segMin;
    }
    return minMeters;
  }

  void _onMapTap(fm.LatLng latlng) {
    // Validate point is near the route (100m tolerance)
    final meters = _distanceToRouteMeters(latlng);
    if (meters > 100) {
      setState(() {
        _errorMessage = 'Selected point is ${meters.toStringAsFixed(0)}m away from the route. Please pick a point on the route.';
      });
      return;
    }
    setState(() {
      _selectedStartLatLng = latlng;
      _selectedStartLocation = '${latlng.latitude.toStringAsFixed(5)}, ${latlng.longitude.toStringAsFixed(5)}';
      _errorMessage = null;
    });
    // Move map to selected point
    try {
      _mapController.move(latlng, 15.0);
    } catch (_) {}
  }

  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Additional validation for non-form fields before proceeding.
    if (_selectedRouteId == null || _selectedStartLocation == null || _selectedStartTime == null) {
      setState(() {
        _errorMessage = 'Please complete all fields, including route, start location, and start time.';
        // This is a good place to trigger autovalidation to highlight missing fields.
        _formKey.currentState?.validate();
      });
      return;
    }

    // Safely capture the required values after validation.
    final routeId = _selectedRouteId!;
    final busCapacityText = _busCapacityController.text;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final error = await authService.setupDriverProfile(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      phoneNumber: _phoneController.text,
      busPlateNumber: _busPlateController.text.toUpperCase(),
      busCapacity: int.parse(busCapacityText),
      routeId: routeId,
      refreshToken: authService.currentState.refreshToken, // use refresh token if available
    );

    if (mounted) {
      if (error != null) {
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
      } else {
        // Success: stop loading; navigation is handled by router/redirects.
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved.')));
        }
      }
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _busPlateController.dispose();
    _busCapacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12161A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Text('Driver Setup',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 10),
                Text(
                  'Complete your profile to get on the road. All fields are required unless marked optional.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[400]),
                ),
                const SizedBox(height: 40),
                _buildSectionHeader('Personal Information'),
                _buildTextField(_firstNameController, 'First Name', Icons.person_outline),
                const SizedBox(height: 16),
                _buildTextField(_lastNameController, 'Last Name', Icons.person_outline),
                const SizedBox(height: 16),
                _buildTextField(_phoneController, 'Phone Number', Icons.phone_outlined, keyboardType: TextInputType.phone),
                _buildSectionHeader('Vehicle Information'),
                _buildTextField(_busPlateController, 'Bus Plate Number (e.g., ABC-1234)', Icons.directions_bus_outlined),
                const SizedBox(height: 16),
                _buildTextField(_busCapacityController, 'Bus Capacity (e.g., 14)', Icons.group_outlined, keyboardType: TextInputType.number),
                _buildSectionHeader('Route & Documents'),
                // Add the route selection and dependent fields here.
                _buildRouteDropdown(),
                // Conditionally display start location and time pickers once a route is selected.
                if (_selectedRouteId != null) ..._buildDynamicRouteFields(),
                const SizedBox(height: 20),
                _buildFileUpload('Driver License (Optional)', Icons.credit_card),
                const SizedBox(height: 12),
                _buildFileUpload('Bus Registration (Optional)', Icons.article_outlined),
                const SizedBox(height: 30),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 14), textAlign: TextAlign.center),
                  ),
                _isLoading || _isFetchingRoutes
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF2ED8C3)))
                    : ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2ED8C3),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Save and Continue',
                          style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _startTripFromUI,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2ED8C3),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Start Trip (test)', style: GoogleFonts.urbanist(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 12.0),
      child: Text(
        title,
        style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
      ),
    );
  }

  List<Widget> _buildDynamicRouteFields() {
    // If we have a selected route with geometry, show a small map picker
    final hasGeometry = _selectedRoute != null && _selectedRoute!.geometry.isNotEmpty;
    final hasStops = _selectedRoute != null && _selectedRoute!.stops.isNotEmpty;
    final showMap = hasGeometry || _forceShowMap;
    return [
      const SizedBox(height: 20),
      if (showMap) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text('Pick start location on map (tap to choose)', style: GoogleFonts.urbanist(color: Colors.white70)),
        ),
        Container(
          height: 260,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0xFF1F2327)),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              // safe fallback center when forcing the map for debugging
              initialCenter: (_selectedRoute != null && _selectedRoute!.geometry.isNotEmpty)
                  ? _selectedRoute!.geometry.first
                  : fm.LatLng(33.89365, 35.55166),
              initialZoom: 13.0,
              onTap: (tapPos, latlng) => _onMapTap(latlng),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
              if (_selectedRoute != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _selectedRoute!.geometry.map((g) => fm.LatLng(g.latitude, g.longitude)).toList(),
                      color: Colors.orangeAccent,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
              MarkerLayer(markers: [
                // Show markers for all stops (if available) so driver can tap them on the map.
                if (_selectedRoute != null && _selectedRoute!.stops.isNotEmpty)
                  ..._selectedRoute!.stops.map((s) => Marker(
                        width: 24,
                        height: 24,
                        point: fm.LatLng(s.location.latitude, s.location.longitude),
                          child: IconButton(
                            padding: const EdgeInsets.all(0),
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            onPressed: () {
                              setState(() {
                                _selectedStopId = s.id;
                                _selectedStartLocation = s.order != null ? 'Stop ${s.order}' : '${s.location.latitude.toStringAsFixed(5)}, ${s.location.longitude.toStringAsFixed(5)}';
                                _selectedStartLatLng = fm.LatLng(s.location.latitude, s.location.longitude);
                                _errorMessage = null;
                              });
                              try {
                                _mapController.move(_selectedStartLatLng!, 15.0);
                              } catch (_) {}
                            },
                            icon: Icon(Icons.location_on, color: Colors.blueAccent.withOpacity(0.95), size: 28),
                          ),
                      ))
                else if (_selectedStartLatLng != null)
                  Marker(
                    width: 36,
                    height: 36,
                    point: _selectedStartLatLng!,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 36),
                  ),
                ]),
              // Moving bus marker from simulator (if present)
              // Moving bus marker removed from onboarding; tracking is on Driver map screen.
            ],
          ),
        ),
        const SizedBox(height: 12),
        // If the route has stops, show the dropdown below the map so the
        // driver can either tap a marker or pick from the list.
        if (hasStops) ...[
          _buildStartLocationDropdown(),
          const SizedBox(height: 12),
        ],
      ] else ...[
        _buildStartLocationDropdown(),
        const SizedBox(height: 12),
      ],

      const SizedBox(height: 20),
      _buildStartTimePicker(),
    ];
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFF1F2327),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '$label is required';
        }
        if (keyboardType == TextInputType.number && int.tryParse(value) == null) {
          return 'Please enter a valid number';
        }
        if (label.contains('Bus Plate') && !RegExp(r'^[A-Z]{1,4}-\d{1,4}$').hasMatch(value)) {
          return 'Use format like T-1234';
        }
        return null;
      },
    );
  }

  Widget _buildRouteDropdown() {
    if (_isFetchingRoutes) {
      return const Center(child: Text("Fetching available routes...", style: TextStyle(color: Colors.white70)));
    }

    if (_availableRoutes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _errorMessage ?? "No routes available.",
              style: const TextStyle(color: Colors.amber),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'If you see "Please complete all fields..." but do not see route, start location or start time fields, tap Refresh to try loading available routes. If the problem persists, contact support.',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchAvailableRoutes,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2ED8C3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Refresh Routes', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }

    // Debug button to force map visibility when troubleshooting (development only)
    Widget debugButton = Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: ElevatedButton(
        onPressed: () {
          setState(() => _forceShowMap = !_forceShowMap);
        },
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ED8C3)),
        child: Text(_forceShowMap ? 'Hide Map (debug)' : 'Show Map (debug)', style: const TextStyle(color: Colors.black)),
      ),
    );

    final currentRouteIds = _availableRoutes.map((r) => r.id).toSet();
    final hasValidRouteSelection = _selectedRouteId != null && currentRouteIds.contains(_selectedRouteId);
    final safeSelectedRouteId = hasValidRouteSelection ? _selectedRouteId : null;
    // Clear an invalid selection on the next frame to avoid Dropdown assertion.
    if (!hasValidRouteSelection && _selectedRouteId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedRouteId = null;
          _selectedRoute = null;
          _selectedStopId = null;
          _selectedStartLocation = null;
        });
      });
    }

    return Column(children: [
      GestureDetector(
        onTap: () {
          setState(() => _isRouteListExpanded = !_isRouteListExpanded);
        },
        child: AbsorbPointer(
          child: TextFormField(
            key: ValueKey('route-picker-${_availableRoutes.length}-${safeSelectedRouteId ?? 'none'}'),
            readOnly: true,
            controller: TextEditingController(text: _selectedRoute?.name ?? ''),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Select Your Operating Route',
              labelStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: const Icon(Icons.route_outlined, color: Colors.white70),
              suffixIcon: Icon(
                _isRouteListExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: Colors.white70,
              ),
              filled: true,
              fillColor: const Color(0xFF1F2327),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
              ),
            ),
            validator: (_) => safeSelectedRouteId == null ? 'Route selection is required' : null,
          ),
        ),
      ),
      if (_isRouteListExpanded)
        Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2327),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2ED8C3).withOpacity(0.4)),
          ),
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _availableRoutes.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
            itemBuilder: (_, index) {
              final route = _availableRoutes[index];
              final isSelected = route.id == _selectedRouteId;
              return ListTile(
                title: Text(route.name, style: const TextStyle(color: Colors.white)),
                trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF2ED8C3)) : null,
                onTap: () async {
                  setState(() {
                    _selectedRouteId = route.id;
                    _selectedRoute = null;
                    _selectedStopId = null;
                    _selectedStartLocation = null;
                    _isRouteListExpanded = false;
                  });
                  await _fetchRouteDetails(route.id);
                },
              );
            },
          ),
        ),
      debugButton,
    ]);
  }

  Widget _buildStartLocationDropdown() {
    // Use stops provided by the selected route when available.
    final routeStops = _selectedRoute?.stops ?? [];

    if (routeStops.isEmpty) {
      return const Text(
        'This route has no defined stops. Please select another route or use the map picker.',
        style: TextStyle(color: Colors.amber),
      );
    }

    // Use stop id (string) as the dropdown value to avoid object identity issues.
    final dropdownItems = routeStops.map((s) {
      final label = s.order != null
          ? 'Stop ${s.order} — ${s.location.latitude.toStringAsFixed(4)}, ${s.location.longitude.toStringAsFixed(4)}'
          : '${s.location.latitude.toStringAsFixed(4)}, ${s.location.longitude.toStringAsFixed(4)}';
      return DropdownMenuItem<String>(
        value: s.id,
        child: Text(label),
      );
    }).toList();

    final hasValidStopSelection = _selectedStopId != null && routeStops.any((s) => s.id == _selectedStopId);
    final safeSelectedStopId = hasValidStopSelection ? _selectedStopId : null;
    // If the selected stop is no longer available (e.g., after a route refresh), clear it.
    if (!hasValidStopSelection && _selectedStopId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedStopId = null;
          _selectedStartLocation = null;
          _selectedStartLatLng = null;
        });
      });
    }

    // Resolve currently selected stop id into a label as needed for the UI.
    return DropdownButtonFormField<String>(
      key: ValueKey('start-stop-dropdown-${_selectedRoute?.id ?? 'none'}-${routeStops.length}-${safeSelectedStopId ?? 'none'}'),
      value: safeSelectedStopId,
      onChanged: (newStopId) async {
        if (newStopId == null) return;
        final chosen = routeStops.firstWhere((s) => s.id == newStopId, orElse: () => routeStops.first);
        setState(() {
          _selectedStopId = chosen.id;
          _selectedStartLocation = chosen.order != null
              ? 'Stop ${chosen.order}'
              : '${chosen.location.latitude.toStringAsFixed(5)}, ${chosen.location.longitude.toStringAsFixed(5)}';
          _selectedStartLatLng = fm.LatLng(chosen.location.latitude, chosen.location.longitude);
          _errorMessage = null;
        });
        try {
          _mapController.move(_selectedStartLatLng!, 15.0);
        } catch (_) {}
      },
      items: dropdownItems,
      hint: const Text('Select Your Starting Location'),
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF1F2327),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1F2327),
        prefixIcon: const Icon(Icons.pin_drop_outlined, color: Colors.white70),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
        ),
      ),
      validator: (value) => value == null ? 'Starting location is required' : null,
    );
  }

  Widget _buildStartTimePicker() {
    final times = List<TimeOfDay>.generate(96, (i) {
      final hour = i ~/ 4;
      final minute = (i % 4) * 15;
      return TimeOfDay(hour: hour, minute: minute);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () async {
            setState(() => _isTimeListExpanded = !_isTimeListExpanded);
          },
          child: AbsorbPointer(
            child: TextFormField(
              // Use a controller to display the formatted time
              controller: TextEditingController(text: _selectedStartTime?.format(context) ?? ''),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Select Start Time',
                labelStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.access_time_outlined, color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF1F2327),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
                ),
              ),
              validator: (value) => _selectedStartTime == null ? 'Start time is required' : null,
            ),
          ),
        ),
        if (_isTimeListExpanded)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2327),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2ED8C3).withOpacity(0.4)),
            ),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: times.length,
              itemBuilder: (_, idx) {
                final t = times[idx];
                final isSelected = _selectedStartTime != null &&
                    _selectedStartTime!.hour == t.hour &&
                    _selectedStartTime!.minute == t.minute;
                return ListTile(
                  title: Text(t.format(context), style: const TextStyle(color: Colors.white)),
                  trailing: isSelected ? const Icon(Icons.check, color: Color(0xFF2ED8C3)) : null,
                  onTap: () {
                    setState(() {
                      _selectedStartTime = t;
                      _isTimeListExpanded = false;
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildFileUpload(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        // TODO: Implement file picking logic
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File upload functionality not yet implemented.')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2327),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white70)),
            ),
            const Icon(Icons.upload_file_outlined, color: Color(0xFF2ED8C3)),
          ],
        ),
      ),
    );
  }
}

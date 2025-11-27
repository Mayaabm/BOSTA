import 'dart:async';
import 'dart:convert';
import 'package:bosta_frontend/models/app_route.dart';
import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as fm;

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
  final bool _forceShowMap = false; // debug toggle to force map rendering
  TimeOfDay? _selectedStartTime;
  // Polling state removed from onboarding — tracking handled on Driver map screen

  bool _isLoading = false;
  bool _isFetchingRoutes = true;
  String? _errorMessage;
  bool _isProfileSaved = false; // To control button visibility

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
      _errorMessage = null;
    });
    final stopwatch = Stopwatch()..start();
    debugPrint("[Onboarding] _fetchRouteDetails: Fetching details for routeId: $routeId...");
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.currentState.token;
      if (token == null) {
        setState(() {
          _errorMessage = 'Authentication error: No token found. Please log in again.';
          _isLoading = false;
        });
        return;
      }
      final uri = Uri.parse('${ApiEndpoints.routes}$routeId/'); // e.g., /api/routes/route-1/
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      debugPrint("[Onboarding] _fetchRouteDetails: Request took ${stopwatch.elapsedMilliseconds}ms. Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _selectedRoute = AppRoute.fromJson(json.decode(response.body) as Map<String, dynamic>);
          });
          debugPrint("[Onboarding] _fetchRouteDetails: Successfully parsed route '${_selectedRoute?.name}'.");
        }
      } else {
        debugPrint("[Onboarding] _fetchRouteDetails: Failed with status ${response.statusCode}. Body: ${response.body}");
        throw Exception('Failed to load route details');
      }
    } catch (e) {
      debugPrint("[Onboarding] _fetchRouteDetails: Exception after ${stopwatch.elapsedMilliseconds}ms. Error: $e");
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not load details for the selected route.';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _centerMapOnRoute() async {
    if (_selectedRoute == null || _selectedRoute!.geometry.isEmpty) return;
    if (mounted) {
      try {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: _selectedRoute!.geometry,
            padding: const EdgeInsets.all(50),
          ),
        );
      } catch (e) {
        debugPrint("Could not center map, it might not be ready yet. Error: $e");
      }
    }
  }

  double _distanceToRouteMeters(fm.LatLng point) {
    // Compute minimum distance from point to any segment of the route polyline
    if (_selectedRoute == null || _selectedRoute!.geometry.isEmpty) return double.infinity;
    double minMeters = double.infinity;

    final coords = _selectedRoute!.geometry;
    for (int i = 0; i < coords.length - 1; i++) {
      final p1 = coords[i];
      final p2 = coords[i + 1];
      final dist = _pointToSegmentDistance(point, p1, p2);
      if (dist < minMeters) {
        minMeters = dist;
      }
    }
    return minMeters;
  }

  // Helper for point-to-line-segment distance calculation.
  double _pointToSegmentDistance(fm.LatLng p, fm.LatLng a, fm.LatLng b) {
    final double l2 = const fm.Distance().distance(a, b);
    if (l2 == 0.0) return const fm.Distance().as(fm.LengthUnit.Meter, p, a);

    // Project p onto the line defined by a, b
    final double t = ((p.latitude - a.latitude) * (b.latitude - a.latitude) + (p.longitude - a.longitude) * (b.longitude - a.longitude)) / l2;
    final double tClamped = t.clamp(0.0, 1.0);

    // Find the closest point on the segment
    final closestPoint = fm.LatLng(
      a.latitude + tClamped * (b.latitude - a.latitude),
      a.longitude + tClamped * (b.longitude - a.longitude),
    );

    // Return the distance from p to that closest point
    return const fm.Distance().as(fm.LengthUnit.Meter, p, closestPoint);
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

    final isFormValid = _formKey.currentState?.validate() ?? false;
    debugPrint("[Onboarding] _submitForm: Form validation state: isFormValid = $isFormValid");

    if (!isFormValid) {
      debugPrint("[Onboarding] _submitForm: Aborting submission because form is invalid.");
      return;
    }

    // Additional validation for non-form fields before proceeding.
    // A start location is valid if either a stop is chosen OR a point is tapped on the map.
    final bool isLocationSelected = _selectedStopId != null || _selectedStartLatLng != null;

    debugPrint("[Onboarding] _submitForm: --- Checking additional fields ---");
    debugPrint("[Onboarding] _submitForm: _selectedRouteId = $_selectedRouteId");
    debugPrint("[Onboarding] _submitForm: _selectedStopId = $_selectedStopId");
    debugPrint("[Onboarding] _submitForm: _selectedStartLatLng = $_selectedStartLatLng");
    debugPrint("[Onboarding] _submitForm: _selectedStartTime = ${_selectedStartTime?.format(context)}");
    debugPrint("[Onboarding] _submitForm: isLocationSelected = $isLocationSelected");

    // The route is considered selected if either its ID is present or the full route object has been loaded.
    final bool isRouteSelected = _selectedRouteId != null || _selectedRoute != null;
    if (!isRouteSelected || !isLocationSelected || _selectedStartTime == null) {
      setState(() {
        _errorMessage = 'Please complete all fields, including route, start location, and start time.';
        // This is a good place to trigger autovalidation to highlight missing fields.
        _formKey.currentState?.validate();
      });
      return;
    }

    // Safely capture the required values after validation.
    // Use the ID from the full route object if available, as _selectedRouteId can become null during rebuilds.
    final routeId = _selectedRoute?.id.toString() ?? _selectedRouteId;
    if (routeId == null) return; // Should not happen due to validation, but as a final safeguard.
    final busCapacityText = _busCapacityController.text;

    String? isoStart;
    if (_selectedStartTime != null) {
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, _selectedStartTime!.hour, _selectedStartTime!.minute);
      isoStart = dt.toIso8601String();
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    debugPrint("[Onboarding] Submitting profile with:");
    debugPrint("  > routeId: $routeId");
    debugPrint("  > startStopId: $_selectedStopId");
    debugPrint("  > startLat: ${_selectedStartLatLng?.latitude}, startLon: ${_selectedStartLatLng?.longitude}");

    final authService = Provider.of<AuthService>(context, listen: false);
    // Pass the selected stop ID and time to be stored in the auth state.
    final error = await authService.setupDriverProfile(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      phoneNumber: _phoneController.text,
      busPlateNumber: _busPlateController.text.toUpperCase(),
      busCapacity: int.parse(busCapacityText),
      routeId: routeId, // Now guaranteed to be non-null
      startStopId: _selectedStopId,
      startTime: isoStart,
      startLat: _selectedStartLatLng?.latitude,
      startLon: _selectedStartLatLng?.longitude,
      refreshToken: authService.currentState.refreshToken, // use refresh token if available
    );

    if (mounted) {
      if (error != null) {
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
      } else {
        // Success: stop loading and show the 'Start' button.
        setState(() {
          _isLoading = false;
          _errorMessage = null;
          _isProfileSaved = true;
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
                _buildTextField(_busCapacityController, 'Bus Capacity (e.g., 14)', Icons.group_outlined, keyboardType: TextInputType.number, isEnabled: !_isFetchingRoutes),
                _buildSectionHeader('Route & Documents'),
                // Add the route selection and dependent fields here.
                _buildRouteDropdown(),
                // Conditionally display start location and time pickers once a route is selected
                // AND its details have been successfully fetched.
                if (_selectedRoute != null) ..._buildDynamicRouteFields()
                else if (_isLoading && _selectedRouteId != null) const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Loading route details...", style: TextStyle(color: Colors.white70)))),
                const SizedBox(height: 40),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 14), textAlign: TextAlign.center),
                  ),
                if (_isLoading || _isFetchingRoutes)
                  const Center(child: CircularProgressIndicator(color: Color(0xFF2ED8C3)))
                else if (_isProfileSaved)
                  ElevatedButton(
                    onPressed: () {
                      debugPrint("--- 'Done' button pressed on Onboarding screen ---");
                      // After setup is complete, navigate back to the home screen.
                      GoRouter.of(context).go('/driver/home');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2ED8C3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Done', style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                  )
                else
                  ElevatedButton(
                    onPressed: _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2ED8C3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Save and Continue', style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
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
    debugPrint("[Onboarding] _buildDynamicRouteFields: Rebuilding dynamic fields...");
    debugPrint("[Onboarding] _buildDynamicRouteFields: _selectedRouteId = $_selectedRouteId");
    debugPrint("[Onboarding] _buildDynamicRouteFields: _selectedRoute is ${ _selectedRoute == null ? 'null' : 'NOT null (name: ${_selectedRoute!.name})'}");
    debugPrint("[Onboarding] _buildDynamicRouteFields: _selectedRoute geometry has ${_selectedRoute?.geometry.length ?? 0} points.");

    final bool isRouteSelected = _selectedRouteId != null || _selectedRoute != null;
    // If we have a selected route with geometry, show a small map picker
    final hasGeometry = _selectedRoute != null && _selectedRoute!.geometry.isNotEmpty;
    final hasStops = _selectedRoute != null && _selectedRoute!.stops.isNotEmpty;
    final showMap = hasGeometry || _forceShowMap;

    if (isRouteSelected) debugPrint("[Onboarding] _buildDynamicRouteFields: showMap = $showMap (hasGeometry: $hasGeometry, hasStops: $hasStops)");

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
                  : const fm.LatLng(33.89365, 35.55166),
              onMapReady: _centerMapOnRoute,
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
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: () {
                              _selectStop(s);
                            },
                            icon: Icon(Icons.location_on,
                                color: _selectedStopId == s.id ? Colors.red : Colors.blueAccent.withOpacity(0.95),
                                size: _selectedStopId == s.id ? 36 : 28),
                          ),
                      )),
                if (_selectedStartLatLng != null && _selectedStopId == null)
                  Marker(
                    width: 36,
                    height: 36,
                    point: _selectedStartLatLng!,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 36),
                  ),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // If the route has stops, show the dropdown below the map so the
        // driver can either tap a marker or pick from the list.
        if (isRouteSelected) ...[
          _buildStartLocationDropdown(isEnabled: hasStops),
          const SizedBox(height: 12),
        ],
      ] else ...[
        _buildStartLocationDropdown(isEnabled: isRouteSelected && hasStops),
        const SizedBox(height: 12),
      ],

      const SizedBox(height: 20),
      _buildStartTimePicker(isEnabled: isRouteSelected),
    ];
  }

  void _selectStop(RouteStop stop) {
    debugPrint("[Onboarding] _selectStop called for stop ID: ${stop.id}");
    debugPrint("  > Location: Lat ${stop.location.latitude}, Lon ${stop.location.longitude}");

    setState(() {
      _selectedStopId = stop.id;
      _selectedStartLocation = stop.order != null
          ? 'Stop ${stop.order}'
          : '${stop.location.latitude.toStringAsFixed(5)}, ${stop.location.longitude.toStringAsFixed(5)}';
      _selectedStartLatLng = fm.LatLng(stop.location.latitude, stop.location.longitude);
      _errorMessage = null;
    });
    try {
      _mapController.move(_selectedStartLatLng!, 15.0);
    } catch (_) {}
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType, bool isEnabled = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: isEnabled,
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
        if (label.contains('Capacity') && (int.tryParse(value) == null || int.parse(value) <= 0)) {
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
            const Text(
              'If you see "Please complete all fields..." but do not see route, start location or start time fields, tap Refresh to try loading available routes. If the problem persists, contact support.',
              style: TextStyle(color: Colors.white70),
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

    final currentRouteIds = _availableRoutes.map((r) => r.id).toSet();
    final hasValidRouteSelection = _selectedRouteId != null && currentRouteIds.contains(int.tryParse(_selectedRouteId!) ?? -1);
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

    return DropdownButtonFormField<String>(
      value: safeSelectedRouteId,
      onChanged: (newRouteId) async {
        if (newRouteId == null) return;
        setState(() {
          _selectedRouteId = newRouteId;
          _selectedRoute = null; // Clear details of previous route
          _selectedStopId = null;
          _selectedStartLocation = null;
          debugPrint("[Onboarding] Route changed to $newRouteId. Clearing dependent state and fetching details.");
        });
        await _fetchRouteDetails(newRouteId);
      },
      items: _availableRoutes.map((route) {
        return DropdownMenuItem<String>(
          value: route.id.toString(),
          child: Text(route.name),
        );
      }).toList(),
      hint: const Text('Select Your Operating Route'),
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF1F2327),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1F2327),
        prefixIcon: const Icon(Icons.route_outlined, color: Colors.white70),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
        ),
      ),
      validator: (value) => value == null ? 'Route selection is required' : null,
    );
  }

  Widget _buildStartLocationDropdown({bool isEnabled = true}) {
    // Use stops provided by the selected route when available.
    final routeStops = _selectedRoute?.stops ?? [];

    if (isEnabled && routeStops.isEmpty) {
      return const Text(
        'This route has no defined stops. Please pick a start point on the map.',
        style: TextStyle(color: Colors.amber),
        textAlign: TextAlign.center,
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
      onChanged: !isEnabled ? null : (newStopId) async {
        if (newStopId == null) return;
        final chosenStop = routeStops.firstWhere((s) => s.id == newStopId);
        _selectStop(chosenStop);
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

  Widget _buildStartTimePicker({bool isEnabled = true}) {
    final times = List<TimeOfDay>.generate(96, (i) {
      final hour = i ~/ 4;
      final minute = (i % 4) * 15;
      return TimeOfDay(hour: hour, minute: minute);
    });

    return DropdownButtonFormField<TimeOfDay>(
      value: _selectedStartTime,
      onChanged: !isEnabled ? null : (newTime) {
        if (newTime != null) {
          setState(() => _selectedStartTime = newTime);
        }
      },
      items: times.map((time) {
        return DropdownMenuItem<TimeOfDay>(
          value: time,
          child: Text(time.format(context)),
        );
      }).toList(),
      hint: const Text('Select Start Time'),
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF1F2327),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1F2327),
        prefixIcon: const Icon(Icons.access_time_outlined, color: Colors.white70),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
        ),
      ),
      validator: (value) => value == null ? 'Start time is required' : null,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bosta_frontend/models/app_route.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/trip_service.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as fm;

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  String? _activeTripId;

  Future<void> _startNewTrip() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final authState = authService.currentState;
    final token = authState.token;
    final onboardingComplete = authService.onboardingComplete; // Get onboarding status
    
    debugPrint("\n=== START NEW TRIP DEBUG ===");
    debugPrint("[_startNewTrip] Token: ${token?.substring(0, 20)}...");
    debugPrint("[_startNewTrip] Auth state authenticated: ${authState.isAuthenticated}");
    
    // The trip is created during onboarding. We need its ID to start it.
    // The backend sends 'active_trip_id' at the top level of the profile response.
    // We need to access it from the raw data stored in the auth service.
    final rawProfileData = authService.rawDriverProfile;    
    // --- THE FIX ---
    // The 'active_trip_id' is only present if the trip is already "in_progress".
    // When a trip is first created via setup, its ID is captured in `lastCreatedTripId`.
    // We must prioritize that ID, then fall back to the one from the raw profile.
    final tripIdToStart = authService.lastCreatedTripId ?? rawProfileData?['active_trip_id']?.toString();

    debugPrint("[_startNewTrip] Trip ID to start: $tripIdToStart");
    debugPrint("[_startNewTrip] Trip ID type: ${tripIdToStart.runtimeType}");
    
    if (token == null || tripIdToStart == null) {
      debugPrint("[_startNewTrip] ERROR: Token is null: ${token == null}, TripID is null: ${tripIdToStart == null}");
      setState(() {
        _errorMessage = "Cannot start trip. No active trip found. Please complete your setup.";
        _isLoading = false;
      });
      debugPrint("=== START NEW TRIP DEBUG (FAILED) ===");
      return;
    }

    // Block "Start Trip" if onboarding is not complete
    if (!onboardingComplete) {
      setState(() {
        _errorMessage = "Please complete your profile setup before starting a trip.";
        _isLoading = false;
      });
      debugPrint("=== START NEW TRIP DEBUG (FAILED - Onboarding Incomplete) ===");
      return;
    }

    try {
      debugPrint("[_startNewTrip] Calling TripService.startNewTrip with tripId: $tripIdToStart");
      // Call the service to start the existing trip on the backend.
      final newTripId = await TripService().startNewTrip(
        token,
        tripId: tripIdToStart, // Pass the correct tripId.
      );

      debugPrint("[_startNewTrip] Success! New trip ID: $newTripId");
      // After creating the trip, update the local state and navigate
      setState(() {
        _activeTripId = newTripId;
        _isLoading = false;
      });
      debugPrint("=== START NEW TRIP DEBUG (SUCCESS) ===");
      // FIX: Directly navigate to the dashboard instead of calling _resumeTrip,
      // which was causing an infinite loop.
      debugPrint("[_startNewTrip] Navigating to dashboard to start/resume trip $newTripId.");
      GoRouter.of(context).go('/driver/dashboard');
    } catch (e) {
      debugPrint("[_startNewTrip] Exception caught: $e");
      debugPrint("[_startNewTrip] Exception type: ${e.runtimeType}");
      debugPrint("[_startNewTrip] Stack trace: ${StackTrace.current}");
      setState(() {
        // Log the full error for debugging, but show a user-friendly message.
        debugPrint("Error starting new trip: $e");
        _errorMessage = "Failed to start new trip. Error: $e";
        _isLoading = false;
      });
      debugPrint("=== START NEW TRIP DEBUG (FAILED WITH EXCEPTION) ===");
    }
  }

  Future<void> _showChangeRouteDialog() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    // Show a loading indicator while fetching routes
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final routes = await authService.fetchAllRoutes();
    Navigator.of(context).pop(); // Dismiss loading indicator

    if (!mounted) return;

    if (routes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not load routes. Please try again later.")),
      );
      return;
    }

    final selectedRoute = await showDialog<AppRoute>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2327),
          title: Text('Select a Route', style: GoogleFonts.urbanist(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: routes.length,
              itemBuilder: (context, index) {
                final route = routes[index];
                return ListTile(
                  title: Text(route.name, style: GoogleFonts.urbanist(color: Colors.white)),
                  onTap: () => Navigator.of(context).pop(route),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selectedRoute != null) {
      // The backend needs a way to associate the driver with the new route.
      // We'll use patchDriverProfile for this.
      setState(() => _isLoading = true);
      await authService.patchDriverProfile({'route_id': selectedRoute.id});
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Compute ETA using the stored driver profile selections (start -> end).
  /// Returns a formatted string like '1h 12m', '45 min', or '<1 min'.
  String? _etaFromProfile({double avgSpeedMps = 10.0}) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final state = authService.currentState;
    final route = state.assignedRoute;   
    if (route == null) return null;

    // Resolve start
    fm.LatLng? startPoint;
    if (state.selectedStopId != null) {
      final matches = route.stops.where((s) => s.id == state.selectedStopId).toList();
      if (matches.isNotEmpty) {
        final s = matches.first;
        startPoint = fm.LatLng(s.location.latitude, s.location.longitude);
      }
    }
    if (startPoint == null && state.selectedStartLat != null && state.selectedStartLon != null) {
      startPoint = fm.LatLng(state.selectedStartLat!, state.selectedStartLon!);
    }

    // Resolve end
    fm.LatLng? endPoint;
    if (state.selectedEndStopId != null) {
      final matches = route.stops.where((s) => s.id == state.selectedEndStopId).toList();
      if (matches.isNotEmpty) {
        final e = matches.first;
        endPoint = fm.LatLng(e.location.latitude, e.location.longitude);
      }
    }

    if (startPoint == null || endPoint == null) return null;

    final distMeters = const fm.Distance().as(fm.LengthUnit.Meter, startPoint, endPoint);
    if (distMeters <= 10) return '<1 min';

    final etaSeconds = distMeters / avgSpeedMps;
    int totalMinutes = (etaSeconds / 60).round();
    if (totalMinutes < 1) return '<1 min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final authState = authService.currentState;
    final driverInfo = authState.driverInfo;
    final assignedRoute = authState.assignedRoute;
    final driverName = driverInfo?.firstName ?? 'Driver';

    // Check for an active trip using the raw profile data from the backend
    final bool hasActiveTrip = authService.rawDriverProfile?['active_trip_id'] != null;

    // Log the raw profile on every build to check the active_trip_id status
    debugPrint("[DriverHomeScreen] build(): Checking raw profile. active_trip_id is: ${authService.rawDriverProfile?['active_trip_id']}");

    // Format the start time for display
    String formattedStartTime = 'Not set';
    if (authState.selectedStartTime != null) {
      try {
        final dateTime = DateTime.parse(authState.selectedStartTime!);
        formattedStartTime = DateFormat.jm().format(dateTime); // e.g., 5:30 PM
      } catch (e) {
        // Handle potential parsing error
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF12161A),
      appBar: AppBar(
        title: Text('Driver Home', style: GoogleFonts.urbanist(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1F2327),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Edit Profile',
            onPressed: () => GoRouter.of(context).go('/driver/onboarding?edit=true'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.logout();
              // The router's redirect will handle navigation to the auth screen.
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Welcome Header
                  Text(
                    'Welcome, $driverName!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasActiveTrip ? 'You have an ongoing trip.' : 'Ready to start your next trip?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 40),

                  // Trip Information Card
                  Card(
                    color: const Color(0xFF1F2327),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasActiveTrip ? 'Active Trip' : 'Next Trip Details',
                            style: GoogleFonts.urbanist(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const Divider(color: Colors.grey, height: 20),
                          _buildInfoRow(
                            Icons.route_outlined,
                            'Route',
                            assignedRoute?.name ?? 'Not Assigned',
                            trailing: TextButton(onPressed: _showChangeRouteDialog, child: const Text('Change')),
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.schedule_outlined, 'Scheduled Start', formattedStartTime),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.pin_drop_outlined, 'Starting Point', authState.selectedStopId != null ? 'Stop #${authState.selectedStopId}' : 'Not Set'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Error Message
                  if (_errorMessage != null) ...[
                    Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],

                  // Action Button
                  ElevatedButton.icon(
                    icon: Icon(hasActiveTrip ? Icons.map_outlined : Icons.play_arrow_rounded, color: Colors.black),
                    label: Text(
                      hasActiveTrip ? 'View Dashboard' : 'Start Trip',
                      style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    onPressed: _startNewTrip,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2ED8C3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
  Widget _buildInfoRow(IconData icon, String label, String value, {Widget? trailing}) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2ED8C3), size: 20),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[400]),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: GoogleFonts.urbanist(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    );
  }
}

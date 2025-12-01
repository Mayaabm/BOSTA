import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/trip_service.dart';
import 'package:latlong2/latlong.dart' as fm;

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  String? _activeTripId; // To hold the active trip ID if one exists

  @override
  void initState() {
    super.initState();
    // When the screen loads, check for an active trip.
    _checkForActiveTrip();
  }

  Future<void> _checkForActiveTrip() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.currentState.token;

    if (token == null) {
      setState(() {
        _errorMessage = "Authentication error. Please log in again.";
        _isLoading = false;
      });
      return;
    }

    try {
      // This is a new service method we'll need to create.
      final tripId = await TripService.checkForActiveTrip(token);
      if (mounted) {
        setState(() {
          _activeTripId = tripId;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to check for active trip: $e";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startNewTrip() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final authState = authService.currentState;
    final token = authState.token;
    
    debugPrint("\n=== START NEW TRIP DEBUG ===");
    debugPrint("[_startNewTrip] Token: ${token?.substring(0, 20)}...");
    debugPrint("[_startNewTrip] Auth state authenticated: ${authState.isAuthenticated}");
    
    // The trip is created during onboarding. We need its ID to start it.
    // The backend sends 'active_trip_id' at the top level of the profile response.
    // We need to access it from the raw data stored in the auth service.
    final rawProfileData = authService.rawDriverProfile;
    debugPrint("[_startNewTrip] Raw profile data: $rawProfileData");
    debugPrint("[_startNewTrip] Raw profile keys: ${rawProfileData?.keys.toList()}");
    
    final tripIdToStart = rawProfileData?['active_trip_id']?.toString();
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

  void _resumeTrip() {
    // If resuming, we now ensure the trip is started on the backend first,
    // then navigate. The logic for starting is now consolidated in _startNewTrip.
    // If the trip is already started, the service will handle it gracefully.
    // We now call _startNewTrip which will handle the navigation on success.
    // This is the correct fix from the previous step.
    _startNewTrip(); 
  }

  void _changeSetup() {
    // Navigate to the onboarding screen, which will now serve as the "edit setup" screen.
    debugPrint("Navigating to onboarding to change setup.");
    GoRouter.of(context).go('/driver/onboarding');
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
    final driverName = authService.currentState.driverInfo?.firstName ?? 'Driver';
    final etaString = _etaFromProfile();

    return Scaffold(
      backgroundColor: const Color(0xFF12161A),
      appBar: AppBar(
        title: Text('Welcome, $driverName'),
        backgroundColor: const Color(0xFF1F2327),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Server Settings',
            onPressed: () {
              GoRouter.of(context).push('/settings/server');
            },
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
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_errorMessage != null) ...[
                        Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                      ],
                      if (_activeTripId != null)
                        _buildActionButton(
                          title: 'Resume Active Trip',
                          icon: Icons.play_arrow_rounded,
                          onPressed: _resumeTrip,
                          isPrimary: true,
                        )
                      else
                        _buildActionButton(
                          title: 'Start New Trip',
                          icon: Icons.play_circle_fill_rounded,
                          onPressed: _startNewTrip,
                          isPrimary: true,
                        ),
                      const SizedBox(height: 20),
                      _buildActionButton(
                        title: 'Change Setup',
                        icon: Icons.edit_location_alt_rounded,
                        onPressed: _changeSetup,
                      ),
                      const SizedBox(height: 12),
                      if (etaString != null)
                        Text('Estimated trip time: $etaString', style: GoogleFonts.urbanist(color: Colors.white70), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildActionButton({required String title, required IconData icon, required VoidCallback onPressed, bool isPrimary = false}) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 24),
      label: Text(title, style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold)),
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? const Color(0xFF2ED8C3) : const Color(0xFF1F2327),
        foregroundColor: isPrimary ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

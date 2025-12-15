import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bosta_frontend/models/app_route.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/trip_service.dart';
import '../services/logger.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  // Local state to manage dropdown changes and prevent unnecessary rebuilds
  String? _selectedStartStopId;
  String? _selectedEndStopId;
  bool _isSavingTripSetup = false;

  Future<void> _startNewTrip() async {
    Logger.debug('DriverHomeScreen', "STARTING 'startNewTrip' PROCESS");
    Logger.debug('DriverHomeScreen', 'BUTTON PRESSED: Start Trip');
    Logger.debug('DriverHomeScreen', 'Current mounted: $mounted');
    Logger.debug('DriverHomeScreen', 'SelectedStartStopId: $_selectedStartStopId');
    Logger.debug('DriverHomeScreen', 'SelectedEndStopId: $_selectedEndStopId');
    // If a trip is already active, just navigate to the dashboard.
    final authService = Provider.of<AuthService>(context, listen: false);
    final activeTripIdFromState = authService.rawDriverProfile?['active_trip_id']?.toString();
    if (activeTripIdFromState != null && mounted) {
      // --- FIX: If a trip is already active, navigate to its dashboard correctly. ---
      // The previous logic was missing the trip ID in the navigation path.
      Logger.info('DriverHomeScreen', "Active trip '$activeTripIdFromState' detected. Navigating directly to dashboard.");
      GoRouter.of(context).go('/driver/dashboard/$activeTripIdFromState'); // This is the correct navigation
      return;
    }

    setState(() => _isLoading = true);
    final authState = authService.currentState;
    final token = authState.token;
    // --- FIX: Validate based on essential data, not just the onboarding flag ---
    // The key requirements to start a trip are having a bus and an assigned route.
    final bool canStartTrip = authState.driverInfo?.busId != null && authState.assignedRoute?.id != null;

    Logger.debug('DriverHomeScreen', 'PRE-FLIGHT CHECKS');
    Logger.debug('DriverHomeScreen', 'Current AuthState: isAuthenticated=${authState.isAuthenticated}, role=${authState.role}');
    Logger.debug('DriverHomeScreen', 'Token available: ${token != null}');
    Logger.debug('DriverHomeScreen', 'Onboarding complete: ${authState.driverInfo?.onboardingComplete}');
    Logger.debug('DriverHomeScreen', "Validation 'canStartTrip': $canStartTrip");
    Logger.debug('DriverHomeScreen', 'selectedStopId: ${authState.selectedStopId}');
    Logger.debug('DriverHomeScreen', 'selectedEndStopId: ${authState.selectedEndStopId}');

    if (token == null) {
      setState(() {
        _errorMessage = "Authentication error. Please log in again.";
        _isLoading = false;
      });
      Logger.error('DriverHomeScreen', 'X FAILED: Token is null. Aborting.');
      return;
    }

    if (!canStartTrip) {
      setState(() {
        _errorMessage = "Please complete your profile setup before starting a trip.";
        _isLoading = false;
      });
      Logger.error('DriverHomeScreen', "X FAILED: 'canStartTrip' is false. Aborting.");
      return;
    }

    // If onboarding isn't complete, guide the user to the edit screen first.
    if (authState.driverInfo?.onboardingComplete == false) {
      setState(() {
        // --- FIX: Do not navigate away. Show an error and stop. ---
        // The previous logic caused a navigation conflict and a disposed context error.
        // The user can use the existing "Edit Profile" button in the AppBar.
        _errorMessage = "Your profile is incomplete. Please use the 'Edit Profile' button to provide your name, phone, and bus details.";
        _isLoading = false;
      });
      Logger.error('DriverHomeScreen', 'X FAILED: Onboarding is not complete. Aborting trip start.');
      return;
    }

    // --- VALIDATION ---
    // Ensure both start and end stops are selected before starting.
    if (authState.selectedStopId == null || authState.selectedEndStopId == null) {
      setState(() {
        _errorMessage = "Please select both a start and end stop for your trip.";
        _isLoading = false;
      });
      Logger.error('DriverHomeScreen', 'X FAILED: Start or End stop not selected. Aborting.');
      return;
    }

    try {
      Logger.debug('DriverHomeScreen', 'CALLING SERVICE: All checks passed. Calling TripService.startNewTrip...');
      // --- FIX: The service now returns the created trip ID directly. ---
      final newTripId = await TripService.startNewTrip(
        authService,
        startStopId: authState.selectedStopId,
        endStopId: authState.selectedEndStopId,
      );

      Logger.info('DriverHomeScreen', 'SERVICE SUCCEEDED: Created trip with ID: $newTripId');
      Logger.debug('DriverHomeScreen', 'Polling for active_trip_id and route after trip creation');
      int pollCount = 0;
      bool tripReady = false;
      // Wait a bit longer for backend to update assigned route/active_trip
      while (pollCount < 20 && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        await authService.fetchAndSetDriverProfile();
        final raw = authService.rawDriverProfile;
        final activeTripId = raw?['active_trip_id']?.toString();
        final route = raw?['route'];
        Logger.debug('DriverHomeScreen', 'Poll $pollCount: active_trip_id=$activeTripId, route=${route != null ? 'present' : 'null'}');
        if (activeTripId == newTripId && route != null) {
          tripReady = true;
          break;
        }
        pollCount++;
      }
      // Ensure we have the latest profile before navigating
      await authService.fetchAndSetDriverProfile();
      if (!tripReady) {
        Logger.debug('DriverHomeScreen', 'Timed out waiting for trip to be ready. Proceeding anyway.');
      }
      Logger.info('DriverHomeScreen', 'Navigating to /driver/dashboard/$newTripId');
      final destinationUrl = '/driver/dashboard/$newTripId';
      Logger.debug('DriverHomeScreen', 'NAVIGATING: Preparing to navigate to: $destinationUrl');
      if (!mounted) return; // Guard against disposed context
      GoRouter.of(context).go('/driver/dashboard/$newTripId');
    } catch (e) {
      Logger.error('DriverHomeScreen', "CATASTROPHIC FAILURE: The 'startNewTrip' process threw an exception. $e");
      _errorMessage = "Could not start trip. Please try again. Error: $e";
      setState(() {
        _isLoading = false;
      });
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
      setState(() => _isLoading = true);
      Logger.info('DriverHomeScreen', 'Attempting to update route to: ${selectedRoute.id}');
      final patchError = await authService.patchDriverProfile({'route_id': selectedRoute.id});
      if (patchError != null) {
        Logger.error('DriverHomeScreen', 'patchDriverProfile error: $patchError');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Backend error: $patchError")),
        );
        setState(() => _isLoading = false);
        return;
      }
      // Print the verbose debug blob created by AuthService for inspection
      try {
        Logger.debug('DriverHomeScreen', 'patch debug:\n${authService.lastPatchDebug}');
      } catch (e) {
        Logger.error('DriverHomeScreen', 'Could not fetch lastPatchDebug: $e');
      }
      // Optimistically update the local assigned route so the UI (and dashboard)
      // shows the newly-selected route immediately while the backend finishes.
      bool optimisticApplied = false;
      try {
        authService.setAssignedRouteLocally(selectedRoute);
        optimisticApplied = true;
        Logger.info('DriverHomeScreen', 'Optimistically set assigned route locally to ${selectedRoute.id}');
      } catch (e) {
        Logger.error('DriverHomeScreen', 'Failed to set assigned route locally: $e');
      }
      int pollCount = 0;
      bool routeReady = false;
      while (pollCount < 20 && mounted) { // Increase retries
        await Future.delayed(const Duration(milliseconds: 500)); // Wait longer
        await authService.fetchAndSetDriverProfile();
        final raw = authService.rawDriverProfile;
        final route = raw?['route'];
        Logger.debug('DriverHomeScreen', 'Poll $pollCount: route=${route != null ? route['id'] : 'null'} (expected: ${selectedRoute.id})');
        if (route != null && route['id'].toString() == selectedRoute.id.toString()) {
          routeReady = true;
          break;
        }
        pollCount++;
      }
      if (!routeReady) {
        if (optimisticApplied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Route change applied locally; awaiting server confirmation.")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to update route to ${selectedRoute.id}. Please try again or check backend logs.")),
          );
        }
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // New method to handle saving the trip setup
  Future<void> _saveTripSetup() async {
    // Only save if there are actual changes to be made.
    if (_selectedStartStopId == null || _selectedEndStopId == null) {
      setState(() => _errorMessage = "Both start and end stops must be selected.");
      return;
    }

    setState(() => _isSavingTripSetup = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    // Log the chosen start/end stop IDs and their coordinates (if available)
    try {
      final assigned = authService.currentState.assignedRoute;
      String startCoords = 'unknown';
      String endCoords = 'unknown';
      String startName = '';
      String endName = '';
      if (assigned != null) {
        try {
          final s = assigned.stops.firstWhere((st) => st.id == _selectedStartStopId);
          startCoords = '${s.location.latitude},${s.location.longitude}';
          startName = s.name;
        } catch (_) {}
        try {
          final e = assigned.stops.firstWhere((st) => st.id == _selectedEndStopId);
          endCoords = '${e.location.latitude},${e.location.longitude}';
          endName = e.name;
        } catch (_) {}
      }
      Logger.info('DriverHomeScreen', 'Saving trip setup -> start=$_selectedStartStopId ($startName) coords=$startCoords ; end=$_selectedEndStopId ($endName) coords=$endCoords');
    } catch (e) {
      Logger.error('DriverHomeScreen', 'Failed to log trip setup details: $e');
    }
    // Use the new, dedicated method for saving trip setup
    final error = await authService.saveTripSetup(
        startStopId: _selectedStartStopId!, endStopId: _selectedEndStopId!);

    if (mounted) {
      setState(() {
        _isSavingTripSetup = false;
        _errorMessage = error != null ? "Failed to save trip setup: $error" : null;
      });
    }

    // Log result
    if (error == null) {
      try {
        final assigned = authService.currentState.assignedRoute;
        String startCoords = 'unknown';
        String endCoords = 'unknown';
        String startName = '';
        String endName = '';
        if (assigned != null) {
          try {
            final s = assigned.stops.firstWhere((st) => st.id == _selectedStartStopId);
            startCoords = '${s.location.latitude},${s.location.longitude}';
            startName = s.name;
          } catch (_) {}
          try {
            final e = assigned.stops.firstWhere((st) => st.id == _selectedEndStopId);
            endCoords = '${e.location.latitude},${e.location.longitude}';
            endName = e.name;
          } catch (_) {}
        }
        Logger.info('DriverHomeScreen', 'Trip setup saved -> start=$_selectedStartStopId ($startName) coords=$startCoords ; end=$_selectedEndStopId ($endName) coords=$endCoords');
      } catch (e) {
        Logger.error('DriverHomeScreen', 'Failed to log saved trip setup details: $e');
      }
    } else {
      Logger.error('DriverHomeScreen', 'saveTripSetup returned error: $error');
    }
  }

  Future<void> _endActiveTrip() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.currentState.token;
    final tripId = authService.rawDriverProfile?['active_trip_id']?.toString();
    if (token == null || tripId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active trip to end.')));
      setState(() => _isLoading = false);
      return;
    }

    try {
      Logger.info('DriverHomeScreen', 'Ending active trip $tripId');
      await TripService.endTrip(token, tripId);
      // Refresh profile so UI reflects the ended trip
      await authService.fetchAndSetDriverProfile();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip ended successfully.')));
    } catch (e) {
      Logger.error('DriverHomeScreen', 'Failed to end trip $tripId: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to end trip: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Clear local dropdown selections on (re)entering this screen so previous
    // trip choices don't persist across logins. Driver should pick fresh stops.
    _selectedStartStopId = null;
    _selectedEndStopId = null;
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context); // Listen to changes
    final authState = authService.currentState;
    final driverInfo = authState.driverInfo;
    final assignedRoute = authState.assignedRoute;
    final driverName = driverInfo?.firstName ?? 'Driver';

    // Check for an active trip using the raw profile data from the backend
    // This is the source of truth for whether a trip is "in_progress".
    final bool hasActiveTrip = authService.rawDriverProfile?['active_trip_id'] != null;

    // Log the raw profile on every build to check the active_trip_id status
    Logger.info('DriverHomeScreen', 'build(): Checking raw profile. active_trip_id is: ${authService.rawDriverProfile?['active_trip_id']}');

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
              final res = await authService.logout();
              if (res != null) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res)));
                return; // Do not navigate away if ending trip failed
              }
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
                          // Start Stop Dropdown
                          _buildStopDropdown(
                            icon: Icons.flag_outlined,
                            label: 'Start Stop',
                            stops: assignedRoute?.stops ?? [],
                            currentValue: _selectedStartStopId,
                            onChanged: (value) {
                              setState(() => _selectedStartStopId = value);
                            },
                          ),
                          const SizedBox(height: 12),
                          // End Stop Dropdown
                          _buildStopDropdown(
                            icon: Icons.tour_outlined,
                            label: 'End Stop',
                            stops: assignedRoute?.stops ?? [],
                            currentValue: _selectedEndStopId,
                            onChanged: (value) {
                              setState(() => _selectedEndStopId = value);
                            },
                          ),
                          const SizedBox(height: 20),
                          // Save Button for Trip Setup
                          if (_isSavingTripSetup)
                            const Center(child: CircularProgressIndicator())
                          else
                            Center(
                              child: ElevatedButton(
                                onPressed: _saveTripSetup,
                                child: const Text('Save Trip Setup'),
                              ),
                            ),
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
                  const SizedBox(height: 12),
                  if (hasActiveTrip)
                    Center(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.stop_circle, color: Colors.white),
                        label: const Text('End Trip', style: TextStyle(color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                        ),
                        onPressed: () async {
                          await _endActiveTrip();
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildStopDropdown({required IconData icon, required String label, required List<RouteStop> stops, required String? currentValue, required ValueChanged<String?> onChanged}) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2ED8C3), size: 20),
        const SizedBox(width: 12),
        Text('$label: ', style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[400])),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentValue,
              isExpanded: true,
              hint: Text('Select Stop', style: GoogleFonts.urbanist(color: Colors.grey[500])),
              dropdownColor: const Color(0xFF2A2F33),
              style: GoogleFonts.urbanist(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              onChanged: onChanged,
              items: stops.map((stop) {
                return DropdownMenuItem<String>(
                  value: stop.id,
                  child: Text(
                    stop.name,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                );
              }).toList(),
              selectedItemBuilder: (context) => stops.map<Widget>((stop) {
                return Align(alignment: Alignment.centerRight, child: Text(stop.name, overflow: TextOverflow.ellipsis));
              }).toList(),
            ),
          ),
        ),
      ],
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

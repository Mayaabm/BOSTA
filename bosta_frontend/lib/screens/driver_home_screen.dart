import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/trip_service.dart';

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

  void _startNewTrip() {
    // The dashboard will now handle the logic of starting the trip
    // based on the saved setup in AuthService.
    debugPrint("Navigating to dashboard to start a new trip.");
    GoRouter.of(context).go('/driver/dashboard');
  }

  void _resumeTrip() {
    // The dashboard will see that a trip is active and resume it.
    debugPrint("Navigating to dashboard to resume trip $_activeTripId.");
    GoRouter.of(context).go('/driver/dashboard');
  }

  void _changeSetup() {
    // Navigate to the onboarding screen, which will now serve as the "edit setup" screen.
    debugPrint("Navigating to onboarding to change setup.");
    GoRouter.of(context).go('/driver/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final driverName = authService.currentState.driverInfo?.firstName ?? 'Driver';

    return Scaffold(
      backgroundColor: const Color(0xFF12161A),
      appBar: AppBar(
        title: Text('Welcome, $driverName'),
        backgroundColor: const Color(0xFF1F2327),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.logout();
              // The router's redirect will handle navigation to the auth screen.
            },
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24.0),
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
                  ],
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


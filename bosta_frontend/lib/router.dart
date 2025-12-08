import 'package:bosta_frontend/screens/driver_dashboard_screen.dart';
import 'package:bosta_frontend/screens/driver_home_screen.dart';
import 'package:bosta_frontend/screens/driver_onboarding_screen.dart';
import 'package:bosta_frontend/screens/rider_home_screen.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Centralized router configuration for the Bosta application.
class AppRouter {
  final AuthService authService;

  AppRouter(this.authService);

  late final GoRouter router = GoRouter(
    initialLocation: '/',
    refreshListenable: authService,
    routes: [
      GoRoute(
        path: '/',
        // The redirect logic below will handle sending the user to the correct
        // screen, so we can just point to a default home screen here. The user
        // will only see it for a fraction of a second.
        builder: (context, state) => const DriverHomeScreen(),
      ),
      GoRoute(
        path: '/driver/home',
        builder: (context, state) => const DriverHomeScreen(),
      ),
      GoRoute(
        path: '/driver/onboarding',
        builder: (context, state) {
          return const DriverOnboardingScreen();
        },
      ),
      // --- FIX: Update the dashboard route to accept a tripId parameter ---
      // The path is changed from '/driver/dashboard' to '/driver/dashboard/:tripId'.
      // The ':tripId' part is a placeholder for the dynamic trip ID.
      GoRoute(
        path: '/driver/dashboard/:tripId',
        builder: (context, state) {
          // We extract the tripId from the URL's path parameters.
          final tripId = state.pathParameters['tripId'];
          // We then pass this ID to the DriverDashboardScreen.
          return DriverDashboardScreen(tripId: tripId);
        },
      ),
      GoRoute(
        path: '/rider/home',
        builder: (context, state) => const RiderHomeScreen(),
      ),
    ],
    redirect: (BuildContext context, GoRouterState state) {
      debugPrint("\n--- [GoRouter Redirect Logic] ---");
      final authState = authService.currentState;
      final isLoggedIn = authState.isAuthenticated;
      final location = state.uri.toString();
      debugPrint("  > Current Location: $location");
      debugPrint("  > Is Logged In: $isLoggedIn");
      debugPrint("  > User Role: ${authState.role}");

      if (!isLoggedIn && location != '/') {
        debugPrint("  > Decision: Not logged in and not at root. Redirecting to '/'.");
        debugPrint("--- [GoRouter Redirect Logic End] ---\n");
        return '/'; // Redirect to login if not authenticated
      }

      if (isLoggedIn && location == '/') {
        if (authState.role == UserRole.driver) {
          debugPrint("  > Decision: Logged in as driver at root. Redirecting to '/driver/home'.");
          debugPrint("--- [GoRouter Redirect Logic End] ---\n");
          return '/driver/home';
        } else if (authState.role == UserRole.rider) {
          debugPrint("  > Decision: Logged in as rider at root. Redirecting to '/rider/home'.");
          debugPrint("--- [GoRouter Redirect Logic End] ---\n");
          return '/rider/home';
        }
      }
      debugPrint("  > Decision: No redirect needed.");
      debugPrint("--- [GoRouter Redirect Logic End] ---\n");
      return null; // No redirect needed
    },
  );
}
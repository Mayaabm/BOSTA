import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth_screen.dart';
import '../screens/register_screen.dart'; // Keep this for the route definition
import 'driver_dashboard.dart' as driver_map; // Import the REAL dashboard with a unique name
import '../screens/driver_onboarding_screen.dart';
import '../screens/rider_home_screen.dart';
import 'auth_service.dart';

class AppRouter {
  late final GoRouter router;

  AppRouter(AuthService authService) {
    router = GoRouter(
      refreshListenable: authService,
      initialLocation: '/auth',
      routes: [
        GoRoute(
          path: '/auth',
          builder: (context, state) => const AuthScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/rider/home',
          builder: (context, state) => const RiderHomeScreen(),
        ),
        GoRoute(
          path: '/driver/dashboard',
          builder: (context, state) {
            // Use the uniquely named import to ensure we get the correct screen
            return const driver_map.DriverDashboardScreen();
          },
        ),
        GoRoute(
          path: '/driver/onboarding',
          builder: (context, state) => const DriverOnboardingScreen(),
        ),
      ],
      redirect: (BuildContext context, GoRouterState state) {
        final authState = authService.currentState;
        final currentLocation = state.matchedLocation;
        final isLoggingIn = currentLocation == '/auth' || currentLocation == '/register';

        // 1. If user is not authenticated:
        if (!authState.isAuthenticated) {
          // Allow them to be on login/register pages, otherwise redirect to login.
          return isLoggingIn ? null : '/auth';
        }

        // 2. If user IS authenticated:
        if (authState.role == UserRole.driver) {
          final driverInfo = authState.driverInfo;
          // Rule 2a: If onboarding is not complete, they MUST be on the onboarding screen.
          if (driverInfo == null || !driverInfo.onboardingComplete) {
            return currentLocation == '/driver/onboarding' ? null : '/driver/onboarding';
          }
          // Rule 2b: If onboarding IS complete and they are on an auth or onboarding page, send them to the dashboard.
          if (isLoggingIn || currentLocation == '/driver/onboarding') {
            return '/driver/dashboard';
          }
        } else if (authState.role == UserRole.rider) {
          // Rule 2c: If they are a rider and on an auth page, send them to their home.
          if (isLoggingIn) return '/rider/home';
        }
        // 3. If none of the above rules apply, no redirect is needed.
        return null;
      },
    );
  }
}

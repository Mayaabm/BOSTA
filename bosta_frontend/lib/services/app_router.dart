import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth_screen.dart';
import '../screens/driver_home_screen.dart'; // Corrected import path
import '../screens/register_screen.dart';
import '../screens/driver_dashboard_screen.dart'; // Corrected import path
import '../screens/driver_onboarding_screen.dart';
import '../screens/rider_home_screen.dart';
import '../screens/server_config_screen.dart';
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
          path: '/driver/home',
          builder: (context, state) => const DriverHomeScreen(), // This should now resolve correctly
        ),
        GoRoute(
          path: '/driver/dashboard',
          builder: (context, state) {
            return const DriverDashboardScreen(); // The const is valid for the correct screen
          },
        ),
        GoRoute(
          path: '/driver/onboarding',
          builder: (context, state) => const DriverOnboardingScreen(),
        ),
        GoRoute(
          path: '/settings/server',
          builder: (context, state) => ServerConfigScreen(
            onConfigSaved: () {
              // Refresh or notify the app that config was changed
            },
          ),
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
          // If the driver is authenticated and is on a login/register page,
          // always redirect them to their home screen, regardless of onboarding status.
          if (isLoggingIn) {
            return '/driver/home'; // Always go to home after login.
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

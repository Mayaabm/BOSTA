import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth_screen.dart';
import 'driver_dashboard.dart';
import 'package:provider/provider.dart';
import '../screens/rider_home_screen.dart';
import 'auth_service.dart';

class AppRouter {
  late final GoRouter router;

  AppRouter(AuthService authService) {
    router = GoRouter(
      refreshListenable: authService,
      initialLocation: '/rider/home',
      routes: [
        GoRoute(
          path: '/auth',
          builder: (context, state) => const AuthScreen(),
        ),
        GoRoute(
          path: '/rider/home',
          builder: (context, state) => const RiderHomeScreen(),
        ),
        GoRoute(
          path: '/driver/dashboard',
          builder: (context, state) {
            // Pass the driver info from the auth state to the dashboard screen.
            // Fetch directly from the provider, which is the source of truth during a redirect.
            final authService = Provider.of<AuthService>(context, listen: false);
            return DriverDashboardScreen(driverInfo: authService.currentState.driverInfo);
          },
        ),
      ],
      redirect: (BuildContext context, GoRouterState state) {
        final authState = authService.currentState;
        final bool onAuthRoute = state.matchedLocation == '/auth';

        if (!authState.isAuthenticated) {
          return onAuthRoute ? null : '/auth';
        }

        if (authState.isAuthenticated && onAuthRoute) {
          return authState.role == UserRole.driver
              ? '/driver/dashboard'
              : '/rider/home';
        }

        // If the user is authenticated but on a route that doesn't match their role, redirect them.
        if (authState.isAuthenticated) {
          if (authState.role == UserRole.driver && state.matchedLocation != '/driver/dashboard') return '/driver/dashboard';
          if (authState.role == UserRole.rider && state.matchedLocation != '/rider/home') return '/rider/home';
        }

        return null;
      },
    );
  }
}

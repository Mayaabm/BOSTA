import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth_screen.dart';
import '../screens/driver_dashboard_screen.dart';
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
          builder: (context, state) => const DriverDashboardScreen(),
        ),
      ],
      redirect: (BuildContext context, GoRouterState state) {
        final authState = authService.currentState;
        final bool onAuthRoute = state.matchedLocation == '/auth';

        if (!authState.isAuthenticated) {
          return onAuthRoute ? null : '/auth';
        }

        if (authState.isAuthenticated && onAuthRoute) {
          return authState.role == UserRole.driver ? '/driver/dashboard' : '/rider/home';
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

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth_screen.dart';
import 'driver_dashboard.dart';
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
          path: '/rider/home',
          builder: (context, state) => const RiderHomeScreen(),
        ),
        GoRoute(
          path: '/driver/dashboard',
          builder: (context, state) {
            return const DriverDashboardScreen();
          },
        ),
        GoRoute(
          path: '/driver/onboarding',
          builder: (context, state) => const DriverOnboardingScreen(),
        ),
      ],
      redirect: (BuildContext context, GoRouterState state) {
        final authState = authService.currentState;
        final bool onAuthRoute = state.matchedLocation == '/auth';
        final bool onOnboardingRoute = state.matchedLocation == '/driver/onboarding';

        // If user is not authenticated, redirect to auth screen, unless they are already there.
        if (!authState.isAuthenticated) {
          return onAuthRoute ? null : '/auth';
        }

        // If user is authenticated...
        if (authState.role == UserRole.driver) {
          final driverInfo = authState.driverInfo;
          // If driver info is missing or onboarding is not complete, redirect to onboarding.
          if (driverInfo == null || !driverInfo.onboardingComplete) {
            return onOnboardingRoute ? null : '/driver/onboarding';
          }
          // If onboarding is complete and they are on the auth/onboarding page, go to dashboard.
          if (onAuthRoute || onOnboardingRoute) {
            return '/driver/dashboard';
          }
        } else if (authState.role == UserRole.rider && onAuthRoute) {
          return '/rider/home';
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

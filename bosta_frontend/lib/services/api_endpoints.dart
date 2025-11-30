import 'config_service.dart';

/// Centralized API endpoint definitions for the Bosta application.
class ApiEndpoints {
  // Use dynamic base URL from ConfigService, which can be changed at runtime
  static String get base => ConfigService().baseUrl;

  // --- Authentication ---
  static String get register => '$base/register/';
  static String get driverLogin => '$base/driver/login/';
  static String get riderLogin => '$base/rider/login/';
  static String get tokenRefresh => '$base/token/refresh/';

  // --- Driver Profile & Onboarding ---
  static String get driverProfile => '$base/driver/me/';
  static String get driverOnboard => '$base/driver/onboard/';

  // --- Bus & Route Information ---
  static String get nearbyBuses => '$base/buses/nearby/';
  static String get busesForRoute => '$base/buses/for_route/';
  static String get busesToDestination => '$base/buses/to_destination/';
  static String busDetails(String busId) => '$base/buses/$busId/';
  static String get allRoutes => '$base/routes/';
  static String routeDetails(String routeId) => '$base/routes/$routeId/';

  // --- Trip Management ---
  static String startTrip(String tripId) => '$base/trips/$tripId/start/';
  static String endTrip(String tripId) => '$base/trips/$tripId/end/';

  // --- ETA & Location ---
  static String get updateLocation => '$base/buses/update_location/';
  static String get eta => '$base/eta/';
}
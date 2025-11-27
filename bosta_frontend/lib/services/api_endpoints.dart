import 'package:flutter/foundation.dart' show kIsWeb;

/// A utility class for holding API endpoint constants.
///
/// This class is not meant to be instantiated.
class ApiEndpoints {
  // Private constructor to prevent instantiation.
  ApiEndpoints._();

  // For web deployment, this MUST be the public domain/IP of your backend.
  // Use --dart-define=BACKEND_HOST=your.backend.domain.com when building.
  static const String _host = String.fromEnvironment('BACKEND_HOST',
      // Default to localhost for web, and your specific IP for other platforms.
      defaultValue: kIsWeb ? 'localhost' : '192.168.1.102');
  static final String _baseUrl = 'http://$_host:8000/api';

  // --- Bus Endpoints ---
  static final String busesNearby = '$_baseUrl/buses/nearby';
  static final String busesToDestination = '$_baseUrl/buses/to_destination';
  static final String busesForRoute = '$_baseUrl/buses/for_route';
  static final String updateBusLocation = '$_baseUrl/buses/update_location/';
  static final String eta = '$_baseUrl/buses/eta';
  static String busById(String busId) => '$_baseUrl/buses/$busId';

  // --- Route Endpoints ---
  // Keep trailing slash to match Django REST Framework convention for endpoints.
  static final String routes = '$_baseUrl/routes/';

  // --- Trip Endpoints ---
  static String startTrip(String tripId) => '$_baseUrl/trips/$tripId/start/';
  static String endTrip(String tripId) => '$_baseUrl/trips/$tripId/end/';

  // --- Auth & User Endpoints ---
  // Note: Trailing slashes are often required by Django REST Framework.
  // Corrected driverLogin to point to the view, not the JWT token endpoint.
  static final String driverLogin = '$_baseUrl/driver/login/';
  static final String driverProfile = '$_baseUrl/driver/me/';
  static final String driverOnboard = '$_baseUrl/driver/onboard/';
  static final String riderLogin = '$_baseUrl/rider/login/';
  static final String register = '$_baseUrl/register/';
  static final String tokenRefresh = '$_baseUrl/token/refresh/';
}
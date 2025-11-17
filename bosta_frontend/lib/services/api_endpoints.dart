import 'package:flutter/foundation.dart' show kIsWeb;

/// A utility class for holding API endpoint constants.
///
/// This class is not meant to be instantiated.
class ApiEndpoints {
  // Private constructor to prevent instantiation.
  ApiEndpoints._();

  // Use 'localhost' for web and '10.0.2.2' for Android emulator
  static final String _host = kIsWeb ? 'localhost' : '10.0.2.2';
  static final String _baseUrl = 'http://$_host:8000/api';

  // --- Bus Endpoints ---
  static final String busesNearby = '$_baseUrl/buses/nearby';
  static final String busesToDestination = '$_baseUrl/buses/to_destination';
  static final String busesForRoute = '$_baseUrl/buses/for_route';
  static final String updateBusLocation = '$_baseUrl/buses/update_location';
  static final String eta = '$_baseUrl/buses/eta';
  static String busById(String busId) => '$_baseUrl/buses/$busId';

  // --- Route Endpoints ---
  static final String routes = '$_baseUrl/routes';

  // --- Auth & User Endpoints ---
  // Note: Trailing slashes are often required by Django REST Framework.
  static final String driverLogin = '$_baseUrl/driver/login/';
  static final String driverProfile = '$_baseUrl/driver/me/';
  static final String driverOnboard = '$_baseUrl/driver/onboard/';
  static final String riderLogin = '$_baseUrl/rider/login/';
  static final String register = '$_baseUrl/register/';
}
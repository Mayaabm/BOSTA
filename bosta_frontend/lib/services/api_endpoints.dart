import 'package:flutter/foundation.dart' show kIsWeb;

class ApiEndpoints {
  // Use 'localhost' for web and '10.0.2.2' for Android emulator
  static final String _host = kIsWeb ? 'localhost' : '10.0.2.2';
  static final String _baseUrl = 'http://$_host:8000/api';

  // Bus related endpoints
  static final String busesNearby = '$_baseUrl/buses/nearby';
  static final String busesToDestination = '$_baseUrl/buses/to_destination';
  static final String busesForRoute = '$_baseUrl/buses/for_route';
  static final String updateBusLocation = '$_baseUrl/buses/update_location';
  static final String eta = '$_baseUrl/buses/eta';

  // Route related endpoints
  static final String routes = '$_baseUrl/routes';
  static String busById(String busId) => '$_baseUrl/buses/$busId';
  static final String driverLogin = '$_baseUrl/driver/login/';

  // Add other endpoints here as needed
}
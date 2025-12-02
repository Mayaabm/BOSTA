class ApiEndpoints {
  // Use this for local development.
  // For Android emulator, use 10.0.2.2. For iOS simulator, use localhost.
  static const String baseUrl = 'http://10.0.2.2:8000/api';

  // Auth
  static const String riderLogin = '$baseUrl/auth/login/rider/';
  static const String driverLogin = '$baseUrl/auth/login/driver/';
  static const String register = '$baseUrl/auth/register/';
  static const String tokenRefresh = '$baseUrl/auth/token/refresh/';

  // Driver
  static const String driverProfile = '$baseUrl/driver/me/';
  static const String driverOnboard = '$baseUrl/driver/onboard/';

  // Rider & Buses
  static const String nearbyBuses = '$baseUrl/buses/nearby/';
  static const String busDetails = '$baseUrl/buses'; // e.g., /api/buses/1/
  static const String planTrip = '$baseUrl/trips/plan/';

  // Search
  static const String searchStops = '$baseUrl/stops/';
  static const String devRiderLocation = 'http://10.0.2.2:8000/dev/rider-location/';
}
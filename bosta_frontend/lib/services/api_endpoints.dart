class ApiEndpoints {
  // The base URL for your Django backend.
  // For the Android emulator, 10.0.2.2 points to your computer's localhost.
  // If you're using an iOS simulator or a physical device,
  // replace '10.0.2.2' with your computer's local IP address.
  static const String _baseUrl = 'http://127.0.0.1:8000/api';

  static const String busesNearby = '$_baseUrl/buses_nearby/';
  static const String eta = '$_baseUrl/eta/';
  static const String busesToDestination = '$_baseUrl/buses_to_destination/';
}
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiEndpoints {
  // The base URL for your Django backend.
  // For the Android emulator, 10.0.2.2 points to your computer's localhost.
  // If you're using an iOS simulator or a physical device,
  // replace '10.0.2.2' with your computer's local IP address.
  static const String _androidBaseUrl = 'http://10.0.2.2:8000/api';
  static const String _webBaseUrl = 'http://127.0.0.1:8000/api';
  static final String _baseUrl = kIsWeb ? _webBaseUrl : _androidBaseUrl;

  static final String busesNearby = '$_baseUrl/buses_nearby/';
  static final String eta = '$_baseUrl/eta/';
  static final String busesToDestination = '$_baseUrl/buses_to_destination/';
  static final String routes = '$_baseUrl/routes/';
}
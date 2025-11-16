import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_endpoints.dart';

enum UserRole { rider, driver, none }

class DriverInfo {
  final String busId;
  final String? routeId;
  final String firstName;
  final String lastName;
  final String username;
  final String email;
  final bool onboardingComplete;

  DriverInfo({
    required this.busId,
    this.routeId,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.email,
    required this.onboardingComplete,
  });
}

class AuthState {
  final bool isAuthenticated;
  final UserRole role;
  final DriverInfo? driverInfo;
  final String? token; // To store the auth token

  AuthState({this.isAuthenticated = false, this.role = UserRole.none, this.driverInfo, this.token});
}

/// A mock authentication service to simulate user login and role management.
/// In a real app, this would interact with your backend API and secure storage.
class AuthService extends ChangeNotifier {
  AuthState _state = AuthState(); // Default to logged-out

  AuthState get currentState => _state;

  /// Logs in a rider.
  /// Returns an error message on failure, or null on success.
  Future<String?> loginAsRider(String email, String password) async {
    final uri = Uri.parse(ApiEndpoints.riderLogin);
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String? token = data['token'];

        _state = AuthState(isAuthenticated: true, role: UserRole.rider, token: token);
        notifyListeners();
        return null; // Success
      } else {
        final errorData = json.decode(response.body);
        // Prefer a specific error key, but fall back to the whole body.
        return errorData['error'] ?? response.body;
      }
    } catch (e) {
      return 'Could not connect to the server. Please check your network.';
    }
  }

  /// Returns an error message on failure, or null on success.
  Future<String?> loginAsDriver(String email, String password) async {
    final uri = Uri.parse(ApiEndpoints.driverLogin);
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        // Django's `authenticate` uses 'username' field by default, even for email login.
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final String? token = data['access']; // SimpleJWT returns 'access' and 'refresh'

      if (token != null) {
        // Store token and set authenticated state, but driverInfo is null for now.
        _state = AuthState(isAuthenticated: true, role: UserRole.driver, token: token);
        notifyListeners();
        // Now fetch the full profile
        return await fetchAndSetDriverProfile();
      }
      return "Login successful, but no token received.";
    } else {
      final errorData = json.decode(response.body);
      // Prefer a specific error key, but fall back to the whole body.
      return errorData['error'] ?? response.body;
    }
  }

  /// Fetches the driver's profile from /api/driver/me/ and updates the state.
  /// Returns null on success, or an error message on failure.
  Future<String?> fetchAndSetDriverProfile() async {
    if (_state.token == null) {
      return "Authentication token not found. Please log in again.";
    }

    final uri = Uri.parse(ApiEndpoints.driverProfile);
    try {
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_state.token}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final info = DriverInfo(
          busId: data['bus_id'],
          routeId: data['route_id'],
          firstName: data['first_name'],
          lastName: data['last_name'],
          username: data['username'],
          email: data['email'],
          onboardingComplete: data['onboarding_complete'] ?? false,
        );
        // Update the state with the fetched driver info
        _state = AuthState(isAuthenticated: true, role: UserRole.driver, driverInfo: info, token: _state.token);
        notifyListeners();
        return null; // Success
      }
      // Provide a more detailed error message for debugging
      final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
      final errorMessage = errorBody['error'] ?? 'No specific error message provided.';
      return "Failed to load driver profile. Status: ${response.statusCode}. Reason: $errorMessage";
    } catch (e) {
      // Catch network or parsing errors
      return "An error occurred while fetching the driver profile: $e";
    }
  }

  /// Registers a new user and logs them in.
  /// Returns an error message on failure, or null on success.
  Future<String?> register({
    required String username,
    required String email,
    required String password,
    required UserRole role,
  }) async {
    final uri = Uri.parse(ApiEndpoints.register);
    try {
      final body = {
        'username': username,
        'email': email,
        'password': password,
        'role': role == UserRole.driver ? 'driver' : 'rider',
      };

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 201) { // 201 Created
        final data = json.decode(response.body);
        // Assuming the register endpoint returns an access token like login
        return null; // Success
      } else {
        final errorData = json.decode(response.body);
        return errorData['error'] ?? 'An unknown registration error occurred.';
      }
    } catch (e) {
      return 'Could not connect to the server. Please check your network.';
    }
  }

  /// Sends the driver's onboarding data to the backend.
  Future<String?> setupDriverProfile({
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String busPlateNumber,
    required int busCapacity,
    required String routeId,
  }) async {
    if (_state.token == null) {
      return "Authentication token not found. Please log in again.";
    }

    final uri = Uri.parse(ApiEndpoints.driverProfile);
    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${_state.token}',
        },
        body: json.encode({
          'first_name': firstName,
          'last_name': lastName,
          'phone_number': phoneNumber,
          'bus_plate_number': busPlateNumber,
          'bus_capacity': busCapacity,
          'route_id': routeId,
        }),
      );

      if (response.statusCode == 200) {
        // On success, the backend has marked onboarding as complete.
        // We re-fetch the profile to get the updated state.
        return await fetchAndSetDriverProfile();
      } else {
        final errorData = json.decode(response.body);
        // Join multiple errors if they exist
        final errors = (errorData as Map<String, dynamic>).entries.map((e) => '${e.key}: ${e.value.toString()}').join('\n');
        return errors.isNotEmpty ? errors : 'An unknown error occurred during setup.';
      }
    } catch (e) {
      return 'Could not connect to the server. Please check your network.';
    }
  }

  Future<void> logout() async {
    _state = AuthState();
    notifyListeners();
  }
}
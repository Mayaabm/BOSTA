import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_endpoints.dart';

enum UserRole { rider, driver, none }

class DriverInfo {
  final String busId;
  final String routeId;
  final String driverName;

  DriverInfo({required this.busId, required this.routeId, required this.driverName});
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
      // IMPORTANT: Your login endpoint should return a token (e.g., from Django REST Framework's JWT or TokenAuthentication)
      final String? token = data['token']; // Assuming the token is in the response

      final info = DriverInfo(
        busId: data['bus_id'],
        routeId: data['route_id'],
        driverName: data['driver_name'],
      );
      _state = AuthState(isAuthenticated: true, role: UserRole.driver, driverInfo: info, token: token);
      notifyListeners();
      return null; // Success
    } else {
      final errorData = json.decode(response.body);
      // Prefer a specific error key, but fall back to the whole body.
      return errorData['error'] ?? response.body;
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
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
          'password': password,
          'role': role == UserRole.driver ? 'driver' : 'rider',
        }),
      );

      if (response.statusCode == 201) { // 201 Created
        final data = json.decode(response.body);
        final String? token = data['token'];

        if (role == UserRole.driver && data.containsKey('driver_name')) {
          final info = DriverInfo(
            busId: data['bus_id'],
            routeId: data['route_id'],
            driverName: data['driver_name'],
          );
          _state = AuthState(isAuthenticated: true, role: UserRole.driver, driverInfo: info, token: token);
        } else {
          _state = AuthState(isAuthenticated: true, role: role, token: token);
        }
        notifyListeners();
        return null; // Success
      } else {
        final errorData = json.decode(response.body);
        return errorData['error'] ?? 'An unknown registration error occurred.';
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
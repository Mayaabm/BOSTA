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

  AuthState({this.isAuthenticated = false, this.role = UserRole.none, this.driverInfo});
}

/// A mock authentication service to simulate user login and role management.
/// In a real app, this would interact with your backend API and secure storage.
class AuthService extends ChangeNotifier {
  AuthState _state = AuthState(); // Default to logged-out

  AuthState get currentState => _state;

  Future<void> login(String email, String password) async {
    // Mock API call
    await Future.delayed(const Duration(seconds: 1));
    _state = AuthState(isAuthenticated: true, role: UserRole.rider); // Simulate rider login
    notifyListeners();
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
      final info = DriverInfo(
        busId: data['bus_id'],
        routeId: data['route_id'],
        driverName: data['driver_name'],
      );
      _state = AuthState(isAuthenticated: true, role: UserRole.driver, driverInfo: info);
      notifyListeners();
      return null; // Success
    } else {
      // Failure: return the error message from the server response.
      return response.body;
    }
  }

  Future<void> logout() async {
    _state = AuthState();
    notifyListeners();
  }
}
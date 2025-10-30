import 'dart:async';
import 'package:flutter/foundation.dart';

enum UserRole { rider, driver, none }

class AuthState {
  final bool isAuthenticated;
  final UserRole role;

  AuthState({this.isAuthenticated = false, this.role = UserRole.none});
}

/// A mock authentication service to simulate user login and role management.
/// In a real app, this would interact with your backend API and secure storage.
class AuthService extends ChangeNotifier {
  AuthState _state = AuthState(isAuthenticated: true, role: UserRole.rider); // Default to logged-in rider for now

  AuthState get currentState => _state;

  Future<void> login(String email, String password) async {
    // Mock API call
    await Future.delayed(const Duration(seconds: 1));
    _state = AuthState(isAuthenticated: true, role: UserRole.rider); // Simulate rider login
    notifyListeners();
  }

  Future<void> logout() async {
    _state = AuthState();
    notifyListeners();
  }
}
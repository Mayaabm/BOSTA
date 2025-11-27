import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:bosta_frontend/models/app_route.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as fm;
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
  final AppRoute? assignedRoute; // Add this to hold the full route object
  final String? token; // To store the auth token
  final String? refreshToken;
  final String? selectedStopId;
  final String? selectedStartTime; // Storing as ISO string for simplicity
  final double? selectedStartLat;
  final double? selectedStartLon;
  final fm.LatLng? initialBusPosition; // The starting coordinates of the bus

  AuthState({
    this.isAuthenticated = false,
    this.role = UserRole.none,
    this.driverInfo,
    this.assignedRoute,
    this.token,
    this.refreshToken,
    this.selectedStopId,
    this.selectedStartTime,
    this.selectedStartLat,
    this.selectedStartLon,
    this.initialBusPosition,
  });
}

/// A mock authentication service to simulate user login and role management.
/// In a real app, this would interact with your backend API and secure storage.
class AuthService extends ChangeNotifier {
  AuthState _state = AuthState(); // Default to logged-out
  String? _lastCreatedTripId;

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
        final String? token = data['access'];

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
      final String? refresh = data['refresh'];

      if (token != null) {
        // Store token and set authenticated state, but driverInfo is null for now.
        // First, fetch the profile with the new token.
        final profileError = await fetchAndSetDriverProfile(token: token, refreshToken: refresh);
        // Only then, notify listeners. This prevents a double navigation trigger.
        return profileError;
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
  Future<String?> fetchAndSetDriverProfile({String? token, String? refreshToken, String? selectedStopId, String? selectedStartTime, double? selectedStartLat, double? selectedStartLon}) async {
    final stopwatch = Stopwatch()..start();
    debugPrint("[AuthService] fetchAndSetDriverProfile: Starting...");

    final authToken = token ?? _state.token;
    final refresh = refreshToken ?? _state.refreshToken;
    if (authToken == null) {
      return "Authentication token not found. Please log in again.";
    } else {
      debugPrint("[AuthService] fetchAndSetDriverProfile: Using token starting with '${authToken.substring(0, 8)}...'");
    }
    debugPrint("[AuthService] fetchAndSetDriverProfile: Fetching from URL: ${ApiEndpoints.driverProfile}");
    final uri = Uri.parse(ApiEndpoints.driverProfile);
    try {
      final response = await http.get( // Added timeout
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      debugPrint("[AuthService] fetchAndSetDriverProfile: Profile fetch took ${stopwatch.elapsedMilliseconds}ms. Status: ${response.statusCode}");
      if (response.statusCode == 200) {
        debugPrint("[AuthService] fetchAndSetDriverProfile: Received 200 OK. Response body: ${response.body}");
        final data = json.decode(response.body);
        // Backend returns 'driver_name', 'bus' and 'route' objects.
        debugPrint("[AuthService] fetchAndSetDriverProfile: Parsing profile data...");
        final busId = data['bus'] != null ? (data['bus']['id']?.toString() ?? '') : '';
        final routeId = data['route'] != null ? (data['route']['id']?.toString() ?? '') : '';
        final driverName = data['driver_name'] ?? '';
        final nameParts = driverName.split(' ');
        final firstName = nameParts.isNotEmpty ? nameParts.first : '';
        final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
        final username = data['bus'] != null ? (data['bus']['plate_number'] ?? '') : '';
        final email = data['bus'] != null ? (data['bus']['driver_email'] ?? '') : '';
        debugPrint("[AuthService] fetchAndSetDriverProfile: Parsed driver info - busId: $busId, routeId: $routeId, name: $driverName");

        final info = DriverInfo(
          busId: busId,
          routeId: routeId,
          firstName: firstName,
          lastName: lastName,
          username: username,
          email: email,
          onboardingComplete: data['onboarding_complete'] ?? false,
        );
        // Update the state with the fetched driver info

        // Now, fetch the full route details if a routeId exists
        AppRoute? fetchedRoute;
        // The /api/driver/me/ endpoint now returns the full route object.
        // We can parse it directly instead of making a second API call.
        if (data['route'] != null) {
          fetchedRoute = AppRoute.fromJson(data['route']);
          debugPrint("[AuthService] fetchAndSetDriverProfile: Successfully parsed embedded route '${fetchedRoute.name}'.");
        } else if (routeId.isNotEmpty) {
          debugPrint("[AuthService] fetchAndSetDriverProfile: Route ID $routeId found, but route object is missing from response.");
        }
        
        // Find the initial bus position from the fetched route and selected stop ID
        fm.LatLng? initialPosition;
        final startStopId = selectedStopId ?? _state.selectedStopId;
        debugPrint("[AuthService] fetchAndSetDriverProfile: Determining initial position. startStopId: $startStopId");
        if (fetchedRoute != null && startStopId != null) {
          final startStop = fetchedRoute.stops.firstWhere((stop) => stop.id == startStopId, orElse: () => fetchedRoute!.stops.first);
          // If a specific start lat/lon was provided from onboarding, use that. Otherwise, use the stop's location.
          // This handles both picking a stop and tapping the map.
          final lat = selectedStartLat ?? startStop.location.latitude;
          final lon = selectedStartLon ?? startStop.location.longitude;
          initialPosition = fm.LatLng(lat, lon);
          debugPrint("[AuthService] fetchAndSetDriverProfile: Initial position set from start stop '${startStop.id}': $initialPosition");
        } else if (fetchedRoute != null && fetchedRoute.geometry.isNotEmpty) {
          initialPosition = fetchedRoute.geometry.first;
          debugPrint("[AuthService] fetchAndSetDriverProfile: Initial position set from first point of route geometry: $initialPosition");
        } else {
          debugPrint("[AuthService] fetchAndSetDriverProfile: Could not determine initial position.");
        }

        debugPrint("[AuthService] Storing final state with:");
        debugPrint("  > selectedStopId: ${selectedStopId ?? _state.selectedStopId}");
        debugPrint("  > selectedStartTime: ${selectedStartTime ?? _state.selectedStartTime}");
        debugPrint("  > selectedStartLat: ${selectedStartLat ?? _state.selectedStartLat}");
        debugPrint("  > selectedStartLon: ${selectedStartLon ?? _state.selectedStartLon}");

        _state = AuthState(
          isAuthenticated: true,
          role: UserRole.driver,
          driverInfo: info,
          assignedRoute: fetchedRoute, // Store the fetched route
          token: authToken,
          refreshToken: refresh,
          selectedStopId: selectedStopId ?? _state.selectedStopId, // Use newly provided trip info, or preserve existing
          selectedStartTime: selectedStartTime ?? _state.selectedStartTime, // Use newly provided trip info, or preserve existing
          selectedStartLat: selectedStartLat ?? _state.selectedStartLat,
          selectedStartLon: selectedStartLon ?? _state.selectedStartLon,
          initialBusPosition: initialPosition,
        );
        notifyListeners();
        debugPrint("[AuthService] fetchAndSetDriverProfile: Success. Total time: ${stopwatch.elapsedMilliseconds}ms.");
        return null; // Success
      }
      // Provide a more detailed error message for debugging
      debugPrint("[AuthService] fetchAndSetDriverProfile: Error. Status: ${response.statusCode}. Total time: ${stopwatch.elapsedMilliseconds}ms.");
      final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
      final errorMessage = errorBody['error'] ?? 'No specific error message provided.';
      return "Failed to load driver profile. Status: ${response.statusCode}. Reason: $errorMessage";
    } catch (e) {
      // Catch network or parsing errors
      debugPrint("[AuthService] fetchAndSetDriverProfile: Exception caught. Total time: ${stopwatch.elapsedMilliseconds}ms. Error: $e");
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
    String? firstName,
    String? lastName,
    String? phoneNumber,
  }) async {
    final uri = Uri.parse(ApiEndpoints.register);
    try {
      final body = <String, dynamic>{
        'username': username,
        'email': email,
        'password': password,
        'role': role == UserRole.driver ? 'driver' : 'rider',
      };

      if (firstName != null && firstName.isNotEmpty) body['first_name'] = firstName;
      if (lastName != null && lastName.isNotEmpty) body['last_name'] = lastName;
      if (phoneNumber != null && phoneNumber.isNotEmpty) body['phone_number'] = phoneNumber;

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 201) { // 201 Created
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
    String? startStopId,
    String? startTime,
    double? startLat,
    double? startLon,
    String? refreshToken,
  }) async {
    final accessToken = _state.token;

    debugPrint("[AuthService] setupDriverProfile called with:");
    debugPrint("  > routeId: $routeId");
    debugPrint("  > startStopId: $startStopId");
    debugPrint("  > startLat: $startLat, startLon: $startLon");

    final effectiveRefresh = refreshToken ?? _state.refreshToken; // optional refresh passed in
    if (accessToken == null) {
      return "Authentication token not found. Please log in again.";
    }
    final uri = Uri.parse(ApiEndpoints.driverOnboard);

    Future<String?> doPost(String token) async {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
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
        final data = json.decode(response.body);
        _lastCreatedTripId = data['trip_id']?.toString(); // Capture the trip ID

        // IMPORTANT: Now that the backend profile is set up, immediately fetch it
        // to get the complete, authoritative state, including the new routeId.
        // This fetch will also update the selected stop and time.
        final fetchError = await fetchAndSetDriverProfile(token: token, selectedStopId: startStopId, selectedStartTime: startTime, selectedStartLat: startLat, selectedStartLon: startLon);
        return fetchError; // Return null on success, or the error message from fetching.
      }
      // Propagate response body for caller to inspect
      return response.body;
    }

    try {
      final result = await doPost(accessToken);
      // If token invalid and refresh available, try refresh once
      if (result != null && (result.contains('token_not_valid') || result.contains('Invalid token')) && effectiveRefresh != null) {
        final refreshUri = Uri.parse(ApiEndpoints.tokenRefresh);
        final refreshRes = await http.post(
          refreshUri,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'refresh': effectiveRefresh}),
        );
        if (refreshRes.statusCode == 200) {
          final data = json.decode(refreshRes.body);
          final newAccess = data['access'] as String?;
          if (newAccess != null) {
            _state = AuthState(
                isAuthenticated: true,
                role: UserRole.driver,
                driverInfo: _state.driverInfo,
                assignedRoute: _state.assignedRoute,
                token: newAccess,
                refreshToken: effectiveRefresh,
                selectedStopId: startStopId,
                selectedStartTime: startTime,
                selectedStartLat: startLat,
                selectedStartLon: startLon);
            notifyListeners();
            return await doPost(newAccess);
          }
        }
      }
      if (result != null) {
        // Try to format as key/value if JSON; otherwise return raw
        try {
          final errorData = json.decode(result);
          if (errorData is Map<String, dynamic>) {
            final errors = errorData.entries.map((e) => '${e.key}: ${e.value}').join('\n');
            return errors.isNotEmpty ? errors : 'An unknown error occurred during setup.';
          }
        } catch (_) {}
        return result;
      }
      return result; // This will be null if doPost was successful
    } catch (e) {
      return 'Could not connect to the server. Please check your network.';
    }
  }

  /// Attempts to get a new access token using a refresh token.
  /// Returns the new access token on success, or null on failure.
  Future<String?> refreshAccessToken(String refreshToken) async {
    final refreshUri = Uri.parse(ApiEndpoints.tokenRefresh);
    debugPrint("[AuthService] Refreshing token at $refreshUri");
    try {
      final refreshRes = await http.post(
        refreshUri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh': refreshToken}),
      );

      if (refreshRes.statusCode == 200) {
        final data = json.decode(refreshRes.body);
        final newAccessToken = data['access'] as String?;
        if (newAccessToken != null) {
          // Update the auth state with the new token
          _state = AuthState(
            isAuthenticated: _state.isAuthenticated,
            role: _state.role,
            driverInfo: _state.driverInfo,
            assignedRoute: _state.assignedRoute,
            token: newAccessToken,
            refreshToken: _state.refreshToken, // The refresh token itself doesn't change
            selectedStopId: _state.selectedStopId,
            selectedStartTime: _state.selectedStartTime,
            selectedStartLat: _state.selectedStartLat,
            selectedStartLon: _state.selectedStartLon,
            initialBusPosition: _state.initialBusPosition,
          );
          notifyListeners();
          debugPrint("[AuthService] Token refresh successful.");
          return newAccessToken;
        }
      }
    } catch (e) {
      debugPrint("[AuthService] Exception during token refresh: $e");
    }
    return null;
  }

  /// Marks the driver's onboarding as complete and notifies listeners.
  /// This is useful for triggering navigation after a final step that doesn't
  /// involve a full profile refetch.
  void completeOnboarding() {
    if (_state.driverInfo != null) {
      // Create a new DriverInfo object based on the existing one,
      // but ensure onboardingComplete is set to true. This preserves
      // all other fetched details like routeId.
      final newInfo = DriverInfo(
        busId: _state.driverInfo!.busId,
        routeId: _state.driverInfo!.routeId,
        firstName: _state.driverInfo!.firstName,
        lastName: _state.driverInfo!.lastName,
        username: _state.driverInfo!.username,
        email: _state.driverInfo!.email,
        onboardingComplete: true,
      );
      _state = AuthState(
        isAuthenticated: _state.isAuthenticated,
        role: _state.role,
        driverInfo: newInfo, // Use the updated info object
        assignedRoute: _state.assignedRoute,
        token: _state.token,
        refreshToken: _state.refreshToken,
        selectedStopId: _state.selectedStopId,
        selectedStartTime: _state.selectedStartTime,
        selectedStartLat: _state.selectedStartLat,
        selectedStartLon: _state.selectedStartLon,
        initialBusPosition: _state.initialBusPosition, // Preserve the initial position
      );
      notifyListeners();
    }
  }

  /// If onboarding created a Trip, this returns its id (useful for testing start)
  String? get lastCreatedTripId => _lastCreatedTripId;

  Future<void> logout() async {
    _state = AuthState();
    notifyListeners();
  }
}

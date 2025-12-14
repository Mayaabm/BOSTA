import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:bosta_frontend/models/app_route.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as fm;
import 'api_endpoints.dart';
import 'route_service.dart';
import 'logger.dart';
import 'trip_service.dart';

enum UserRole { rider, driver, none }

class DriverInfo {
  final String busId;
  final String? routeId;
  final String firstName;
  final String lastName;
  final String username;
  final String email;
  final bool onboardingComplete;
  final String? phoneNumber;
  final String? busPlateNumber;
  final int? busCapacity;
  final bool? documentsApproved; // Placeholder for future document approval status

  DriverInfo({
    required this.busId,
    this.routeId,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.email,
    required this.onboardingComplete,
    this.phoneNumber,
    this.busPlateNumber,
    this.busCapacity,
    this.documentsApproved,
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
  final String? selectedEndStopId;
  final String? selectedStartTime; // Storing as ISO string for simplicity
  final double? selectedStartLat;
  final double? selectedStartLon;
  final fm.LatLng? initialBusPosition; // The starting coordinates of the bus
  final String? phoneNumber; // Added to AuthState for easy access
  final String? busPlateNumber; // Added to AuthState for easy access
  final int? busCapacity; // Added to AuthState for easy access
  final String? lastCreatedTripId;
  final Map<String, dynamic>? rawDriverProfile;

  AuthState({
    this.isAuthenticated = false,
    this.role = UserRole.none,
    this.driverInfo,
    this.assignedRoute,
    this.token,
    this.refreshToken,
    this.selectedStopId,
    this.selectedEndStopId,
    this.selectedStartTime,
    this.selectedStartLat,
    this.selectedStartLon,
    this.initialBusPosition,
    this.phoneNumber,
    this.busPlateNumber,
    this.busCapacity,
    this.lastCreatedTripId,
    this.rawDriverProfile,
  });
}

/// A mock authentication service to simulate user login and role management.
/// In a real app, this would interact with your backend API and secure storage.
class AuthService extends ChangeNotifier {
  AuthState _state = AuthState(); // Default to logged-out
  String? _lastPatchDebug;

  /// Detailed debug information about the last call to `patchDriverProfile`.
  String? get lastPatchDebug => _lastPatchDebug;

  AuthState get currentState => _state;

  // Convenience getter for onboarding status
  bool get onboardingComplete => _state.driverInfo?.onboardingComplete ?? false;

  /// Logs in a rider.
  /// Returns an error message on failure, or null on success.
  Future<String?> loginAsRider(String email, String password) async {
    debugPrint("[AuthService] loginAsRider: Attempting login for email: $email");
    final uri = Uri.parse(ApiEndpoints.riderLogin);
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email, 'password': password}),
      );

      debugPrint("[AuthService] loginAsRider: Response status: ${response.statusCode}, body: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final String? token = data['access'];

        _state = AuthState(isAuthenticated: true, role: UserRole.rider, token: token);
        debugPrint("[AuthService] loginAsRider: Success. State updated for rider.");
        notifyListeners();
        return null; // Success
      } else {
        final errorData = json.decode(response.body);
        debugPrint("[AuthService] loginAsRider: Failed. Error: $errorData");
        // Prefer a specific error key, but fall back to the whole body.
        return errorData['error'] ?? response.body;
      }
    } catch (e) {
      return 'Could not connect to the server. Please check your network.';
    }
  }

  /// Returns an error message on failure, or null on success.
  Future<String?> loginAsDriver(String email, String password) async {
    debugPrint("[AuthService] loginAsDriver: Attempting login for email: $email");
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

    debugPrint("[AuthService] loginAsDriver: Response status: ${response.statusCode}, body: ${response.body}");

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final String? token = data['access']; // SimpleJWT returns 'access' and 'refresh'
      final String? refresh = data['refresh'];

      if (token != null) {
        // Store token and set authenticated state, but driverInfo is null for now.
        // First, fetch the profile with the new token.
        final profileError = await fetchAndSetDriverProfile(token: token, refreshToken: refresh);
        debugPrint("[AuthService] loginAsDriver: Profile fetch completed. Error: $profileError");
        // Only then, notify listeners. This prevents a double navigation trigger.
        return profileError;
      }
      debugPrint("[AuthService] loginAsDriver: Login successful but no token was received.");
      return "Login successful, but no token received.";
    } else {
      debugPrint("[AuthService] loginAsDriver: Login failed.");
      final errorData = json.decode(response.body);
      // Prefer a specific error key, but fall back to the whole body.
      return errorData['error'] ?? response.body;
    }
  }

  /// Fetches the driver's profile from /api/driver/me/ and updates the state.
  /// Returns null on success, or an error message on failure.
  Future<String?> fetchAndSetDriverProfile({String? token, String? refreshToken, String? selectedStopId, String? selectedEndStopId, String? selectedStartTime, double? selectedStartLat, double? selectedStartLon, String? lastCreatedTripId}) async {
    final stopwatch = Stopwatch()..start();
    Logger.info('AuthService', 'fetchAndSetDriverProfile: starting');

    final authToken = token ?? _state.token;
    final refresh = refreshToken ?? _state.refreshToken;
    if (authToken == null) {
      return "Authentication token not found. Please log in again.";
    } else {
      Logger.debug('AuthService', 'using token starting ${authToken.substring(0, 8)}...');
    }
    Logger.debug('AuthService', 'GET ${ApiEndpoints.driverProfile}');
    final uri = Uri.parse(ApiEndpoints.driverProfile);
    try {
      final response = await http.get( // Added timeout
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      Logger.debug('AuthService', 'profile fetch took ${stopwatch.elapsedMilliseconds}ms status=${response.statusCode}');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // --- FIX: Log the response but exclude the noisy geometry data ---
        final loggableData = Map<String, dynamic>.from(data);
        if (loggableData['route'] != null && loggableData['route'] is Map) {
          final routeForLogging = Map<String, dynamic>.from(loggableData['route']);
          routeForLogging.remove('geometry');
          loggableData['route'] = routeForLogging;
        }
        Logger.debug('AuthService', 'profile received; route present: ${data['route'] != null}, active_trip_id: ${data['active_trip_id'] ?? 'null'}');

        final busId = data['bus'] != null ? (data['bus']['id']?.toString() ?? '') : '';
        final routeId = data['route'] != null ? (data['route']['id']?.toString() ?? '') : '';
        final driverName = data['driver_name'] ?? '';
        final nameParts = driverName.split(' ');
        final firstName = nameParts.isNotEmpty ? nameParts.first : '';
        final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
        final username = data['bus'] != null ? (data['bus']['plate_number'] ?? '') : '';
        final phoneNumber = data['phone_number']?.toString() ?? ''; // Correctly parse from the top-level
        final busPlateNumber = data['bus'] != null ? (data['bus']['plate_number'] ?? '') : '';
        final busCapacity = data['bus'] != null ? (data['bus']['capacity'] as int?) : null;
        final email = data['bus'] != null ? (data['bus']['driver_email'] ?? '') : '';
        Logger.info('AuthService', 'parsed driver info: busId=$busId routeId=$routeId name=$driverName');

        final info = DriverInfo(
          busId: busId,
          routeId: routeId,
          firstName: firstName,
          lastName: lastName,
          username: username,
          email: email,
          phoneNumber: phoneNumber,
          busPlateNumber: busPlateNumber,
          busCapacity: busCapacity,
          onboardingComplete: data['onboarding_complete'] ?? false,
          documentsApproved: data['documents_approved'] ?? false,
        );
        // Update the state with the fetched driver info

        // Now, fetch the full route details if a routeId exists
        AppRoute? fetchedRoute;
        // The /api/driver/me/ endpoint now returns the full route object.
        // We can parse it directly instead of making a second API call.
        if (data['route'] != null) {
          fetchedRoute = AppRoute.fromJson(data['route']);
          Logger.info('AuthService', "parsed embedded route: ${fetchedRoute.name}");
        } else if (routeId.isNotEmpty) {
          Logger.debug('AuthService', 'route id present but route object missing; attempting fetch by id');
          try {
            fetchedRoute = await RouteService.getRouteById(routeId);
            Logger.info('AuthService', 'fetched route by id: ${fetchedRoute?.name}');
          } catch (e) {
            Logger.error('AuthService', 'failed to fetch route by id $routeId: $e');
          }
        }
        
        // Find the initial bus position from the fetched route and selected stop ID
        fm.LatLng? initialPosition; // The 'selectedStopId' here refers to the parameter passed to the function
        final startStopId = selectedStopId ?? _state.selectedStopId;
        Logger.debug('AuthService', 'determining initial position startStopId=$startStopId');
        if (fetchedRoute != null && startStopId != null) {
          final startStop = fetchedRoute.stops.firstWhere((stop) => stop.id == startStopId, orElse: () => fetchedRoute!.stops.first);
          // If a specific start lat/lon was provided from onboarding, use that. Otherwise, use the stop's location.
          // This handles both picking a stop and tapping the map.
          final lat = selectedStartLat ?? startStop.location.latitude;
          final lon = selectedStartLon ?? startStop.location.longitude;
          initialPosition = fm.LatLng(lat, lon);
          Logger.debug('AuthService', 'initial position from start stop ${startStop.id}: $initialPosition');
        } else if (fetchedRoute != null && fetchedRoute.geometry.isNotEmpty) {
          initialPosition = fetchedRoute.geometry.first;
          Logger.debug('AuthService', 'initial position from route geometry: $initialPosition');
        } else {
          Logger.debug('AuthService', 'could not determine initial position');
        }

        debugPrint("[AuthService] Storing final state with:");
        debugPrint("  > selectedStopId: ${selectedStopId ?? _state.selectedStopId}");
        debugPrint("  > selectedStartTime: ${selectedStartTime ?? _state.selectedStartTime}");
        debugPrint("  > selectedStartLat: ${selectedStartLat ?? _state.selectedStartLat}");
        debugPrint("  > selectedStartLon: ${selectedStartLon ?? _state.selectedStartLon}");

        // Store the raw response JSON so callers can access top-level fields
        // that aren't yet represented in AuthState (e.g., active_trip_id).
        final rawProfile = data is Map<String, dynamic> ? data : null;
        Logger.info('AuthService', 'active_trip_id=${rawProfile?['active_trip_id']}');
        
        // If the backend response doesn't contain full route details yet,
        // preserve any previously-known (optimistic) assigned route so the
        // UI doesn't revert to an older route while the server catches up.
        final AppRoute? finalAssignedRoute = fetchedRoute ?? _state.assignedRoute;

        _state = AuthState(
          isAuthenticated: true,
          role: UserRole.driver,
          driverInfo: info,
          assignedRoute: finalAssignedRoute, // Store fetched or existing route
          token: authToken, // Use the token that was used for the fetch
          refreshToken: refresh,
          // --- FIX: Prioritize passed-in parameters over the backend response for trip details.
          // This ensures that when we patch the profile, the new values are immediately reflected
          // in the state, even if the backend GET response hasn't caught up yet.
          selectedStopId: () {
            final id = data['selected_start_stop_id']?.toString() ?? selectedStopId;
            debugPrint("[AuthService] Parsed 'selected_start_stop_id': $id");
            return id;
          }(),
          selectedEndStopId: data['selected_end_stop_id']?.toString() ?? selectedEndStopId,
          selectedStartTime: selectedStartTime ?? data['selected_start_time']?.toString(),
          // Preserve lat/lon if they were set from a map tap, as they might not be in the response.
          selectedStartLat: selectedStartLat ?? _state.selectedStartLat,
          selectedStartLon: selectedStartLon ?? _state.selectedStartLon,
          initialBusPosition: initialPosition,
          // --- DEFINITIVE FIX ---
          // The phone number, along with other direct driver attributes, MUST come from the
          // newly fetched 'info' object, not the old state. This was the root cause of the bug.
          phoneNumber: info.phoneNumber,
          busPlateNumber: info.busPlateNumber,
          busCapacity: info.busCapacity,
          lastCreatedTripId: lastCreatedTripId ?? _state.lastCreatedTripId, // Use new ID if provided, else preserve
          rawDriverProfile: rawProfile,
        );
        notifyListeners();
        Logger.debug('AuthService', 'fetchAndSetDriverProfile success ${stopwatch.elapsedMilliseconds}ms');
        return null; // Success
      }
      // Provide a more detailed error message for debugging
      Logger.error('AuthService', 'fetch failed status=${response.statusCode} time=${stopwatch.elapsedMilliseconds}ms');
      final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
      final errorMessage = errorBody['error'] ?? response.body;
      return "Failed to load driver profile. Status: ${response.statusCode}.";
    } catch (e) {
      // Catch network or parsing errors
      Logger.error('AuthService', 'exception during fetchAndSetDriverProfile: $e');
      return "An error occurred while fetching the driver profile.";
    }
  }

  /// Updates the driver's profile information (e.g., name, phone number).
  /// This method is for updating user data, NOT for trip management.
  Future<String?> patchDriverProfile(Map<String, dynamic> data) async {
    final stopwatch = Stopwatch()..start(); // For performance monitoring
  
    final accessToken = _state.token;
    if (accessToken == null) {
      return "Authentication token not found. Please log in again.";
    }

    // If this patch is intended to set up a new trip, add a flag for the backend.
    final requestData = Map<String, dynamic>.from(data);

    // The backend uses the same 'onboard' endpoint for both initial setup and updates.
    // It expects a POST request, not a PATCH or PUT on /driver/me/.
    final uri = Uri.parse(ApiEndpoints.driverOnboard);
    Logger.info('AuthService', 'patchDriverProfile: POST to $uri');
    Logger.debug('AuthService', 'patch payload: ${json.encode(data)}');
    try {
      // Use http.post to match the backend's expectation for this endpoint.
      final requestBody = json.encode(data);
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: requestBody,
      );

      // Build verbose debug info for later inspection
      final buffer = StringBuffer();
      buffer.writeln('=== AuthService.patchDriverProfile DEBUG ===');
      buffer.writeln('Endpoint: $uri');
      buffer.writeln('Request: $requestBody');
      buffer.writeln('Status: ${response.statusCode}');
      buffer.writeln('Raw response body: ${response.body}');
      // Try to parse JSON if possible
      try {
        final parsed = json.decode(response.body);
        buffer.writeln('Parsed response JSON: $parsed');
      } catch (_) {
        buffer.writeln('Response is not JSON.');
      }

      _lastPatchDebug = buffer.toString();
      Logger.debug('AuthService', 'patch response status=${response.statusCode}');

      if (response.statusCode == 200) {
        Logger.info('AuthService', 'patchDriverProfile: POST successful. Refreshing profile...');
        final fetchError = await fetchAndSetDriverProfile();
        if (fetchError != null) {
          Logger.error('AuthService', 'error re-fetching profile after patch: $fetchError');
          _lastPatchDebug = (_lastPatchDebug ?? '') + '\nFetch error: $fetchError';
        }
        return fetchError; // null on complete success, otherwise the fetch error
      } else {
        Logger.error('AuthService', 'patchDriverProfile failed status=${response.statusCode}');
        String errorMessage = 'No specific error message provided.';
        try {
          final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
          if (errorBody is Map && errorBody.containsKey('error')) {
            errorMessage = errorBody['error'].toString();
          } else if (errorBody is Map) {
            errorMessage = errorBody.toString();
          }
        } catch (_) {}
        _lastPatchDebug = (_lastPatchDebug ?? '') + '\nErrorMessage: $errorMessage';
        return "Failed to update driver profile. Status: ${response.statusCode}. Reason: $errorMessage";
      }
    } catch (e) {
      final msg = "An error occurred while updating the driver profile.";
      Logger.error('AuthService', 'patchDriverProfile exception: $e');
      _lastPatchDebug = (_lastPatchDebug ?? '') + '\nException: $e';
      return msg;
    }
  }
  
  /// Saves the selected start and end stops for the upcoming trip.
  /// This updates the local state immediately for a responsive UI and sends the update to the backend.
  Future<String?> saveTripSetup({required String startStopId, required String endStopId}) async {
    debugPrint("[AuthService.saveTripSetup] Saving trip setup: Start=$startStopId, End=$endStopId");

    // 1. Optimistically update local state
    _state = AuthState(
        isAuthenticated: _state.isAuthenticated,
        role: _state.role,
        driverInfo: _state.driverInfo,
        assignedRoute: _state.assignedRoute,
        token: _state.token,
        refreshToken: _state.refreshToken,
        selectedStopId: startStopId, // Update
        selectedEndStopId: endStopId, // Update
        selectedStartTime: _state.selectedStartTime,
        selectedStartLat: _state.selectedStartLat,
        selectedStartLon: _state.selectedStartLon,
        initialBusPosition: _state.initialBusPosition,
        phoneNumber: _state.phoneNumber,
        busPlateNumber: _state.busPlateNumber,
        busCapacity: _state.busCapacity,
        lastCreatedTripId: _state.lastCreatedTripId,
        rawDriverProfile: _state.rawDriverProfile,
    );
    notifyListeners();

    // 2. Send update to the backend
    final accessToken = _state.token;
    if (accessToken == null) return "Not authenticated.";

    final uri = Uri.parse(ApiEndpoints.driverOnboard);
    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: json.encode({
          'selected_start_stop_id': startStopId,
          'selected_end_stop_id': endStopId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint("[AuthService.saveTripSetup] Backend successfully updated.");
        return null; // Success
      } else {
        final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
        return "Failed to save trip setup to backend. Status: ${response.statusCode}. Reason: ${errorBody['error'] ?? 'Unknown'}";
      }
    } catch (e) {
      return "An error occurred while saving trip setup: $e";
    }
  }

  /// Optimistically set the assigned route locally so the UI reflects
  /// the driver's choice immediately while the backend update is pending.
  void setAssignedRouteLocally(AppRoute route) {
    final newRaw = Map<String, dynamic>.from(_state.rawDriverProfile ?? {});
    // Minimal route representation for checks elsewhere
    newRaw['route'] = {'id': route.id, 'name': route.name};

    _state = AuthState(
      isAuthenticated: _state.isAuthenticated,
      role: _state.role,
      driverInfo: _state.driverInfo,
      assignedRoute: route,
      token: _state.token,
      refreshToken: _state.refreshToken,
      selectedStopId: _state.selectedStopId,
      selectedEndStopId: _state.selectedEndStopId,
      selectedStartTime: _state.selectedStartTime,
      selectedStartLat: _state.selectedStartLat,
      selectedStartLon: _state.selectedStartLon,
      initialBusPosition: _state.initialBusPosition,
      phoneNumber: _state.phoneNumber,
      busPlateNumber: _state.busPlateNumber,
      busCapacity: _state.busCapacity,
      lastCreatedTripId: _state.lastCreatedTripId,
      rawDriverProfile: newRaw,
    );
    notifyListeners();
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
    String? busPlateNumber,
    int? busCapacity,
    String? phoneNumber,
  }) async {
    debugPrint("[AuthService] register: Attempting to register new ${role.name}: $email");
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
      if (role == UserRole.driver) {
        if (busPlateNumber != null && busPlateNumber.isNotEmpty) body['bus_plate_number'] = busPlateNumber;
        if (busCapacity != null) body['bus_capacity'] = busCapacity;
      }

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      debugPrint("[AuthService] register: Response status: ${response.statusCode}, body: ${response.body}");

      if (response.statusCode == 201) { // 201 Created
        debugPrint("[AuthService] register: Success. Now attempting to log in the new user.");
        // --- FIX: After successful registration, immediately log the user in ---
        if (role == UserRole.driver) {
          // For drivers, login fetches the full profile
          return await loginAsDriver(email, password);
        } else {
          // For riders, login is simpler
          return await loginAsRider(email, password);
        }
      } else {
        final errorData = json.decode(response.body);
        debugPrint("[AuthService] register: Failed. Error: $errorData");
        return errorData['error'] ?? 'An unknown registration error occurred.';
      }
    } catch (e) {
      debugPrint("[AuthService] register: Exception caught: $e");
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
    String? refreshToken,
  }) async {
    final accessToken = _state.token;

    debugPrint("\n\n[AuthService] ===== STARTING DRIVER PROFILE SETUP/TRIP CREATION =====");

    final effectiveRefresh = refreshToken ?? _state.refreshToken; // optional refresh passed in
    if (accessToken == null) {
      return "Authentication token not found. Please log in again.";
    } // This is for initial onboarding, not partial updates
    final uri = Uri.parse(ApiEndpoints.driverOnboard);
    debugPrint("[AuthService] Target Endpoint: $uri");

    Future<String?> doPost(String token) async {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(<String, dynamic>{
          'first_name': firstName,
          'last_name': lastName,
          'phone_number': phoneNumber,
          'bus_plate_number': busPlateNumber,
          'bus_capacity': busCapacity,
        }),
      );
      
      debugPrint("[AuthService.doPost] Response status: ${response.statusCode}");
      debugPrint("[AuthService.doPost] Response body: ${response.body}");

      if (response.statusCode == 200) {
        debugPrint("[AuthService.doPost] POST successful. Parsing response...");
        final data = json.decode(response.body);
        debugPrint("[AuthService.doPost] Parsed response: $data");
        debugPrint("[AuthService.doPost] Response keys: ${data.keys.toList()}");
        
        final newTripId = data['trip_id']?.toString();
        debugPrint("[AuthService.doPost] Captured trip_id: $newTripId");

        // IMPORTANT: Now that the backend profile is set up, immediately fetch it
        // to get the complete, authoritative state, including the new routeId.
        // This fetch will also update the selected stop and time.
        debugPrint("[AuthService.doPost] ---> STEP 1 COMPLETE. Now calling fetchAndSetDriverProfile to get full profile state...");
        final fetchError = await fetchAndSetDriverProfile(
          token: token, // Ensure we use the current token
          lastCreatedTripId: newTripId,
          // Lat/Lon are not part of this flow, so they remain null/unchanged.
        );

        // --- THE FIX ---
        // If the fetch was successful but the active_trip_id is null (due to a race condition),
        // manually inject the trip ID we just received from the creation response.
        debugPrint("[AuthService.doPost] ---> STEP 2: CHECKING FOR RACE CONDITION...");
        if (fetchError == null && newTripId != null && _state.rawDriverProfile?['active_trip_id'] == null) {
          debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"); // Keep this for high visibility
          debugPrint("[AuthService.doPost] RACE CONDITION DETECTED. Manually setting active_trip_id to '$newTripId'.");
          debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
          final newRawProfile = Map<String, dynamic>.from(_state.rawDriverProfile ?? {});
          newRawProfile['active_trip_id'] = newTripId;
          
          // Create a new state object with the updated raw profile
          _state = AuthState(
            isAuthenticated: _state.isAuthenticated, role: _state.role, driverInfo: _state.driverInfo, assignedRoute: _state.assignedRoute, token: _state.token, refreshToken: _state.refreshToken, selectedStopId: _state.selectedStopId, selectedEndStopId: _state.selectedEndStopId, selectedStartTime: _state.selectedStartTime, selectedStartLat: _state.selectedStartLat, selectedStartLon: _state.selectedStartLon, initialBusPosition: _state.initialBusPosition, phoneNumber: _state.phoneNumber, busPlateNumber: _state.busPlateNumber, busCapacity: _state.busCapacity, lastCreatedTripId: _state.lastCreatedTripId,
            rawDriverProfile: newRawProfile,
          );
          notifyListeners();
        }

        debugPrint("[AuthService.doPost] fetchAndSetDriverProfile returned: $fetchError");
        return fetchError; // Return null on success, or the error message from fetching.
      }
      // Propagate response body for caller to inspect
      debugPrint("[AuthService.doPost] Error response status: ${response.statusCode}. Setup failed.");
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
            );
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
            selectedEndStopId: _state.selectedEndStopId,
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
    debugPrint("[AuthService] completeOnboarding: Manually marking onboarding as complete.");
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
        phoneNumber: _state.driverInfo!.phoneNumber,
        busPlateNumber: _state.driverInfo!.busPlateNumber,
        busCapacity: _state.driverInfo!.busCapacity,
      );
      _state = AuthState(
        isAuthenticated: _state.isAuthenticated,
        role: _state.role,
        driverInfo: newInfo, // Use the updated info object
        assignedRoute: _state.assignedRoute,
        token: _state.token,
        refreshToken: _state.refreshToken,
        selectedStopId: _state.selectedStopId,
        selectedEndStopId: _state.selectedEndStopId,
        selectedStartTime: _state.selectedStartTime,
        selectedStartLat: _state.selectedStartLat,
        selectedStartLon: _state.selectedStartLon,
        initialBusPosition: _state.initialBusPosition, // Preserve the initial position
        phoneNumber: _state.phoneNumber,
        busPlateNumber: _state.busPlateNumber,
        busCapacity: _state.busCapacity,
      );
      notifyListeners();
    }
  }

  /// Returns the raw driver profile JSON returned by the backend (nullable).
  /// This lets UI code access top-level fields such as `active_trip_id`.
  Map<String, dynamic>? get rawDriverProfile => _state.rawDriverProfile;

  /// Attempts to end any active trip before clearing auth state.
  /// Returns null on success, or an error message if ending the trip failed.
  Future<String?> logout() async {
    debugPrint("[AuthService] logout: Attempting safe logout.");
    final token = _state.token;
    final activeTripId = _state.rawDriverProfile?['active_trip_id']?.toString();
    if (token != null && activeTripId != null) {
      try {
        Logger.info('AuthService', 'logout: Ending active trip $activeTripId before logout');
        await TripService.endTrip(token, activeTripId);
        Logger.info('AuthService', 'logout: Ended active trip $activeTripId');
      } catch (e) {
        Logger.error('AuthService', 'logout: Failed to end active trip $activeTripId: $e');
        return 'Failed to end active trip: $e';
      }
    }

    debugPrint("[AuthService] logout: Clearing auth state and logging out.");
    _state = AuthState();
    notifyListeners();
    return null;
  }

  /// Fetches all available routes from the backend.
  /// This is useful for allowing a driver to select or change their route.
  Future<List<AppRoute>> fetchAllRoutes() async {
    final authToken = _state.token;
    if (authToken == null) {
      debugPrint("[AuthService] fetchAllRoutes: No auth token found.");
      return [];
    }

    final uri = Uri.parse(ApiEndpoints.allRoutes);
    debugPrint("[AuthService] fetchAllRoutes: Fetching from $uri");
    try {
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $authToken',
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((routeJson) => AppRoute.fromJson(routeJson)).toList();
      }
    } catch (e) {
      debugPrint("[AuthService] fetchAllRoutes: Exception caught: $e");
    }
    return [];
  }
}

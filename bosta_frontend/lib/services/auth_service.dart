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
        debugPrint("[AuthService] fetchAndSetDriverProfile: Raw JSON data from /api/driver/me/: $data");
        debugPrint("[AuthService] fetchAndSetDriverProfile: Parsing profile data...");
        final busId = data['bus'] != null ? (data['bus']['id']?.toString() ?? '') : '';
        final routeId = data['route'] != null ? (data['route']['id']?.toString() ?? '') : '';
        final driverName = data['driver_name'] ?? '';
        final nameParts = driverName.split(' ');
        final firstName = nameParts.isNotEmpty ? nameParts.first : '';
        final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
        final username = data['bus'] != null ? (data['bus']['plate_number'] ?? '') : '';
        final phoneNumber = data['phone_number'] ?? ''; // Assuming backend provides this
        final busPlateNumber = data['bus'] != null ? (data['bus']['plate_number'] ?? '') : '';
        final busCapacity = data['bus'] != null ? (data['bus']['capacity'] as int?) : null;
        final email = data['bus'] != null ? (data['bus']['driver_email'] ?? '') : '';
        debugPrint("[AuthService] fetchAndSetDriverProfile: Parsed driver info - busId: $busId, routeId: $routeId, name: $driverName");

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
          debugPrint("[AuthService] fetchAndSetDriverProfile: Successfully parsed embedded route '${fetchedRoute.name}'.");
        } else if (routeId.isNotEmpty) {
          debugPrint("[AuthService] fetchAndSetDriverProfile: Route ID $routeId found, but route object is missing from response.");
        }
        
        // Find the initial bus position from the fetched route and selected stop ID
        fm.LatLng? initialPosition; // The 'selectedStopId' here refers to the parameter passed to the function
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

        // Store the raw response JSON so callers can access top-level fields
        // that aren't yet represented in AuthState (e.g., active_trip_id).
        final rawProfile = data is Map<String, dynamic> ? data : null;
        debugPrint("[AuthService] Stored raw driver profile: $rawProfile");
        debugPrint("[AuthService] >> active_trip_id from raw profile GET response: ${rawProfile?['active_trip_id']}");
        debugPrint("[AuthService] Raw profile keys: ${rawProfile?.keys.toList()}");
        
        _state = AuthState(
          isAuthenticated: true,
          role: UserRole.driver,
          driverInfo: info,
          assignedRoute: fetchedRoute, // Store the fetched route
          token: authToken, // Use the token that was used for the fetch
          refreshToken: refresh,
          // --- FIX: Prioritize passed-in parameters over the backend response for trip details.
          // This ensures that when we patch the profile, the new values are immediately reflected
          // in the state, even if the backend GET response hasn't caught up yet.
          selectedStopId: () {
            final id = selectedStopId ?? data['selected_start_stop_id']?.toString();
            debugPrint("[AuthService] Parsed 'selected_start_stop_id': $id");
            return id;
          }(),
          selectedEndStopId: selectedEndStopId ?? data['selected_end_stop_id']?.toString(),
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

  /// Sends partial updates to the driver's profile using a PATCH request.
  /// Returns null on success, or an error message on failure.
  Future<String?> patchDriverProfile(Map<String, dynamic> data, {bool createNewTrip = false}) async {
    final stopwatch = Stopwatch()..start(); // For performance monitoring

    final accessToken = _state.token;
    if (accessToken == null) {
      return "Authentication token not found. Please log in again.";
    }

    // If this patch is intended to set up a new trip, add a flag for the backend.
    final requestData = Map<String, dynamic>.from(data);
    if (createNewTrip) {
      requestData['create_new_trip'] = true;
    }

    // The backend uses the same 'onboard' endpoint for both initial setup and updates.
    // It expects a POST request, not a PATCH or PUT on /driver/me/.
    final uri = Uri.parse(ApiEndpoints.driverOnboard);
    debugPrint("======================================================================");
    debugPrint("[AuthService.patchDriverProfile] Initiating trip creation/profile patch.");
    debugPrint("  > Endpoint: $uri");
    debugPrint("  > createNewTrip flag: $createNewTrip");
    debugPrint("[AuthService] patchDriverProfile: Sending POST to $uri with data: ${json.encode(requestData)}");
    try {
      // Use http.post to match the backend's expectation for this endpoint.
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: json.encode(requestData),
      );

      debugPrint("[AuthService] patchDriverProfile: Response status: ${response.statusCode}, body: ${response.body}");
      debugPrint("  > Raw Response Body: ${response.body}");
      debugPrint("======================================================================");

      if (response.statusCode == 200) {
        // --- NEW SOLUTION: Smart State Update ---
        // If we are NOT creating a new trip, we are just saving the start/end stops.
        // In this case, we should NOT re-fetch the entire profile. Doing so wipes
        // the state because the POST response is minimal.
        // --- FIX: This optimization should ONLY apply if we are *only* saving stops.
        // If other profile data is present, we must re-fetch.
        final isSavingStopsOnly = data.keys.isNotEmpty && data.keys.every(
            (k) => k == 'selected_start_stop_id' || k == 'selected_end_stop_id'
        );

        if (!createNewTrip && isSavingStopsOnly) {
            debugPrint("[AuthService.patchDriverProfile] Saving stops only. Updating state locally without re-fetch.");
            debugPrint("  > STATE BEFORE UPDATE: driverInfo is ${ _state.driverInfo != null ? 'PRESENT' : 'NULL'}, assignedRoute is ${_state.assignedRoute != null ? 'PRESENT' : 'NULL'}");
            debugPrint("  > Updating selectedStopId to: ${data['selected_start_stop_id']?.toString()}");
            debugPrint("  > Updating selectedEndStopId to: ${data['selected_end_stop_id']?.toString()}");

            _state = AuthState(
                // --- THE FIX: Ensure ALL properties are copied from the old state ---
                isAuthenticated: _state.isAuthenticated,
                role: _state.role,
                driverInfo: _state.driverInfo, // Preserve existing driver info
                assignedRoute: _state.assignedRoute, // Preserve existing route info
                token: _state.token,
                refreshToken: _state.refreshToken,
                // Update only the changed fields
                selectedStopId: data['selected_start_stop_id']?.toString(),
                selectedEndStopId: data['selected_end_stop_id']?.toString(),
                // Preserve all other fields
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
            debugPrint("  > STATE AFTER UPDATE: driverInfo is ${ _state.driverInfo != null ? 'PRESENT' : 'NULL'}, assignedRoute is ${_state.assignedRoute != null ? 'PRESENT' : 'NULL'}");
            debugPrint("[AuthService.patchDriverProfile] State updated with new stops. Returning success.");
            return null; // <-- CRITICAL FIX: Exit the function here.
          }

        // --- EXISTING LOGIC for createNewTrip=true ---
        // This part only runs when the "Start Trip" button is pressed.
        final responseData = json.decode(response.body);
        final newTripId = responseData['trip_id']?.toString();
        
        // --- LOGIC FOR createNewTrip=true OR for general profile updates ---
        // If we are creating a new trip, the backend MUST return the new trip_id.
        // We pass this ID to the state update to avoid race conditions.
        debugPrint("[AuthService] patchDriverProfile: POST successful. Now re-fetching the full profile to get the latest state...");
        // --- FIX: When re-fetching after a general profile update, we must NOT pass old/stale stop IDs.
        // Passing null for the stop IDs ensures that fetchAndSetDriverProfile uses the values from the backend
        // or preserves the existing state, preventing the new profile data from being overwritten.
        String? fetchError = await fetchAndSetDriverProfile(
          lastCreatedTripId: newTripId, // Pass the new trip ID to the state
        );

        // If we were creating a trip and the re-fetch *still* didn't see the active_trip_id,
        // it's a race condition. Wait a moment and try one more time.
        // Also check if the newTripId from the POST response is available.
        if (createNewTrip && newTripId != null && _state.rawDriverProfile?['active_trip_id'] == null) {
          debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
          debugPrint("[AuthService] RACE CONDITION DETECTED. active_trip_id is null after first fetch.");
          debugPrint("[AuthService] Waiting 1 second and re-fetching...");
          debugPrint("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
          await Future.delayed(const Duration(seconds: 1));
          // --- DEFINITIVE FIX: When re-fetching due to a race condition, do NOT pass any parameters. ---
          // Passing any parameters was causing the state to be partially overwritten.
          // A clean fetch gets the true state from the backend.
          fetchError = await fetchAndSetDriverProfile(token: accessToken, refreshToken: _state.refreshToken);
        }

        if (fetchError != null) {
          debugPrint("[AuthService] patchDriverProfile: Error re-fetching profile after patch: $fetchError");
        }

        // If we were creating a trip, return the new trip ID. Otherwise, return null for success.
        return createNewTrip ? newTripId : null;
      } else {
        // Provide a more detailed error message for debugging
        debugPrint("[AuthService] patchDriverProfile: Error. Status: ${response.statusCode}.");
        final errorBody = response.body.isNotEmpty ? json.decode(response.body) : {};
        final errorMessage = errorBody['error'] ?? 'No specific error message provided.';
        return "Failed to update driver profile. Status: ${response.statusCode}. Reason: $errorMessage";
      }
    } catch (e) {
      // Catch network or parsing errors
      debugPrint("[AuthService] patchDriverProfile: Exception caught. Total time: ${stopwatch.elapsedMilliseconds}ms. Error: $e");
      return "An error occurred while updating the driver profile: $e";
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

  Future<void> logout() async {
    debugPrint("[AuthService] logout: Clearing auth state and logging out.");
    _state = AuthState();
    notifyListeners();
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

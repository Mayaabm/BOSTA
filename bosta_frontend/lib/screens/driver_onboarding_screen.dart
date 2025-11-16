import 'dart:convert';

import 'package:bosta_frontend/models/app_route.dart';
import 'package:bosta_frontend/services/api_endpoints.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _busPlateController = TextEditingController();
  final _busCapacityController = TextEditingController();

  List<AppRoute> _availableRoutes = []; // All routes from backend
  String? _selectedRouteId;
  AppRoute? _selectedRoute; // Will hold the full details of the chosen route
  String? _selectedStartLocation; // Will store the selected stop name
  TimeOfDay? _selectedStartTime;

  bool _isLoading = false;
  bool _isFetchingRoutes = true;
  String? _errorMessage;

  bool _didFetchRoutes = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fetch routes only once when the screen is first built and dependencies are available.
    if (!_didFetchRoutes) {
      _didFetchRoutes = true;
      // Use a post-frame callback to ensure the widget is fully mounted
      // and context is available before accessing Provider.
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAvailableRoutes());
    }
  }
  
  Future<void> _fetchAvailableRoutes() async {
    setState(() {
      _isFetchingRoutes = true;
      _errorMessage = null;
    });
    try {
      // The user must be authenticated to reach this screen, so we need to include the auth token.
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.currentState.token;
      if (token == null) {
        throw Exception('Authentication token not found.');
      }

      final uri = Uri.parse(ApiEndpoints.routes);
      final response = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _availableRoutes = data.map((json) => AppRoute.fromJson(json)).toList();
            _isFetchingRoutes = false;
          });
        }
      } else {
        throw Exception('Failed to load routes. Status: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not fetch routes. Please try again.';
          _isFetchingRoutes = false;
        });
      }
    }
  }

  /// Fetches the full details (including geometry) for a single, selected route.
  Future<void> _fetchRouteDetails(String routeId) async {
    setState(() {
      _isLoading = true; // Use the main loader while fetching details
      _selectedRoute = null;
      _selectedStartLocation = null;
      _selectedStartTime = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final token = authService.currentState.token;
      final uri = Uri.parse('${ApiEndpoints.routes}$routeId/'); // e.g., /api/routes/route-1/
      final response = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _selectedRoute = AppRoute.fromJson(json.decode(response.body));
          });
        }
      } else {
        throw Exception('Failed to load route details');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not load details for the selected route.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Additional validation for non-form fields before proceeding.
    if (_selectedRouteId == null || _selectedStartLocation == null || _selectedStartTime == null) {
      setState(() {
        _errorMessage = 'Please complete all fields, including route, start location, and start time.';
        // This is a good place to trigger autovalidation to highlight missing fields.
        _formKey.currentState?.validate();
      });
      return;
    }

    // Safely capture the required values after validation.
    final routeId = _selectedRouteId!;
    final busCapacityText = _busCapacityController.text;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final error = await authService.setupDriverProfile(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      phoneNumber: _phoneController.text,
      busPlateNumber: _busPlateController.text.toUpperCase(),
      busCapacity: int.parse(busCapacityText),
      routeId: routeId,
    );

    if (mounted) {
      if (error != null) {
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
      }
      // On success, the AppRouter's redirect logic will handle navigation
      // because the auth state (onboardingComplete) will change.
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _busPlateController.dispose();
    _busCapacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12161A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Text('Driver Setup',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 10),
                Text(
                  'Complete your profile to get on the road. All fields are required unless marked optional.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[400]),
                ),
                const SizedBox(height: 40),
                _buildSectionHeader('Personal Information'),
                _buildTextField(_firstNameController, 'First Name', Icons.person_outline),
                const SizedBox(height: 16),
                _buildTextField(_lastNameController, 'Last Name', Icons.person_outline),
                const SizedBox(height: 16),
                _buildTextField(_phoneController, 'Phone Number', Icons.phone_outlined, keyboardType: TextInputType.phone),
                _buildSectionHeader('Vehicle Information'),
                _buildTextField(_busPlateController, 'Bus Plate Number (e.g., ABC-1234)', Icons.directions_bus_outlined),
                const SizedBox(height: 16),
                _buildTextField(_busCapacityController, 'Bus Capacity (e.g., 14)', Icons.group_outlined, keyboardType: TextInputType.number),
                _buildSectionHeader('Route & Documents'),
                // Add the route selection and dependent fields here.
                _buildRouteDropdown(),
                // Conditionally display start location and time pickers once a route is selected.
                if (_selectedRouteId != null) ..._buildDynamicRouteFields(),
                const SizedBox(height: 20),
                _buildFileUpload('Driver License (Optional)', Icons.credit_card),
                const SizedBox(height: 12),
                _buildFileUpload('Bus Registration (Optional)', Icons.article_outlined),
                const SizedBox(height: 30),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 14), textAlign: TextAlign.center),
                  ),
                _isLoading || _isFetchingRoutes
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF2ED8C3)))
                    : ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2ED8C3),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Save and Continue',
                          style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 12.0),
      child: Text(
        title,
        style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
      ),
    );
  }

  List<Widget> _buildDynamicRouteFields() {
    return [
      const SizedBox(height: 20),
      _buildStartLocationDropdown(),
      const SizedBox(height: 20),
      _buildStartTimePicker(),
    ];
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFF1F2327),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '$label is required';
        }
        if (keyboardType == TextInputType.number && int.tryParse(value) == null) {
          return 'Please enter a valid number';
        }
        if (label.contains('Bus Plate') && !RegExp(r'^[A-Z]{1,4}-\d{1,4}$').hasMatch(value)) {
          return 'Use format like T-1234';
        }
        return null;
      },
    );
  }

  Widget _buildRouteDropdown() {
    if (_isFetchingRoutes) {
      return const Center(child: Text("Fetching available routes...", style: TextStyle(color: Colors.white70)));
    }

    if (_availableRoutes.isEmpty) {
      return Center(
        child: Text(
          _errorMessage ?? "No routes available. Please contact support.",
          style: const TextStyle(color: Colors.red),
          textAlign: TextAlign.center,
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedRouteId,
      onChanged: (newValue) async {
        setState(() {
          _selectedRouteId = newValue;
        });
        if (newValue != null) {
          await _fetchRouteDetails(newValue);
        }
      },
      items: _availableRoutes.map<DropdownMenuItem<String>>((AppRoute route) {
        return DropdownMenuItem<String>(
          value: route.id,
          child: Text(route.name),
        );
      }).toList(),
      hint: const Text('Select Your Operating Route'),
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF1F2327),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1F2327),
        prefixIcon: const Icon(Icons.route_outlined, color: Colors.white70),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
        ),
      ),
      validator: (value) => value == null ? 'Route selection is required' : null,
    );
  }

  Widget _buildStartLocationDropdown() {
    // The AppRoute model uses 'geometry' for its coordinates, not 'stops'.
    // We can format the LatLng objects into readable strings for the dropdown.
    final stops = _selectedRoute?.geometry
            .map((latlng) =>
                '${latlng.latitude.toStringAsFixed(4)}, ${latlng.longitude.toStringAsFixed(4)}')
            .toList() ??
        [];

    if (stops.isEmpty) {
      return const Text(
        'This route has no defined starting points. Please select another route.',
        style: TextStyle(color: Colors.amber),
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedStartLocation,
      onChanged: (newValue) {
        setState(() => _selectedStartLocation = newValue);
      },
      items: stops.map<DropdownMenuItem<String>>((String stop) {
        return DropdownMenuItem<String>(
          value: stop,
          child: Text(stop),
        );
      }).toList(),
      hint: const Text('Select Your Starting Location'),
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF1F2327),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF1F2327),
        prefixIcon: const Icon(Icons.pin_drop_outlined, color: Colors.white70),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
        ),
      ),
      validator: (value) => value == null ? 'Starting location is required' : null,
    );
  }

  Widget _buildStartTimePicker() {
    return GestureDetector(
      onTap: () async {
        final TimeOfDay? pickedTime = await showTimePicker(
          context: context,
          initialTime: _selectedStartTime ?? TimeOfDay.now(),
        );
        if (pickedTime != null && pickedTime != _selectedStartTime) {
          setState(() {
            _selectedStartTime = pickedTime;
          });
        }
      },
      child: AbsorbPointer(
        child: TextFormField(
          // Use a controller to display the formatted time
          controller: TextEditingController(text: _selectedStartTime?.format(context) ?? ''),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Select Start Time',
            labelStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: const Icon(Icons.access_time_outlined, color: Colors.white70),
            filled: true,
            fillColor: const Color(0xFF1F2327),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2ED8C3)),
            ),
          ),
          validator: (value) => _selectedStartTime == null ? 'Start time is required' : null,
        ),
      ),
    );
  }

  Widget _buildFileUpload(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        // TODO: Implement file picking logic
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File upload functionality not yet implemented.')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2327),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white70)),
            ),
            const Icon(Icons.upload_file_outlined, color: Color(0xFF2ED8C3)),
          ],
        ),
      ),
    );
  }
}
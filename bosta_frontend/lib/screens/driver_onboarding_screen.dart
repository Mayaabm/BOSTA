import 'dart:async';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:bosta_frontend/models/app_route.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class DriverOnboardingScreen extends StatefulWidget {
  const DriverOnboardingScreen({super.key});

  @override
  State<DriverOnboardingScreen> createState() => _DriverOnboardingScreenState();
}

class _DriverOnboardingScreenState extends State<DriverOnboardingScreen> {
  // Separate form keys for each section
  final _personalInfoFormKey = GlobalKey<FormState>();
  final _vehicleInfoFormKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _busPlateController = TextEditingController();
  final _busCapacityController = TextEditingController();

  bool _isLoading = false;
  String? _generalErrorMessage; // For errors not tied to a specific section

  // Loading states for individual sections
  bool _isSavingPersonalInfo = false;
  bool _isSavingVehicleInfo = false;

  // Track if we are in edit mode (from query params)
  bool _isEditMode = false;
  AppRoute? _assignedRoute;

  @override
  void initState() {
    super.initState();
    _isEditMode = GoRouter.of(context).routeInformationProvider.value.uri.queryParameters.containsKey('edit');
    if (_isEditMode) {
      // Load existing data after the first frame
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExistingProfileData());
    }
  }

  // Generic method to save a section
  Future<String?> _saveSection(Map<String, dynamic> data, {bool isInitialOnboard = false}) async {
    FocusScope.of(context).unfocus();
    final authService = Provider.of<AuthService>(context, listen: false);

    String? error;
    if (isInitialOnboard) {
      // This path is for the very first time a driver sets up their profile
      error = await authService.setupDriverProfile(
        firstName: _firstNameController.text, lastName: _lastNameController.text,
        phoneNumber: _phoneController.text, busPlateNumber: _busPlateController.text.toUpperCase(), 
        busCapacity: int.parse(_busCapacityController.text), refreshToken: authService.currentState.refreshToken,
      );
    } else {
      // This path is for editing existing profile sections
      error = await authService.patchDriverProfile(data);
    }
    return error;
  }

  // Method to load existing profile data into controllers
  void _loadExistingProfileData() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final authState = authService.currentState;
    final driverInfo = authState.driverInfo;
    _assignedRoute = authState.assignedRoute;

    if (driverInfo != null) {
      _firstNameController.text = driverInfo.firstName;
      _lastNameController.text = driverInfo.lastName;
      _phoneController.text = driverInfo.phoneNumber ?? ''; // Assuming phoneNumber is added to DriverInfo
      _busPlateController.text = driverInfo.busPlateNumber ?? '';
      _busCapacityController.text = driverInfo.busCapacity?.toString() ?? '';
    }
  }

  Future<void> _submitPersonalInfo() async {
    if (!_personalInfoFormKey.currentState!.validate()) return;
    setState(() => _isSavingPersonalInfo = true);
    final data = {
      'first_name': _firstNameController.text,
      'last_name': _lastNameController.text,
      'phone_number': _phoneController.text,
    };
    final error = await _saveSection(data);
    if (mounted) {
      setState(() {
        _isSavingPersonalInfo = false;
        _generalErrorMessage = error;
      });
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Personal info saved!'), duration: Duration(seconds: 2)),
        );
        // No navigation needed, just show confirmation.
      }
    }
  }

  Future<void> _submitVehicleInfo() async {
    if (!_vehicleInfoFormKey.currentState!.validate()) return;
    setState(() => _isSavingVehicleInfo = true);
    final data = {
      'bus_plate_number': _busPlateController.text.toUpperCase(),
      'bus_capacity': int.parse(_busCapacityController.text),
    };
    final error = await _saveSection(data);
    if (mounted) {
      setState(() {
        _isSavingVehicleInfo = false;
        _generalErrorMessage = error;
      });
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle info saved!'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  // This method is for the initial onboarding submission, which calls setupDriverProfile (POST)
  Future<void> _submitInitialOnboarding() async {
    // Validate all forms
    final bool personalValid = _personalInfoFormKey.currentState?.validate() ?? false;
    final bool vehicleValid = _vehicleInfoFormKey.currentState?.validate() ?? false;

    // Safely capture the required values after validation.
    setState(() => _isLoading = true); // Global loading for initial setup
    final error = await _saveSection({}, isInitialOnboard: true);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _generalErrorMessage = error;
      });
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved. You can now start your trip!')));
        GoRouter.of(context).go('/driver/home'); // Navigate to home after initial setup
      }
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

  // Helper to build a section with a title, content, and save button
  Widget _buildSection({
    required String title,
    required GlobalKey<FormState> formKey,
    required List<Widget> children,
    required VoidCallback onSave,
    required bool isSaving,
    bool initiallyExpanded = false,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      color: const Color(0xFF1F2327),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(
          title,
          style: GoogleFonts.urbanist(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...children,
                  const SizedBox(height: 20),
                  if (isSaving)
                    const Center(child: CircularProgressIndicator(color: Color(0xFF2ED8C3)))
                  else
                    ElevatedButton(
                      onPressed: onSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2ED8C3),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Save $title', style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isEditMode
          ? AppBar(
              title: const Text('Edit Profile'),
              backgroundColor: const Color(0xFF1F2327),
              foregroundColor: Colors.white,
            )
          : null,
      backgroundColor: const Color(0xFF12161A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [              const SizedBox(height: 40),
              Text(_isEditMode ? 'Edit Profile' : 'Driver Setup',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.urbanist(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 10),
              Text(
                _isEditMode
                    ? 'Update your personal and vehicle information.'
                    : 'Complete your profile to get on the road. All fields are required unless marked optional.',
                textAlign: TextAlign.center,
                style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[400]),
              ),
              const SizedBox(height: 20),

              // Personal Information Section
              _buildSection(
                title: 'Personal Information',
                formKey: _personalInfoFormKey,
                children: [
                  _buildTextField(_firstNameController, 'First Name', Icons.person_outline),
                  const SizedBox(height: 16),
                  _buildTextField(_lastNameController, 'Last Name', Icons.person_outline),
                  const SizedBox(height: 16),
                  _buildTextField(_phoneController, 'Phone Number', Icons.phone_outlined, keyboardType: TextInputType.phone),
                ],
                onSave: _submitPersonalInfo,
                isSaving: _isSavingPersonalInfo,
                initiallyExpanded: true, // Expand first section by default
              ),

              // Vehicle Information Section
              _buildSection(
                title: 'Vehicle Information',
                formKey: _vehicleInfoFormKey,
                children: [
                  _buildTextField(_busPlateController, 'Bus Plate Number (e.g., ABC-1234)', Icons.directions_bus_outlined),
                  const SizedBox(height: 16),
                  _buildTextField(_busCapacityController, 'Bus Capacity (e.g., 14)', Icons.group_outlined, keyboardType: TextInputType.number),
                ],
                onSave: _submitVehicleInfo,
                isSaving: _isSavingVehicleInfo,
              ),

              const SizedBox(height: 20),
              if (_generalErrorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(_generalErrorMessage!, style: const TextStyle(color: Colors.red, fontSize: 14), textAlign: TextAlign.center),
                  ),

              // Only show "Complete Onboarding" button if not in edit mode
              if (!_isEditMode && _isLoading)
                const Center(child: CircularProgressIndicator(color: Color(0xFF2ED8C3)))
              else if (!_isEditMode) // Only show this button for initial onboarding
                  ElevatedButton(
                    onPressed: _submitInitialOnboarding,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2ED8C3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Complete Onboarding', style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
              // Show "Done" button when in edit mode
              if (_isEditMode)
                ElevatedButton(
                  // --- FIX: Use pop() instead of go() ---
                  // This returns to the previous screen (DriverHomeScreen) which is waiting
                  // for the onboarding to complete. Using go() creates a new instance of
              // the home screen, which is not the desired behavior.
                  onPressed: () {                    
                    if (GoRouter.of(context).canPop()) {
                      context.pop();
                    } else {
                      GoRouter.of(context).go('/driver/home');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2327), // A more subtle color for "Done"
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Done', style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildErrorMessage() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        _generalErrorMessage!,
        style: const TextStyle(color: Colors.red, fontSize: 14),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType, bool isEnabled = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: isEnabled,
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
        if (label.contains('Capacity') && (int.tryParse(value) == null || int.parse(value) <= 0)) {
          return 'Please enter a valid number';
        }
        if (label.contains('Bus Plate') && !RegExp(r'^[A-Z]{1,4}-\d{1,4}$').hasMatch(value)) {
          return 'Use format like T-1234';
        }
        return null;
      },
    );
  }
}
   
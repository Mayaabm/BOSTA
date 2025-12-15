import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // Driver onboarding controllers (account info only)
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  // Optional bus info if registering as a driver
  final _busPlateController = TextEditingController();
  final _busCapacityController = TextEditingController();

  UserRole _selectedRole = UserRole.rider;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _submitForm() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    String? error;

    try {
      final registrationError = await authService.register(
        username: _usernameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        role: _selectedRole,
        firstName: _firstNameController.text.isNotEmpty ? _firstNameController.text : null,
        lastName: _lastNameController.text.isNotEmpty ? _lastNameController.text : null,
        phoneNumber: _phoneController.text.isNotEmpty ? _phoneController.text : null,
        // include bus info when registering as a driver
        busPlateNumber: _busPlateController.text.isNotEmpty ? _busPlateController.text : null,
        busCapacity: _busCapacityController.text.isNotEmpty ? int.tryParse(_busCapacityController.text) : null,
      );

      // If registration failed, use that error. Otherwise, proceed to login.
      if (registrationError == null) {
        // After successful registration, immediately log in to get the auth token
        // and trigger the profile fetch and redirect logic.
        if (_selectedRole == UserRole.driver) {
          error = await authService.loginAsDriver(_emailController.text, _passwordController.text);
        } else {
          error = await authService.loginAsRider(_emailController.text, _passwordController.text);
        }
      } else {
        error = registrationError;
      }

      if (error == null) {
        // SUCCESS.
        // The AuthService has been updated and has called notifyListeners().
        // The app's centralized router will now automatically handle navigation.
        // We MUST NOT call Navigator.of(context) here to avoid race conditions.
      } else {
        // If there was an error, stop loading and show the message.
        if (!mounted) return;
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An unexpected error occurred: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Text(
                  'Create Account',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.urbanist(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  'Start your journey with us today.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.urbanist(fontSize: 16, color: Colors.grey[400]),
                ),
                const SizedBox(height: 40),
                _buildRoleSelector(),
                const SizedBox(height: 20),
                _buildTextField(_usernameController, 'Username', Icons.person_outline),
                const SizedBox(height: 20),
                _buildTextField(_emailController, 'Email Address', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 20),
                _buildTextField(_passwordController, 'Password', Icons.lock_outline, obscureText: true, onFieldSubmitted: (_) => _submitForm()),
                const SizedBox(height: 20),
                // For drivers, onboarding (name/phone/bus) happens after signup.
                // Keep the controllers available, but do not show the fields here.
                if (_selectedRole == UserRole.driver) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Drivers will complete onboarding after Sign Up.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                ],
                const SizedBox(height: 30),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 14), textAlign: TextAlign.center),
                  ),
                _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF2ED8C3)))
                    : ElevatedButton(
                        onPressed: _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2ED8C3),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Sign Up',
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

  Widget _buildRoleSelector() {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1F2327), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _buildRoleOption(UserRole.rider, 'I\'m a Rider'),
          _buildRoleOption(UserRole.driver, 'I\'m a Driver'),
        ],
      ),
    );
  }

  Widget _buildRoleOption(UserRole role, String title) {
    final isSelected = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!_isLoading) {
            setState(() => _selectedRole = role);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2ED8C3) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.urbanist(
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool obscureText = false, TextInputType? keyboardType, Function(String)? onFieldSubmitted}) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onFieldSubmitted: onFieldSubmitted,
      textInputAction: onFieldSubmitted != null ? TextInputAction.done : TextInputAction.next,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(icon, color: Colors.grey[400]),
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
      validator: (value) {
        if (value == null || value.isEmpty) {
          return '$label is required';
        }
        if (label.contains('Email') && !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
          return 'Please enter a valid email';
        }
        return null;
      },
    );
  }
}

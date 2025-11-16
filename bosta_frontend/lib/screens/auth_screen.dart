import 'package:bosta_frontend/services/driver_dashboard.dart';
import 'package:bosta_frontend/screens/register_screen.dart'; // Make sure this import is correct
import 'package:bosta_frontend/screens/rider_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // State for the role selection toggle
  UserRole _selectedRole = UserRole.rider;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _submitForm() async {
    // Hide keyboard and validate form
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
      if (_selectedRole == UserRole.driver) {
        error = await authService.loginAsDriver(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        error = await authService.loginAsRider(
          _emailController.text,
          _passwordController.text,
        );
      }

      if (error == null) {
        // Success! Navigation will be handled by a listener or redirect logic.
        // Navigation is now handled by the AppRouter's redirect logic.
      } else {
        // Failure: show the error message.
        if (!mounted) return;
        setState(() => _errorMessage = error);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
                const SizedBox(height: 60),
                Text(
                  'Welcome Back',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.urbanist(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Log in to continue your journey.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.urbanist(
                    fontSize: 16,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(height: 40),
                _buildRoleSelector(),
                const SizedBox(height: 20),
                _buildTextField(_emailController, 'Email Address', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 20),
                _buildTextField(_passwordController, 'Password', Icons.lock_outline, obscureText: true, onFieldSubmitted: (_) => _submitForm()),
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
                          'Log In',
                          style: GoogleFonts.urbanist(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                        ),
                      ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const RegisterScreen()),
                    );
                  },
                  child: Text(
                    "Don't have an account? Sign Up",
                    style: GoogleFonts.urbanist(
                      color: const Color(0xFF2ED8C3),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2327),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildRoleOption(UserRole.rider, 'Rider'),
          _buildRoleOption(UserRole.driver, 'Driver'),
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
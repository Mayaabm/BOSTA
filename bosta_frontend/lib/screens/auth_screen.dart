import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import 'dart:convert';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    // Start the fade-in animation after a short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _opacity = 1.0);
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      // The login call will trigger a state change in AuthService.
      // GoRouter's redirect logic will handle navigation automatically.
      await authService.login(
        _emailController.text,
        _passwordController.text,
      );
      // On success, the screen will be replaced, so no need to set _isLoading back to false.
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Invalid credentials or network issue.";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loginAsDriver() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = Provider.of<AuthService>(context, listen: false);

    // The method now returns an error string on failure, or null on success.
    final errorBody = await authService.loginAsDriver(
      _emailController.text,
      _passwordController.text,
    );

    if (mounted) {
      setState(() {
        if (errorBody != null) {
          // We have an error from the backend.
          try {
            final decoded = json.decode(errorBody);
            _errorMessage = decoded['error'] ?? "An unknown error occurred.";
          } catch (_) {
            _errorMessage = "Failed to parse server response. Please try again.";
          }
        }
        // If errorBody is null, login was successful and the redirect will happen automatically.
        // We only need to stop the loading indicator if there was an error.
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: AnimatedOpacity(
            opacity: _opacity,
            duration: const Duration(seconds: 1),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'BOSTA',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.urbanist(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Smart Bus Transit',
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 48),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(hintText: 'Email or Phone'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) => (value?.isEmpty ?? true) ? 'Please enter your email or phone' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(hintText: 'Password'),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    validator: (value) => (value?.isEmpty ?? true) ? 'Please enter your password' : null,
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _login,
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 3,
                              ),
                            )
                          : const Text('Login'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Account creation coming soon!')),
                          );
                        },
                        child: const Text('Create an Account'),
                      ),
                      TextButton(
                        onPressed: _loginAsDriver,
                        child: const Text('Continue as Driver'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
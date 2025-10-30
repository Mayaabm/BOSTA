import 'package:flutter/material.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to BOSTA')),
      body: const Center(child: Text('Login/Register Screen Placeholder')),
    );
  }
}
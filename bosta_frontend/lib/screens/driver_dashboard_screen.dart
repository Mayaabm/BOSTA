import 'package:flutter/material.dart';
import '../services/auth_service.dart'; // Import DriverInfo

class DriverDashboardScreen extends StatelessWidget {
  final DriverInfo? driverInfo;

  const DriverDashboardScreen({super.key, this.driverInfo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Dashboard')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome, Driver!', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 20),
            if (driverInfo != null) ...[
              Text('Name: ${driverInfo!.firstName} ${driverInfo!.lastName}', style: const TextStyle(fontSize: 18)),
              Text('Bus ID: ${driverInfo!.busId}', style: const TextStyle(fontSize: 18)),
              Text('Route ID: ${driverInfo!.routeId}', style: const TextStyle(fontSize: 18)),
            ] else
              const Text('Driver information not available.'),
          ],
        ),
      ),
    );
  }
}
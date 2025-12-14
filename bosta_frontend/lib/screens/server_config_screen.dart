import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/config_service.dart';

class ServerConfigScreen extends StatefulWidget {
  final VoidCallback onConfigSaved;

  const ServerConfigScreen({
    super.key,
    required this.onConfigSaved,
  });

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _mapboxController;
  bool _isTestingConnection = false;
  String? _connectionStatus;

  @override
  void initState() {
    super.initState();
    final config = ConfigService();
    _hostController = TextEditingController(text: config.serverHost);
    _portController = TextEditingController(text: config.serverPort.toString());
    _mapboxController = TextEditingController(text: config.mapboxToken ?? '');
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _mapboxController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final host = _hostController.text.trim();
    final portStr = _portController.text.trim();

    if (host.isEmpty || portStr.isEmpty) {
      setState(() {
        _connectionStatus = 'Please enter both host and port';
      });
      return;
    }

    final port = int.tryParse(portStr);
    if (port == null || port <= 0 || port > 65535) {
      setState(() {
        _connectionStatus = 'Invalid port number (1-65535)';
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _connectionStatus = 'Testing connection...';
    });

    try {
      // Temporarily set the config to test
      ConfigService().setServerConfig(host: host, port: port);

      // Try a simple HTTP GET to the base URL to test connectivity
      final uri = Uri.parse('${ConfigService().baseUrl}/');
      final response = await Future.delayed(
        const Duration(seconds: 2),
        () => Uri.parse('${ConfigService().baseUrl}/').toString(),
      );

      setState(() {
        _connectionStatus = '✓ Connection successful!';
      });
    } catch (e) {
      setState(() {
        _connectionStatus = '✗ Connection failed: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isTestingConnection = false;
      });
    }
  }

  void _saveConfig() {
    final host = _hostController.text.trim();
    final portStr = _portController.text.trim();

    if (host.isEmpty || portStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both host and port')),
      );
      return;
    }

    final port = int.tryParse(portStr);
    if (port == null || port <= 0 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid port number')),
      );
      return;
    }

    ConfigService().setServerConfig(host: host, port: port);
    // Save mapbox token (can be empty to clear)
    ConfigService().setMapboxToken(_mapboxController.text.trim());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Server configured: http://$host:$port/api')),
    );

    widget.onConfigSaved();
    Navigator.of(context).pop();
  }

  void _resetToDefault() {
    ConfigService().resetToDefault();
    _hostController.text = ConfigService().serverHost;
    _portController.text = ConfigService().serverPort.toString();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reset to default server settings')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Server Configuration',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF2C3E50),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Configure Backend Server',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Enter your backend server host and port to connect the app to your server.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 32),
            // Host Input
            Text(
              'Server Host',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hostController,
              decoration: InputDecoration(
                hintText: 'e.g., 192.168.1.100 or localhost',
                hintStyle: GoogleFonts.poppins(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 24),
            // Port Input
            Text(
              'Server Port',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 24),
            // Mapbox Token Input
            Text(
              'Mapbox Access Token (optional)',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2C3E50),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mapboxController,
              decoration: InputDecoration(
                hintText: 'pk.... (your Mapbox public token)',
                hintStyle: GoogleFonts.poppins(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'e.g., 8000',
                hintStyle: GoogleFonts.poppins(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 24),
            // Current Configuration Display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Configuration',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[900],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ConfigService().baseUrl,
                    style: GoogleFonts.courierPrime(
                      fontSize: 14,
                      color: Colors.blue[900],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Connection Status
            if (_connectionStatus != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _connectionStatus!.contains('✓')
                      ? Colors.green[50]
                      : Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _connectionStatus!.contains('✓')
                        ? Colors.green[300]!
                        : Colors.red[300]!,
                  ),
                ),
                child: Text(
                  _connectionStatus!,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _connectionStatus!.contains('✓')
                        ? Colors.green[900]
                        : Colors.red[900],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Buttons
            ElevatedButton(
              onPressed: _isTestingConnection ? null : _testConnection,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isTestingConnection
                  ? SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.8),
                        ),
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Test Connection',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _saveConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27AE60),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Save Configuration',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _resetToDefault,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Color(0xFFE74C3C)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Reset to Default',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFE74C3C),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

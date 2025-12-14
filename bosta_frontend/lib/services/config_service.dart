import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage application configuration (API server, etc.)
/// Uses in-memory storage. Can be enhanced with SharedPreferences later.
class ConfigService extends ChangeNotifier {
  // Singleton so callers like ApiEndpoints() get the same instance.
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal() {
    _loadFromPrefs();
  }

  static const String _defaultHost = 'localhost';
  static const int _defaultPort = 8000;
  static const String _kHost = 'bosta_server_host';
  static const String _kPort = 'bosta_server_port';
  static const String _kMapboxToken = 'mapbox_access_token';

  String _serverHost = _defaultHost;
  int _serverPort = _defaultPort;
  String? _mapboxToken;

  String get serverHost => _serverHost;
  int get serverPort => _serverPort;
  String get baseUrl => 'http://$_serverHost:$_serverPort/api';
  String? get mapboxToken => _mapboxToken;

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString(_kHost);
      final port = prefs.getInt(_kPort);
      final token = prefs.getString(_kMapboxToken);
      if (host != null) _serverHost = host;
      if (port != null) _serverPort = port;
      if (token != null) _mapboxToken = token;
      notifyListeners();
    } catch (e) {
      // ignore and keep defaults
      if (kDebugMode) print('ConfigService: failed to load prefs: $e');
    }
  }

  /// Update server configuration
  Future<void> setServerConfig({required String host, required int port}) async {
    _serverHost = host.trim();
    _serverPort = port;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kHost, _serverHost);
      await prefs.setInt(_kPort, _serverPort);
      // Do not overwrite Mapbox token here
    } catch (e) {
      if (kDebugMode) print('ConfigService: failed to save prefs: $e');
    }
    notifyListeners();
  }

  /// Set Mapbox access token for the app and persist it.
  Future<void> setMapboxToken(String? token) async {
    _mapboxToken = token?.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_mapboxToken == null || _mapboxToken!.isEmpty) {
        await prefs.remove(_kMapboxToken);
      } else {
        await prefs.setString(_kMapboxToken, _mapboxToken!);
      }
    } catch (e) {
      if (kDebugMode) print('ConfigService: failed to save mapbox token: $e');
    }
    notifyListeners();
  }

  /// Reset to default configuration
  Future<void> resetToDefault() async {
    _serverHost = _defaultHost;
    _serverPort = _defaultPort;
    _mapboxToken = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kHost);
      await prefs.remove(_kPort);
      await prefs.remove(_kMapboxToken);
    } catch (e) {
      if (kDebugMode) print('ConfigService: failed to clear prefs: $e');
    }
    notifyListeners();
  }
}

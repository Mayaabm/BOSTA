# Dynamic Server Configuration Implementation

## Overview
The app now supports dynamic server configuration, allowing users to connect to different backend servers without hardcoding IP addresses. This solves the network connectivity issue when switching between WiFi networks.

## Components Added

### 1. ConfigService (`lib/services/config_service.dart`)
A service class that manages the API server configuration:
- **Getters:**
  - `serverHost`: Returns the configured server host (default: `'localhost'`)
  - `serverPort`: Returns the configured server port (default: `8000`)
  - `baseUrl`: Composes the full base URL dynamically (e.g., `'http://localhost:8000/api'`)

- **Methods:**
  - `setServerConfig({required String host, required int port})`: Updates the server configuration at runtime
  - `resetToDefault()`: Reverts to default server settings

- **Storage:** Currently uses in-memory storage (no persistence between app restarts). Can be extended with SharedPreferences for persistence.

### 2. ServerConfigScreen (`lib/screens/server_config_screen.dart`)
A dedicated UI screen for managing server configuration with:
- **Input Fields:**
  - Server Host text input (e.g., `192.168.1.100` or `localhost`)
  - Server Port number input (default: `8000`)

- **Features:**
  - **Current Configuration Display:** Shows the currently active API base URL
  - **Test Connection Button:** Attempts to verify the server is reachable
  - **Save Configuration Button:** Applies the new server settings
  - **Reset to Default Button:** Reverts to default server settings (localhost:8000)
  - **Connection Status Feedback:** Displays success or error messages

### 3. Updated API Endpoints (`lib/services/api_endpoints.dart`)
All endpoint strings now use **dynamic getters** instead of constants:
- Changed from: `static const String register = '$base/register/'`
- Changed to: `static String get register => '$base/register/'`

This allows endpoints to use the dynamic base URL from ConfigService.

### 4. Router Updates (`lib/services/app_router.dart`)
Added new route for server configuration:
```dart
GoRoute(
  path: '/settings/server',
  builder: (context, state) => ServerConfigScreen(
    onConfigSaved: () {
      // Refresh or notify the app that config was changed
    },
  ),
)
```

### 5. UI Integration
- **Auth Screen:** Added a settings gear icon in the AppBar to access server configuration before login
- **Driver Home Screen:** Added a settings gear icon in the AppBar for drivers to change server settings at any time

## How It Works

1. **Default Configuration:** The app starts with default settings (localhost:8000)
2. **User Access:** Users can access server settings via:
   - Settings button in the Auth Screen (before login)
   - Settings button in the Driver Home Screen (after login)
3. **Configuration:** Users enter their backend server host and port
4. **Testing:** Users can test connectivity to verify the server is reachable
5. **Saving:** When saved, the new configuration is applied to all subsequent API calls
6. **Dynamic API Calls:** All API endpoints automatically use the configured base URL

## Usage Example

### Scenario: Switching WiFi Networks
1. User is connected to WiFi Network A (192.168.1.102) - app works fine
2. User switches to WiFi Network B where the backend is at (192.168.1.150)
3. User opens the app and sees connection errors
4. User taps the settings gear icon
5. User changes the host from `192.168.1.102` to `192.168.1.150`
6. User taps "Save Configuration"
7. App now connects to the new server

### Scenario: Development to Production
1. Developer is testing with local backend (localhost:8000)
2. Production backend is at (api.example.com:443)
3. Developer taps settings, changes host to `api.example.com` and port to `443`
4. All API calls now go to production backend

## Future Enhancements

1. **Persistent Storage:** Add SharedPreferences to save server configuration between app restarts
2. **Connection History:** Remember previously used servers for quick switching
3. **SSL/TLS Support:** Add option to use `https://` instead of `http://`
4. **Advanced Settings:** Add timeouts, retry policies, and custom headers
5. **Automatic Discovery:** Implement mDNS or Bluetooth discovery for local servers
6. **Validation:** Add hostname validation and certificate pinning for security

## Technical Details

### In-Memory vs Persistent Storage
Currently, the ConfigService uses in-memory storage with a singleton pattern. This means:
- ✓ Settings are applied immediately to the running app
- ✓ No file I/O overhead
- ✗ Settings are lost when the app restarts (can add persistence later)

### Dynamic URL Composition
The `baseUrl` getter constructs the full URL:
```dart
String get baseUrl => 'http://$_serverHost:$_serverPort/api';
```

This pattern ensures all API endpoints automatically use the latest configured server.

### Error Handling
The ServerConfigScreen validates:
- Host and port fields are not empty
- Port is a valid number (1-65535)
- Connection test attempts to reach the server

## Code Files Modified/Created

| File | Type | Changes |
|------|------|---------|
| `lib/services/config_service.dart` | Created | New ConfigService class |
| `lib/screens/server_config_screen.dart` | Created | New ServerConfigScreen UI |
| `lib/services/api_endpoints.dart` | Modified | Changed const strings to dynamic getters |
| `lib/services/app_router.dart` | Modified | Added `/settings/server` route |
| `lib/screens/driver_home_screen.dart` | Modified | Added settings gear icon to AppBar |
| `lib/screens/auth_screen.dart` | Modified | Added AppBar with settings gear icon |

## Testing Recommendations

1. **Test Default Configuration:** Verify app works with default localhost:8000
2. **Test Configuration Change:** Change server host/port and verify new settings are used
3. **Test Connection Test:** Verify connection test provides appropriate feedback
4. **Test Reset:** Verify reset to default button restores original settings
5. **Test Multi-Network:** Manually switch WiFi networks and verify app can reconnect
6. **Test Persistence (Future):** After adding SharedPreferences, verify settings survive app restart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'screens/transit_tokens.dart';
import 'services/auth_service.dart';
import 'services/app_router.dart';

void main() {
  runApp(const MyApp());
}

// --- BOSTA Design System Definition ---

final _bostaColorSchemeDark = ColorScheme(
  brightness: Brightness.dark,
  primary: const Color(0xFF2ED8C3), // Teal accent
  onPrimary: Color(0xFF000000),
  secondary: const Color(0xFF8A7FF0), // Violet for highlights
  onSecondary: Color(0xFF000000),
  error: const Color(0xFFFF5A5F),
  onError: Color(0xFFFFFFFF), // Main text
  surface: const Color(0xFF12161A), // Elevated elements
  onSurface: const Color(0xFFE6EAEE), // Main text
  outline: const Color(0xFF2A3238), // Border and separators
);

final _bostaColorSchemeLight = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF2EE57E), // accent
  onPrimary: Color(0xFFFFFFFF),
  secondary: Color(0xFF2EE57E),
  onSecondary: Color(0xFFFFFFFF),
  error: Color(0xFFFF5A5F),
  onError: Color(0xFFFFFFFF), // textHigh
  surface: Color(0xFFFFFFFF), // surfaceAlt
  onSurface: Color(0xFF111111), // textHigh
  outline: Color(0xFFE5E7EB), // border
);

final _bostaTextTheme = GoogleFonts.urbanistTextTheme().copyWith(
  displayLarge: GoogleFonts.inter(fontWeight: FontWeight.w700),
  displayMedium: GoogleFonts.inter(fontWeight: FontWeight.w700),
  displaySmall: GoogleFonts.inter(fontWeight: FontWeight.w700),
  headlineLarge: GoogleFonts.inter(fontWeight: FontWeight.w700),
  headlineMedium: GoogleFonts.inter(fontWeight: FontWeight.w600),
  headlineSmall: GoogleFonts.inter(fontWeight: FontWeight.w700),
  titleLarge: const TextStyle(fontWeight: FontWeight.w500),
  titleMedium: const TextStyle(fontWeight: FontWeight.w500),
  titleSmall: const TextStyle(fontWeight: FontWeight.w500),
);

final darkTheme = ThemeData(
  colorScheme: _bostaColorSchemeDark,
  textTheme: _bostaTextTheme,
  useMaterial3: true,
  extensions: const <ThemeExtension<dynamic>>[
    TransitTokens(
      routePrimary: Color(0xFF2ED8C3),
      sheetSurface: Color(0xFF1A2025), // Card color
      markerNormal: Color(0xFFA7B0B6), // Text Muted
      markerSelected: Color(0xFF2ED8C3), // Primary
      markerDelayed: Color(0xFFF9A825), // Accent
      chipSurface: Color(0xFF2A3238), // Divider
      etaPositive: Color(0xFF2ED8C3), // Primary
    ),
  ],
);

final lightTheme = ThemeData(
  colorScheme: _bostaColorSchemeLight,
  textTheme: _bostaTextTheme,
  useMaterial3: true,
  extensions: const <ThemeExtension<dynamic>>[
    TransitTokens(
      routePrimary: Color(0xFF2ED8C3),
      sheetSurface: Color(0xFFFFFFFF),
      markerNormal: Color(0xFF6B7280),
      markerSelected: Color(0xFF2ED8C3),
      markerDelayed: Color(0xFFF9A825),
      chipSurface: Color(0xFFE5E7EB),
      etaPositive: Color(0xFF2ED8C3),
    ),
  ],
);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthService _authService;
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _appRouter = AppRouter(_authService);
  }
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Bosta',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark, // Dark-by-default
      routerConfig: _appRouter.router,
    );
  }
}

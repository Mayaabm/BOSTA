import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/map_screen.dart';
import 'screens/transit_tokens.dart';

void main() {
  runApp(const MyApp());
}

// --- BOSTA Design System Definition ---

const _bostaColorSchemeDark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF2EE57E), // accent
  onPrimary: Color(0xFF000000),
  secondary: Color(0xFF2EE57E),
  onSecondary: Color(0xFF000000),
  error: Color(0xFFFF5A5F),
  onError: Color(0xFFFFFFFF),
  background: Color(0xFF0F1115), // surface
  onBackground: Color(0xFFFFFFFF), // textHigh
  surface: Color(0xFF171A20), // surfaceAlt
  onSurface: Color(0xFFFFFFFF), // textHigh
  outline: Color(0xFF2A2E36), // border
);

const _bostaColorSchemeLight = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF2EE57E), // accent
  onPrimary: Color(0xFFFFFFFF),
  secondary: Color(0xFF2EE57E),
  onSecondary: Color(0xFFFFFFFF),
  error: Color(0xFFFF5A5F),
  onError: Color(0xFFFFFFFF),
  background: Color(0xFFF3F4F6), // surface
  onBackground: Color(0xFF111111), // textHigh
  surface: Color(0xFFFFFFFF), // surfaceAlt
  onSurface: Color(0xFF111111), // textHigh
  outline: Color(0xFFE5E7EB), // border
);

final _bostaTextTheme = GoogleFonts.interTextTheme().copyWith(
  displayLarge: GoogleFonts.inter(fontWeight: FontWeight.w700),
  displayMedium: GoogleFonts.inter(fontWeight: FontWeight.w700),
  displaySmall: GoogleFonts.inter(fontWeight: FontWeight.w700),
  headlineLarge: GoogleFonts.inter(fontWeight: FontWeight.w700),
  headlineMedium: GoogleFonts.inter(fontWeight: FontWeight.w700),
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
      routePrimary: Color(0xFF2EE57E),
      sheetSurface: Color(0xFF171A20),
      markerNormal: Color(0xFFB5B8BE),
      markerSelected: Color(0xFF2EE57E),
      markerDelayed: Color(0xFFFFC857),
      chipSurface: Color(0xFF2A2E36),
      etaPositive: Color(0xFF2EE57E),
    ),
  ],
);

final lightTheme = ThemeData(
  colorScheme: _bostaColorSchemeLight,
  textTheme: _bostaTextTheme,
  useMaterial3: true,
  extensions: const <ThemeExtension<dynamic>>[
    TransitTokens(
      routePrimary: Color(0xFF2EE57E),
      sheetSurface: Color(0xFFFFFFFF),
      markerNormal: Color(0xFF6B7280),
      markerSelected: Color(0xFF2EE57E),
      markerDelayed: Color(0xFFFFC857),
      chipSurface: Color(0xFFE5E7EB),
      etaPositive: Color(0xFF2EE57E),
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bosta',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark, // Dark-by-default
      home: const MapScreen(),
    );
  }
}

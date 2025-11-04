import 'package:bosta_frontend/services/app_router.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:bosta_frontend/screens/transit_tokens.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

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

  @override
  Widget build(BuildContext context) {
    const darkNavy = Color(0xFF0B0E11);
    const inputBackground = Color(0xFF12161A);
    const accentColor = Color(0xFF2ED8C3);

    return ChangeNotifierProvider.value(
      value: _authService,
      child: MaterialApp.router(
        title: 'Bosta',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: darkNavy,
          primaryColor: accentColor,
          textTheme: GoogleFonts.urbanistTextTheme(ThemeData.dark().textTheme),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: inputBackground,
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.black,
              textStyle: GoogleFonts.urbanist(fontWeight: FontWeight.bold),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withOpacity(0.7),
              textStyle: GoogleFonts.urbanist(),
            ),
          ),
          colorScheme: const ColorScheme.dark(
            primary: accentColor,
            secondary: accentColor,
            background: darkNavy,
            error: Colors.redAccent,
          ),
          extensions: const <ThemeExtension<dynamic>>[
            TransitTokens(
              routePrimary: Colors.blue,
              sheetSurface: Colors.white,
              markerNormal: Colors.black,
              markerSelected: Colors.red,
              markerDelayed: Colors.orange,
              chipSurface: Colors.grey,
              etaPositive: Colors.green,
            ),
          ],
        ),
        routerConfig: _appRouter.router,
      ),
    );
  }
}
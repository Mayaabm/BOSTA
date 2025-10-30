import 'package:bosta_frontend/services/app_router.dart';
import 'package:bosta_frontend/services/auth_service.dart';
import 'package:bosta_frontend/screens/transit_tokens.dart';
import 'package:flutter/material.dart';

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
    return MaterialApp.router(
      title: 'Bosta',
      theme: ThemeData(
        primarySwatch: Colors.blue,
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
    );
  }
}
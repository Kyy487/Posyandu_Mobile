import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'demo/demo_mode.dart';
import 'demo/mock_api.dart';
import 'screens/assignment/assignment_splash_screen.dart';
import 'screens/shared/login_screen.dart';
import 'screens/kader/validasi/kader_registrations_screen.dart';
import 'theme/app_theme.dart';

void main() {
  http.runWithClient(
    () {
      runApp(const MyApp());
    },
    () => (DemoMode.enabled || DemoMode.frontendOnly)
        ? MockApiClient()
        : IOClient(),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Posyandu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const AssignmentSplashScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/kader/registrations': (context) => const KaderRegistrationsScreen(),
      },
    );
  }
}

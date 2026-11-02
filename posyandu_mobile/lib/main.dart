import 'package:flutter/material.dart';

import 'screens/shared/login_screen.dart';
import 'screens/kader/validasi/kader_registrations_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Posyandu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: const LoginScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/kader/registrations': (context) => const KaderRegistrationsScreen(),
      },
    );
  }
}
